// The env: builds the operation model over the published model, installs the
// standard responder and the bus log, and pumps interrupts into the model's
// notify_irq() (event-wait profile: a rising edge of the interrupt line
// wakes a blocked operation).
//
// If the top also publishes "ref_model" (an R76 arm), this is an equivalence
// view (bench-plan §3): each design gets its own operation model instance and
// interrupt pump, tests get fw_i2c_op_eq as the operation API and an
// i2c_eq_model as "model", the DUT side's responder is recorded and mirrored
// onto R76's bus, and the two bus streams are compared.
class fw_i2c_env extends uvm_env;
    `uvm_component_utils(fw_i2c_env)

    i2c_model_base      model;  // what tests see: the DUT, or the pair
    i2c_model_base      dut;
    i2c_pss_mem_adapter pss;
    fw_i2c_regs_c       regs;   // the generated register group, for register-level tests
    i2c_mem_target      tgt;    // the active responder (the DUT side's)
    i2c_bus_log         log;    // the DUT's bus

    // ---- equivalence views only ----
    bit                 eq;
    i2c_model_base      refm;
    i2c_pss_mem_adapter pss_ref;
    fw_i2c_op_eq        op_eq;
    i2c_allowed_diffs   allow;
    i2c_stream_cmp      cmp;
    i2c_decision_q      decisions;
    i2c_mirror_target   mirror;
    i2c_bus_log         ref_log;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(i2c_model_base)::get(this, "", "model", dut))
            `uvm_fatal("CFG", "no i2c_model_base \"model\" in the config DB")
        eq = uvm_config_db #(i2c_model_base)::get(this, "", "ref_model", refm);
        pss = new(dut);
        tgt = new();
        log = new();
        dut.mon.add(log);
        if (!eq) begin
            model = dut;
            regs  = new(pss, 0);
            dut.tgt.impl = tgt;
            return;
        end

        begin
            i2c_eq_model        m = new(dut, refm);
            i2c_pss_mem_adapter tee_pss;
            model   = m;
            tee_pss = new(m);
            regs    = new(tee_pss, 0);
        end
        pss_ref   = new(refm);
        allow     = new();
        op_eq     = new(pss.dev, pss_ref.dev, allow);
        decisions = new();
        begin
            i2c_decision_rec rec = new(tgt, decisions);
            dut.tgt.impl = rec;
        end
        mirror        = new(decisions);
        refm.tgt.impl = mirror;
        cmp     = new();
        ref_log = new();
        dut.mon.add(cmp.dut_side);
        refm.mon.add(cmp.ref_side);
        refm.mon.add(ref_log);
    endfunction

    // Self-test: report every difference as information and count it.
    function void expect_mismatch();
        i2c_eq_model m;
        void'($cast(m, model));
        op_eq.rpt.expect_mismatch  = 1'b1;
        cmp.rpt.expect_mismatch    = 1'b1;
        mirror.rpt.expect_mismatch = 1'b1;
        m.rpt.expect_mismatch      = 1'b1;
    endfunction

    task run_phase(uvm_phase phase);
        model.start();
        fork
            pump(dut, pss.dev);
            if (eq) pump(refm, pss_ref.dev);
        join
    endtask

    protected task pump(i2c_model_base m, fw_i2c_c_ctxt_if d);
        forever begin
            m.wait_irq_change();
            if (m.irq_level()) d.notify_irq();
        end
    endtask

    function void check_phase(uvm_phase phase);
        if (!eq) return;
        cmp.check_end();
        mirror.check_end();
    endfunction

    function void report_phase(uvm_phase phase);
        if (!eq) return;
        op_eq.report();
        cmp.report();
        mirror.report();
        allow.report();
        `uvm_info("EQ", {"R76 bus: ", ref_log.str()}, UVM_HIGH)
    endfunction

    // The operation API, for tests.
    function fw_i2c_c_ctxt_if dev(); return eq ? op_eq : pss.dev; endfunction
endclass
