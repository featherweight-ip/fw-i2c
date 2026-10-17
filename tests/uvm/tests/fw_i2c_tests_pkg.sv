// fw-i2c tests: common to every view. A test programs the device only
// through the operation model (env.dev()) and checks results, the responder's
// memory and the bus log.
`include "uvm_macros.svh"

package fw_i2c_tests_pkg;
    import uvm_pkg::*;
    import fw_proto_i2c_pkg::*;
    import fw_i2c_c_pkg::*;
    import fw_i2c_env_pkg::*;

    `include "fw_i2c_base_test.svh"
    `include "fw_i2c_smoke_test.svh"
    `include "fw_i2c_reg_test.svh"
    `include "fw_i2c_write_test.svh"
    `include "fw_i2c_read_test.svh"
    `include "fw_i2c_nack_test.svh"
    `include "fw_i2c_irq_test.svh"
    `include "fw_i2c_prer_test.svh"
    `include "fw_i2c_stretch_test.svh"
    `include "fw_i2c_addr10_test.svh"
    `include "fw_i2c_eq_sabotage_test.svh"
    // Reference confirmation tests (bench-plan E3), `ref` view only.
    `include "fw_i2c_ref_base_test.svh"
    `include "fw_i2c_ref_timing_test.svh"
    `include "fw_i2c_ref_cr_race_test.svh"
    `include "fw_i2c_ref_en_midbyte_test.svh"
    `include "fw_i2c_ref_prer_min_test.svh"
    `include "fw_i2c_ref_arb_test.svh"
endpackage
