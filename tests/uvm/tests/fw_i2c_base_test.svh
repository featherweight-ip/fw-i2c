// Base test: builds the env, counts check failures, reports the verdict.
// Helpers wrap common transfers in terms of the operation model.
class fw_i2c_base_test extends uvm_test;
    `uvm_component_utils(fw_i2c_base_test)

    fw_i2c_env   env;
    int unsigned errors;

    // A prescaler that keeps runs short: SCL at f(clk) / (5 * (PRER+1)).
    bit [15:0] prer = 16'd4;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = fw_i2c_env::type_id::create("env", this);
    endfunction

    function fw_i2c_c_ctxt_if dev(); return env.dev(); endfunction

    function void check(bit cond, string what);
        if (!cond) begin
            errors++;
            `uvm_error("CHECK", what)
        end
    endfunction

    // Check an operation's result: the core reports completion, no
    // arbitration loss, and the expected acknowledge.
    function void check_result(string what, fw_i2c_result_s r, bit exp_rxack = 0);
        check(r.sr.irq_flag == 1 && r.sr.tip == 0,
              $sformatf("%s: not complete (IF=%0d TIP=%0d)", what, r.sr.irq_flag, r.sr.tip));
        check(r.sr.al == 0, $sformatf("%s: arbitration lost", what));
        check(r.sr.rxack == exp_rxack,
              $sformatf("%s: RXACK=%0d, expected %0d", what, r.sr.rxack, exp_rxack));
    endfunction

    // Write bytes to the target's memory at `off`: S A(W) off data... P.
    task write_mem(bit [6:0] addr7, bit [7:0] off, bit [7:0] data[]);
        fw_i2c_result_s r;
        dev().address(r, {addr7, 1'b0});
        check_result("write: address", r);
        dev().write_byte(r, off, data.size() == 0);
        check_result("write: offset", r);
        foreach (data[i]) begin
            dev().write_byte(r, data[i], i == data.size() - 1);
            check_result($sformatf("write: data[%0d]", i), r);
        end
    endtask

    // Read n bytes from `off`: S A(W) off Sr A(R) data... P, NACKing the last.
    task read_mem(bit [6:0] addr7, bit [7:0] off, int n, output bit [7:0] data[]);
        fw_i2c_result_s r;
        data = new[n];
        dev().address(r, {addr7, 1'b0});
        check_result("read: address", r);
        dev().write_byte(r, off, 1'b0);
        check_result("read: offset", r);
        dev().address(r, {addr7, 1'b1});
        check_result("read: Sr address", r);
        for (int i = 0; i < n; i++) begin
            bit last = (i == n - 1);
            dev().read_byte(r, last, last);
            // After a read, RXACK is the bit the core sent itself (CR.ACK).
            check_result($sformatf("read: data[%0d]", i), r, last);
            data[i] = r.data;
        end
    endtask

    function void report_phase(uvm_phase phase);
        if (errors == 0 && uvm_report_server::get_server().get_severity_count(UVM_ERROR) == 0)
            `uvm_info("RESULT", "** TEST PASSED **", UVM_LOW)
        else
            `uvm_error("RESULT", $sformatf("** TEST FAILED (%0d check errors) **", errors))
    endfunction
endclass
