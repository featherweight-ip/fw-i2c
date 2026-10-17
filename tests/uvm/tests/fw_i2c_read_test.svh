// Reads: a repeated-START read (set the pointer, Sr, read), a current-address
// read (no pointer write) that continues where the last one stopped, and a
// single-byte read. Every read NACKs its last byte.
class fw_i2c_read_test extends fw_i2c_base_test;
    `uvm_component_utils(fw_i2c_read_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void check_data(string what, bit [7:0] off, bit [7:0] data[]);
        foreach (data[i])
            check(data[i] == env.tgt.peek(8'(off + i)),
                  $sformatf("%s[%0d] = 0x%02h, expected 0x%02h", what, i, data[i],
                            env.tgt.peek(8'(off + i))));
    endfunction

    task run_phase(uvm_phase phase);
        bit [7:0] wr[] = '{8'h3C, 8'hC3, 8'h00, 8'hFF};
        bit [7:0] rd[];
        fw_i2c_result_s r;
        int log0;
        phase.raise_objection(this);

        dev().configure(prer, 1'b1);
        write_mem(7'h50, 8'h40, wr);
        wait_idle("after the write");
        log0 = env.log.events.size();

        // Repeated-START read of what was written, and two bytes past it
        // (the responder's initial contents).
        read_mem(7'h50, 8'h40, 6, rd);
        check_data("Sr read", 8'h40, rd);
        foreach (wr[i]) check(rd[i] == wr[i], $sformatf("Sr read[%0d] != written", i));
        wait_idle("after the Sr read");

        // Current-address read: carries on from 0x46.
        dev().address(r, {7'h50, 1'b1});
        check_result("current-address read: address", r);
        read_bytes("current-address read", 3, rd);
        check_data("current-address read", 8'h46, rd);
        wait_idle("after the current-address read");

        // One byte, NACKed straight away.
        read_mem(7'h50, 8'h41, 1, rd);
        check(rd[0] == 8'hC3, $sformatf("1-byte read 0x%02h, expected 0xc3", rd[0]));

        check_log("reads",
                  $sformatf({"S Aa0+ D40+ Sr Aa1+ D3c+ Dc3+ D00+ Dff+ D%02h+ D%02h- P ",
                             "S Aa1+ D%02h+ D%02h+ D%02h- P ",
                             "S Aa0+ D41+ Sr Aa1+ Dc3- P"},
                            env.tgt.peek(8'h44), env.tgt.peek(8'h45),
                            env.tgt.peek(8'h46), env.tgt.peek(8'h47), env.tgt.peek(8'h48)),
                  log0);
        `uvm_info("READ", {"bus: ", env.log.str(log0)}, UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass
