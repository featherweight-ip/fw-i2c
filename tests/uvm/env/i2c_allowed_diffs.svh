// The allowed differences between the design under test and R76, as one
// table of named rules (bench-plan §3.5). Each rule cites the defect, risk or
// OI-6 item behind it. The scoreboards ask allow(name) before reporting a
// difference the rule covers; every rule applied is counted and reported.
//
// A test enables or disables a rule with enable(name, on), or from the command
// line with +EQ_ALLOW=<name>[,<name>...] and +EQ_DENY=.... A test that targets
// a fixed defect calls expect(name): the run then fails if the rule never
// applied.
//
// +EQ_EXPECT=<name>[,<name>...] does the same as expect_rule() from the
// command line.
//
// Two kinds of rule:
//   - a field rule (busy_lag, busy_lag_self) covers one field of one comparison, and the
//     scoreboard asks allow(name) at that comparison;
//   - a defect rule (d7) covers every difference while R76 is in the state
//     the defect needs, because the defect makes R76's whole run diverge. The
//     scoreboards ask blanket() before reporting any difference.
//
// More rules follow the OI-6 resolution (design §8.1) as the tests that
// expect them arrive: d1, d6, sta_rd, al_unexp_stop, d9_stop.
class i2c_allowed_diff;
    string       name;
    string       cite;
    string       desc;
    bit          enabled;
    bit          expected;
    int unsigned count;
endclass

class i2c_allowed_diffs;
    i2c_allowed_diff rules[string];

    function new();
        add("busy_lag", "bench-plan P5",
            "SR.BUSY = 1 on R76 where the DUT reads 0, in the result of an operation that ends in STOP: R76's BUSY follows its filtered STOP detector, which lags its own IF",
            1'b1);
        // On the self-test view the DUT is R76 as well and lags the same way.
        // completion_check reads the DUT first and R76 only once the DUT is
        // done, so the DUT can still read BUSY = 1 where R76, read later,
        // reads 0. The env turns this on when the DUT arm is R76.
        add("busy_lag_self", "bench-plan P5, §3.4",
            "SR.BUSY = 1 on the DUT where R76 reads 0, when the DUT is R76 too (ref-eq): the same lag, sampled earlier on the DUT side",
            1'b0);
        add("d7", "D7, OI-6 (design §8.1)",
            "R76 at PRER < 2 loses arbitration against a single target; fw-i2c works at every PRER. Covers every difference while R76's PRER is below 2",
            1'b0);
        apply_plusargs();
    endfunction

    function void add(string name, string cite, string desc, bit enabled);
        i2c_allowed_diff r = new();
        r.name = name;
        r.cite = cite;
        r.desc = desc;
        r.enabled = enabled;
        rules[name] = r;
    endfunction

    protected function i2c_allowed_diff get(string name);
        if (!rules.exists(name)) begin
            `uvm_fatal("EQALLOW", {"no allowed-difference rule \"", name, "\""})
            return null;
        end
        return rules[name];
    endfunction

    function void enable(string name, bit on = 1'b1); get(name).enabled = on; endfunction

    function void expect_rule(string name);
        i2c_allowed_diff r = get(name);
        r.enabled  = 1'b1;
        r.expected = 1'b1;
    endfunction

    // 1 if the difference is allowed (and counted), 0 if it is a mismatch.
    function bit allow(string name);
        i2c_allowed_diff r = get(name);
        if (!r.enabled) return 1'b0;
        r.count++;
        return 1'b1;
    endfunction

    protected function void apply_list(string arg, bit on);
        string s;
        if (!$value$plusargs({arg, "=%s"}, s)) return;
        while (s.len() != 0) begin
            int    i = 0;
            string n;
            while (i < s.len() && s[i] != ",") i++;
            n = s.substr(0, i - 1);
            s = (i < s.len()) ? s.substr(i + 1, s.len() - 1) : "";
            if (n.len() != 0) enable(n, on);
        end
    endfunction

    function void apply_plusargs();
        string s;
        apply_list("EQ_ALLOW", 1'b1);
        apply_list("EQ_DENY",  1'b0);
        if ($value$plusargs("EQ_EXPECT=%s", s))
            while (s.len() != 0) begin
                int i = 0;
                while (i < s.len() && s[i] != ",") i++;
                if (i != 0) expect_rule(s.substr(0, i - 1));
                s = (i < s.len()) ? s.substr(i + 1, s.len() - 1) : "";
            end
    endfunction

    // R76's state, as the operation scoreboard last configured it.
    bit [15:0] ref_prer = 16'hFFFF;

    // 1 if a defect rule covers any difference now (and counts it).
    function bit blanket();
        if (ref_prer < 2 && allow("d7")) return 1'b1;
        return 1'b0;
    endfunction

    function void report();
        foreach (rules[n]) begin
            i2c_allowed_diff r = rules[n];
            `uvm_info("EQALLOW", $sformatf("%-13s %-3s applied %0d time(s)  [%s] %s", r.name,
                                           r.enabled ? "on" : "off", r.count, r.cite, r.desc),
                      UVM_LOW)
            if (r.expected && r.count == 0)
                `uvm_error("EQALLOW", $sformatf("rule %s was expected to apply and never did", r.name))
        end
    endfunction
endclass
