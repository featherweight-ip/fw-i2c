# Deviations, defects and quirks

This page lists every point where the RTL at `3b067f0` differs from the
PDF, and every suspected defect found while reading the RTL. Each
suspected defect needs a directed test. The tests are planned in
{doc}`verification`, and the IDs are used there and in
{doc}`../design/index`.

## Suspected defects

| ID | Area | Description | Since | Status |
|---|---|---|---|---|
| D1 | Top: CR | The command-bit auto-clear is skipped if a WISHBONE write to any register is accepted in the same clock as `done` or `i2c_al`. The command bits stay set and the byte controller **repeats the command**. A TXR write for the next byte, timed to land as a byte completes, can trigger it. | before rev 76 | to confirm |
| D2 | Byte ctrl: slave reset | `slave_reset = sta_condition \| sto_condition` resets the byte FSM, including `master_mode`, on **every** START the bus carries, including the core's own START as master. For one clock `master_mode` = 0, the pad mux selects the (released) slave enables, and SDA is released while SCL is high: a 1-clock STOP+START glitch on the bus. The byte FSM then re-enters `START` because the CR bits are still set, and it completes because the bit FSM was not reset. Devices whose spike filter is shorter than one `wb_clk_i` period see a spurious STOP/START. | slave ext. | to confirm |
| D3 | Top: SR[4] | `SR.SLV_MODE` is loaded from `slave_act` only on `done`, when `slave_act` is always 0, so it always reads 0. | slave ext. | to confirm |
| D4 | Slave | SL_CONT loads TXR into the shift register, which is RXR, so a received byte is lost if software writes SL_CONT before reading RXR. This is a hazard rather than a bug, and the PDF does not cover it. | slave ext. | to confirm |
| D5 | Slave | The slave bit FSM is reset by START but not STOP. After an aborted transfer it can be left mid-byte until the next START. | slave ext. | to confirm |
| D6 | Bit ctrl | With `CTR.EN` = 0 the prescaler ticks on every clock, and the master bit FSM is not gated by EN. Clearing EN mid-command finishes the command at `wb_clk_i` rate. | before rev 76 | to confirm |
| D7 | Bit ctrl | PRER = 0 re-executes the previous bit command (stale command at the idle tick). | before rev 76 | to confirm |
| D8 | Bit ctrl | Standard-mode tSU;STA (repeated START) is about 1.5 ticks (≈3 µs, less than 4.7 µs). tVD;DAT is 2 ticks, more than the Sm and Fm maximums. See {doc}`timing`. | before rev 76 | to confirm |
| D9 | Bit ctrl | Arbitration is checked only during transmitted bits. A START or STOP collision with another master is not detected. A possible false AL: `scl_sync` in `wr_c` advances to `wr_d` (check on) while another master holds SCL low and may change SDA. | before rev 76 | to confirm |
| D10 | Bit ctrl | The SCL rate is about 10% below the PDF formula, because the prescaler stops after each SCL release until the filtered input reads high. | 2009 | to confirm |

## Differences from the PDF (by design or documentation drift)

| Item | PDF | RTL |
|---|---|---|
| `ARST_LVL` default | `1'b0` | `1'b1` |
| Pad enable names | `scl_pad_oe`, `sda_pad_oe` | `scl_padoen_o`, `sda_padoen_o` |
| Register 0x5, 0x6 | not described | read TXR and CR |
| Register 0x7 | not described | SLADR (reads 0 in rev 76) |
| CTR[4:0] | reserved | stored and read back; CTR[5] is SLV_EN |
| CR[1] | reserved | SL_CONT |
| SR[4:2] | reserved, read 0 | SLV_MODE, SLV_DAT_AVAIL, SLV_DAT_REQ |
| STA alone | "generate (repeated) start" | does nothing until RD, WR or STO is also set |
| STA + STO | not described | START, write TXR, STOP |
| IF sources | byte done, AL | also slave byte done and the slave level flags |
| AL on STOP | "a STOP is detected but not requested" | only while a non-STOP command is in progress (2004 fix) |
| Glitch filter | not described | 3-sample majority filter at PRER/4 |
| Prescaler comment | 5×SCL | code comment says 4×SCL; behaviour is 5 ticks per bit |

## Lint and coding notes

- `full_case parallel_case` pragmas on `case (c_state)` without a
  default, in both FSMs. Simulation and synthesis can differ on an
  illegal state.
- The master bit FSM is declared 18 bits wide, but only 17 bits are used.
- `dscl_oen`, `dout` (bit controller), `wb_ack_o` and `wb_dat_o` (top)
  have no reset.
- `slave_adr_received_d` in the bit controller is declared but not used.
- The slave bit FSM is binary-encoded with no default branch, and mixes
  `|` and `||` in its reset condition.
- `data/verilator_waiver.vlt` in the repository waives the remaining
  Verilator lint warnings.
