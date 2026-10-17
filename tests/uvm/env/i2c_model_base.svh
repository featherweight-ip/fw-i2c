// The design under test, as the bench sees it, whatever the view (the R76
// reference, fw-i2c at TLM, behind transactors, or as RTL). Like fw-wb-dma's
// wb_dma_model_base: the env, the operation model and the tests depend on
// this surface only.
//
//   rf_if()    the register port: one access() per WISHBONE cycle
//   tgt        the I2C target slot; the env installs the responder
//   mon        the I2C bus event stream (passive)
//   irq seam   irq_changed() from the view's producer; the bench waits only
//              on wait_irq_change()
virtual class i2c_model_base;
    string             name;
    i2c_target_slot    tgt;
    i2c_monitor_fanout mon;

    bit   m_irq_level;
    event m_irq_ev;

    function new(string name);
        this.name = name;
        tgt = new();
        mon = new();
    endfunction

    pure virtual function wb_proto_if #(32, 32) rf_if();

    // Start whatever runs in the background (transactor bridges). Called by
    // the env before the first operation.
    virtual task start(); endtask

    // 1 if the view models bus timing (SCL periods, clock stretching), so
    // tests may check durations. An untimed TLM view returns 0.
    virtual function bit timed(); return 1'b1; endfunction

    // ---- interrupt seam ----
    virtual function void irq_changed(bit level);
        if (level === m_irq_level) return;
        m_irq_level = level;
        -> m_irq_ev;
    endfunction
    task wait_irq_change(); @m_irq_ev; endtask
    function bit irq_level(); return m_irq_level; endfunction
endclass
