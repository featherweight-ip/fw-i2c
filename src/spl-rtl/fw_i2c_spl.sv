// fw-i2c behind pins (bench-plan E8): the class model (src/spl) with the same
// pins as the R76 shim oc_i2c_wb32, so the same bench, firmware and register
// tests apply. For simulation: the sequencer and registers are the class
// model; the bit level is the fw-proto-i2c controller transactor core with
// the fw-i2c timing (design §8.1). A watcher (the kit's monitor core) gives
// SR.BUSY.
//
// Two input filters, both R76's structure (sync, 3 samples, majority):
//   u_filter_ctl  sampled every clock, in front of the controller core. The
//                 core counts a high phase from the moment it sees SCL high,
//                 so its input latency adds to every SCL period; R76's slow
//                 filter here would bring back D10 (measured: +7..17%).
//                 This one adds 4 clocks.
//   u_filter      sampled every floor(PRER/4)+1 clocks, as R76, in front of
//                 the bus watcher: START/STOP detection keeps R76's glitch
//                 rejection.
//
// The model starts when reset is released; a later reset is not supported.
module fw_i2c_spl (
        input  wire        wb_clk_i,
        input  wire        wb_rst_i,
        input  wire [4:0]  wb_adr_i,     // byte address; [1:0] ignored
        input  wire [31:0] wb_dat_i,
        output wire [31:0] wb_dat_o,
        input  wire [3:0]  wb_sel_i,
        input  wire        wb_we_i,
        input  wire        wb_stb_i,
        input  wire        wb_cyc_i,
        output wire        wb_ack_o,
        output wire        wb_err_o,
        output wire        wb_inta_o,

        input  wire        scl_pad_i,
        output wire        scl_pad_o,
        output wire        scl_padoen_o,  // active low
        input  wire        sda_pad_i,
        output wire        sda_pad_o,
        output wire        sda_padoen_o   // active low
    );
    import fw_hdl_pkg::*;
    import fw_proto_wb_pkg::*;
    import fw_proto_i2c_pkg::*;
    import fw_i2c_spl_rtl_pkg::*;

    // Bus timing in ticks of PRER+1 clocks: a 5-tick bit (the PDF formula,
    // D10) with tSU;STA of 3 ticks (UM10204 Standard mode, D8).
    localparam int T_LOW = 3, T_HIGH = 2, T_HD_STA = 2, T_SU_STA = 3, T_SU_STO = 2, T_BUF = 4;

    wb_target_xtor #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) u_wb (
        .clock(wb_clk_i), .reset(wb_rst_i),
        .adr({27'b0, wb_adr_i}), .dat_w(wb_dat_i), .dat_r(wb_dat_o), .cyc(wb_cyc_i),
        .err(wb_err_o), .sel(wb_sel_i), .stb(wb_stb_i), .ack(wb_ack_o), .we(wb_we_i));

    wire scl_f, sda_f;
    wire ctl_scl_o, ctl_scl_oe, ctl_sda_o, ctl_sda_oe;

    i2c_controller_xtor #(
        .T_LOW(T_LOW), .T_HIGH(T_HIGH), .T_HD_STA(T_HD_STA),
        .T_SU_STA(T_SU_STA), .T_SU_STO(T_SU_STO), .T_BUF(T_BUF)
    ) u_ctl (
        .clock(wb_clk_i), .reset(wb_rst_i),
        .scl_o(ctl_scl_o), .scl_oe(ctl_scl_oe), .scl_i(scl_f),
        .sda_o(ctl_sda_o), .sda_oe(ctl_sda_oe), .sda_i(sda_f));

    fw_i2c_filter u_filter_ctl (
        .clock(wb_clk_i), .reset(wb_rst_i), .prer(16'd0),
        .scl_i(scl_pad_i), .sda_i(sda_pad_i), .scl_f(scl_f), .sda_f(sda_f));

    wire scl_w, sda_w;
    fw_i2c_filter u_filter (
        .clock(wb_clk_i), .reset(wb_rst_i), .prer(u_ctl.prescale),
        .scl_i(scl_pad_i), .sda_i(sda_pad_i), .scl_f(scl_w), .sda_f(sda_w));

    i2c_monitor_xtor u_watch (.clock(wb_clk_i), .reset(wb_rst_i), .scl_i(scl_w), .sda_i(sda_w));

    // R76 pad convention: the outputs are 0, the active-low enables drive.
    assign scl_pad_o    = 1'b0;
    assign sda_pad_o    = 1'b0;
    assign scl_padoen_o = !(ctl_scl_oe && !ctl_scl_o);
    assign sda_padoen_o = !(ctl_sda_oe && !ctl_sda_o);

    fw_i2c_irq_xtor_if u_irq (.clock(wb_clk_i), .reset(wb_rst_i), .irq(wb_inta_o));
    fw_clock_xtor_if   u_clk (.clock(wb_clk_i), .reset(wb_rst_i));

    fw_component_root #(fw_i2c_pin_top) root;

    initial begin
        fw_clock_xtor_bridge                clk;
        fw_i2c_irq_pin                      irq;
        wb_target_xtor_bridge #(32, 32)     wb;
        i2c_monitor_xtor_bridge             watch;
        @(negedge wb_rst_i);
        root = new("fw_i2c");
        clk  = new("clock", root, u_clk);
        irq  = new(u_irq);
        root.clock.connect(clk);
        root.ctl_vif = u_ctl.u_if;
        root.irq     = irq;
        fork
            root.start();
        join_none
        wait (root.elaborated);
        wb    = new(u_wb.u_if, root.dut.host);
        watch = new(u_watch.u_if, root.dut.bus_mon);
        wb.start();
        watch.start_bridge();
    end
endmodule
