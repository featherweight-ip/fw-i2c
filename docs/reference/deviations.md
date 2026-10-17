# Deviations, defects and quirks

This page lists every point where the RTL (R76, `dba90b2`) differs from
the PDF, and every suspected defect found while reading it. Each defect
gets a directed test, planned in {doc}`verification`. The IDs are also
used in {doc}`../design/index`.

## Suspected defects

| ID | Area | Description | Status |
|---|---|---|---|
| D1 | Top: CR | The command-bit auto-clear is skipped if a WISHBONE write to any register is accepted in the same clock as `done` (or an unexpected-STOP arbitration loss). The command bits stay set and the byte controller **repeats the command**. A TXR write for the next byte, timed to land as a byte completes, can trigger it. | confirmed by code review; sim to do |
| D6 | Bit ctrl | With `CTR.EN` = 0 the prescaler ticks on every clock, and the bit FSM is not gated by EN; the byte controller ignores EN altogether. Clearing EN mid-command finishes the command at `wb_clk_i` rate. | confirmed by code review; sim to do |
| D7 | Bit ctrl | Minimum PRER. With PRER = 0 the bit FSM's idle tick falls on the clock after `cmd_ack`, before the byte controller changes the command, so it runs every command twice (one behind), ending with an extra STOP. With PRER = 1 a tick is 2 clocks, shorter than the input sync and filter latency, and the core reports **arbitration lost against a single slave** on the first address byte (SR = 0x61). **PRER must be at least 2.** | PRER = 1 confirmed by simulation (`ref_wb32 +PRER=1`, now `ref-smoke +PRER=1`); PRER = 0 by trace |
| D8 | Bit ctrl | Standard-mode tSU;STA (repeated START) is about 1.5 ticks (≈3 µs, less than 4.7 µs). tVD;DAT is 2 ticks, more than the Sm and Fm maximums. See {doc}`timing`. | to confirm |
| D9 | Bit ctrl | Arbitration is checked only during transmitted bits. A START or STOP collision with another master is not detected. A possible false AL: `scl_sync` in `wr_c` advances to `wr_d` (check on) while another master holds SCL low and may change SDA. | to confirm |
| D10 | Bit ctrl | The SCL rate is about 10% below the PDF formula, because the prescaler stops after each SCL release until the filtered input reads high. | to confirm |

IDs D2–D5 were defects in the later slave extension; they do not apply to
R76 and are recorded in {doc}`later-extension`.

## Differences from the PDF

| Item | PDF | RTL |
|---|---|---|
| Pad enable names | `scl_pad_oe`, `sda_pad_oe` | `scl_padoen_o`, `sda_padoen_o` |
| Register 0x5, 0x6 | not described | read TXR and CR |
| CTR[5:0] | reserved | stored and read back |
| STA alone | "generate (repeated) start" | does nothing until RD, WR or STO is also set |
| STA + STO | not described | START, write TXR, STOP |
| RxACK after a read | "acknowledge from the addressed slave" | the ACK/NACK the core itself sent |
| AL on STOP | "a STOP is detected but not requested" | only while a non-STOP command is in progress (2004 fix) |
| Glitch filter | not described | 3-sample majority filter at PRER/4 |
| Prescaler comment | 5×SCL | code comment says 4×SCL; behaviour is 5 ticks per bit |

## Lint and coding notes

- `timescale.v` is included by every RTL file, and most non-blocking
  assignments carry `#1`. Verilator needs `--no-timing` (or `--timing`).
  With `--no-timing -Wall -Wno-ASSIGNDLY`, the only remaining warning is
  WIDTHTRUNC on `filter_cnt <= clk_cnt >> 2` (bit controller).
- `i2c_master_defines.v` has no include guard; every file includes it.
- `full_case parallel_case` pragmas on `case (c_state)` without a
  default, in both FSMs. Simulation and synthesis can differ on an
  illegal state.
- The bit FSM is declared 18 bits wide, but only 17 bits are used.
- `dscl_oen`, `dout` (bit controller), `wb_ack_o` and `wb_dat_o` (top)
  have no reset.
