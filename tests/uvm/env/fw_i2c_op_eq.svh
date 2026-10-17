// The operation-level equivalence scoreboard (bench-plan §3.1): an
// implementation of the operation API that forks each call into two operation
// model instances, one per design, and compares their outputs once both have
// returned. The DUT's outputs go back to the test. Each instance runs its own
// wait loop on its own design, so the designs are aligned at every operation
// boundary and timing inside an operation never matters.
//
// Status operations need one more rule, because a test acts on what the DUT
// reports. When the DUT reports a state that R76 reaches only later (IF set
// for completion_check, BUSY clear for read_status), the scoreboard re-reads
// R76 until it gets there (bounded) before comparing. completion_check is
// only forwarded to R76 once the DUT reports done; until then R76 runs free.
//
// Timing is report-only: per operation kind, the time each design took.
class fw_i2c_op_eq implements fw_i2c_c_ctxt_if;
    fw_i2c_c_ctxt_if  a;      // the DUT
    fw_i2c_c_ctxt_if  b;      // R76
    i2c_allowed_diffs allow;
    i2c_eq_report     rpt;

    // Self-test hook: R76 runs with PRER' = (PRER+1) * ref_prer_scale - 1, so
    // its bus is slower by that factor and the timing report shows the ratio.
    // +EQ_REF_PRER_SCALE=<n>.
    int unsigned ref_prer_scale = 1;
    int unsigned max_align_reads = 10000;

    int unsigned n_ops, n_aligned;
    protected realtime t_a[string], t_b[string];
    protected int unsigned n_kind[string];

    function new(fw_i2c_c_ctxt_if a, fw_i2c_c_ctxt_if b, i2c_allowed_diffs allow);
        this.a = a;
        this.b = b;
        this.allow = allow;
        rpt = new();
        void'($value$plusargs("EQ_REF_PRER_SCALE=%d", ref_prer_scale));
        if (ref_prer_scale == 0) ref_prer_scale = 1;
    endfunction

    // ---- recording and comparison ----

    protected function void timed(string kind, realtime t0, realtime ta, realtime tb);
        n_ops++;
        if (!n_kind.exists(kind)) begin
            n_kind[kind] = 0;
            t_a[kind] = 0;
            t_b[kind] = 0;
        end
        n_kind[kind]++;
        t_a[kind] += ta - t0;
        t_b[kind] += tb - t0;
    endfunction

    protected function string sr_str(fw_i2c_sr_s s);
        return $sformatf("{RXACK=%0d BUSY=%0d AL=%0d TIP=%0d IF=%0d}",
                         s.rxack, s.busy, s.al, s.tip, s.irq_flag);
    endfunction

    // Compare two SR decodes. BUSY is left to the busy_lag rule.
    protected function void cmp_sr(string op, fw_i2c_sr_s sa, fw_i2c_sr_s sb);
        if (sa.rxack != sb.rxack || sa.al != sb.al || sa.tip != sb.tip ||
            sa.irq_flag != sb.irq_flag)
            rpt.mismatch("EQOP", $sformatf("%s: out status %s vs %s", op, sr_str(sa), sr_str(sb)));
        else if (sa.busy != sb.busy && !allow.allow("busy_lag"))
            rpt.mismatch("EQOP", $sformatf("%s: out status BUSY %0d vs %0d", op, sa.busy, sb.busy));
    endfunction

    protected function void cmp_result(string op, fw_i2c_result_s ra, fw_i2c_result_s rb,
                                       bit cmp_data = 0);
        cmp_sr(op, ra.sr, rb.sr);
        if (cmp_data && ra.data != rb.data)
            rpt.mismatch("EQOP", $sformatf("%s: out data 0x%02h vs 0x%02h", op, ra.data, rb.data));
    endfunction

    protected function string opname(string kind, string args);
        return $sformatf("op #%0d %s(%s) [DUT vs R76]", n_ops, kind, args);
    endfunction

    function bit [15:0] ref_prer(bit [15:0] prer);
        return 16'((32'(prer) + 1) * ref_prer_scale - 1);
    endfunction

    // ---- the API ----

    virtual task address_start(input bit [7:0] addr_byte);
        realtime t0 = $realtime, ta, tb;
        fork
            begin a.address_start(addr_byte); ta = $realtime; end
            begin b.address_start(addr_byte); tb = $realtime; end
        join
        timed("address_start", t0, ta, tb);
    endtask

    virtual task address(output fw_i2c_result_s status, input bit [7:0] addr_byte);
        fw_i2c_result_s ra, rb;
        realtime t0 = $realtime, ta, tb;
        fork
            begin a.address(ra, addr_byte); ta = $realtime; end
            begin b.address(rb, addr_byte); tb = $realtime; end
        join
        timed("address", t0, ta, tb);
        cmp_result(opname("address", $sformatf("0x%02h", addr_byte)), ra, rb);
        status = ra;
    endtask

    virtual task write_byte_start(input bit [7:0] data, input bit stop);
        realtime t0 = $realtime, ta, tb;
        fork
            begin a.write_byte_start(data, stop); ta = $realtime; end
            begin b.write_byte_start(data, stop); tb = $realtime; end
        join
        timed("write_byte_start", t0, ta, tb);
    endtask

    virtual task write_byte(output fw_i2c_result_s status, input bit [7:0] data, input bit stop);
        fw_i2c_result_s ra, rb;
        realtime t0 = $realtime, ta, tb;
        fork
            begin a.write_byte(ra, data, stop); ta = $realtime; end
            begin b.write_byte(rb, data, stop); tb = $realtime; end
        join
        timed("write_byte", t0, ta, tb);
        cmp_result(opname("write_byte", $sformatf("0x%02h, stop=%0d", data, stop)), ra, rb);
        status = ra;
    endtask

    virtual task read_byte_start(input bit nack, input bit stop);
        realtime t0 = $realtime, ta, tb;
        fork
            begin a.read_byte_start(nack, stop); ta = $realtime; end
            begin b.read_byte_start(nack, stop); tb = $realtime; end
        join
        timed("read_byte_start", t0, ta, tb);
    endtask

    virtual task read_byte(output fw_i2c_result_s status, input bit nack, input bit stop);
        fw_i2c_result_s ra, rb;
        realtime t0 = $realtime, ta, tb;
        fork
            begin a.read_byte(ra, nack, stop); ta = $realtime; end
            begin b.read_byte(rb, nack, stop); tb = $realtime; end
        join
        timed("read_byte", t0, ta, tb);
        cmp_result(opname("read_byte", $sformatf("nack=%0d, stop=%0d", nack, stop)), ra, rb, 1);
        status = ra;
    endtask

    virtual task stop_start();
        realtime t0 = $realtime, ta, tb;
        fork
            begin a.stop_start(); ta = $realtime; end
            begin b.stop_start(); tb = $realtime; end
        join
        timed("stop_start", t0, ta, tb);
    endtask

    virtual task stop(output fw_i2c_result_s status);
        fw_i2c_result_s ra, rb;
        realtime t0 = $realtime, ta, tb;
        fork
            begin a.stop(ra); ta = $realtime; end
            begin b.stop(rb); tb = $realtime; end
        join
        timed("stop", t0, ta, tb);
        cmp_result(opname("stop", ""), ra, rb);
        status = ra;
    endtask

    // Forwarded to R76 only once the DUT reports done; then R76 is polled
    // until it is done too, and the two are compared.
    virtual task completion_check(output fw_i2c_check_s status);
        fw_i2c_check_s sa, sb;
        realtime t0 = $realtime, ta, tb;
        int unsigned n = 0;
        a.completion_check(sa);
        ta = $realtime;
        status = sa;
        if (!sa.done) return;
        do begin
            b.completion_check(sb);
            n++;
        end while (!sb.done && n < max_align_reads);
        tb = $realtime;
        if (n > 1) n_aligned++;
        timed("completion_check (done)", t0, ta, tb);
        if (!sb.done)
            rpt.mismatch("EQOP", $sformatf("%s: R76 not done after %0d reads",
                                           opname("completion_check", ""), n));
        cmp_sr(opname("completion_check", ""), sa.sr, sb.sr);
    endtask

    virtual task completion_wait(output fw_i2c_result_s status);
        fw_i2c_result_s ra, rb;
        realtime t0 = $realtime, ta, tb;
        fork
            begin a.completion_wait(ra); ta = $realtime; end
            begin b.completion_wait(rb); tb = $realtime; end
        join
        timed("completion_wait", t0, ta, tb);
        cmp_result(opname("completion_wait", ""), ra, rb);
        status = ra;
    endtask

    // When the DUT reads idle and R76 still busy, R76 is re-read until it is
    // idle too (its STOP detector is behind; bench-plan P5).
    virtual task read_status(output fw_i2c_result_s status);
        fw_i2c_result_s ra, rb;
        realtime t0 = $realtime, ta, tb;
        int unsigned n = 0;
        fork
            begin a.read_status(ra); ta = $realtime; end
            begin b.read_status(rb); tb = $realtime; end
        join
        if (!ra.sr.busy && rb.sr.busy) begin
            n_aligned++;
            while (rb.sr.busy && n < max_align_reads) begin
                b.read_status(rb);
                n++;
            end
            tb = $realtime;
        end
        timed("read_status", t0, ta, tb);
        cmp_result(opname("read_status", ""), ra, rb);
        status = ra;
    endtask

    // The env pumps each instance's interrupt itself; this is for callers
    // that hold only the API.
    virtual task notify_irq();
        a.notify_irq();
        b.notify_irq();
    endtask

    virtual task configure(input bit [15:0] prer, input bit ien);
        realtime t0 = $realtime, ta, tb;
        fork
            begin a.configure(prer, ien); ta = $realtime; end
            begin b.configure(ref_prer(prer), ien); tb = $realtime; end
        join
        timed("configure", t0, ta, tb);
    endtask

    virtual task shutdown();
        realtime t0 = $realtime, ta, tb;
        fork
            begin a.shutdown(); ta = $realtime; end
            begin b.shutdown(); tb = $realtime; end
        join
        timed("shutdown", t0, ta, tb);
    endtask

    // ---- report ----

    // The timing report: per kind, the time each design took and the ratio.
    function void report();
        realtime sa = 0, sb = 0;
        `uvm_info("EQOP", $sformatf("%0d operations compared, %0d difference(s), %0d status alignment(s)%s",
                                    n_ops, rpt.n_mismatch, n_aligned,
                                    ref_prer_scale != 1 ? $sformatf("; R76 PRER scale %0d", ref_prer_scale) : ""),
                  UVM_LOW)
        foreach (n_kind[k]) begin
            sa += t_a[k];
            sb += t_b[k];
            `uvm_info("EQTIME", $sformatf("%-24s %5d  DUT %10.0f ns  R76 %10.0f ns  R76/DUT %5.2f",
                                          k, n_kind[k], t_a[k] / 1ns, t_b[k] / 1ns,
                                          t_a[k] > 0 ? t_b[k] / t_a[k] : 0.0), UVM_LOW)
        end
        `uvm_info("EQTIME", $sformatf("%-24s %5d  DUT %10.0f ns  R76 %10.0f ns  R76/DUT %5.2f",
                                      "all", n_ops, sa / 1ns, sb / 1ns, sa > 0 ? sb / sa : 0.0),
                  UVM_LOW)
    endfunction
endclass
