// Equivalence self-test (bench-plan §3.4, E4), on an equivalence view only:
// the mirror inverts R76's ACK of one data byte. Both scoreboards must catch
// it, and the first difference each reports must name that byte: write_byte's
// RXACK in the operation compare, D5a+ against D5a- in the bus compare. SR.RXACK
// is sticky, so the status reads that follow differ too until the next
// transfer; a clean transfer after that must add no difference. Differences
// are reported as information (expect_mismatch) and counted.
class fw_i2c_eq_sabotage_test extends fw_i2c_base_test;
    `uvm_component_utils(fw_i2c_eq_sabotage_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        bit [7:0] wr[] = '{8'h5A};
        bit [7:0] rd[];
        int unsigned n_op, n_bus;
        phase.raise_objection(this);
        if (!env.eq) `uvm_fatal("EQSELF", "this test needs an equivalence view (a \"ref_model\")")
        env.expect_mismatch();

        dev().configure(prer, 1'b1);
        // Decisions: 1 the address, 2 the offset, 3 the data byte.
        env.mirror.sabotage_at = 3;
        write_mem(7'h50, 8'h10, wr);
        env.mirror.sabotage_at = 0;
        check(env.op_eq.rpt.n_mismatch == 1,
              $sformatf("operation differences after the write: %0d, expected 1",
                        env.op_eq.rpt.n_mismatch));
        check(env.cmp.rpt.n_mismatch == 1,
              $sformatf("bus differences after the write: %0d, expected 1", env.cmp.rpt.n_mismatch));
        check(match(env.op_eq.rpt.first, "write_byte(0x5a, stop=1)") &&
              match(env.op_eq.rpt.first, "RXACK=0") && match(env.op_eq.rpt.first, "RXACK=1"),
              {"first operation difference: ", env.op_eq.rpt.first});
        check(match(env.cmp.rpt.first, "DUT D5a+, R76 D5a-"),
              {"first bus difference: ", env.cmp.rpt.first});
        wait_idle("after the sabotaged write");

        // A clean transfer: the address phase clears RXACK on both.
        n_op  = env.op_eq.rpt.n_mismatch;
        n_bus = env.cmp.rpt.n_mismatch;
        read_mem(7'h50, 8'h10, 1, rd);
        wait_idle("after the clean read");
        check(rd[0] == 8'h5A, $sformatf("read 0x%02h, expected 0x5a", rd[0]));
        check(env.op_eq.rpt.n_mismatch == n_op,
              $sformatf("the clean read added %0d operation difference(s)",
                        env.op_eq.rpt.n_mismatch - n_op));
        check(env.cmp.rpt.n_mismatch == n_bus,
              $sformatf("the clean read added %0d bus difference(s)", env.cmp.rpt.n_mismatch - n_bus));
        phase.drop_objection(this);
    endtask

    // 1 if `sub` occurs in `s`.
    function bit match(string s, string sub);
        for (int i = 0; i + sub.len() <= s.len(); i++)
            if (s.substr(i, i + sub.len() - 1) == sub) return 1'b1;
        return 1'b0;
    endfunction

    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        // The env's end-of-test checks (leftover events or decisions) run
        // first, bottom-up, and would have added to these counts.
        check(env.cmp.rpt.n_mismatch == 1,
              $sformatf("bus differences at the end: %0d, expected 1", env.cmp.rpt.n_mismatch));
        check(env.mirror.rpt.n_mismatch == 0,
              $sformatf("responder differences: %0d, expected 0", env.mirror.rpt.n_mismatch));
    endfunction
endclass
