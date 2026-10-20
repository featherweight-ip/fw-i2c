// The classes that put the fw-i2c class model behind pins (fw_i2c_spl.sv,
// bench-plan E8): the model's root component, the controller transactor as an
// fw-hdl export, and the interrupt pin.
package fw_i2c_spl_rtl_pkg;
    import fw_hdl_pkg::*;
    import fw_proto_i2c_pkg::*;
    import fw_i2c_spl_pkg::*;

    // The kit's controller bridge is a plain class; this makes it the export
    // the model's i2c port connects to.
    class fw_i2c_ctl_export extends fw_export #(i2c_controller_if) implements i2c_controller_if;
        protected i2c_controller_xtor_bridge m_br;

        function new(string name, fw_component parent, virtual i2c_controller_xtor_if vif);
            super.new(name, parent, null);
            set_imp(this);
            m_br = new(vif);
        endfunction

        virtual task start(input bit [9:0] addr, input bit addr_10b, input bit read,
                           input bit repeated, output bit ack, output bit arb_lost);
            m_br.start(addr, addr_10b, read, repeated, ack, arb_lost);
        endtask
        virtual task tx_byte(input bit [7:0] data, output bit ack, output bit arb_lost);
            m_br.tx_byte(data, ack, arb_lost);
        endtask
        virtual task rx_byte(input bit ack, output bit [7:0] data, output bit arb_lost);
            m_br.rx_byte(ack, data, arb_lost);
        endtask
        virtual task stop(); m_br.stop(); endtask
        virtual function void set_prescale(bit [15:0] prescale); m_br.set_prescale(prescale); endfunction
    endclass

    // wb_inta_o: the model's interrupt level, registered by the interface.
    class fw_i2c_irq_pin implements fw_i2c_irq_if;
        virtual fw_i2c_irq_xtor_if vif;
        function new(virtual fw_i2c_irq_xtor_if vif); this.vif = vif; endfunction
        virtual function void irq_changed(bit level); vif.level = level; endfunction
    endclass

    // The model's root: fw_i2c on the controller transactor.
    class fw_i2c_pin_top extends fw_component;
        fw_i2c                         dut;
        fw_i2c_ctl_export              ctl;
        virtual i2c_controller_xtor_if ctl_vif;   // set before start()
        fw_i2c_irq_if                  irq;       // set before start()

        function new(string name, fw_component parent); super.new(name, parent); endfunction

        function void build();
            dut = new("dut", this);
            ctl = new("ctl", this, ctl_vif);
        endfunction

        function void connect();
            dut.i2c.connect(ctl);
            dut.add_irq_sink(irq);
        endfunction
    endclass
endpackage
