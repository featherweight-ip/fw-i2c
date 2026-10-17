// Clock stretching: the responder takes time over every decision, which the
// target holds SCL low for. The same write and read run first without, then
// with a latency as long as the whole unstretched transfer. Data and bus
// events must be the same. On a timed view, every decision must add about its
// latency: a stretch starts while SCL is already low, so it absorbs the part
// of that low time the core would have spent anyway, and the bound is 90%.
class fw_i2c_stretch_test extends fw_i2c_base_test;
    `uvm_component_utils(fw_i2c_stretch_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    // Write 2 bytes and read them back: 2 + 4 decisions for the write
    // (address, offset, 2 data), 1 + 1 + 1 + 2 for the read (address, offset,
    // Sr address, then a tx_byte per byte). Returns the elapsed time.
    task xfer(bit [7:0] off, bit [7:0] wr[], output realtime dur);
        bit [7:0] rd[];
        realtime  t0 = $realtime;
        write_mem(7'h50, off, wr);
        read_mem(7'h50, off, wr.size(), rd);
        dur = $realtime - t0;
        foreach (wr[i])
            check(rd[i] == wr[i], $sformatf("read[%0d] = 0x%02h, expected 0x%02h", i, rd[i], wr[i]));
        wait_idle("after the transfer");
    endtask

    task run_phase(uvm_phase phase);
        localparam int N_DECISIONS = 4 + 5;
        bit [7:0] wr0[] = '{8'h12, 8'h34};
        bit [7:0] wr1[] = '{8'h56, 8'h78};
        realtime  d0, d1;
        int       log0;
        phase.raise_objection(this);

        dev().configure(prer, 1'b1);
        xfer(8'h70, wr0, d0);
        log0 = env.log.events.size();

        env.tgt.latency = time'(d0);
        xfer(8'h70, wr1, d1);

        check_log("stretched transfer",
                  "S Aa0+ D70+ D56+ D78+ P S Aa0+ D70+ Sr Aa1+ D56+ D78- P", log0);
        `uvm_info("STRETCH", $sformatf("unstretched %0t, stretched %0t (latency %0t x %0d decisions)",
                                        d0, d1, env.tgt.latency, N_DECISIONS), UVM_LOW)
        if (env.model.timed())
            check(d1 - d0 >= 0.9 * N_DECISIONS * env.tgt.latency,
                  $sformatf("stretching added %0t, expected about %0t",
                            d1 - d0, N_DECISIONS * env.tgt.latency));
        env.tgt.latency = 0;
        phase.drop_objection(this);
    endtask
endclass
