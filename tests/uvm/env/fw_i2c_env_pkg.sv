// fw-i2c UVM environment: what every view and every test shares. Tests reach
// the design under test only through i2c_model_base (published as "model"),
// and program it only through the generated operation model
// (fw_i2c_c_pkg, docs/design/operation-model.md). Plan: docs/design/bench-plan.md.
`include "uvm_macros.svh"

package fw_i2c_env_pkg;
    import uvm_pkg::*;
    import fw_proto_wb_pkg::*;
    import fw_proto_i2c_pkg::*;
    import pssc_reg_pkg::*;
    import fw_i2c_c_pkg::*;

    `include "i2c_bus_hooks.svh"
    `include "i2c_model_base.svh"
    `include "i2c_mem_target.svh"
    `include "i2c_bus_log.svh"
    `include "i2c_pss_mem_adapter.svh"
    `include "i2c_ref_model.svh"
    `include "i2c_eq_report.svh"
    `include "i2c_allowed_diffs.svh"
    `include "i2c_stream_cmp.svh"
    `include "i2c_mirror_target.svh"
    `include "i2c_eq_model.svh"
    `include "fw_i2c_op_eq.svh"
    `include "fw_i2c_env.svh"
endpackage
