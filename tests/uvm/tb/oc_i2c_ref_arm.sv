// The R76 reference arm: the OpenCores i2c core through the 32-bit WISHBONE
// shim (src/ref/oc_i2c_wb32.sv), a WISHBONE initiator transactor for its
// register port, and its own open-drain I2C bus with a target and a monitor
// transactor. Instanced by hdl_top_ref and, later, by every equivalence top
// beside the design under test (bench-plan §4.3). i2c_ref_model drives it
// through u_wb.u_if, u_tgt.u_if and u_mon.u_if, and watches `inta`.
//
// The bus also has a second master, a controller transactor (u_ctl), idle
// unless a test drives it: the arbitration confirmation test (D9, E3).
module oc_i2c_ref_arm (
        input  wire clock,
        input  wire reset,
        output wire inta,
        // The bus lines, for a top that wants to look at them.
        output wire scl,
        output wire sda
    );
    wire [31:0] adr, dat_w, dat_r;
    wire [3:0]  sel;
    wire        cyc, stb, we, ack, err;

    wb_initiator_xtor #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) u_wb (
        .clock(clock), .reset(reset),
        .adr(adr), .dat_w(dat_w), .dat_r(dat_r), .cyc(cyc), .err(err),
        .sel(sel), .stb(stb), .ack(ack), .we(we));

    // Open-drain wired-AND. The core drives a line low when its active-low
    // enable is 0; the target transactor when its _oe is 1.
    wire core_scl_o, core_scl_oen, core_sda_o, core_sda_oen;
    wire tgt_scl_o, tgt_scl_oe, tgt_sda_o, tgt_sda_oe;
    wire ctl_scl_o, ctl_scl_oe, ctl_sda_o, ctl_sda_oe;
    assign scl = !((!core_scl_oen && !core_scl_o) || (tgt_scl_oe && !tgt_scl_o) ||
                   (ctl_scl_oe && !ctl_scl_o));
    assign sda = !((!core_sda_oen && !core_sda_o) || (tgt_sda_oe && !tgt_sda_o) ||
                   (ctl_sda_oe && !ctl_sda_o));

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

    i2c_controller_xtor u_ctl (
        .clock(clock), .reset(reset),
        .scl_o(ctl_scl_o), .scl_oe(ctl_scl_oe), .scl_i(scl),
        .sda_o(ctl_sda_o), .sda_oe(ctl_sda_oe), .sda_i(sda));

    i2c_monitor_xtor u_mon (
        .clock(clock), .reset(reset),
        .scl_i(scl), .sda_i(sda));
endmodule
