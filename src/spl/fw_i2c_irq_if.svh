// The interrupt seam: the model calls irq_changed() on every change of
// wb_inta_o (IF & IEN). A view subscribes with fw_i2c::add_irq_sink(); the
// pin-level view drives the pin from it.
interface class fw_i2c_irq_if;
    pure virtual function void irq_changed(bit level);
endclass
