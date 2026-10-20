// HVL top for the `wb` view: the common tests on fw-i2c behind pins.
`include "uvm_macros.svh"

module hvl_top_wb;
    import uvm_pkg::*;
    import fw_i2c_env_pkg::*;
    import fw_i2c_tests_pkg::*;

    hdl_top_wb hdl_top_wb();

    i2c_ref_model   model  = new("wb");
    i2c_line_timing timing = new();

    initial begin
        model.vwb  = hdl_top_wb.u_arm.u_wb.u_if;
        model.vtgt = hdl_top_wb.u_arm.u_tgt.u_if;
        model.vmon = hdl_top_wb.u_arm.u_mon.u_if;
        uvm_config_db #(i2c_model_base)::set(null, "*", "model", model);
        uvm_config_db #(i2c_line_timing)::set(null, "*", "line_timing", timing);
        run_test();
    end

    always @(hdl_top_wb.inta) model.irq_changed(hdl_top_wb.inta);

    // Bus timing for fw_i2c_um10204_test; `drv` is fw-i2c's own SDA drive.
    wire core_sda_drive = !hdl_top_wb.u_arm.core_sda_oen && !hdl_top_wb.u_arm.core_sda_o;
    always @(hdl_top_wb.scl or hdl_top_wb.sda or core_sda_drive)
        timing.sample($realtime, hdl_top_wb.scl, hdl_top_wb.sda, core_sda_drive);

    initial begin
        #10ms;
        $fatal(1, "[hvl_top_wb] TIMEOUT");
    end
endmodule
