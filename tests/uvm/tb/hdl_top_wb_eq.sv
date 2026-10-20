// HDL top for the `wb-eq` view: fw-i2c behind pins and the R76 arm, each on
// its own I2C bus (bench-plan §3.4).
module hdl_top_wb_eq;
    logic clock = 1'b0;
    logic reset = 1'b1;
    always #5ns clock = ~clock;          // 100 MHz
    initial begin
        repeat (4) @(posedge clock);
        reset = 1'b0;
    end

    wire dut_inta, dut_scl, dut_sda;
    wire ref_inta, ref_scl, ref_sda;
    fw_i2c_wb_arm  u_dut (.clock(clock), .reset(reset), .inta(dut_inta), .scl(dut_scl), .sda(dut_sda));
    oc_i2c_ref_arm u_ref (.clock(clock), .reset(reset), .inta(ref_inta), .scl(ref_scl), .sda(ref_sda));
endmodule
