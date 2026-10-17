// Bus timing measured from the SCL/SDA lines, against UM10204 Table 10
// (Standard mode and Fast mode). A view's top calls sample() whenever a line
// changes; `drv` is the measured master's own SDA drive (1 = pulling low),
// so tVD;DAT is the master's and not the target's. Measurement runs only
// while `enabled`; clear() starts again.
//
//   period   SCL rise to SCL rise (not across a START or STOP)
//   tLOW     SCL fall to SCL rise
//   tHIGH    SCL rise to SCL fall (not the high phase of a START)
//   tHD;STA  START/Sr edge to the SCL fall that follows
//   tSU;STA  SCL rise to an Sr edge
//   tSU;STO  SCL rise to the STOP edge
//   tBUF     STOP edge to the next START edge
//   tSU;DAT  the last SDA change while SCL is low, to the SCL rise
//   tVD;DAT  SCL fall to a change of the master's SDA drive
class i2c_timing_stat;
    string       name;
    int unsigned n;
    realtime     min, max;
    function void add(realtime v);
        if (n == 0 || v < min) min = v;
        if (n == 0 || v > max) max = v;
        n++;
    endfunction
endclass

class i2c_line_timing;
    bit              enabled;
    i2c_timing_stat  stats[string];
    string           order[$];
    int unsigned     n_scl_rise;
    event            scl_rise_ev;

    protected bit      m_scl = 1, m_sda = 1, m_drv = 0;
    protected bit      m_busy, m_start_pending;
    protected bit      m_have_rise, m_have_fall, m_have_sda_chg, m_have_stop;
    protected realtime m_t_rise, m_t_fall, m_t_sda_chg, m_t_start, m_t_stop;

    function new();
        string names[] = '{"period", "tLOW", "tHIGH", "tHD;STA", "tSU;STA", "tSU;STO",
                           "tBUF", "tSU;DAT", "tVD;DAT"};
        foreach (names[i]) order.push_back(names[i]);
        clear();
    endfunction

    function void clear();
        foreach (order[i]) begin
            i2c_timing_stat s = new();
            s.name = order[i];
            stats[order[i]] = s;
        end
    endfunction

    function i2c_timing_stat get(string name); return stats[name]; endfunction

    protected function void add(string name, realtime v);
        if (enabled) stats[name].add(v);
    endfunction

    function void sample(realtime t, bit scl, bit sda, bit drv);
        if (scl != m_scl) begin
            if (scl) begin
                if (m_have_fall)    add("tLOW", t - m_t_fall);
                if (m_have_rise)    add("period", t - m_t_rise);
                if (m_have_sda_chg) add("tSU;DAT", t - m_t_sda_chg);
                m_t_rise = t;
                m_have_rise = 1;
                m_have_sda_chg = 0;
                n_scl_rise++;
                -> scl_rise_ev;
            end else begin
                if (m_start_pending) add("tHD;STA", t - m_t_start);
                else if (m_have_rise) add("tHIGH", t - m_t_rise);
                m_start_pending = 0;
                m_t_fall = t;
                m_have_fall = 1;
            end
            m_scl = scl;
        end
        if (sda != m_sda) begin
            if (m_scl) begin
                if (!sda) begin                  // START or Sr
                    if (m_busy) add("tSU;STA", t - m_t_rise);
                    else if (m_have_stop) add("tBUF", t - m_t_stop);
                    m_busy = 1;
                    m_start_pending = 1;
                    m_t_start = t;
                    m_have_rise = 0;
                end else begin                   // STOP
                    if (m_have_rise) add("tSU;STO", t - m_t_rise);
                    m_busy = 0;
                    m_t_stop = t;
                    m_have_stop = 1;
                    m_have_rise = 0;
                    m_have_fall = 0;
                end
            end else begin
                m_t_sda_chg = t;
                m_have_sda_chg = 1;
            end
            m_sda = sda;
        end
        if (drv != m_drv) begin
            if (!m_scl && m_have_fall && m_busy) add("tVD;DAT", t - m_t_fall);
            m_drv = drv;
        end
    endfunction

    // UM10204 Table 10 limits, in ns: [mode][param] = {min, max}; 0 = none.
    static function void limits(string mode, string name, output real lo, output real hi);
        lo = 0;
        hi = 0;
        if (mode == "sm") begin
            case (name)
                "period":  lo = 10000;
                "tLOW":    lo = 4700;
                "tHIGH":   lo = 4000;
                "tHD;STA": lo = 4000;
                "tSU;STA": lo = 4700;
                "tSU;STO": lo = 4000;
                "tBUF":    lo = 4700;
                "tSU;DAT": lo = 250;
                "tVD;DAT": hi = 3450;
            endcase
        end else begin
            case (name)
                "period":  lo = 2500;
                "tLOW":    lo = 1300;
                "tHIGH":   lo = 600;
                "tHD;STA": lo = 600;
                "tSU;STA": lo = 600;
                "tSU;STO": lo = 600;
                "tBUF":    lo = 1300;
                "tSU;DAT": lo = 100;
                "tVD;DAT": hi = 900;
            endcase
        end
    endfunction

    // 1 if every measured value is within the mode's limits. Reports each.
    function bit report(string mode, string id);
        bit ok = 1;
        foreach (order[i]) begin
            i2c_timing_stat s = stats[order[i]];
            real lo, hi;
            string verdict;
            limits(mode, s.name, lo, hi);
            if (s.n == 0) verdict = "not seen";
            else if ((lo != 0 && $rtoi(s.min / 1ns + 0.5) < lo) ||
                     (hi != 0 && $rtoi(s.max / 1ns + 0.5) > hi)) begin
                verdict = "VIOLATES";
                ok = 0;
            end else verdict = "ok";
            `uvm_info(id, $sformatf("%-8s n=%4d  min %8.0f ns  max %8.0f ns  limit %s%6.0f ns  %s",
                                    s.name, s.n, s.min / 1ns, s.max / 1ns,
                                    hi != 0 ? "<=" : ">=", hi != 0 ? hi : lo, verdict), UVM_LOW)
        end
        return ok;
    endfunction
endclass
