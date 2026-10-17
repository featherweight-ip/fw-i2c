// Writes: a multi-byte write, a single-byte write, and a pointer-only write
// (address and offset, then STOP). Checks the responder's memory and the bus.
class fw_i2c_write_test extends fw_i2c_base_test;
    `uvm_component_utils(fw_i2c_write_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        bit [7:0] wr[] = '{8'h01, 8'h23, 8'h45, 8'h67, 8'h89, 8'hAB, 8'hCD, 8'hEF};
        bit [7:0] one[] = '{8'h5A};
        bit [7:0] none[];
        phase.raise_objection(this);

        dev().configure(prer, 1'b1);
        write_mem(7'h50, 8'h20, wr);
        wait_idle("after the 8-byte write");
        write_mem(7'h50, 8'hFF, one);
        wait_idle("after the 1-byte write");
        write_mem(7'h50, 8'h80, none);
        wait_idle("after the pointer-only write");

        foreach (wr[i])
            check(env.tgt.peek(8'(8'h20 + i)) == wr[i],
                  $sformatf("target memory[0x%02h] = 0x%02h, expected 0x%02h",
                            8'h20 + i, env.tgt.peek(8'(8'h20 + i)), wr[i]));
        check(env.tgt.peek(8'hFF) == 8'h5A, "target memory[0xff]");
        check(env.tgt.ptr == 8'h80, $sformatf("target pointer 0x%02h, expected 0x80",
                                               env.tgt.ptr));
        check(env.tgt.mem.size() == 9, $sformatf("%0d bytes written, expected 9",
                                                  env.tgt.mem.size()));

        check_log("writes", {"S Aa0+ D20+ D01+ D23+ D45+ D67+ D89+ Dab+ Dcd+ Def+ P ",
                             "S Aa0+ Dff+ D5a+ P ",
                             "S Aa0+ D80+ P"});
        `uvm_info("WRITE", {"bus: ", env.log.str()}, UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass
