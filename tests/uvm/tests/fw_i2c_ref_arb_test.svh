// D9 (docs/reference/deviations.md): arbitration. R76 and a second master
// (the kit's controller transactor on the same bus) start together with the
// same address byte, then:
//
//   A  diverge on the next byte, R76 sending the 1: R76 must lose (SR.AL),
//      the other master finishes alone;
//   B  diverge the other way: the other master must lose, R76 finishes;
//   C  agree on the next byte, then R76 sends STOP while the other master
//      sends a data byte starting with 0. R76 checks arbitration only during
//      the bits it transmits, so it does not see that its STOP never
//      reached the bus: STOP completes with AL = 0 and BUSY still 1.
//
// Every case ends with the bus free and the target's memory as the winner
// wrote it.
class fw_i2c_ref_arb_test extends fw_i2c_ref_base_test;
    `uvm_component_utils(fw_i2c_ref_arb_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    // Both masters: START + address 0x50 (write), in parallel.
    task both_address(string what);
        fw_i2c_result_s r;
        bit ack, al;
        fork
            dev().address(r, {7'h50, 1'b0});
            probe.ctl.start(10'h50, 1'b0, 1'b0, 1'b0, ack, al);
        join
        check_result({what, ": R76 address"}, r);
        check(ack && !al, $sformatf("%s: other master's address: ack=%0d al=%0d", what, ack, al));
    endtask

    task run_phase(uvm_phase phase);
        fw_i2c_result_s r;
        bit ack, al;
        int log0;
        phase.raise_objection(this);

        dev().configure(prer, 1'b1);
        probe.ctl.set_prescale(prer);

        // ---- A: R76 sends 0xFF, the other master 0x0F: R76 loses ----
        log0 = env.log.events.size();
        both_address("A");
        fork
            dev().write_byte(r, 8'hFF, 1'b0);
            probe.ctl.tx_byte(8'h0F, ack, al);
        join
        check(r.sr.al == 1, $sformatf("A: R76 did not lose arbitration (AL=%0d)", r.sr.al));
        check(!al && ack, $sformatf("A: other master: ack=%0d al=%0d", ack, al));
        probe.ctl.tx_byte(8'h11, ack, al);
        probe.ctl.stop();
        wait_idle("A: after the other master's STOP");
        check(env.tgt.peek(8'h0F) == 8'h11, "A: the winner's byte is not in the target");
        `uvm_info("D9", {"A: bus ", env.log.str(log0)}, UVM_LOW)
        check_log("A", "S Aa0+ D0f+ D11+ P", log0);

        // ---- B: R76 sends 0x10, the other master 0x90: the other loses ----
        log0 = env.log.events.size();
        both_address("B");
        fork
            dev().write_byte(r, 8'h10, 1'b0);
            probe.ctl.tx_byte(8'h90, ack, al);
        join
        check_result("B: R76 offset", r);
        check(al, "B: the other master did not lose arbitration");
        dev().write_byte(r, 8'h77, 1'b1);
        check_result("B: R76 data + STOP", r);
        wait_idle("B: after R76's STOP");
        check(env.tgt.peek(8'h10) == 8'h77, "B: the winner's byte is not in the target");
        `uvm_info("D9", {"B: bus ", env.log.str(log0)}, UVM_LOW)
        check_log("B", "S Aa0+ D10+ D77+ P", log0);

        // ---- C: R76's STOP against the other master's data bit 0 ----
        log0 = env.log.events.size();
        both_address("C");
        fork
            dev().write_byte(r, 8'h20, 1'b0);
            probe.ctl.tx_byte(8'h20, ack, al);
        join
        check_result("C: R76 offset", r);
        check(ack && !al, $sformatf("C: other master's offset: ack=%0d al=%0d", ack, al));
        fork
            dev().stop(r);
            probe.ctl.tx_byte(8'h00, ack, al);
        join
        `uvm_info("D9", $sformatf("C: R76 STOP result {AL=%0d BUSY=%0d IF=%0d}; other master's byte ack=%0d al=%0d",
                                  r.sr.al, r.sr.busy, r.sr.irq_flag, ack, al), UVM_LOW)
        check(r.sr.irq_flag && !r.sr.al,
              "D9 not confirmed: R76 detected the STOP collision (AL)");
        check(r.sr.busy, "C: BUSY clear after R76's STOP: a STOP reached the bus");
        probe.ctl.stop();
        wait_idle("C: after the other master's STOP");
        check(env.tgt.peek(8'h20) == 8'h00, "C: the other master's byte is not in the target");
        `uvm_info("D9", {"C: bus ", env.log.str(log0)}, UVM_LOW)
        check_log("C", "S Aa0+ D20+ D00+ P", log0);
        phase.drop_objection(this);
    endtask
endclass
