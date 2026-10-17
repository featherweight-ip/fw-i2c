// HVL top for the `ref` view: the common tests run on R76 itself. Seats the
// arm's transactor interfaces in an i2c_ref_model, feeds its interrupt pin to
// the model's irq seam, publishes the model and runs the test.
`include "uvm_macros.svh"

module hvl_top_ref;
    import uvm_pkg::*;
    import fw_i2c_env_pkg::*;
    import fw_i2c_tests_pkg::*;

    hdl_top_ref hdl_top_ref();

    i2c_ref_model model = new("ref");

    initial begin
        model.vwb  = hdl_top_ref.u_arm.u_wb.u_if;
        model.vtgt = hdl_top_ref.u_arm.u_tgt.u_if;
        model.vmon = hdl_top_ref.u_arm.u_mon.u_if;
        uvm_config_db #(i2c_model_base)::set(null, "*", "model", model);
        run_test();
    end

    always @(hdl_top_ref.inta) model.irq_changed(hdl_top_ref.inta);

    initial begin
        #10ms;
        $fatal(1, "[hvl_top_ref] TIMEOUT");
    end
endmodule
