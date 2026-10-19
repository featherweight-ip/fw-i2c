// The fw-i2c master (design §3; behaviour per design §5 and the OI-6
// resolution in design §8.1).
//
// Edges:
//   host    register port, an export of wb_proto_if #(32, 32)
//   i2c     the controller API (fw-proto-i2c), a port; PRER drives set_prescale()
//   bus_mon the bus watcher, an i2c_monitor_if the view subscribes to the bus
//   irq     fw_i2c_irq_if sinks (add_irq_sink), told of every change of IF & IEN
//
// Registers follow R76 (the 4-byte-stride map, docs/reference/registers.md):
// writes need sel[0] and take bits [7:0]; adr[1:0] is ignored; a CR write is
// ignored while CTR.EN is 0 (IACK included). Each register access takes
// HOST_TICKS clocks, about one R76 WISHBONE cycle.
//
// Commands (docs/reference/operation.md): a CR write starts a command when
// RD, WR or STO is set; STA alone stays pending. STA sends START (repeated if
// this master owns the bus) with TXR as the address byte; RD takes priority
// over WR; STO follows. At the end the command bits clear, RXACK is updated
// and IF sets; arbitration lost sets AL and IF and abandons the command.
// Unlike R76 (OI-6):
//   D1  a register write never repeats a command (commands are taken from the
//       CR write itself, not from bits left set at completion)
//   D6  clearing EN in the middle of a command abandons it at the next
//       operation boundary, with no STOP and no IF; the lines are released
//   D7  every PRER works
//   STA + RD sends START and TXR as an address byte before the read (the
//       kit cannot read without an address byte): allowed difference sta_rd
class fw_i2c extends fw_component implements fw_runnable;
    localparam int HOST_TICKS = 3;

    fw_i2c_regs                regs;
    fw_i2c_host                host;
    fw_port #(i2c_controller_if) i2c;
    fw_i2c_bus_watch           bus_mon;

    protected fw_i2c_irq_if    m_irq_sinks[$];
    protected bit              m_irq;          // the level last reported
    protected bit              m_cmd_pending;  // a CR write with a command
    protected bit              m_own_bus;      // this master sent START, not yet STOP
    protected bit [15:0]       m_prescale = '1;
    protected bit              m_prescale_set;

    function new(string name, fw_component parent);
        super.new(name, parent);
        add_runnable(this);
    endfunction

    function void build();
        fw_i2c_wr_obs   cr_obs, ctr_obs;
        fw_i2c_readback txr_rb, cr_rb;
        regs    = new("regs");     // the block adopts the component being built
        host    = new("host", this, this);
        i2c     = new("i2c", this);
        bus_mon = new();
        cr_obs  = new(this, fw_i2c_wr_obs::OBS_CR);
        ctr_obs = new(this, fw_i2c_wr_obs::OBS_CTR);
        regs.CR.add_wr(cr_obs);
        regs.CTR.add_wr(ctr_obs);
        txr_rb = new(regs.TXR);
        cr_rb  = new(regs.CR);
        regs.TXR_DBG.set_rd(txr_rb);
        regs.CR_DBG.set_rd(cr_rb);
    endfunction

    function void add_irq_sink(fw_i2c_irq_if s); m_irq_sinks.push_back(s); endfunction

    // ---- register port ----

    task host_access(input bit [31:0] adr, input bit [31:0] dat_w, input bit [3:0] sel,
                     input bit we, output bit [31:0] dat_r, output bit err);
        int unsigned off = int'({adr[4:2], 2'b00});
        tick(HOST_TICKS);
        err   = 1'b0;
        dat_r = '0;
        if (!we) begin
            dat_r = regs.read_val(off);
            return;
        end
        if (!sel[0]) return;
        if (off == regs.CR.offset && !regs.CTR.read().EN) return;
        regs.write_val(off, {24'h0, dat_w[7:0]});
    endtask

    // ---- register hooks (called inside a software write) ----

    // CR: IACK clears IF; STA clears AL (as R76's `al & ~sta`); a command
    // starts the sequencer and shows TIP for RD and WR at once.
    task on_cr_write(bit [31:0] val);
        fw_i2c_regs__CR_t cr = fw_i2c_regs__CR_t'(val);
        fw_i2c_regs__SR_t sr = regs.SR.read();
        if (cr.IACK) sr.IF = 1'b0;
        if (cr.STA)  sr.AL = 1'b0;
        if (cr.RD || cr.WR || cr.STO) begin
            sr.TIP = cr.RD || cr.WR;
            m_cmd_pending = 1'b1;
        end
        regs.SR.update(sr);
        update_irq();
    endtask

    task on_ctr_write(bit [31:0] val, bit [31:0] prev);
        update_irq();
    endtask

    protected task update_irq();
        bit level = regs.SR.read().IF && regs.CTR.read().IEN;
        if (level == m_irq) return;
        m_irq = level;
        foreach (m_irq_sinks[i]) m_irq_sinks[i].irq_changed(level);
    endtask

    // ---- processes ----

    virtual task run();
        if (!i2c.is_connected()) $fatal(1, "fw_i2c %s: the i2c port is unconnected", get_name());
        fork
            sequencer();
            busy_watch();
        join
    endtask

    protected task busy_watch();
        forever begin
            fw_i2c_regs__SR_t sr;
            wait (bus_mon.dirty);
            bus_mon.dirty = 1'b0;
            sr      = regs.SR.read();
            sr.BUSY = bus_mon.busy;
            regs.SR.update(sr);
        end
    endtask

    protected task sequencer();
        forever begin
            wait (m_cmd_pending);
            m_cmd_pending = 1'b0;
            run_command(regs.CR.read());
        end
    endtask

    protected task set_prescale();
        bit [15:0] p = {regs.PRERhi.read().PRER_HI, regs.PRERlo.read().PRER_LO};
        if (m_prescale_set && p == m_prescale) return;
        i2c.t.set_prescale(p);
        m_prescale     = p;
        m_prescale_set = 1'b1;
    endtask

    // 1 if EN was cleared: abandon the command (D6, fixed).
    protected function bit disabled(); return !regs.CTR.read().EN; endfunction

    protected task run_command(fw_i2c_regs__CR_t cr);
        fw_i2c_regs__SR_t sr;
        bit [7:0] txr = regs.TXR.read().DATA;
        bit       ack, al, rxack;
        bit [7:0] data;

        set_prescale();
        rxack = regs.SR.read().RXACK;
        al    = 1'b0;

        if (cr.STA) begin
            i2c.t.start(10'(txr[7:1]), 1'b0, txr[0], m_own_bus, ack, al);
            if (!al) begin
                m_own_bus = 1'b1;
                rxack     = !ack;
            end
        end else if (cr.RD) begin
            i2c.t.rx_byte(!cr.ACK, data, al);
            if (!al) begin
                fw_i2c_regs__RXR_t rxr = '0;
                rxr.DATA = data;
                regs.RXR.update(rxr);
                rxack = cr.ACK;              // the bit the core sent
            end
        end else if (cr.WR) begin
            i2c.t.tx_byte(txr, ack, al);
            if (!al) rxack = !ack;
        end
        // STA + RD: the read after the address byte.
        if (cr.STA && cr.RD && !al && !disabled()) begin
            i2c.t.rx_byte(!cr.ACK, data, al);
            if (!al) begin
                fw_i2c_regs__RXR_t rxr = '0;
                rxr.DATA = data;
                regs.RXR.update(rxr);
                rxack = cr.ACK;
            end
        end
        if (cr.STO && !al && !disabled()) begin
            i2c.t.stop();
            m_own_bus = 1'b0;
        end
        if (al) m_own_bus = 1'b0;

        // Completion: the command bits clear, then SR.
        regs.CR.update('0, '{STA: 1'b1, STO: 1'b1, RD: 1'b1, WR: 1'b1, default: '0});
        sr     = regs.SR.read();
        sr.TIP = 1'b0;
        if (disabled() && !al) begin
            // D6: abandoned, no completion.
            m_own_bus = 1'b0;
        end else begin
            sr.RXACK = rxack;
            sr.AL    = al;
            sr.IF    = 1'b1;
        end
        regs.SR.update(sr);
        update_irq();
    endtask
endclass
