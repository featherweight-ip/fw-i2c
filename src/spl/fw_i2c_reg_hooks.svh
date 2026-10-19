// Register hooks: write observers that tell the model about software writes,
// and read providers for the two readback registers.

// CR, CTR and TXR writes. The observer sees the written word with the pulse
// bits (IACK, RSVD2, RSVD1) set, although the register never stores them.
class fw_i2c_wr_obs implements fw_reg_wr_if #(32);
    typedef enum { OBS_CR, OBS_CTR } which_e;
    local fw_i2c  m_dev;
    local which_e m_which;
    function new(fw_i2c dev, which_e which); m_dev = dev; m_which = which; endfunction
    virtual task on_write(input bit [31:0] val, input bit [31:0] prev);
        if (m_which == OBS_CR) m_dev.on_cr_write(val);
        else                   m_dev.on_ctr_write(val, prev);
    endtask
endclass

// TXR_DBG and CR_DBG read back TXR and the stored CR.
class fw_i2c_readback implements fw_reg_rd_if #(32);
    local fw_reg_base #(32) m_src;
    function new(fw_reg_base #(32) src); m_src = src; endfunction
    virtual function bit [31:0] on_read(input bit [31:0] stored);
        return m_src.read_val();
    endfunction
endclass
