# Deviations, defects and quirks

This page lists every point where the RTL (R76, `dba90b2`) differs from
the PDF, and every suspected defect found while reading it. Each defect
gets a directed test, planned in {doc}`verification`. The IDs are also
used in {doc}`../design/index`.

## Suspected defects

| ID | Area | Description | Status |
|---|---|---|---|
| D1 | Top: CR | The command-bit auto-clear is skipped if a WISHBONE write to any register is accepted in the same clock as `done` (or an unexpected-STOP arbitration loss). The command bits stay set and the byte controller **repeats the command**. A TXR write for the next byte, timed to land as a byte completes, can trigger it. | **confirmed by simulation** (`ref-cr-race`): of 17 TXR writes swept across the end of a byte, the 2 that landed in the `done` clock each put one extra byte on the bus, the value just written (`D1a+ Dca+`); the others none |
| D6 | Bit ctrl | With `CTR.EN` = 0 the prescaler ticks on every clock, and the bit FSM is not gated by EN; the byte controller ignores EN altogether. Clearing EN mid-command runs the rest of the command at `wb_clk_i` rate. The `!ena` branch of the clock enable also overrides `slave_wait`, so the core stops waiting for SCL to rise, and it outruns its own input filter (as at PRER = 0, D7). | **confirmed by simulation** (`ref-en-midbyte`, PRER = 24): SCL period 1400 ns → 90 ns; within two SCL periods a STOP condition appears on the bus and the command ends by arbitration lost (SR AL = 1, IF = 1, no `done`); the byte never completes |
| D7 | Bit ctrl | Minimum PRER. With PRER < 2 a tick is shorter than the input sync and filter latency, and the core reports **arbitration lost against a single slave**. PRER = 1: AL on the first address byte (SR = 0x61); the bus carries only the START. PRER = 0: every command ends in AL and no byte reaches the bus, only START, Sr and STOP conditions (`S Sr Sr P S P` for address, offset, data + STOP). **PRER must be at least 2.** | **confirmed by simulation** (`ref-prer1`, `ref-prer0`). The earlier trace-only reading of PRER = 0 (each command run twice, one behind) does not hold on a bus with a target: the AL comes first |
| D8 | Bit ctrl | Standard-mode tSU;STA (repeated START) is about 1.5 ticks (≈3 µs, less than 4.7 µs). tVD;DAT is 2 ticks, more than the Sm and Fm maximums. See {doc}`timing`. | **confirmed by simulation** (`ref-timing-sm`, `ref-timing-fm`, nominal PRER 199 and 49 at 100 MHz): Sm tSU;STA 3.0 µs, tVD;DAT 4.0 µs (limit 3.45 µs); Fm tVD;DAT 1.0 µs (limit 0.9 µs). Fm tSU;STA (0.73 µs) meets its 0.6 µs minimum. Sm tHD;STA is exactly 4.0 µs, the minimum |
| D9 | Bit ctrl | Arbitration is checked only during transmitted bits. A START or STOP collision with another master is not detected. A possible false AL: `scl_sync` in `wr_c` advances to `wr_d` (check on) while another master holds SCL low and may change SDA. | **STOP collision confirmed by simulation** (`ref-arb`, against the kit controller on the same bus): R76 sends STOP while the other master sends a 0 bit; the STOP never reaches the bus, yet R76 completes it with AL = 0 (BUSY stays 1). Data-bit arbitration works both ways (R76 loses with AL; R76 wins). Not tested: a START against another master's data bit, and the false AL |
| D10 | Bit ctrl | The SCL rate is about 10% below the PDF formula, because the prescaler stops after each SCL release until the filtered input reads high. | **confirmed by simulation** (`ref-timing-sm`, `ref-timing-fm`, ideal lines with no rise time): SCL period 11.0 µs for 10 µs programmed (90.9 kHz), 2.69–2.75 µs for 2.5 µs (≈ 364 kHz), × 1.10 in both modes |

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
