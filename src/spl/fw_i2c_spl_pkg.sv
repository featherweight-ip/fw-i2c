// fw-i2c: the I2C master as an fw-hdl class model (bench-plan E6, design §3).
// R76-compatible registers (the generated fw_i2c_regs), a command sequencer
// that maps CR commands onto the fw-proto-i2c controller API, a bus watcher
// for SR.BUSY, and the interrupt. The same model runs at TLM (over
// i2c_tlm_bus) and behind pins (src/spl-rtl, later).
package fw_i2c_spl_pkg;
    import fw_hdl_pkg::*;
    import fw_proto_wb_pkg::*;
    import fw_proto_i2c_pkg::*;
    import fw_i2c_reg_pkg::*;

    typedef class fw_i2c;

    `include "fw_i2c_irq_if.svh"
    `include "fw_i2c_host.svh"
    `include "fw_i2c_reg_hooks.svh"
    `include "fw_i2c_bus_watch.svh"
    `include "fw_i2c.svh"
endpackage
