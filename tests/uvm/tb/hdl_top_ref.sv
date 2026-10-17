// HDL top for the `ref` view: the R76 arm alone, with clock and reset.
module hdl_top_ref;
    logic clock = 1'b0;
    logic reset = 1'b1;
    always #5ns clock = ~clock;          // 100 MHz
    initial begin
        repeat (4) @(posedge clock);
        reset = 1'b0;
    end

    wire inta, scl, sda;
    oc_i2c_ref_arm u_arm (.clock(clock), .reset(reset), .inta(inta), .scl(scl), .sda(sda));
endmodule
