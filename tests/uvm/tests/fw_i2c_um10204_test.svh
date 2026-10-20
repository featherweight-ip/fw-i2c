// Bus timing of the design under test against UM10204 Table 10, at the
// nominal prescaler for Standard mode (+I2C_MODE=sm, 100 kHz) or Fast mode
// (+I2C_MODE=fm, 400 kHz) with the bench's 100 MHz clock. For views whose top
// publishes an i2c_line_timing ("line_timing"): the fw-i2c pin view. This is
// the fw-i2c side of D8 and D10 (OI-6, design §8.1): every parameter within
// its limit, and the shortest SCL period (a bit with no stall) as the PDF
// formula 5 (PRER+1) / f(clk), plus at most `max_lag_clocks` of input
// latency. Longer periods are stalls: the kit core leaves SCL high between
// commands while software issues the next one (R76 holds it low).
class fw_i2c_um10204_test extends fw_i2c_base_test;
    `uvm_component_utils(fw_i2c_um10204_test)

    string          mode = "sm";
    i2c_line_timing timing;
    int unsigned    max_lag_clocks = 6;   // +MAX_LAG_CLOCKS=<n>

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(i2c_line_timing)::get(this, "", "line_timing", timing))
            `uvm_fatal("CFG", "no \"line_timing\": this test needs a view that measures the bus lines")
        void'($value$plusargs("I2C_MODE=%s", mode));
        void'($value$plusargs("MAX_LAG_CLOCKS=%d", max_lag_clocks));
        prer = (mode == "fm") ? 16'd49 : 16'd199;
    endfunction

    task run_phase(uvm_phase phase);
        bit [7:0] wr[] = '{8'h3C};
        bit [7:0] rd[];
        realtime  formula = 5.0 * (prer + 1) * 10ns;
        i2c_timing_stat per;
        bit ok;
        phase.raise_objection(this);

        dev().configure(prer, 1'b1);
        timing.enabled = 1;
        write_mem(7'h50, 8'h40, wr);
        wait_idle("after the write");
        read_mem(7'h50, 8'h40, 1, rd);
        wait_idle("after the read");
        timing.enabled = 0;
        check(rd[0] == 8'h3C, $sformatf("read 0x%02h, expected 0x3c", rd[0]));
        check_log("UM10204", "S Aa0+ D40+ D3c+ P S Aa0+ D40+ Sr Aa1+ D3c- P");

        ok  = timing.report(mode, "UM10204");
        per = timing.get("period");
        `uvm_info("UM10204", $sformatf("%s, PRER %0d: SCL period %.0f..%.0f ns, formula %.0f ns (x%.3f..%.3f)",
                                       mode, prer, per.min / 1ns, per.max / 1ns, formula / 1ns,
                                       per.min / formula, per.max / formula), UVM_LOW)
        check(ok, $sformatf("bus timing outside UM10204 %s-mode limits", mode));
        check(per.min >= formula && per.min <= formula + max_lag_clocks * 10ns,
              $sformatf("shortest SCL period %.0f ns, not within %.0f..%.0f ns (the formula plus %0d clocks)",
                        per.min / 1ns, formula / 1ns, (formula + max_lag_clocks * 10ns) / 1ns,
                        max_lag_clocks));
        phase.drop_objection(this);
    endtask
endclass
