// Records the I2C bus event stream as short strings: S, Sr, P, and bytes as
// A<hex>+/- (address phase) or D<hex>+/- (data), + for ACK and - for NACK.
// Tests check it against what they expect; the equivalence views compare two
// of them (bench-plan §3.2).
class i2c_bus_log implements i2c_monitor_if;
    string events[$];

    function void clear(); events.delete(); endfunction

    function string str(int from = 0);
        string s = "";
        for (int i = from; i < events.size(); i++)
            s = {s, (i == from) ? "" : " ", events[i]};
        return s;
    endfunction

    virtual function void observe_start(input bit repeated);
        events.push_back(repeated ? "Sr" : "S");
    endfunction
    virtual function void observe_stop();
        events.push_back("P");
    endfunction
    virtual function void observe_byte(input bit addr_phase, input bit [7:0] data,
                                       input bit ack);
        events.push_back($sformatf("%s%02h%s", addr_phase ? "A" : "D", data,
                                   ack ? "+" : "-"));
    endfunction
    virtual function void observe_arb_lost();
        events.push_back("AL");
    endfunction
endclass
