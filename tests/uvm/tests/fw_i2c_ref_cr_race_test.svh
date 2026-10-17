// D1 (docs/reference/deviations.md): a WISHBONE write accepted in the clock
// where the byte controller pulses `done` skips the command-bit clear, and
// the command runs again.
//
// Method: a write of N data bytes; for each, a TXR write (the next byte, as
// software that preloads it would) timed to land a sweep of offsets around
// the clock `done` is expected in. The probe says which writes hit the clock.
// Each hit must put one extra byte on the bus, the TXR value just written;
// a miss must put none.
class fw_i2c_ref_cr_race_test extends fw_i2c_ref_base_test;
    `uvm_component_utils(fw_i2c_ref_cr_race_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        fw_i2c_result_s  r;
        fw_i2c_check_s   st;
        longint unsigned c0, c_call;
        int unsigned     t_done, lat;
        int unsigned     hits = 0, misses = 0, extra_ok = 0;
        string           exp = "S Aa0+ D00+";
        phase.raise_objection(this);

        dev().configure(prer, 1'b1);
        dev().address(r, {7'h50, 1'b0});
        check_result("address", r);

        // Calibrate: clocks from a byte's start to its `done`, and from a
        // register write call to its acceptance.
        dev().write_byte_start(8'h00, 1'b0);
        c0 = probe.n_clk;
        @(probe.done_ev);
        t_done = int'(probe.last_done_clk - c0);
        poll_done("calibration byte", st);
        c_call = probe.n_clk;
        reg_write(32'(env.regs.TXR.addr()), 32'h0);
        probe.wait_clocks(1);                 // let the probe sample the accepting clock
        lat = int'(probe.last_wacc_clk - c_call);
        `uvm_info("D1", $sformatf("PRER %0d: done %0d clocks after the CR write; a register write lands %0d clocks after the call",
                                  prer, t_done, lat), UVM_LOW)

        for (int d = -8; d <= 8; d++) begin
            bit [7:0] data = 8'(8'h10 + d + 8);
            bit [7:0] next = 8'(8'hC0 + d + 8);
            int unsigned race0 = probe.n_race;
            int          log0  = env.log.events.size();
            int          wait_n = int'(t_done) - int'(lat) + d;

            dev().write_byte_start(data, 1'b0);
            if (wait_n > 0) probe.wait_clocks(wait_n);
            reg_write(32'(env.regs.TXR.addr()), {24'h0, next});
            poll_done($sformatf("offset %0d", d), st);
            check(st.done && !st.sr.al, $sformatf("offset %0d: not complete, or AL", d));
            probe.wait_clocks(2 * (prer + 1));   // the monitor reports the ACK bit after SCL falls
            if (probe.n_race != race0) begin
                hits++;
                exp = {exp, $sformatf(" D%02h+ D%02h+", data, next)};
                if (env.log.str(log0) == $sformatf("D%02h+ D%02h+", data, next)) extra_ok++;
                `uvm_info("D1", $sformatf("offset %0d: write in the done clock; bus %s", d, env.log.str(log0)), UVM_LOW)
            end else begin
                misses++;
                exp = {exp, $sformatf(" D%02h+", data)};
                check(env.log.str(log0) == $sformatf("D%02h+", data),
                      $sformatf("offset %0d (no race): bus %s, expected D%02h+", d, env.log.str(log0), data));
            end
        end
        dev().stop(r);
        wait_idle("after the STOP");
        exp = {exp, " P"};
        check_log("D1", exp);

        `uvm_info("D1", $sformatf("%0d of %0d timed writes hit the done clock; %0d of them repeated the byte",
                                  hits, hits + misses, extra_ok), UVM_LOW)
        check(hits != 0, "D1 not exercised: no write landed in the done clock");
        check(extra_ok == hits, "D1 not confirmed: a write in the done clock did not repeat the byte");
        phase.drop_objection(this);
    endtask
endclass
