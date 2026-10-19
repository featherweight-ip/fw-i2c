// The `tlm` view's model (bench-plan §3.4, E7): the fw-i2c class model over
// i2c_tlm_bus, with no signal-level transactors. i2c_tlm_model presents it to
// the env as an i2c_model_base: the register port is the model's own
// wb_proto_if export, the bus calls the env's target slot and feeds its
// monitor fan-out, and the model's interrupt goes to the irq seam.
`include "uvm_macros.svh"

package fw_i2c_tlm_view_pkg;
    import uvm_pkg::*;
    import fw_hdl_pkg::*;
    import fw_proto_wb_pkg::*;
    import fw_proto_i2c_pkg::*;
    import fw_i2c_spl_pkg::*;
    import fw_i2c_env_pkg::*;

    // Bus timing in ticks of PRER+1 clocks: the fw-i2c timing (design §8.1):
    // a 5-tick bit as R76 (D10: no filter lag, so exactly the PDF formula),
    // with tSU;STA raised to 3 ticks to meet UM10204 in Standard mode (D8).
    localparam int T_LOW = 3, T_HIGH = 2, T_HD_STA = 2, T_SU_STA = 3, T_SU_STO = 2, T_BUF = 4;

    class fw_i2c_tlm_top extends fw_component;
        fw_i2c                       dut;
        i2c_tlm_bus                  bus;
        fw_export #(i2c_controller_if) bus_exp;

        // Set by the model before start().
        i2c_target_if  tgt;
        i2c_monitor_if mon;
        fw_i2c_irq_if  irq;
        time           clk_period;

        function new(string name, fw_component parent); super.new(name, parent); endfunction

        function void build();
            dut = new("dut", this);
            bus = new(tgt);
            bus.set_timing(clk_period, T_LOW, T_HIGH, T_HD_STA, T_SU_STA, T_SU_STO, T_BUF);
            bus_exp = new("bus", this, bus);
        endfunction

        function void connect();
            dut.i2c.connect(bus_exp);
            bus.add_monitor(mon);
            bus.add_monitor(dut.bus_mon);
            dut.add_irq_sink(irq);
        endfunction
    endclass

    // Register accesses that arrive before the model has elaborated wait for it.
    class fw_i2c_tlm_rf implements wb_proto_if #(32, 32);
        fw_component_root #(fw_i2c_tlm_top) root;
        virtual task access(input  [31:0] adr, input [31:0] dat_w, input [3:0] sel, input we,
                            output [31:0] dat_r, output err);
            wait (root.elaborated);
            root.dut.host.access(adr, dat_w, sel, we, dat_r, err);
        endtask
    endclass

    class i2c_tlm_model extends i2c_model_base implements fw_i2c_irq_if;
        virtual fw_clock_xtor_if            vclk;
        time                                clk_period = 10ns;
        fw_component_root #(fw_i2c_tlm_top) root;
        protected fw_i2c_tlm_rf             m_rf;

        function new(string name = "tlm");
            super.new(name);
            root = new("root");
            m_rf = new();
            m_rf.root = root;
        endfunction

        virtual function wb_proto_if #(32, 32) rf_if(); return m_rf; endfunction

        virtual function void irq_changed(bit level); super.irq_changed(level); endfunction

        virtual task start();
            fw_clock_xtor_bridge clk;
            if (vclk == null) `uvm_fatal("TLMMODEL", "vclk not seated")
            root.tgt        = tgt;
            root.mon        = mon;
            root.irq        = this;
            root.clk_period = clk_period;
            clk = new("clock", root, vclk);
            root.clock.connect(clk);
            fork
                root.start();
            join_none
            wait (root.elaborated);
        endtask
    endclass
endpackage
