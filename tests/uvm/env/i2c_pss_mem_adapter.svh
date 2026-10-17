// The generated operation model's import seam: every register access the
// model makes becomes one access() on the model's register port. Unlike
// fw-wb-dma's adapter, there is no UVM sequence in between: the equivalence
// scoreboard runs two of these in parallel, one per design, and a register
// access is a direct call on that design's port.
class i2c_pss_mem_adapter implements fw_i2c_c_imp_if;
    i2c_model_base   model;
    fw_i2c_c_ctxt_if dev;          // the operation model, over this adapter
    int unsigned     n_reads, n_writes;

    function new(i2c_model_base model, addr_handle_t base = 0);
        this.model = model;
        dev = fw_i2c_c_root #(fw_i2c_c_imp_if)::create(this, base);
    endfunction

    virtual task write32(addr_handle_t addr, bit [31:0] data);
        bit [31:0] rd;
        bit        err;
        n_writes++;
        `uvm_info("PSSBUS", $sformatf("%s: write 0x%02h <- 0x%02h", model.name, addr, data), UVM_DEBUG)
        model.rf_if().access(32'(addr), data, 4'hF, 1'b1, rd, err);
        if (err) `uvm_error("PSSBUS", $sformatf("%s: write 0x%0h <- 0x%08h: bus error",
                                                model.name, addr, data))
    endtask

    virtual task read32(addr_handle_t addr, output bit [31:0] data);
        bit err;
        n_reads++;
        model.rf_if().access(32'(addr), 32'h0, 4'hF, 1'b0, data, err);
        `uvm_info("PSSBUS", $sformatf("%s: read  0x%02h -> 0x%02h", model.name, addr, data), UVM_DEBUG)
        if (err) `uvm_error("PSSBUS", $sformatf("%s: read 0x%0h: bus error",
                                                model.name, addr))
    endtask

    // Every fw-i2c register is 32 bits wide, so reg_c never selects these.
    virtual task write8 (addr_handle_t a, bit [7:0]  d);        unsupported("write8");  endtask
    virtual task read8  (addr_handle_t a, output bit [7:0]  d); unsupported("read8");  d = '0; endtask
    virtual task write16(addr_handle_t a, bit [15:0] d);        unsupported("write16"); endtask
    virtual task read16 (addr_handle_t a, output bit [15:0] d); unsupported("read16"); d = '0; endtask
    virtual task write64(addr_handle_t a, bit [63:0] d);        unsupported("write64"); endtask
    virtual task read64 (addr_handle_t a, output bit [63:0] d); unsupported("read64"); d = '0; endtask

    protected function void unsupported(string who);
        `uvm_fatal("PSSWIDTH", {who, ": fw-i2c registers are 32 bits; reg_c should never select this width"})
    endfunction
endclass
