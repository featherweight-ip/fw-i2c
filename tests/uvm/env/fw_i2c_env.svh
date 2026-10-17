// The env: builds the operation model over the published model, installs the
// standard responder and the bus log, and pumps interrupts into the model's
// notify_irq() (event-wait profile: a rising edge of the interrupt line
// wakes a blocked operation).
class fw_i2c_env extends uvm_env;
    `uvm_component_utils(fw_i2c_env)

    i2c_model_base      model;
    i2c_pss_mem_adapter pss;
    fw_i2c_regs_c       regs;   // the generated register group, for register-level tests
    i2c_mem_target      tgt;
    i2c_bus_log         log;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(i2c_model_base)::get(this, "", "model", model))
            `uvm_fatal("CFG", "no i2c_model_base \"model\" in the config DB")
        pss = new(model);
        regs = new(pss, 0);
        tgt = new();
        log = new();
        model.tgt.impl = tgt;
        model.mon.add(log);
    endfunction

    task run_phase(uvm_phase phase);
        model.start();
        forever begin
            model.wait_irq_change();
            if (model.irq_level()) pss.dev.notify_irq();
        end
    endtask

    // The operation model, for tests.
    function fw_i2c_c_ctxt_if dev(); return pss.dev; endfunction
endclass
