// The standard responder: a byte-addressed memory behind a 7-bit address,
// EEPROM-style. The first byte written after an address phase sets the
// pointer; later bytes write and increment it. Reads return from the pointer
// and increment it. Every decision can take simulated time, which stretches
// the clock at signal level.
//
// Knobs a test sets: addr7 (the address answered), nack_wr_at (NACK the n-th
// data byte of a write, 1-based; 0 = never), latency.
class i2c_mem_target implements i2c_target_if;
    bit [6:0]    addr7   = 7'h50;
    int unsigned nack_wr_at;
    time         latency = 0;

    bit [7:0]    mem[bit [7:0]];
    bit [7:0]    ptr;
    protected bit          m_ptr_next;   // the next write byte is the pointer
    protected int unsigned m_wr_count;   // data bytes in this write

    static function bit [7:0] init_byte(bit [7:0] off);
        return off ^ 8'hA5;
    endfunction

    function bit [7:0] peek(bit [7:0] off);
        return mem.exists(off) ? mem[off] : init_byte(off);
    endfunction

    protected task delay();
        if (latency != 0) #(latency);
    endtask

    virtual task addressed(input bit [9:0] addr, input bit addr_10b, input bit read,
                           output bit ack);
        delay();
        ack = !addr_10b && addr[6:0] == addr7;
        if (ack && !read) begin
            m_ptr_next = 1'b1;
            m_wr_count = 0;
        end
    endtask

    virtual task addressed_10b_hi(input bit [1:0] addr_hi, output bit ack);
        delay();
        ack = 1'b0;
    endtask

    virtual task rx_byte(input bit [7:0] data, output bit ack);
        delay();
        m_wr_count++;
        ack = !(nack_wr_at != 0 && m_wr_count == nack_wr_at);
        if (!ack) return;
        if (m_ptr_next) begin
            ptr        = data;
            m_ptr_next = 1'b0;
        end else begin
            mem[ptr] = data;
            ptr++;
        end
    endtask

    virtual task tx_byte(output bit [7:0] data, input bit ack);
        delay();
        data = peek(ptr);
        ptr++;
    endtask
endclass
