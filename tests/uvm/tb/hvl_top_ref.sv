// HVL top for the `ref` view: the common tests run on R76 itself. Seats the
// arm's transactor interfaces in an i2c_ref_model, feeds its interrupt pin to
// the model's irq seam, publishes the model and runs the test. Also publishes
// an i2c_ref_probe for the reference confirmation tests (bench-plan E3): R76
// internals each clock, the bus lines, and the arm's second master.
`include "uvm_macros.svh"

module hvl_top_ref;
    import uvm_pkg::*;
    import fw_i2c_env_pkg::*;
    import fw_proto_i2c_pkg::*;
    import fw_i2c_tests_pkg::*;

    hdl_top_ref hdl_top_ref();

    i2c_ref_model model = new("ref");
    i2c_ref_probe probe = new();

    initial begin
        model.vwb  = hdl_top_ref.u_arm.u_wb.u_if;
        model.vtgt = hdl_top_ref.u_arm.u_tgt.u_if;
        model.vmon = hdl_top_ref.u_arm.u_mon.u_if;
        begin
            i2c_controller_xtor_bridge ctl = new(hdl_top_ref.u_arm.u_ctl.u_if);
            probe.ctl = ctl;
        end
        uvm_config_db #(i2c_model_base)::set(null, "*", "model", model);
        uvm_config_db #(i2c_ref_probe)::set(null, "*", "ref_probe", probe);
        run_test();
    end

    always @(hdl_top_ref.inta) model.irq_changed(hdl_top_ref.inta);

    always @(posedge hdl_top_ref.clock)
        probe.tick(hdl_top_ref.u_arm.u_dut.u_core.done,
                   hdl_top_ref.u_arm.u_dut.u_core.wb_wacc,
                   hdl_top_ref.u_arm.u_dut.u_core.i2c_al);

    wire core_sda_drive = !hdl_top_ref.u_arm.core_sda_oen && !hdl_top_ref.u_arm.core_sda_o;
    always @(hdl_top_ref.scl or hdl_top_ref.sda or core_sda_drive)
        probe.timing.sample($realtime, hdl_top_ref.scl, hdl_top_ref.sda, core_sda_drive);

    initial begin
        #10ms;
        $fatal(1, "[hvl_top_ref] TIMEOUT");
    end
endmodule
