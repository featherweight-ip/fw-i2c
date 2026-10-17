// What a test sees as "the model" in an equivalence view: the DUT and the R76
// arm as one. Operations do not come through here: each design has its own
// operation model instance under fw_i2c_op_eq. This covers what tests do
// beside operations:
//
//   rf_if()     a tee: each register access goes to both designs at once;
//               a read returns the DUT's value, and the two are compared
//   irq_level() the DUT's line, compared with R76's
//   timed()     both are timed
class i2c_rf_tee implements wb_proto_if #(32, 32);
    wb_proto_if #(32, 32) a, b;
    i2c_eq_report         rpt;
    bit                   cmp_reads = 1'b1;

    function new(wb_proto_if #(32, 32) a, wb_proto_if #(32, 32) b, i2c_eq_report rpt);
        this.a = a;
        this.b = b;
        this.rpt = rpt;
    endfunction

    virtual task access(input  [31:0] adr, input [31:0] dat_w, input [3:0] sel, input we,
                        output [31:0] dat_r, output err);
        bit [31:0] ra, rb;
        bit        ea, eb;
        fork
            a.access(adr, dat_w, sel, we, ra, ea);
            b.access(adr, dat_w, sel, we, rb, eb);
        join
        if (ea != eb)
            rpt.mismatch("EQREG", $sformatf("%s 0x%02h: bus error %0d vs %0d [DUT vs R76]",
                                            we ? "write" : "read", adr, ea, eb));
        else if (!we && cmp_reads && ra != rb)
            rpt.mismatch("EQREG", $sformatf("read 0x%02h: 0x%08h vs 0x%08h [DUT vs R76]",
                                            adr, ra, rb));
        dat_r = ra;
        err   = ea;
    endtask
endclass

class i2c_eq_model extends i2c_model_base;
    i2c_model_base dut, refm;
    i2c_eq_report  rpt;
    protected i2c_rf_tee m_tee;

    function new(i2c_model_base dut, i2c_model_base refm);
        super.new({dut.name, "+", refm.name});
        this.dut  = dut;
        this.refm = refm;
        rpt = new();
    endfunction

    virtual function wb_proto_if #(32, 32) rf_if();
        if (m_tee == null) m_tee = new(dut.rf_if(), refm.rf_if(), rpt);
        return m_tee;
    endfunction

    virtual task start();
        dut.start();
        refm.start();
    endtask

    virtual function bit timed(); return dut.timed() && refm.timed(); endfunction

    virtual function bit irq_level();
        if (dut.irq_level() !== refm.irq_level())
            rpt.mismatch("EQIRQ", $sformatf("interrupt line %0d vs %0d [DUT vs R76]",
                                            dut.irq_level(), refm.irq_level()));
        return dut.irq_level();
    endfunction
endclass
