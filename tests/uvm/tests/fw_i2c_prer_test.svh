// PRER sweep: the same write and read back at several prescaler values (all
// at least 2: D7). Data and bus events must not depend on PRER. On a timed
// view the transfer time must grow with PRER, roughly as PRER + 1.
class fw_i2c_prer_test extends fw_i2c_base_test;
    `uvm_component_utils(fw_i2c_prer_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        bit [15:0] prers[] = '{16'd2, 16'd4, 16'd9, 16'd24};
        realtime   dur[];
        string     exp = "";
        phase.raise_objection(this);

        dur = new[prers.size()];
        foreach (prers[k]) begin
            bit [7:0] wr[] = '{8'(8'h10 * k), 8'(8'h10 * k + 1), 8'(8'h10 * k + 2)};
            bit [7:0] rd[];
            bit [7:0] off = 8'(8'h50 + 8'h10 * k);
            realtime  t0;

            if (k != 0) dev().shutdown();
            dev().configure(prers[k], 1'b1);
            t0 = $realtime;
            write_mem(7'h50, off, wr);
            dur[k] = $realtime - t0;
            wait_idle($sformatf("PRER %0d: after the write", prers[k]));
            read_mem(7'h50, off, wr.size(), rd);
            wait_idle($sformatf("PRER %0d: after the read", prers[k]));
            foreach (wr[i])
                check(rd[i] == wr[i], $sformatf("PRER %0d: read[%0d] = 0x%02h, expected 0x%02h",
                                                prers[k], i, rd[i], wr[i]));
            exp = {exp, (k == 0) ? "" : " ",
                   $sformatf("S Aa0+ D%02h+ D%02h+ D%02h+ D%02h+ P ", off, wr[0], wr[1], wr[2]),
                   $sformatf("S Aa0+ D%02h+ Sr Aa1+ D%02h+ D%02h+ D%02h- P", off, wr[0], wr[1], wr[2])};
            `uvm_info("PRER", $sformatf("PRER %0d: 4-byte write took %0t", prers[k], dur[k]), UVM_LOW)
        end
        check_log("PRER sweep", exp);

        if (env.model.timed()) begin
            foreach (prers[k]) if (k != 0) begin
                real got  = dur[k] / dur[0];
                real want = real'(prers[k] + 1) / real'(prers[0] + 1);
                check(dur[k] > dur[k-1],
                      $sformatf("PRER %0d took no longer than PRER %0d", prers[k], prers[k-1]));
                check(got > 0.5 * want && got < 1.5 * want,
                      $sformatf("PRER %0d / PRER %0d: time ratio %.2f, expected about %.2f",
                                prers[k], prers[0], got, want));
                `uvm_info("PRER", $sformatf("PRER %0d / PRER %0d: time ratio %.2f (PRER+1 ratio %.2f)",
                                            prers[k], prers[0], got, want), UVM_LOW)
            end
        end
        phase.drop_objection(this);
    endtask
endclass
