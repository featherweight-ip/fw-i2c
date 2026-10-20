// HDL top for the `wb` view: fw-i2c behind pins, alone.
module hdl_top_wb;
    logic clock = 1'b0;
    logic reset = 1'b1;
    always #5ns clock = ~clock;          // 100 MHz
    initial begin
        repeat (4) @(posedge clock);
        reset = 1'b0;
    end

    wire inta, scl, sda;
    fw_i2c_wb_arm u_arm (.clock(clock), .reset(reset), .inta(inta), .scl(scl), .sda(sda));
endmodule
