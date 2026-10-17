// HDL top for the `ref-eq` view, the equivalence self-test (bench-plan §3.4,
// E4): two R76 arms, each on its own I2C bus. u_dut stands in for the design
// under test; u_ref is the reference arm every equivalence top will carry.
module hdl_top_ref_eq;
    logic clock = 1'b0;
    logic reset = 1'b1;
    always #5ns clock = ~clock;          // 100 MHz
    initial begin
        repeat (4) @(posedge clock);
        reset = 1'b0;
    end

    wire dut_inta, dut_scl, dut_sda;
    wire ref_inta, ref_scl, ref_sda;
    oc_i2c_ref_arm u_dut (.clock(clock), .reset(reset), .inta(dut_inta), .scl(dut_scl), .sda(dut_sda));
    oc_i2c_ref_arm u_ref (.clock(clock), .reset(reset), .inta(ref_inta), .scl(ref_scl), .sda(ref_sda));
endmodule
