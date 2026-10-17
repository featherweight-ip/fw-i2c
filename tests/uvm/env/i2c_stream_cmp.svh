// Passive compare of the two designs' I2C bus event streams (bench-plan
// §3.2). Each side's monitor feeds a queue; once an event is present on both
// sides the pair is compared. Events match by order, never by time. At the
// end both queues must be empty. Events are kept in the bus log's notation
// (S, Sr, P, A<hex>+/-, D<hex>+/-, AL).
typedef class i2c_stream_cmp;

// One monitor subscriber per side of an i2c_stream_cmp.
class i2c_stream_side implements i2c_monitor_if;
    i2c_stream_cmp cmp;
    int            idx;
    function new(i2c_stream_cmp cmp, int idx); this.cmp = cmp; this.idx = idx; endfunction
    virtual function void observe_start(input bit repeated);
        cmp.push(idx, repeated ? "Sr" : "S");
    endfunction
    virtual function void observe_stop();
        cmp.push(idx, "P");
    endfunction
    virtual function void observe_byte(input bit addr_phase, input bit [7:0] data,
                                       input bit ack);
        cmp.push(idx, $sformatf("%s%02h%s", addr_phase ? "A" : "D", data, ack ? "+" : "-"));
    endfunction
    virtual function void observe_arb_lost();
        cmp.push(idx, "AL");
    endfunction
endclass

class i2c_stream_cmp;
    i2c_eq_report rpt;
    string        q[2][$];
    int unsigned  n_matched;

    i2c_stream_side dut_side, ref_side;

    function new();
        rpt = new();
        dut_side = new(this, 0);
        ref_side = new(this, 1);
    endfunction

    function void push(int idx, string ev);
        q[idx].push_back(ev);
        while (q[0].size() != 0 && q[1].size() != 0) begin
            string a = q[0].pop_front();
            string b = q[1].pop_front();
            if (a != b)
                rpt.mismatch("EQBUS", $sformatf("bus event #%0d: DUT %s, R76 %s", n_matched, a, b));
            n_matched++;
        end
    endfunction

    function string rest(int idx);
        string s = "";
        foreach (q[idx][i]) s = {s, (i == 0) ? "" : " ", q[idx][i]};
        return s;
    endfunction

    // End of test: an event left on one side is an extra or missing event.
    function void check_end();
        if (q[0].size() != 0)
            rpt.mismatch("EQBUS", $sformatf("bus event #%0d on: the DUT has %s; R76 has nothing",
                                            n_matched, rest(0)));
        if (q[1].size() != 0)
            rpt.mismatch("EQBUS", $sformatf("bus event #%0d on: R76 has %s; the DUT has nothing",
                                            n_matched, rest(1)));
    endfunction

    function void report();
        `uvm_info("EQBUS", $sformatf("%0d bus events compared, %0d difference(s)",
                                     n_matched, rpt.n_mismatch), UVM_LOW)
    endfunction
endclass
