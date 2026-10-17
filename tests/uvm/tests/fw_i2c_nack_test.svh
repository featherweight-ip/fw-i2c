// NACKs: an unanswered write address and read address, each ended with a STOP
// on its own; a data byte NACKed by the target in the middle of a write; and
// a normal transfer afterwards. (The master's own NACK of the last read byte
// is in every read.)
class fw_i2c_nack_test extends fw_i2c_base_test;
    `uvm_component_utils(fw_i2c_nack_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        bit [7:0] rd[];
        bit [7:0] wr[] = '{8'h99};
        fw_i2c_result_s r;
        phase.raise_objection(this);

        dev().configure(prer, 1'b1);

        // Nobody at 0x33, write and read direction.
        dev().address(r, {7'h33, 1'b0});
        check_result("unanswered write address", r, 1'b1);
        dev().stop(r);
        check(r.sr.al == 0 && r.sr.irq_flag == 1, "stop after the write-address NACK");
        wait_idle("after the write-address NACK");
        dev().address(r, {7'h33, 1'b1});
        check_result("unanswered read address", r, 1'b1);
        dev().stop(r);
        check(r.sr.al == 0 && r.sr.irq_flag == 1, "stop after the read-address NACK");
        wait_idle("after the read-address NACK");

        // The target NACKs the second data byte of the write (the first is the
        // pointer). The byte is not stored; the master stops.
        env.tgt.nack_wr_at = 2;
        dev().address(r, {7'h50, 1'b0});
        check_result("write: address", r);
        dev().write_byte(r, 8'h60, 1'b0);
        check_result("write: offset", r);
        dev().write_byte(r, 8'h77, 1'b0);
        check_result("write: NACKed data byte", r, 1'b1);
        dev().stop(r);
        check(r.sr.al == 0 && r.sr.irq_flag == 1, "stop after the data NACK");
        wait_idle("after the data NACK");
        check(!env.tgt.mem.exists(8'h60), "the NACKed byte was stored");
        env.tgt.nack_wr_at = 0;

        // The core carries on normally.
        write_mem(7'h50, 8'h60, wr);
        wait_idle("after the write");
        read_mem(7'h50, 8'h60, 1, rd);
        check(rd[0] == 8'h99, $sformatf("read back 0x%02h, expected 0x99", rd[0]));

        check_log("NACKs", {"S A66- P S A67- P ",
                            "S Aa0+ D60+ D77- P ",
                            "S Aa0+ D60+ D99+ P ",
                            "S Aa0+ D60+ Sr Aa1+ D99- P"});
        `uvm_info("NACK", {"bus: ", env.log.str()}, UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass
