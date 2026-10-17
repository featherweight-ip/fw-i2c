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
// Rules are added here as the designs that need them arrive (D1, D7, STA+RD:
// see docs/reference/deviations.md and design §3.3).
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
            "SR.BUSY in a status result (read_status, stop, completion): it follows the core's filtered STOP detector, so it settles at a design-specific time",
            1'b0);   // off: fw_i2c_op_eq's re-reads cover R76 lagging; enable for a DUT that lags R76
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
        apply_list("EQ_ALLOW", 1'b1);
        apply_list("EQ_DENY",  1'b0);
    endfunction

    function void report();
        foreach (rules[n]) begin
            i2c_allowed_diff r = rules[n];
            `uvm_info("EQALLOW", $sformatf("%-10s %-3s applied %0d time(s)  [%s] %s", r.name,
                                           r.enabled ? "on" : "off", r.count, r.cite, r.desc),
                      UVM_LOW)
            if (r.expected && r.count == 0)
                `uvm_error("EQALLOW", $sformatf("rule %s was expected to apply and never did", r.name))
        end
    endfunction
endclass
