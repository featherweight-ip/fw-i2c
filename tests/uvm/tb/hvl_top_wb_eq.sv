// HVL top for the `wb-eq` view: fw-i2c behind pins ("model") against R76
// ("ref_model").
`include "uvm_macros.svh"

module hvl_top_wb_eq;
    import uvm_pkg::*;
    import fw_i2c_env_pkg::*;
    import fw_i2c_tests_pkg::*;

    hdl_top_wb_eq hdl_top_wb_eq();

    i2c_ref_model dut  = new("wb");
    i2c_ref_model refm = new("ref");

    initial begin
        dut.vwb   = hdl_top_wb_eq.u_dut.u_wb.u_if;
        dut.vtgt  = hdl_top_wb_eq.u_dut.u_tgt.u_if;
        dut.vmon  = hdl_top_wb_eq.u_dut.u_mon.u_if;
        refm.vwb  = hdl_top_wb_eq.u_ref.u_wb.u_if;
        refm.vtgt = hdl_top_wb_eq.u_ref.u_tgt.u_if;
        refm.vmon = hdl_top_wb_eq.u_ref.u_mon.u_if;
        uvm_config_db #(i2c_model_base)::set(null, "*", "model", dut);
        uvm_config_db #(i2c_model_base)::set(null, "*", "ref_model", refm);
        run_test();
    end

    always @(hdl_top_wb_eq.dut_inta) dut.irq_changed(hdl_top_wb_eq.dut_inta);
    always @(hdl_top_wb_eq.ref_inta) refm.irq_changed(hdl_top_wb_eq.ref_inta);

    initial begin
        #20ms;
        $fatal(1, "[hvl_top_wb_eq] TIMEOUT");
    end
endmodule
