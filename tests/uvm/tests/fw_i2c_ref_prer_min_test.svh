// D7 (docs/reference/deviations.md): the minimum PRER. Run with +PRER=1 or
// +PRER=0: a write of one data byte with STOP, each command polled.
//
// Confirms: with PRER = 1 the core reports arbitration lost against a single
// target on the first address byte (SR = 0x61 at completion: BUSY, AL, IF),
// and the bus carries only the START. With PRER = 0 every command ends in
// arbitration lost and no byte reaches the bus, only START, Sr and STOP
// conditions.
class fw_i2c_ref_prer_min_test extends fw_i2c_ref_base_test;
    `uvm_component_utils(fw_i2c_ref_prer_min_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task step(string what, output fw_i2c_check_s st);
        poll_done(what, st, 2000);
        `uvm_info("D7", $sformatf("PRER %0d, %s: done=%0d SR {RXACK=%0d BUSY=%0d AL=%0d TIP=%0d IF=%0d}",
                                  prer, what, st.done, st.sr.rxack, st.sr.busy, st.sr.al,
                                  st.sr.tip, st.sr.irq_flag), UVM_LOW)
    endtask

    task run_phase(uvm_phase phase);
        fw_i2c_check_s st_a, st_o, st_d;
        phase.raise_objection(this);
        if (prer > 1) `uvm_fatal("D7", "run with +PRER=0 or +PRER=1")

        dev().configure(prer, 1'b0);
        dev().address_start({7'h50, 1'b0});
        step("address", st_a);
        check(st_a.done && st_a.sr.al && st_a.sr.busy,
              $sformatf("D7 not confirmed: no arbitration loss on the address byte at PRER %0d", prer));
        if (prer == 0) begin
            dev().write_byte_start(8'h60, 1'b0);
            step("offset", st_o);
            check(st_o.done && st_o.sr.al, "D7 not confirmed: no arbitration loss on the offset at PRER 0");
            dev().write_byte_start(8'hA7, 1'b1);
            step("data + STOP", st_d);
            check(st_d.done && st_d.sr.al, "D7 not confirmed: no arbitration loss on the data at PRER 0");
        end
        probe.wait_clocks(2000);
        `uvm_info("D7", $sformatf("PRER %0d: bus %s; %0d done pulses, %0d AL pulses", prer,
                                  env.log.str(), probe.n_done, probe.n_al), UVM_LOW)
        check(count_log("D") + count_log("A") == 0,
              $sformatf("D7 not confirmed: a byte reached the bus at PRER %0d (%s)", prer, env.log.str()));
        check(probe.n_done == 0,
              $sformatf("D7 not confirmed: %0d commands completed without AL at PRER %0d", probe.n_done, prer));
        phase.drop_objection(this);
    endtask
endclass
