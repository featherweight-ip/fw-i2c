// IF, IACK and the interrupt line. With IEN = 0 the operations run polled
// (the _start halves and completion_check): IF sets on every completion and
// the line stays low. Setting IEN with IF pending raises the line; IACK on its
// own clears IF and the line; clearing IEN drops the line with IF still set.
// Then the blocking operations run on interrupts.
class fw_i2c_irq_test extends fw_i2c_base_test;
    `uvm_component_utils(fw_i2c_irq_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    // Status reads: a few clocks for the line to follow IF (R76 registers IF,
    // then the line).
    task settle();
        fw_i2c_result_s r;
        repeat (2) dev().read_status(r);
    endtask

    function void check_irq(string what, bit exp);
        check(env.model.irq_level() == exp,
              $sformatf("%s: interrupt line %0d, expected %0d", what,
                        env.model.irq_level(), exp));
    endfunction

    // Poll an operation started with a _start half to completion; the line
    // must stay low throughout (IEN = 0).
    task poll(string what, bit exp_rxack = 0);
        fw_i2c_check_s  st;
        fw_i2c_result_s r;
        int n = 0;
        do begin
            dev().completion_check(st);
            check_irq($sformatf("%s, poll %0d", what, n), 1'b0);
            n++;
        end while (!st.done && n < 10000);
        r.sr = st.sr;
        check_result(what, r, exp_rxack);
    endtask

    task run_phase(uvm_phase phase);
        fw_i2c_result_s    r;
        fw_i2c_regs__CTR_s ctr;
        fw_i2c_regs__CR_s  cr;
        bit [7:0] wr[] = '{8'hC3};
        phase.raise_objection(this);

        // ---- polled, IEN = 0 ----
        dev().configure(prer, 1'b0);
        dev().address_start({7'h50, 1'b0});
        poll("polled address");
        dev().write_byte_start(8'h30, 1'b0);
        poll("polled offset");
        dev().write_byte_start(8'h5A, 1'b1);
        poll("polled data + STOP");
        settle();
        check_irq("IF set, IEN = 0", 1'b0);

        // ---- IEN with IF pending raises the line ----
        ctr = '0;
        ctr.EN  = 1'b1;
        ctr.IEN = 1'b1;
        env.regs.CTR.write(ctr);
        settle();
        check_irq("IF set, IEN = 1", 1'b1);
        dev().read_status(r);
        check(r.sr.irq_flag == 1, "IF cleared by the CTR write");

        // ---- IACK alone clears IF and the line ----
        cr = '0;
        cr.IACK = 1'b1;
        env.regs.CR.write(cr);
        settle();
        check_irq("after IACK", 1'b0);
        dev().read_status(r);
        check(r.sr.irq_flag == 0, "IF not cleared by IACK");
        wait_idle("after the polled write");

        // ---- interrupt-driven operations ----
        write_mem(7'h50, 8'h31, wr);
        settle();
        check_irq("after an interrupt-driven write", 1'b1);

        // ---- clearing IEN drops the line; IF stays ----
        ctr.IEN = 1'b0;
        env.regs.CTR.write(ctr);
        settle();
        check_irq("IF set, IEN cleared", 1'b0);
        dev().read_status(r);
        check(r.sr.irq_flag == 1, "IF cleared by clearing IEN");

        check(env.tgt.peek(8'h30) == 8'h5A, "target memory[0x30]");
        check(env.tgt.peek(8'h31) == 8'hC3, "target memory[0x31]");
        check_log("IRQ", "S Aa0+ D30+ D5a+ P S Aa0+ D31+ Dc3+ P");
        phase.drop_objection(this);
    endtask
endclass
