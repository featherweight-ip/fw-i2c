// The bus watcher: SR.BUSY from the bus, not from the core's own state. Set
// by any START, cleared by any STOP (as R76). Subscribed to the bus monitor
// at TLM; driven by the filtered lines behind pins. The monitor callbacks are
// functions, so they only record the level; fw_i2c's run() moves it into SR.
class fw_i2c_bus_watch implements i2c_monitor_if;
    bit busy;
    bit dirty;

    virtual function void observe_start(input bit repeated);
        busy  = 1'b1;
        dirty = 1'b1;
    endfunction
    virtual function void observe_stop();
        busy  = 1'b0;
        dirty = 1'b1;
    endfunction
    virtual function void observe_byte(input bit addr_phase, input bit [7:0] data,
                                       input bit ack);
    endfunction
    virtual function void observe_arb_lost();
    endfunction
endclass
