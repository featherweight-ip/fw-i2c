// HDL top for the `tlm-eq` view: the clock for the fw-i2c class model and the
// R76 reference arm, each with its own I2C bus (bench-plan §3.4).
module hdl_top_spl_eq;
    logic clock = 1'b0;
    logic reset = 1'b1;
    always #5ns clock = ~clock;          // 100 MHz
    initial begin
        repeat (4) @(posedge clock);
        reset = 1'b0;
    end

    fw_clock_xtor_if u_clk (.clock(clock), .reset(reset));

    wire ref_inta, ref_scl, ref_sda;
    oc_i2c_ref_arm u_ref (.clock(clock), .reset(reset), .inta(ref_inta), .scl(ref_scl), .sda(ref_sda));
endmodule
