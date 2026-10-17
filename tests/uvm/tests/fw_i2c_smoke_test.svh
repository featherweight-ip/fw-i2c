// Smoke: set up, write three bytes, read them back with a repeated START,
// then check the data, the responder's memory and the bus event stream.
class fw_i2c_smoke_test extends fw_i2c_base_test;
    `uvm_component_utils(fw_i2c_smoke_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        bit [7:0] wr[] = '{8'h11, 8'h22, 8'h33};
        bit [7:0] rd[];
        fw_i2c_result_s r;
        phase.raise_objection(this);

        dev().configure(prer, 1'b1);
        write_mem(7'h50, 8'h10, wr);
        read_mem(7'h50, 8'h10, 3, rd);

        foreach (wr[i]) begin
            check(rd[i] == wr[i], $sformatf("read-back[%0d] = 0x%02h, expected 0x%02h",
                                            i, rd[i], wr[i]));
            check(env.tgt.peek(8'(8'h10 + i)) == wr[i],
                  $sformatf("target memory[0x%02h] = 0x%02h, expected 0x%02h",
                            8'h10 + i, env.tgt.peek(8'(8'h10 + i)), wr[i]));
        end

        // An address nobody answers: NACK at the address byte, then STOP.
        dev().address(r, {7'h33, 1'b0});
        check_result("unanswered address", r, 1'b1);
        dev().stop(r);
        check(r.sr.al == 0 && r.sr.irq_flag == 1, "stop after NACK");

        // BUSY clears when the core's filtered STOP detector sees the STOP on
        // the bus, which is after the STOP command's IF: R76 reads BUSY = 1
        // right after `stop` completes. Poll, bounded.
        begin
            int n = 0;
            do begin
                dev().read_status(r);
                n++;
            end while (r.sr.busy && n < 100);
            check(r.sr.busy == 0, "bus not idle 100 status reads after the STOP");
            `uvm_info("SMOKE", $sformatf("BUSY cleared after %0d status reads", n), UVM_LOW)
        end

        begin
            // Address bytes: 0x50 << 1 = a0 (write), a1 (read); 0x33 << 1 = 66.
            string exp = {"S Aa0+ D10+ D11+ D22+ D33+ P ",
                          "S Aa0+ D10+ Sr Aa1+ D11+ D22+ D33- P ",
                          "S A66- P"};
            check(env.log.str() == exp,
                  $sformatf("bus log:\n  got      %s\n  expected %s", env.log.str(), exp));
        end
        `uvm_info("SMOKE", {"bus: ", env.log.str()}, UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass
