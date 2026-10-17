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
endpackage
