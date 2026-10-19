// HVL top for the `tlm-eq` view: the fw-i2c class model is the design under
// test ("model"), R76 the reference ("ref_model"); the env compares them.
`include "uvm_macros.svh"

module hvl_top_spl_eq;
    import uvm_pkg::*;
    import fw_i2c_env_pkg::*;
    import fw_i2c_tests_pkg::*;
    import fw_i2c_tlm_view_pkg::*;

    hdl_top_spl_eq hdl_top_spl_eq();

    i2c_tlm_model dut  = new("tlm");
    i2c_ref_model refm = new("ref");

    initial begin
        dut.vclk  = hdl_top_spl_eq.u_clk;
        refm.vwb  = hdl_top_spl_eq.u_ref.u_wb.u_if;
        refm.vtgt = hdl_top_spl_eq.u_ref.u_tgt.u_if;
        refm.vmon = hdl_top_spl_eq.u_ref.u_mon.u_if;
        uvm_config_db #(i2c_model_base)::set(null, "*", "model", dut);
        uvm_config_db #(i2c_model_base)::set(null, "*", "ref_model", refm);
        run_test();
    end

    always @(hdl_top_spl_eq.ref_inta) refm.irq_changed(hdl_top_spl_eq.ref_inta);

    initial begin
        #20ms;
        $fatal(1, "[hvl_top_spl_eq] TIMEOUT");
    end
endmodule
