// D8, D10 (docs/reference/deviations.md): bus timing at the nominal
// prescaler for Standard mode (+I2C_MODE=sm, 100 kHz) or Fast mode
// (+I2C_MODE=fm, 400 kHz), PRER = f(clk) / (5 f(SCL)) - 1 with the bench's
// 100 MHz clock. One transfer with every bus condition: START, address,
// data, Sr, a read, STOP, and a second START after the bus-free time. The
// line timing is measured against UM10204 Table 10.
//
// Confirms: in Standard mode tSU;STA of the Sr is below the minimum; in both
// modes the master's tVD;DAT is above the maximum (D8); the SCL period is
// longer than the PDF formula 5 (PRER+1) / f(clk) (D10).
class fw_i2c_ref_timing_test extends fw_i2c_ref_base_test;
    `uvm_component_utils(fw_i2c_ref_timing_test)

    string mode = "sm";

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        void'($value$plusargs("I2C_MODE=%s", mode));
        prer = (mode == "fm") ? 16'd49 : 16'd199;
    endfunction

    task run_phase(uvm_phase phase);
        bit [7:0] wr[] = '{8'h3C};
        bit [7:0] rd[];
        realtime  formula = 5.0 * (prer + 1) * 10ns;
        i2c_timing_stat per, su_sta, vd_dat;
        phase.raise_objection(this);

        dev().configure(prer, 1'b1);
        probe.timing.enabled = 1;
        write_mem(7'h50, 8'h40, wr);
        wait_idle("after the write");
        read_mem(7'h50, 8'h40, 1, rd);
        wait_idle("after the read");
        probe.timing.enabled = 0;
        check(rd[0] == 8'h3C, $sformatf("read 0x%02h, expected 0x3c", rd[0]));
        check_log("timing", "S Aa0+ D40+ D3c+ P S Aa0+ D40+ Sr Aa1+ D3c- P");

        void'(probe.timing.report(mode, "TIMING"));
        per    = probe.timing.get("period");
        su_sta = probe.timing.get("tSU;STA");
        vd_dat = probe.timing.get("tVD;DAT");
        `uvm_info("TIMING", $sformatf("%s, PRER %0d: SCL period %.0f..%.0f ns, formula %.0f ns (x%.3f); f(SCL) %.1f kHz",
                                      mode, prer, per.min / 1ns, per.max / 1ns, formula / 1ns,
                                      per.max / formula, 1.0e6 / (per.max / 1ns)), UVM_LOW)

        // D8
        check(su_sta.n != 0, "no repeated START measured");
        if (mode == "sm")
            check(su_sta.max / 1ns < 4700,
                  $sformatf("D8 not confirmed: tSU;STA %.0f ns meets the minimum", su_sta.max / 1ns));
        check(vd_dat.max / 1ns > ((mode == "fm") ? 900 : 3450),
              $sformatf("D8 not confirmed: tVD;DAT %.0f ns meets the maximum", vd_dat.max / 1ns));
        // D10
        check(per.min > formula,
              $sformatf("D10 not confirmed: SCL period %.0f ns, formula %.0f ns", per.min / 1ns, formula / 1ns));
        phase.drop_objection(this);
    endtask
endclass
