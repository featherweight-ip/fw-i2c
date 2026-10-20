// The input filter, as R76's bit controller (docs/reference/timing.md, "Input
// filter"): a two-flop synchronizer, a 3-bit shift register sampled once every
// floor(PRER/4)+1 clocks, and a registered 2-of-3 majority.
module fw_i2c_filter (
        input  wire        clock,
        input  wire        reset,
        input  wire [15:0] prer,
        input  wire        scl_i,
        input  wire        sda_i,
        output reg         scl_f,
        output reg         sda_f
    );
    reg [1:0]  c_scl, c_sda;
    reg [2:0]  f_scl, f_sda;
    reg [13:0] cnt;

    always @(posedge clock) begin
        if (reset) begin
            c_scl <= 2'b11;
            c_sda <= 2'b11;
            f_scl <= 3'b111;
            f_sda <= 3'b111;
            cnt   <= '0;
            scl_f <= 1'b1;
            sda_f <= 1'b1;
        end else begin
            c_scl <= {c_scl[0], scl_i};
            c_sda <= {c_sda[0], sda_i};
            if (cnt == '0) begin
                cnt   <= prer[15:2];
                f_scl <= {f_scl[1:0], c_scl[1]};
                f_sda <= {f_sda[1:0], c_sda[1]};
            end else begin
                cnt <= cnt - 14'd1;
            end
            scl_f <= (f_scl[2] & f_scl[1]) | (f_scl[1] & f_scl[0]) | (f_scl[2] & f_scl[0]);
            sda_f <= (f_sda[2] & f_sda[1]) | (f_sda[1] & f_sda[0]) | (f_sda[2] & f_sda[0]);
        end
    end
endmodule
