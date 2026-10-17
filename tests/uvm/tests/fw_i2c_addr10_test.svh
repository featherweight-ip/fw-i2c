// 10-bit addressing, sequenced by software: the core sends each header byte
// as an ordinary byte. Write: address(11110 A9 A8 0), write_byte(A7..A0),
// then the offset and data. Read: the same, then a repeated-START
// address(11110 A9 A8 1). Also both header bytes of a 10-bit address nobody
// answers.
class fw_i2c_addr10_test extends fw_i2c_base_test;
    `uvm_component_utils(fw_i2c_addr10_test)

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function bit [7:0] hdr(bit [9:0] a, bit read); return {5'b11110, a[9:8], read}; endfunction

    // The header: first byte by address(), second by write_byte().
    task header(string what, bit [9:0] a, bit exp_rxack_hi = 0, bit exp_rxack_lo = 0);
        fw_i2c_result_s r;
        dev().address(r, hdr(a, 1'b0));
        check_result({what, ": header byte 1"}, r, exp_rxack_hi);
        if (exp_rxack_hi) return;
        dev().write_byte(r, a[7:0], 1'b0);
        check_result({what, ": header byte 2"}, r, exp_rxack_lo);
    endtask

    task run_phase(uvm_phase phase);
        bit [9:0] a = env.tgt.addr10;
        bit [7:0] wr[] = '{8'hDE, 8'hAD, 8'hBE};
        bit [7:0] rd[];
        fw_i2c_result_s r;
        phase.raise_objection(this);

        dev().configure(prer, 1'b1);

        // Write.
        header("write", a);
        dev().write_byte(r, 8'h90, 1'b0);
        check_result("write: offset", r);
        foreach (wr[i]) begin
            dev().write_byte(r, wr[i], i == wr.size() - 1);
            check_result($sformatf("write: data[%0d]", i), r);
        end
        wait_idle("after the 10-bit write");

        // Read with a repeated START.
        header("read", a);
        dev().write_byte(r, 8'h90, 1'b0);
        check_result("read: offset", r);
        dev().address(r, hdr(a, 1'b1));
        check_result("read: Sr header", r);
        read_bytes("read", wr.size(), rd);
        foreach (wr[i])
            check(rd[i] == wr[i], $sformatf("read[%0d] = 0x%02h, expected 0x%02h", i, rd[i], wr[i]));
        wait_idle("after the 10-bit read");

        // Nobody there: wrong A9..A8 (NACK at byte 1), wrong A7..A0 (byte 2).
        header("wrong A9..A8", a ^ 10'h100, 1'b1);
        dev().stop(r);
        wait_idle("after the byte-1 NACK");
        header("wrong A7..A0", a ^ 10'h001, 1'b0, 1'b1);
        dev().stop(r);
        wait_idle("after the byte-2 NACK");

        foreach (wr[i])
            check(env.tgt.peek(8'(8'h90 + i)) == wr[i], $sformatf("target memory[0x%02h]", 8'h90 + i));
        // Both header bytes are address phases on the bus.
        check_log("10-bit", $sformatf({"S A%02h+ A%02h+ D90+ Dde+ Dad+ Dbe+ P ",
                                       "S A%02h+ A%02h+ D90+ Sr A%02h+ Dde+ Dad+ Dbe- P ",
                                       "S A%02h- P S A%02h+ A%02h- P"},
                                      hdr(a, 0), a[7:0], hdr(a, 0), a[7:0], hdr(a, 1),
                                      hdr(a ^ 10'h100, 0), hdr(a, 0), 8'(a[7:0] ^ 8'h01)));
        `uvm_info("ADDR10", {"bus: ", env.log.str()}, UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass
