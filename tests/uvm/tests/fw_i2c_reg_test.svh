// Register map and reset (register level, not through the operation model):
// reset values, 4-byte stride, reads zero-extended, writes take bits [7:0]
// and need sel[0], adr[1:0] ignored, the TXR/CR readbacks, the reserved word,
// CR ignoring writes while EN is 0, IACK and the reserved CR bits clearing,
// and CR.ACK holding its value after a command. Addresses come from the
// generated register group (env.regs); the expected values from the RDL.
class fw_i2c_reg_test extends fw_i2c_base_test;
    `uvm_component_utils(fw_i2c_reg_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        bit [31:0] PRERLO, PRERHI, CTR, TXR, RXR, CR, SR, TXR_DBG, CR_DBG, RSVD7;
        bit [7:0]  rd[];
        phase.raise_objection(this);

        PRERLO  = 32'(env.regs.PRERlo.addr());
        PRERHI  = 32'(env.regs.PRERhi.addr());
        CTR     = 32'(env.regs.CTR.addr());
        TXR     = 32'(env.regs.TXR.addr());
        RXR     = 32'(env.regs.RXR.addr());
        CR      = 32'(env.regs.CR.addr());
        SR      = 32'(env.regs.SR.addr());
        TXR_DBG = 32'(env.regs.TXR_DBG.addr());
        CR_DBG  = 32'(env.regs.CR_DBG.addr());
        RSVD7   = 32'(env.regs.RSVD7.addr());

        // ---- reset values ----
        expect_reg("PRERlo reset",  PRERLO,  32'h0000_00FF);
        expect_reg("PRERhi reset",  PRERHI,  32'h0000_00FF);
        expect_reg("CTR reset",     CTR,     32'h0000_0000);
        expect_reg("RXR reset",     RXR,     32'h0000_0000);
        expect_reg("SR reset",      SR,      32'h0000_0000);
        expect_reg("TXR_DBG reset", TXR_DBG, 32'h0000_0000);
        expect_reg("CR_DBG reset",  CR_DBG,  32'h0000_0000);
        expect_reg("RSVD7 reset",   RSVD7,   32'h0000_0000);

        // ---- writes take bits [7:0]; reads are zero-extended ----
        reg_write(PRERLO, 32'hFFFF_FF34);
        reg_write(PRERHI, 32'hA5A5_A512);
        expect_reg("PRERlo write", PRERLO, 32'h0000_0034);
        expect_reg("PRERhi write", PRERHI, 32'h0000_0012);

        // CTR stores all eight bits, including the reserved ones.
        reg_write(CTR, 32'h0000_003F);
        expect_reg("CTR reserved bits", CTR, 32'h0000_003F);
        reg_write(CTR, 32'h0000_0000);

        // ---- sel[0] and adr[1:0] ----
        reg_write(CTR, 32'h0000_0080, 4'b1110);
        expect_reg("CTR write without sel[0]", CTR, 32'h0000_0000);
        reg_write(CTR, 32'h0000_0080, 4'b0001);
        expect_reg("CTR write with sel[0] only", CTR, 32'h0000_0080);
        expect_reg("CTR, adr[1:0] = 3", CTR | 32'h3, 32'h0000_0080);
        reg_write(PRERLO | 32'h2, 32'h0000_0056);
        expect_reg("PRERlo written at adr[1:0] = 2", PRERLO, 32'h0000_0056);

        // ---- the reserved word reads 0 and ignores writes ----
        reg_write(RSVD7, 32'hFFFF_FFFF);
        expect_reg("RSVD7 after a write", RSVD7, 32'h0000_0000);

        // ---- TXR readback ----
        reg_write(TXR, 32'h0000_00A0);
        expect_reg("TXR readback", TXR_DBG, 32'h0000_00A0);

        // ---- CR ignores writes while EN is 0 ----
        reg_write(CTR, 32'h0000_0000);
        reg_write(CR, 32'h0000_0008);
        expect_reg("CR write with EN = 0", CR_DBG, 32'h0000_0000);

        // With EN = 1, ACK is stored and holds; IACK and the reserved bits
        // 2:1 clear on the next clock. No command bit, so nothing starts.
        reg_write(CTR, 32'h0000_0080);
        reg_write(CR, 32'h0000_000F);
        expect_reg("CR readback: ACK holds, IACK/RSVD clear", CR_DBG, 32'h0000_0008);
        expect_reg("SR after a CR write with no command", SR, 32'h0000_0000);
        reg_write(CR, 32'h0000_0000);
        expect_reg("CR readback cleared", CR_DBG, 32'h0000_0000);
        reg_write(CTR, 32'h0000_0000);

        // ---- after a transfer ----
        // A read ending with NACK + STOP: the command bits clear, ACK holds,
        // RXR holds the byte read.
        dev().configure(prer, 1'b1);
        read_mem(7'h50, 8'h00, 1, rd);
        check(rd[0] == env.tgt.peek(8'h00),
              $sformatf("read 0x%02h, expected 0x%02h", rd[0], env.tgt.peek(8'h00)));
        expect_reg("CR readback after NACK + STOP", CR_DBG, 32'h0000_0008);
        expect_reg("RXR after the read", RXR, {24'h0, rd[0]});
        expect_reg("TXR readback after the transfer", TXR_DBG, {24'h0, 7'h50, 1'b1});
        wait_idle("after the read");
        dev().shutdown();
        expect_reg("CTR after shutdown", CTR, 32'h0000_0000);

        phase.drop_objection(this);
    endtask
endclass
