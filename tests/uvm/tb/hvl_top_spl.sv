// HVL top for the `tlm` view: the common tests on the fw-i2c class model.
`include "uvm_macros.svh"

module hvl_top_spl;
    import uvm_pkg::*;
    import fw_i2c_env_pkg::*;
    import fw_i2c_tests_pkg::*;
    import fw_i2c_tlm_view_pkg::*;

    hdl_top_spl hdl_top_spl();

    i2c_tlm_model model = new("tlm");

    initial begin
        model.vclk = hdl_top_spl.u_clk;
        uvm_config_db #(i2c_model_base)::set(null, "*", "model", model);
        run_test();
    end

    initial begin
        #10ms;
        $fatal(1, "[hvl_top_spl] TIMEOUT");
    end
endmodule
