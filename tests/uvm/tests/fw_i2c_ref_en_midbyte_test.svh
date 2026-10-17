// D6 (docs/reference/deviations.md): with CTR.EN = 0 the prescaler ticks
// every clock and nothing else looks at EN, so clearing EN in the middle of a
// byte runs the rest of it at wb_clk_i rate. The `!ena` branch of the clock
// enable also takes priority over slave_wait, so the core no longer waits for
// SCL to rise: as at PRER 0 (D7), it outruns its own input filter.
//
// Method: a byte at PRER 24; after its third SCL rise, CTR = 0. Confirms: SCL
// runs more than 4 times faster; within a few periods a STOP condition
// appears on the bus, and the command ends by arbitration lost (SR AL = 1,
// IF = 1) without a `done`; the byte never completes on the bus.
class fw_i2c_ref_en_midbyte_test extends fw_i2c_ref_base_test;
    `uvm_component_utils(fw_i2c_ref_en_midbyte_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        fw_i2c_result_s r;
        fw_i2c_check_s  st;
        realtime        p_en, p_dis;
        i2c_timing_stat per;
        int unsigned    rise0;
        realtime        t_dis;
        longint unsigned t_end;
        phase.raise_objection(this);

        prer = 16'd24;
        dev().configure(prer, 1'b1);
        dev().address(r, {7'h50, 1'b0});
        check_result("address", r);

        dev().write_byte_start(8'h5A, 1'b0);
        probe.timing.clear();
        probe.timing.enabled = 1;
        repeat (3) @(probe.timing.scl_rise_ev);
        per  = probe.timing.get("period");
        p_en = per.max;
        probe.timing.clear();
        rise0 = probe.timing.n_scl_rise;
        t_dis = $realtime;
        reg_write(32'(env.regs.CTR.addr()), 32'h0);
        poll_done("after EN = 0", st, 1000);
        t_end = probe.last_done_clk;
        probe.timing.enabled = 0;
        per   = probe.timing.get("period");
        p_dis = per.min;
        `uvm_info("D6", $sformatf("SCL period %.0f ns with EN = 1, %.0f..%.0f ns after EN = 0 (%0d periods, %0d SCL rises); done at clock %0d, EN cleared at %.0f ns, now %.0f ns; SR IF=%0d TIP=%0d AL=%0d; bus %s",
                                  p_en / 1ns, per.min / 1ns, per.max / 1ns, per.n,
                                  probe.timing.n_scl_rise - rise0, t_end, t_dis / 1ns, $realtime / 1ns,
                                  st.sr.irq_flag, st.sr.tip, st.sr.al, env.log.str()), UVM_LOW)
        check(st.done && st.sr.al,
              $sformatf("D6: the command did not end by arbitration lost (done=%0d AL=%0d)", st.done, st.sr.al));
        check(t_end < longint'(t_dis / 10ns), "D6: `done` pulsed after EN = 0");
        check_log("D6", "S Aa0+ P");
        check(per.n != 0, "no SCL period measured after EN = 0");
        check(per.max < p_en / 4,
              $sformatf("D6 not confirmed: SCL period %.0f ns after EN = 0, %.0f ns before",
                        per.max / 1ns, p_en / 1ns));
        phase.drop_objection(this);
    endtask
endclass
