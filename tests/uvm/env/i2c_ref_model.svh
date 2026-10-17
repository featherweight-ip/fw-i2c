// The R76 reference (OpenCores i2c through the 32-bit WISHBONE shim), behind
// transactors: tests/uvm/tb/oc_i2c_ref_arm.sv. The top seats the three
// transactor interfaces and drives irq_changed() from the shim's wb_inta_o.
class i2c_ref_model extends i2c_model_base;
    virtual wb_initiator_xtor_if #(32, 32) vwb;
    virtual i2c_target_xtor_if             vtgt;
    virtual i2c_monitor_xtor_if            vmon;

    protected wb_initiator_xtor_bridge #(32, 32) m_wb;
    protected i2c_target_xtor_bridge             m_tgt;
    protected i2c_monitor_xtor_bridge            m_mon;

    function new(string name = "ref");
        super.new(name);
    endfunction

    virtual function wb_proto_if #(32, 32) rf_if();
        if (m_wb == null) begin
            if (vwb == null) `uvm_fatal("REFMODEL", "vwb not seated")
            m_wb = new(vwb);
        end
        return m_wb;
    endfunction

    virtual task start();
        if (vtgt == null || vmon == null) `uvm_fatal("REFMODEL", "vtgt/vmon not seated")
        m_tgt = new(vtgt, tgt);
        m_mon = new(vmon, mon);
        m_tgt.start_bridge();
        m_mon.start_bridge();
    endtask
endclass
