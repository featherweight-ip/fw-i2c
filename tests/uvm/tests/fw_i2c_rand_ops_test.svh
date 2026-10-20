// Random operation streams (bench-plan E9): the equivalence workhorse.
//
// A seeded stream of transfers, each legal under the R76 programming model:
// 7-bit writes and reads (with or without a pointer write and a repeated
// START), unanswered addresses, 10-bit writes and reads (header sequenced by
// software, as in fw_i2c_addr10_test), target NACKs at a random data byte,
// and transfers ended by a STOP on the last byte, by a separate STOP, or
// chained into the next transfer with a repeated START. The stream is split
// into segments; each segment reprograms the core (shutdown, configure) with
// a random PRER and IEN, and each transfer gets a random responder latency
// (clock stretching).
//
// Each operation runs in a random style: blocking (IEN = 1), _start then
// completion_wait (IEN = 1), or _start then polling completion_check. Status
// reads are sprinkled between operations, and the wait for an idle bus after
// a STOP is sometimes skipped (STOP straight into START).
//
// The test keeps a shadow of the responder and checks every result, every
// byte read and the whole bus log, so the single-design views check
// themselves; on the -eq views the scoreboards also compare against R76.
//
// Plusargs: +SEED=<n> (default 1), +N_XFERS=<n> (default 60),
// +PRER_MIN=<n> / +PRER_MAX=<n> (default 2..16; PRER >= 2, D7 is not this
// test's subject), +MAX_LAT_BITS=<n> (largest latency, in SCL periods;
// default 3).
class fw_i2c_rand_ops_test extends fw_i2c_base_test;
    `uvm_component_utils(fw_i2c_rand_ops_test)

    typedef enum { OP_ADDR, OP_WR, OP_RD, OP_STOP } op_e;
    typedef enum { X_W7, X_R7, X_NONE7, X_W10, X_R10, X_BAD10 } xfer_e;

    int unsigned seed = 1;
    int unsigned n_xfers = 60;
    int unsigned prer_min = 2, prer_max = 16;
    int unsigned max_lat_bits = 3;

    bit       ien;
    bit [6:0] addr7;
    bit [9:0] addr10;

    // ---- the shadow responder (i2c_mem_target's rules) ----
    bit [7:0]    s_mem[bit [7:0]];
    bit [7:0]    s_ptr;
    bit          s_ptr_next;
    int unsigned s_wr_count;

    // ---- the expected bus log, and statistics ----
    string       exp_log[$];
    bit          in_xfer;      // a START has been sent and no STOP since
    int unsigned n_kind[string];
    int unsigned n_style[3];
    int unsigned n_ops, n_status, n_back_to_back;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        void'($value$plusargs("SEED=%d", seed));
        void'($value$plusargs("N_XFERS=%d", n_xfers));
        void'($value$plusargs("PRER_MIN=%d", prer_min));
        void'($value$plusargs("PRER_MAX=%d", prer_max));
        void'($value$plusargs("MAX_LAT_BITS=%d", max_lat_bits));
    endfunction

    // The test's own generator (splitmix64), so that +SEED selects the
    // stream, and one seed gives the same stream on every view. (Verilator's
    // $urandom(seed) does not reseed the calling thread.)
    bit [63:0] rng_state;

    function bit [31:0] rnd();
        bit [63:0] z;
        rng_state += 64'h9E3779B97F4A7C15;
        z = rng_state;
        z = (z ^ (z >> 30)) * 64'hBF58476D1CE4E5B9;
        z = (z ^ (z >> 27)) * 64'h94D049BB133111EB;
        return 32'(z ^ (z >> 31));
    endfunction

    // A value in [lo, hi].
    function int unsigned rnd_range(int unsigned hi, int unsigned lo = 0);
        return lo + rnd() % (hi - lo + 1);
    endfunction

    function bit pct(int unsigned p); return rnd_range(99) < p; endfunction

    function bit [7:0] hdr10(bit [9:0] a, bit read); return {5'b11110, a[9:8], read}; endfunction

    function string ack_s(bit nack); return nack ? "-" : "+"; endfunction

    // ---- shadow responder ----

    function void s_addressed_write();
        s_ptr_next = 1'b1;
        s_wr_count = 0;
    endfunction

    // A data byte the master writes: the target's acknowledge (1 = NACK).
    function bit s_rx(bit [7:0] data);
        s_wr_count++;
        if (env.tgt.nack_wr_at != 0 && s_wr_count == env.tgt.nack_wr_at) return 1'b1;
        if (s_ptr_next) begin
            s_ptr      = data;
            s_ptr_next = 1'b0;
        end else begin
            s_mem[s_ptr] = data;
            s_ptr++;
        end
        return 1'b0;
    endfunction

    function bit [7:0] s_tx();
        bit [7:0] d = s_mem.exists(s_ptr) ? s_mem[s_ptr] : i2c_mem_target::init_byte(s_ptr);
        s_ptr++;
        return d;
    endfunction

    // ---- one operation, in a random style ----

    task poll(output fw_i2c_result_s r);
        fw_i2c_check_s st;
        int n = 0;
        do begin
            dev().completion_check(st);
            n++;
        end while (!st.done && n < 100000);
        check(st.done, "operation never completed (polled)");
        r.data = 0;
        r.sr = st.sr;
    endtask

    task op(op_e k, output fw_i2c_result_s r, input bit [7:0] b = 0,
            input bit nack = 0, input bit stop = 0);
        int unsigned style = ien ? rnd_range(2, 0) : 2;
        n_style[style]++;
        n_ops++;
        if (style == 0) begin
            case (k)
                OP_ADDR: dev().address(r, b);
                OP_WR:   dev().write_byte(r, b, stop);
                OP_RD:   dev().read_byte(r, nack, stop);
                OP_STOP: dev().stop(r);
            endcase
        end else begin
            case (k)
                OP_ADDR: dev().address_start(b);
                OP_WR:   dev().write_byte_start(b, stop);
                OP_RD:   dev().read_byte_start(nack, stop);
                OP_STOP: dev().stop_start();
            endcase
            if (style == 1) dev().completion_wait(r);
            else            poll(r);
            if (k == OP_RD) begin
                fw_i2c_regs__RXR_s rxr;
                env.regs.RXR.read(rxr);
                r.data = rxr.DATA;
            end
        end
        if (pct(15)) begin
            fw_i2c_result_s s;
            dev().read_status(s);
            n_status++;
        end
    endtask

    // ---- the pieces of a transfer; each appends to the expected log ----

    // START (or a repeated START, if a transfer is open) and an address byte.
    task send_addr(string what, bit [7:0] b, bit exp_nack);
        fw_i2c_result_s r;
        exp_log.push_back(in_xfer ? "Sr" : "S");
        in_xfer = 1'b1;
        op(OP_ADDR, r, b);
        check_result(what, r, exp_nack);
        exp_log.push_back($sformatf("A%02h%s", b, ack_s(exp_nack)));
    endtask

    // The second header byte of a 10-bit address (an address phase too).
    task send_addr10_lo(string what, bit [7:0] b, bit exp_nack, bit stop = 0);
        fw_i2c_result_s r;
        op(OP_WR, r, b, 0, stop);
        check_result(what, r, exp_nack);
        exp_log.push_back($sformatf("A%02h%s", b, ack_s(exp_nack)));
        if (stop) end_stop();
    endtask

    // A data byte; returns the target's NACK.
    task send_data(string what, bit [7:0] b, bit stop, output bit nacked);
        fw_i2c_result_s r;
        nacked = s_rx(b);
        op(OP_WR, r, b, 0, stop);
        check_result(what, r, nacked);
        exp_log.push_back($sformatf("D%02h%s", b, ack_s(nacked)));
        if (stop) end_stop();
    endtask

    task recv_data(string what, bit nack, bit stop);
        fw_i2c_result_s r;
        bit [7:0] exp = s_tx();
        op(OP_RD, r, 0, nack, stop);
        check_result(what, r, nack);
        check(r.data == exp, $sformatf("%s: read 0x%02h, expected 0x%02h", what, r.data, exp));
        exp_log.push_back($sformatf("D%02h%s", exp, ack_s(nack)));
        if (stop) end_stop();
    endtask

    function void end_stop();
        exp_log.push_back("P");
        in_xfer = 1'b0;
    endfunction

    task send_stop(string what);
        fw_i2c_result_s r;
        op(OP_STOP, r);
        check(r.sr.irq_flag == 1 && r.sr.al == 0, {what, ": STOP"});
        end_stop();
    endtask

    // How a transfer ends: 0 = STOP with its last byte, 1 = a separate STOP,
    // 2 = left open for a repeated START (not for a segment's last transfer:
    // the core is reconfigured only with the bus idle).
    function int unsigned pick_end(bit last);
        int unsigned e = rnd_range(99, 0);
        if (e < 50) return 0;
        if (e < 75 || last) return 1;
        return 2;
    endfunction

    // Bytes to write, then end the transfer as `how` says. A target NACK
    // ends the write early: with a STOP, or left open for a repeated START.
    task write_body(string what, int unsigned n, int unsigned how);
        bit nacked = 0;
        for (int unsigned i = 0; i < n && !nacked; i++)
            send_data($sformatf("%s: byte %0d", what, i), 8'(rnd()),
                      i == n - 1 && how == 0, nacked);
        if (in_xfer && how != 2) send_stop(what);
    endtask

    task read_body(string what, int unsigned n, int unsigned how);
        for (int unsigned i = 0; i < n; i++) begin
            bit last = (i == n - 1);
            recv_data($sformatf("%s: byte %0d", what, i), last, last && how == 0);
        end
        if (how == 1) send_stop(what);
    endtask

    // ---- one transfer ----

    task xfer(int unsigned idx, bit last);
        xfer_e       k   = xfer_e'(rnd_range(5, 0));
        int unsigned how = pick_end(last);
        string       what = $sformatf("xfer %0d (%s)", idx, k.name());
        n_kind[k.name()]++;

        // The responder, for this transfer: NACK one data byte now and then
        // (the pointer byte is byte 1), and a random latency.
        env.tgt.nack_wr_at = pct(20) ? rnd_range(5, 1) : 0;
        env.tgt.latency    = pct(30) ? rnd_range(max_lat_bits * 50 * (prer + 1), 1) * 1ns : 0;

        case (k)
            X_W7: begin
                send_addr({what, ": address"}, {addr7, 1'b0}, 0);
                s_addressed_write();
                write_body(what, rnd_range(6, 0), how);
            end
            X_R7: begin
                if (pct(60)) begin   // set the pointer, then a repeated START
                    bit nacked;
                    send_addr({what, ": address"}, {addr7, 1'b0}, 0);
                    s_addressed_write();
                    send_data({what, ": pointer"}, 8'(rnd()), 0, nacked);
                    if (nacked) begin
                        send_stop(what);
                        return;
                    end
                end
                send_addr({what, ": read address"}, {addr7, 1'b1}, 0);
                read_body(what, rnd_range(6, 1), how);
            end
            X_NONE7: begin
                bit [6:0] a;
                do a = 7'(rnd_range(7'h77, 7'h08)); while (a == addr7);
                send_addr({what, ": address"}, {a, 1'(rnd())}, 1);
                if (how != 2) send_stop(what);
            end
            X_W10: begin
                send_addr({what, ": header 1"}, hdr10(addr10, 0), 0);
                send_addr10_lo({what, ": header 2"}, addr10[7:0], 0);
                s_addressed_write();
                write_body(what, rnd_range(6, 0), how);
            end
            X_R10: begin
                bit nacked;
                send_addr({what, ": header 1"}, hdr10(addr10, 0), 0);
                send_addr10_lo({what, ": header 2"}, addr10[7:0], 0);
                s_addressed_write();
                send_data({what, ": pointer"}, 8'(rnd()), 0, nacked);
                if (nacked) begin
                    send_stop(what);
                    return;
                end
                send_addr({what, ": Sr header"}, hdr10(addr10, 1), 0);
                read_body(what, rnd_range(6, 1), how);
            end
            X_BAD10: begin
                // Wrong A9..A8 (NACK at header byte 1) or wrong A7..A0 (byte 2).
                if (pct(50)) begin
                    send_addr({what, ": header 1"}, hdr10(addr10 ^ 10'h100, 0), 1);
                end else begin
                    send_addr({what, ": header 1"}, hdr10(addr10, 0), 0);
                    send_addr10_lo({what, ": header 2"}, 8'(addr10[7:0] ^ 8'h01), 1);
                end
                if (how != 2) send_stop(what);
            end
        endcase

        // After a STOP: usually wait for the bus to go idle, sometimes go
        // straight on to the next START.
        if (!in_xfer) begin
            if (pct(70) || last) wait_idle({what, ": after the STOP"});
            else n_back_to_back++;
        end
    endtask

    task segment(ref int unsigned idx, input int unsigned n);
        if (idx != 0) begin
            wait_idle("before reconfiguring");
            dev().shutdown();
        end
        prer = 16'(rnd_range(prer_max, prer_min));
        ien  = 1'(rnd());
        `uvm_info("RAND", $sformatf("segment at xfer %0d: PRER %0d, IEN %0d, %0d transfer(s)",
                                    idx, prer, ien, n), UVM_MEDIUM)
        dev().configure(prer, ien);
        for (int unsigned i = 0; i < n; i++) begin
            xfer(idx, i == n - 1);
            idx++;
        end
    endtask

    task run_phase(uvm_phase phase);
        int unsigned idx = 0;
        int          log0;
        string       exp;
        phase.raise_objection(this);

        rng_state = 64'(seed);
        `uvm_info("RAND", $sformatf("seed %0d, %0d transfers, PRER %0d..%0d",
                                    seed, n_xfers, prer_min, prer_max), UVM_LOW)
        addr7  = env.tgt.addr7;
        addr10 = env.tgt.addr10;
        log0   = env.log.events.size();

        while (idx < n_xfers) begin
            int unsigned n = rnd_range(10, 1);
            if (n > n_xfers - idx) n = n_xfers - idx;
            segment(idx, n);
        end
        env.tgt.nack_wr_at = 0;
        env.tgt.latency    = 0;

        // The responder's memory against the shadow, and the whole bus log.
        foreach (s_mem[a])
            check(env.tgt.peek(a) == s_mem[a],
                  $sformatf("target memory[0x%02h] = 0x%02h, expected 0x%02h",
                            a, env.tgt.peek(a), s_mem[a]));
        foreach (exp_log[i]) exp = (i == 0) ? exp_log[i] : {exp, " ", exp_log[i]};
        check_log("random stream", exp, log0);

        begin
            string ks = "";
            foreach (n_kind[k]) ks = {ks, $sformatf(" %s=%0d", k, n_kind[k])};
            `uvm_info("RAND", $sformatf({"seed %0d: %0d transfers (%s ), %0d operations ",
                                         "(blocking %0d, start+wait %0d, start+poll %0d), ",
                                         "%0d status reads, %0d STOP-to-START without idle wait, ",
                                         "%0d bus events, %0d bytes written to memory"},
                                        seed, n_xfers, ks, n_ops, n_style[0], n_style[1],
                                        n_style[2], n_status, n_back_to_back,
                                        env.log.events.size() - log0, s_mem.size()),
                      UVM_LOW)
        end
        phase.drop_objection(this);
    endtask
endclass
