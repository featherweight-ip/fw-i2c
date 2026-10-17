// ======================================================================
// Directed test for oc_i2c_wb32: the OpenCores i2c core (R76) behind the
// 32-bit WISHBONE shim.
//
// A fw-proto-wb initiator drives the shim (32-bit data, byte addresses);
// the core's I2C pads go to a fw-proto-i2c target transactor with a small
// memory responder, on a wired-AND open-drain bus. Checks:
//   - registers on a 4-byte stride, reads zero-extended, reset values;
//   - writes take wb_dat_i[7:0]; a write without wb_sel_i[0] is ignored;
//   - wb_adr_i[1:0] are ignored;
//   - TXR/CR readbacks (0x14, 0x18) and the reserved word (0x1C);
//   - a write of two bytes, then a repeated-START read back of them;
//   - an address NACK; IF / IACK and wb_inta_o.
//
// Run:  dfm run ref-wb32   (+PRER=<n> sets the prescaler; default 5)
// ======================================================================
module oc_i2c_wb32_tb;
    import fw_proto_i2c_pkg::*;

    localparam bit [6:0] TGT_ADDR = 7'h50;

    // Register byte addresses behind the shim (register n at 4*n).
    localparam bit [31:0] PRERLO = 32'h00, PRERHI = 32'h04, CTR = 32'h08,
                          TXR = 32'h0C, RXR = 32'h0C, CR = 32'h10, SR = 32'h10,
                          TXR_DBG = 32'h14, CR_DBG = 32'h18, RSVD7 = 32'h1C;
    localparam bit [7:0] SR_RXACK = 8'h80, SR_BUSY = 8'h40, SR_AL = 8'h20,
                         SR_TIP = 8'h02, SR_IF = 8'h01;
    localparam bit [7:0] CR_STA = 8'h80, CR_STO = 8'h40, CR_RD = 8'h20,
                         CR_WR = 8'h10, CR_ACK = 8'h08, CR_IACK = 8'h01;

    // --------------------------------------------------------------
    // Target memory: the first addressed() of each transfer resets the
    // pointer to 0; written bytes are stored, read bytes returned in order.
    // --------------------------------------------------------------
    class mem_model implements i2c_target_if;
        bit [7:0] mem [bit [7:0]];
        bit [7:0] ptr;
        virtual task addressed(input bit [9:0] addr, input bit addr_10b,
                               input bit read, output bit ack);
            ack = !addr_10b && addr[6:0] == TGT_ADDR;
            if (ack) ptr = 8'h00;
        endtask
        virtual task addressed_10b_hi(input bit [1:0] addr_hi, output bit ack);
            ack = 1'b0;
        endtask
        virtual task rx_byte(input bit [7:0] data, output bit ack);
            ack = 1'b1;
            mem[ptr] = data;
            ptr++;
        endtask
        virtual task tx_byte(output bit [7:0] data, input bit ack);
            data = mem.exists(ptr) ? mem[ptr] : 8'hEE;
            ptr++;
        endtask
    endclass

    logic clock = 1'b0;
    logic reset = 1'b1;
    always #5ns clock = ~clock;

    // WISHBONE (32-bit) between the initiator and the shim
    wire [31:0] adr, dat_w, dat_r;
    wire [3:0]  sel;
    wire        cyc, stb, we, ack, err, inta;

    wb_initiator_xtor #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) u_wb (
        .clock(clock), .reset(reset),
        .adr(adr), .dat_w(dat_w), .dat_r(dat_r), .cyc(cyc), .err(err),
        .sel(sel), .stb(stb), .ack(ack), .we(we));

    // I2C: open-drain wired-AND. The core drives a line low when its
    // (active-low) enable is 0; the target when its scl_oe/sda_oe is 1.
    wire core_scl_o, core_scl_oen, core_sda_o, core_sda_oen;
    wire tgt_scl_o, tgt_scl_oe, tgt_sda_o, tgt_sda_oe;
    wire scl = !((!core_scl_oen && !core_scl_o) || (tgt_scl_oe && !tgt_scl_o));
    wire sda = !((!core_sda_oen && !core_sda_o) || (tgt_sda_oe && !tgt_sda_o));

    oc_i2c_wb32 u_dut (
        .wb_clk_i(clock), .wb_rst_i(reset),
        .wb_adr_i(adr[4:0]), .wb_dat_i(dat_w), .wb_dat_o(dat_r),
        .wb_sel_i(sel), .wb_we_i(we), .wb_stb_i(stb), .wb_cyc_i(cyc),
        .wb_ack_o(ack), .wb_err_o(err), .wb_inta_o(inta),
        .scl_pad_i(scl), .scl_pad_o(core_scl_o), .scl_padoen_o(core_scl_oen),
        .sda_pad_i(sda), .sda_pad_o(core_sda_o), .sda_padoen_o(core_sda_oen));

    i2c_target_xtor u_tgt (
        .clock(clock), .reset(reset),
        .scl_o(tgt_scl_o), .scl_oe(tgt_scl_oe), .scl_i(scl),
        .sda_o(tgt_sda_o), .sda_oe(tgt_sda_oe), .sda_i(sda));

    int unsigned errors = 0;

    task automatic wb_write(input bit [31:0] a, input bit [31:0] d,
                            input bit [3:0] s = 4'hF);
        bit [31:0] rd;
        bit        e;
        u_wb.u_if.request(a, d, s, 1'b1);
        u_wb.u_if.response(rd, e);
    endtask

    task automatic wb_read(input bit [31:0] a, output bit [31:0] d);
        bit e;
        u_wb.u_if.request(a, 32'h0, 4'hF, 1'b0);
        u_wb.u_if.response(d, e);
    endtask

    task automatic expect_rd(input string what, input bit [31:0] a,
                             input bit [31:0] exp);
        bit [31:0] d;
        wb_read(a, d);
        if (d !== exp) begin
            $display("FAIL: %s: read 0x%02h = 0x%08h, expected 0x%08h", what, a, d, exp);
            errors++;
        end else
            $display("[wb32] %s: 0x%02h = 0x%08h OK", what, a, d);
    endtask

    // Issue a command and wait for it to finish (TIP low, IF set).
    task automatic cmd(input bit [7:0] c, output bit [7:0] status);
        bit [31:0] d;
        wb_write(CR, {24'h0, c});
        do wb_read(SR, d); while ((d[7:0] & SR_TIP) != 0 || (d[7:0] & SR_IF) == 0);
        status = d[7:0];
        if (d[31:8] != 0) begin
            $display("FAIL: SR upper bits 0x%06h", d[31:8]);
            errors++;
        end
    endtask

    initial begin
        automatic mem_model              mem = new();
        automatic i2c_target_xtor_bridge tbr;
        bit [7:0]  st;
        bit [31:0] d;
        automatic int unsigned prer = 5;  // +PRER=<n>; 5 = 400 kHz from 12 MHz
        void'($value$plusargs("PRER=%d", prer));

        repeat (4) @(posedge clock);
        reset = 1'b0;
        @(posedge clock);
        tbr = new(u_tgt.u_if, mem);
        tbr.start_bridge();

        // ---- register map --------------------------------------------
        expect_rd("PRERlo reset", PRERLO, 32'h0000_00FF);
        expect_rd("PRERhi reset", PRERHI, 32'h0000_00FF);
        expect_rd("CTR reset",    CTR,    32'h0000_0000);
        expect_rd("SR reset",     SR,     32'h0000_0000);
        expect_rd("reserved 0x1C", RSVD7, 32'h0000_0000);

        wb_write(PRERLO, {24'hFF_FFFF, prer[7:0]}); // upper bits ignored
        wb_write(PRERHI, {24'h0, prer[15:8]});
        expect_rd("PRERlo write", PRERLO, {24'h0, prer[7:0]});
        expect_rd("PRERhi write", PRERHI, {24'h0, prer[15:8]});
        $display("[wb32] PRER = %0d", prer);

        wb_write(CTR, 32'h0000_0080, 4'b1110);    // no lane 0: ignored
        expect_rd("CTR write without sel[0]", CTR, 32'h0000_0000);
        wb_write(CTR, 32'h0000_0080, 4'b0001);    // lane 0 only: written
        expect_rd("CTR write with sel[0]", CTR, 32'h0000_0080);
        expect_rd("CTR, adr[1:0]=3 ignored", CTR | 32'h3, 32'h0000_0080);

        wb_write(TXR, 32'h0000_00A0);
        expect_rd("TXR readback", TXR_DBG, 32'h0000_00A0);

        // ---- I2C write: START, address+W, 2 data bytes, STOP ---------
        wb_write(TXR, {24'h0, TGT_ADDR, 1'b0});
        cmd(CR_STA | CR_WR | CR_IACK, st);
        if ((st & SR_RXACK) != 0) begin $display("FAIL: address not ACKed"); errors++; end
        wb_write(TXR, 32'h11);
        cmd(CR_WR | CR_IACK, st);
        wb_write(TXR, 32'h22);
        cmd(CR_WR | CR_STO | CR_IACK, st);
        if ((st & (SR_RXACK | SR_AL)) != 0) begin $display("FAIL: write status 0x%02h", st); errors++; end

        // ---- I2C read back with a repeated START ---------------------
        wb_write(TXR, {24'h0, TGT_ADDR, 1'b0});
        cmd(CR_STA | CR_WR | CR_IACK, st);        // pointer back to 0
        wb_write(TXR, {24'h0, TGT_ADDR, 1'b1});
        cmd(CR_STA | CR_WR | CR_IACK, st);        // Sr, address+R
        if ((st & SR_RXACK) != 0) begin $display("FAIL: read address not ACKed"); errors++; end
        cmd(CR_RD | CR_IACK, st);                 // ACK
        expect_rd("read byte 0", RXR, 32'h0000_0011);
        cmd(CR_RD | CR_ACK | CR_STO | CR_IACK, st); // NACK, STOP
        expect_rd("read byte 1", RXR, 32'h0000_0022);
        expect_rd("CR readback after STOP", CR_DBG, {24'h0, CR_ACK}); // ACK bit holds

        // ---- address NACK --------------------------------------------
        wb_write(TXR, {24'h0, 7'h7F, 1'b0});
        cmd(CR_STA | CR_WR | CR_IACK, st);
        if ((st & SR_RXACK) == 0) begin $display("FAIL: address 0x7F was ACKed"); errors++; end
        else $display("[wb32] address 0x7F NACKed OK");
        cmd(CR_STO | CR_IACK, st);

        // ---- interrupt -----------------------------------------------
        wb_write(CTR, 32'h0000_00C0);             // EN | IEN; IF still set
        repeat (2) @(posedge clock);
        if (inta !== 1'b1) begin $display("FAIL: wb_inta_o not set with IF and IEN"); errors++; end
        wb_write(CR, {24'h0, CR_IACK});
        // IACK -> cr[0] -> irq_flag -> wb_inta_o: registered at each step.
        repeat (4) @(posedge clock);
        if (inta !== 1'b0) begin $display("FAIL: wb_inta_o not cleared by IACK"); errors++; end
        else $display("[wb32] IF/IACK and wb_inta_o OK");

        if (mem.mem[0] != 8'h11 || mem.mem[1] != 8'h22) begin
            $display("FAIL: target memory 0x%02h 0x%02h", mem.mem[0], mem.mem[1]);
            errors++;
        end

        if (errors != 0) $fatal(1, "[oc_i2c_wb32] FAIL (%0d errors)", errors);
        $display("[oc_i2c_wb32] PASS");
        $finish;
    end

    initial begin
        #2ms;
        $fatal(1, "[oc_i2c_wb32] TIMEOUT");
    end
endmodule
