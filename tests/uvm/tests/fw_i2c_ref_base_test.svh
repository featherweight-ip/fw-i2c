// Base for the reference confirmation tests (bench-plan E3): `ref` view only.
// Adds the probe (R76 internals, bus line timing, the second master) and a
// bounded poll for operations started with a _start half.
class fw_i2c_ref_base_test extends fw_i2c_base_test;
    `uvm_component_utils(fw_i2c_ref_base_test)

    i2c_ref_probe probe;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(i2c_ref_probe)::get(this, "", "ref_probe", probe))
            `uvm_fatal("CFG", "no \"ref_probe\": the reference confirmation tests run on the ref view only")
    endfunction

    // Poll completion_check until done (IF and not TIP) or `max_reads`.
    task poll_done(string what, output fw_i2c_check_s st, input int max_reads = 100000);
        int n = 0;
        do begin
            dev().completion_check(st);
            n++;
        end while (!st.done && n < max_reads);
        if (!st.done)
            `uvm_info(what, $sformatf("not done after %0d reads (SR TIP=%0d IF=%0d BUSY=%0d AL=%0d)",
                                      n, st.sr.tip, st.sr.irq_flag, st.sr.busy, st.sr.al), UVM_LOW)
    endtask

    // Count the events of a kind in the bus log from `from`.
    function int count_log(string prefix, int from = 0);
        int n = 0;
        for (int i = from; i < env.log.events.size(); i++)
            if (env.log.events[i].len() >= prefix.len() &&
                env.log.events[i].substr(0, prefix.len() - 1) == prefix)
                n++;
        return n;
    endfunction
endclass
