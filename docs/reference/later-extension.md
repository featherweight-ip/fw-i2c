# Appendix: the later slave extension (not used)

The freecores repository continues past R76. In 2013 H. Baier added a
slave (target) mode (commit `4ed851d`), and later commits up to `3b067f0`
(2022) added FuseSoC packaging, lint fixes and CI. `fw-i2c` uses **only
R76** as its reference and size baseline. This page records what the later
revision changes and why it was not chosen, so the findings are not lost.

## Why R76 and not the latest freecores revision

- **Scope.** `fw-i2c` is master-only (design decision OI-1). The slave
  extension adds about a third to the core (below), which a master-only
  design would never have. That would make the area comparison unfair.
- **Credibility.** R76 is the core the PDF describes and the one most
  engineers know. The slave mode was never tested upstream: its bench has
  no slave-mode test.
- **Defects.** The extension adds the defects below. D2 affects plain
  master operation.

## What changes after R76

| Area | R76 | Latest (`3b067f0`) |
|---|---|---|
| `ARST_LVL` default | `1'b0` (active-low `arst_i`) | `1'b1` (active-high) |
| Parameters | `ARST_LVL` | adds `DEFAULT_SLAVE_ADDR` (7'h7E) |
| 0x7 | reads 0 | SLADR, slave address (reset 0x7E) |
| CTR[5] | reserved | SLV_EN |
| CR[1] | reserved | SL_CONT, release SCL after a slave byte |
| SR[4:2] | 0 | SLV_MODE, SLV_DAT_AVAIL, SLV_DAT_REQ |
| IF sources | done, AL | also slave byte done and the slave level flags |
| Pad enables | from the master FSM | `master_mode ? master : slave` |
| Byte FSM reset | `rst \| al` | also every START or STOP on the bus |
| `timescale.v`, `#1` | present | removed |
| Master byte and bit FSMs, prescaler, filter, arbitration | — | unchanged |

## Defects of the extension (D2–D5)

These were found by reading the RTL. They were never simulated, because
`fw-i2c` does not use this revision.

| ID | Description |
|---|---|
| D2 | `slave_reset = sta_condition \| sto_condition` resets the byte FSM, including `master_mode`, on **every** START on the bus, including the core's own START as master. For one clock `master_mode` = 0, the pad mux selects the released slave enables, and SDA is released while SCL is high: a 1-clock STOP+START glitch on every master START. This is not gated by SLV_EN. |
| D3 | `SR.SLV_MODE` is loaded from `slave_act` only when a master command completes, when `slave_act` is always 0, so it always reads 0. |
| D4 | SL_CONT loads TXR into the shift register, which is RXR, so a received byte is lost if software writes SL_CONT before reading RXR. |
| D5 | The slave bit FSM is reset by START but not STOP. After an aborted transfer it can be left mid-byte until the next START. |

Other limits of the slave mode: 7-bit addresses only, no general call,
the core always ACKs a write, and SCL is held only between bytes.

## Size

Same flow as {doc}`synthesis` (Yosys 0.69, iCE40UP5K, one seed):

| Revision | Flops | SB_LUT4 | Logic cells | Fmax |
|---|---|---|---|---|
| R76 (`dba90b2`) | 154 | 322 | 368 | 46.0 MHz |
| Latest (`3b067f0`) | 202 | 436 | 500 | 44.9 MHz |
| Difference | +31% | +35% | +36% | |
