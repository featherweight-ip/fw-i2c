// The fw-i2c arm for the pin-level views (`wb`, `wb-eq`): fw_i2c_spl (the class
// model behind the R76 shim's pins) with the same WISHBONE initiator, open-drain
// bus, target and monitor as the R76 arm (oc_i2c_ref_arm), so the same
// transactor-backed model class (i2c_ref_model) drives either.
module fw_i2c_wb_arm (
        input  wire clock,
        input  wire reset,
        output wire inta,
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

    wire core_scl_o, core_scl_oen, core_sda_o, core_sda_oen;
    wire tgt_scl_o, tgt_scl_oe, tgt_sda_o, tgt_sda_oe;
    assign scl = !((!core_scl_oen && !core_scl_o) || (tgt_scl_oe && !tgt_scl_o));
    assign sda = !((!core_sda_oen && !core_sda_o) || (tgt_sda_oe && !tgt_sda_o));

    fw_i2c_spl u_dut (
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

    i2c_monitor_xtor u_mon (
        .clock(clock), .reset(reset),
        .scl_i(scl), .sda_i(sda));
endmodule
