// The responder pair of an equivalence view (bench-plan §3.2). The DUT side's
// responder is the active one; i2c_decision_rec wraps it and records each
// decision it makes, in order. On R76's side, i2c_mirror_target takes the
// next decision, checks that R76 asked the same question at the same position,
// and gives the same answer.
//
// If R76 gets to a position before the DUT has decided it, the mirror blocks.
// The target transactor holds SCL low meanwhile, so the wait is ordinary clock
// stretching on R76's bus. The mirror also keeps the responder's latency: it
// answers no sooner than the active responder took to decide. A guard turns a
// decision that never arrives into a report.
typedef enum { I2C_DEC_ADDR, I2C_DEC_ADDR10_HI, I2C_DEC_RX, I2C_DEC_TX } i2c_decision_kind_e;

class i2c_decision;
    i2c_decision_kind_e kind;
    bit [9:0] addr;       // ADDR: the address; ADDR10_HI: addr[1:0]
    bit       addr_10b;   // ADDR
    bit       read;       // ADDR
    bit [7:0] data;       // RX: the byte received; TX: the byte sent
    bit       ack;        // ADDR, ADDR10_HI, RX: the answer; TX: the input ack
    time      latency;    // how long the active responder took

    function string str();
        case (kind)
            I2C_DEC_ADDR:      return $sformatf("addressed(0x%03h, 10b=%0d, read=%0d) -> ack=%0d",
                                                addr, addr_10b, read, ack);
            I2C_DEC_ADDR10_HI: return $sformatf("addressed_10b_hi(%0d) -> ack=%0d", addr[1:0], ack);
            I2C_DEC_RX:        return $sformatf("rx_byte(0x%02h) -> ack=%0d", data, ack);
            default:           return $sformatf("tx_byte(ack=%0d) -> 0x%02h", ack, data);
        endcase
    endfunction

    // The question part (what the bus asked), for the mirror's position check.
    function string question();
        case (kind)
            I2C_DEC_ADDR:      return $sformatf("addressed(0x%03h, 10b=%0d, read=%0d)", addr, addr_10b, read);
            I2C_DEC_ADDR10_HI: return $sformatf("addressed_10b_hi(%0d)", addr[1:0]);
            I2C_DEC_RX:        return $sformatf("rx_byte(0x%02h)", data);
            default:           return $sformatf("tx_byte(ack=%0d)", ack);
        endcase
    endfunction
endclass

// The decisions made so far, shared by the recorder and the mirror.
class i2c_decision_q;
    i2c_decision q[$];
    event        pushed;
    function void push(i2c_decision d); q.push_back(d); -> pushed; endfunction
endclass

class i2c_decision_rec implements i2c_target_if;
    i2c_target_if  impl;
    i2c_decision_q dq;

    function new(i2c_target_if impl, i2c_decision_q dq); this.impl = impl; this.dq = dq; endfunction

    virtual task addressed(input bit [9:0] addr, input bit addr_10b, input bit read,
                           output bit ack);
        i2c_decision d = new();
        time t0 = $time;
        impl.addressed(addr, addr_10b, read, ack);
        d.kind = I2C_DEC_ADDR; d.addr = addr; d.addr_10b = addr_10b; d.read = read;
        d.ack = ack; d.latency = $time - t0;
        dq.push(d);
    endtask
    virtual task addressed_10b_hi(input bit [1:0] addr_hi, output bit ack);
        i2c_decision d = new();
        time t0 = $time;
        impl.addressed_10b_hi(addr_hi, ack);
        d.kind = I2C_DEC_ADDR10_HI; d.addr = 10'(addr_hi); d.ack = ack; d.latency = $time - t0;
        dq.push(d);
    endtask
    virtual task rx_byte(input bit [7:0] data, output bit ack);
        i2c_decision d = new();
        time t0 = $time;
        impl.rx_byte(data, ack);
        d.kind = I2C_DEC_RX; d.data = data; d.ack = ack; d.latency = $time - t0;
        dq.push(d);
    endtask
    virtual task tx_byte(output bit [7:0] data, input bit ack);
        i2c_decision d = new();
        time t0 = $time;
        impl.tx_byte(data, ack);
        d.kind = I2C_DEC_TX; d.data = data; d.ack = ack; d.latency = $time - t0;
        dq.push(d);
    endtask
endclass

class i2c_mirror_target implements i2c_target_if;
    i2c_decision_q dq;
    i2c_eq_report  rpt;
    int unsigned   pos;              // decisions used so far
    time           guard = 1ms;      // longest wait for the DUT's decision
    time           blocked;          // total time R76 waited on the DUT
    int unsigned   sabotage_at;      // self-test: invert the answer at this decision (1-based)

    function new(i2c_decision_q dq); this.dq = dq; rpt = new(); endfunction

    // Wait for decision `pos`, check its question, and keep the latency.
    protected task next(i2c_decision ask, output i2c_decision d);
        time t0 = $time;
        d = null;
        if (dq.q.size() <= pos) begin
            fork
                begin
                    while (dq.q.size() <= pos) @(dq.pushed);
                end
                #(guard);
            join_any
            disable fork;
            blocked += $time - t0;
        end
        if (dq.q.size() <= pos) begin
            rpt.mismatch("EQTGT", $sformatf("R76 waiting at decision #%0d (%s) for %0t; the DUT has made %0d",
                                            pos + 1, ask.question(), guard, dq.q.size()));
            return;
        end
        d = dq.q[pos];
        pos++;
        if (d.kind != ask.kind || d.question() != ask.question())
            rpt.mismatch("EQTGT", $sformatf("decision #%0d: R76 asked %s, the DUT was asked %s",
                                            pos, ask.question(), d.question()));
        if ($time - t0 < d.latency) #(d.latency - ($time - t0));
    endtask

    protected function bit sabotage();
        if (sabotage_at == 0 || pos != sabotage_at) return 1'b0;
        `uvm_info("EQTGT", $sformatf("self-test: the mirror inverts its answer at decision #%0d", pos),
                  UVM_LOW)
        return 1'b1;
    endfunction

    virtual task addressed(input bit [9:0] addr, input bit addr_10b, input bit read,
                           output bit ack);
        i2c_decision ask = new(), d;
        ask.kind = I2C_DEC_ADDR; ask.addr = addr; ask.addr_10b = addr_10b; ask.read = read;
        next(ask, d);
        ack = (d == null) ? 1'b0 : d.ack ^ sabotage();
    endtask
    virtual task addressed_10b_hi(input bit [1:0] addr_hi, output bit ack);
        i2c_decision ask = new(), d;
        ask.kind = I2C_DEC_ADDR10_HI; ask.addr = 10'(addr_hi);
        next(ask, d);
        ack = (d == null) ? 1'b0 : d.ack ^ sabotage();
    endtask
    virtual task rx_byte(input bit [7:0] data, output bit ack);
        i2c_decision ask = new(), d;
        ask.kind = I2C_DEC_RX; ask.data = data;
        next(ask, d);
        ack = (d == null) ? 1'b0 : d.ack ^ sabotage();
    endtask
    virtual task tx_byte(output bit [7:0] data, input bit ack);
        i2c_decision ask = new(), d;
        ask.kind = I2C_DEC_TX; ask.ack = ack;
        next(ask, d);
        data = (d == null) ? 8'hFF : d.data ^ {8{sabotage()}};
    endtask

    // End of test: every DUT decision must have been used.
    function void check_end();
        if (dq.q.size() > pos)
            rpt.mismatch("EQTGT", $sformatf("the DUT made %0d decisions, R76 used %0d; next unused: %s",
                                            dq.q.size(), pos, dq.q[pos].str()));
    endfunction

    function void report();
        `uvm_info("EQTGT", $sformatf("%0d responder decisions mirrored; R76 waited %0.0f ns in all for the DUT's decisions",
                                     pos, real'(blocked) / real'(1ns)), UVM_LOW)
    endfunction
endclass
