// HDL top for the `tlm` view: only a clock and reset for the class model's
// clock domain. There is no RTL and no bus.
module hdl_top_spl;
    logic clock = 1'b0;
    logic reset = 1'b1;
    always #5ns clock = ~clock;          // 100 MHz, as the ref view
    initial begin
        repeat (4) @(posedge clock);
        reset = 1'b0;
    end

    fw_clock_xtor_if u_clk (.clock(clock), .reset(reset));
endmodule
