// What the reference confirmation tests (bench-plan E3) see of R76 beyond
// its pins: a few internal signals, sampled every clock by the `ref` top
// (hvl_top_ref), the bus line timing, and the second master on its bus.
// Published as "ref_probe" by the `ref` view only.
//
//   done   the byte controller's command acknowledge (cmd_ack)
//   wacc   a WISHBONE write accepted (wb_we_i & wb_ack_o)
//   al     arbitration lost (i2c_al)
//   race   done and wacc in the same clock: D1
class i2c_ref_probe;
    longint unsigned  n_clk;
    int unsigned      n_done, n_wacc, n_race, n_al;
    longint unsigned  last_done_clk, last_wacc_clk, last_race_clk;
    event             clk_ev, done_ev;
    i2c_line_timing   timing;
    i2c_controller_if ctl;     // the second master (u_ctl), for D9

    function new(); timing = new(); endfunction

    function void tick(bit done, bit wacc, bit al);
        n_clk++;
        if (done) begin
            n_done++;
            last_done_clk = n_clk;
        end
        if (wacc) begin
            n_wacc++;
            last_wacc_clk = n_clk;
        end
        if (done && wacc) begin
            n_race++;
            last_race_clk = n_clk;
        end
        if (al) n_al++;
        -> clk_ev;
        if (done) -> done_ev;
    endfunction

    task wait_clocks(int unsigned n); repeat (n) @(clk_ev); endtask
endclass
