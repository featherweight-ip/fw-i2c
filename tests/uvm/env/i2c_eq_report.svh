// Where the equivalence scoreboards send a difference. Normally it is a
// UVM error. A self-test that sabotages one side sets expect_mismatch: the
// difference is then reported as information and only counted, and the test
// checks the count.
class i2c_eq_report;
    bit          expect_mismatch;
    int unsigned n_mismatch;
    string       first;               // the first difference reported
    int unsigned max_reported = 10;   // per scoreboard; the rest are counted

    function void mismatch(string id, string msg);
        n_mismatch++;
        if (n_mismatch == 1) first = msg;
        if (n_mismatch > max_reported) return;
        if (expect_mismatch)
            `uvm_info(id, {"(expected) ", msg}, UVM_LOW)
        else
            `uvm_error(id, msg)
        if (n_mismatch == max_reported)
            `uvm_info(id, "further differences are counted, not reported", UVM_LOW)
    endfunction
endclass
