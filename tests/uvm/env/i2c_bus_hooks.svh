// Two small seams every model has on its I2C side.
//
// i2c_target_slot: the target the bus addresses. A model's transactor bridge
// (or TLM bus) is built with this slot, and the env installs the responder in
// it later, so a model can be constructed before the test chooses its
// responder.
class i2c_target_slot implements i2c_target_if;
    i2c_target_if impl;

    local function void check(string who);
        if (impl == null)
            `uvm_fatal("I2CTGT", {who, ": no responder installed in the model's target slot"})
    endfunction

    virtual task addressed(input bit [9:0] addr, input bit addr_10b, input bit read,
                           output bit ack);
        check("addressed");
        impl.addressed(addr, addr_10b, read, ack);
    endtask
    virtual task addressed_10b_hi(input bit [1:0] addr_hi, output bit ack);
        check("addressed_10b_hi");
        impl.addressed_10b_hi(addr_hi, ack);
    endtask
    virtual task rx_byte(input bit [7:0] data, output bit ack);
        check("rx_byte");
        impl.rx_byte(data, ack);
    endtask
    virtual task tx_byte(output bit [7:0] data, input bit ack);
        check("tx_byte");
        impl.tx_byte(data, ack);
    endtask
endclass

// i2c_monitor_fanout: one monitor stream, any number of subscribers (the bus
// log, the stream comparator, a test's own checks).
class i2c_monitor_fanout implements i2c_monitor_if;
    i2c_monitor_if subs[$];

    function void add(i2c_monitor_if s); subs.push_back(s); endfunction

    virtual function void observe_start(input bit repeated);
        foreach (subs[i]) subs[i].observe_start(repeated);
    endfunction
    virtual function void observe_stop();
        foreach (subs[i]) subs[i].observe_stop();
    endfunction
    virtual function void observe_byte(input bit addr_phase, input bit [7:0] data,
                                       input bit ack);
        foreach (subs[i]) subs[i].observe_byte(addr_phase, data, ack);
    endfunction
    virtual function void observe_arb_lost();
        foreach (subs[i]) subs[i].observe_arb_lost();
    endfunction
endclass
