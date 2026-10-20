// The interrupt pin: `level` is set by the model (fw_i2c_irq_pin); `irq`
// follows it one clock later, as R76 registers wb_inta_o.
interface fw_i2c_irq_xtor_if (input clock, input reset, output logic irq);
    bit level;
    always @(posedge clock or posedge reset)
        if (reset) irq <= 1'b0;
        else       irq <= level;
endinterface
