// ----------------------------------------------------------------------------
// oc_i2c_wb32 -- 32-bit WISHBONE shim around the OpenCores i2c core (R76).
//
// The fw-XXX convention for WISHBONE IP is a 32-bit data bus with one
// register per 32-bit word, even when only the low byte is valid. The core
// (i2c_master_top, from featherweight-ip/oc-i2c) has an 8-bit bus with one
// register per byte address, so this shim:
//
// - maps register n to byte address 4*n: the core sees wb_adr_i[4:2], and
//   wb_adr_i[1:0] are ignored (the same layout as Linux i2c-ocores with
//   reg-shift = 2, reg-io-width = 4);
// - returns {24'b0, register} on reads and takes the register value from
//   wb_dat_i[7:0] on writes;
// - writes only when byte lane 0 is selected (wb_sel_i[0]). A write
//   without it is passed to the core as a read: it is acknowledged, and
//   it has no effect because every core register read is side-effect free;
// - ties the core's asynchronous reset (arst_i) inactive, so wb_rst_i
//   (synchronous, active high) is the only reset;
// - passes wb_cyc_i/wb_stb_i/wb_ack_o, the interrupt and the pads straight
//   through, and drives wb_err_o low.
//
// No logic is added beyond the write-enable AND: everything else is wiring
// and zero extension.
// ----------------------------------------------------------------------------
module oc_i2c_wb32 (
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

    wire [7:0] dat8_o;

    i2c_master_top #(
        .ARST_LVL(1'b0)                  // arst_i active low ...
    ) u_core (
        .wb_clk_i     (wb_clk_i),
        .wb_rst_i     (wb_rst_i),
        .arst_i       (1'b1),            // ... and tied inactive
        .wb_adr_i     (wb_adr_i[4:2]),
        .wb_dat_i     (wb_dat_i[7:0]),
        .wb_dat_o     (dat8_o),
        .wb_we_i      (wb_we_i & wb_sel_i[0]),
        .wb_stb_i     (wb_stb_i),
        .wb_cyc_i     (wb_cyc_i),
        .wb_ack_o     (wb_ack_o),
        .wb_inta_o    (wb_inta_o),
        .scl_pad_i    (scl_pad_i),
        .scl_pad_o    (scl_pad_o),
        .scl_padoen_o (scl_padoen_o),
        .sda_pad_i    (sda_pad_i),
        .sda_pad_o    (sda_pad_o),
        .sda_padoen_o (sda_padoen_o)
    );

    assign wb_dat_o = {24'b0, dat8_o};
    assign wb_err_o = 1'b0;

endmodule
