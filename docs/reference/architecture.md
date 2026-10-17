# Architecture

The core is three modules, each one level below the last. All of them are
clocked by `wb_clk_i`.

| Module | Lines | Contents |
|---|---|---|
| `i2c_master_top` | 327 | WISHBONE slave, PRER/CTR/TXR/CR/SLADR registers, SR assembly, IRQ |
| `i2c_master_byte_ctrl` | 503 | Byte FSM, 8-bit shift register (TXR load / RXR), 3-bit bit counter |
| `i2c_master_bit_ctrl` | 726 | Prescaler, synchronizer and filter, START/STOP detection, busy, arbitration, master bit FSM, slave bit FSM, slave address shifter |
| `i2c_master_defines` | 63 | Bit-command and slave-command encodings |

## Top level

The WISHBONE logic is described in {doc}`interface` and the registers in
{doc}`registers`. Status bits are registered here:

```verilog
al       <= i2c_al | (al & ~sta);
rxack    <= irxack;
tip      <= rd | wr;
irq_flag <= (done | slave_done | i2c_al | slave_dat_req |
             slave_dat_avail | irq_flag) & ~iack;
if (done) slave_mode <= slave_act;
wb_inta_o <= irq_flag && ien;
```

## Byte controller

The byte controller turns one CR command into a sequence of bit commands
(`START`, `WRITE`, `READ`, `STOP`, one-hot 4 bits) and runs the slave
byte sequence. Its 10-bit one-hot state register has 11 states (`IDLE`
is all-zeros).

```{mermaid}
stateDiagram-v2
  [*] --> IDLE
  IDLE --> START: STA (and RD/WR/STO)
  IDLE --> READ: RD
  IDLE --> WRITE: WR
  IDLE --> STOP: STO only
  START --> READ: RD
  START --> WRITE: otherwise
  WRITE --> WRITE: bit, cnt != 0
  WRITE --> ACK: cnt == 0 (receive ACK)
  READ --> READ: bit, cnt != 0
  READ --> ACK: cnt == 0 (send ACK bit)
  ACK --> STOP: STO
  ACK --> IDLE: no STO / done
  STOP --> IDLE: done
  IDLE --> SL_ACK: slave addressed
  note left of IDLE: any state → IDLE on\nreset, AL, START/STOP
```

The slave states (`SL_ACK`, `SL_WAIT`, `SL_PRELOAD`, `SL_RD`, `SL_WR`) are
shown in {doc}`slave-mode`.

- **Shift register and RXR.** The shift register is loaded from TXR when a
  command starts (`ld`) and shifts left on each bit, taking in the
  received bit. It is RXR. After a write it holds the bits sampled from
  SDA during the write, which equal TXR unless arbitration was lost.
- **Bit counter.** `dcnt` loads 7 and counts down once per bit.

## Bit controller

### Master bit FSM

The 18-bit state register holds 17 one-hot states plus all-zeros for
`idle`. Bit 17 is never set (the `wr_d` literal is 17 bits wide), so one
flop is dead. Each state lasts one tick. The per-state outputs and the
sequences are in {doc}`timing`.

### Slave bit FSM

A 5-bit, binary-encoded FSM with 7 states. It transmits a bit when SCL is
low, receives on the SCL rising edge, and reports each bit back to the
byte controller (`cmd_slave_ack`). The slave drives SCL low (stretches)
only while the byte controller asserts `sl_wait`, in `SL_WAIT`. The
output mux selects the master or slave enables using `master_mode`, which
the byte controller sets on a master START.

### Shared logic

- Input synchronizer and filter: see {doc}`timing`.
- START/STOP detection: registered, on the filtered lines:
  `sta = ~sSDA & dSDA & sSCL`, `sto = sSDA & ~dSDA & sSCL`.
- `busy <= (sta | busy) & ~sto`
- `al <= (sda_chk & ~sSDA & sda_oen) | (|c_state & sto & ~cmd_stop)`

## State and flop counts

From the RTL (before synthesis optimizations):

| Block | Flops (approx.) | Notes |
|---|---|---|
| Top | 16 PRER + 8 CTR + 8 TXR + 8 CR + 7 SLADR + 8 `wb_dat_o` + ~6 status/ack | CR bits 2, 1, 0 are single-pulse |
| Byte controller | 10 state + 8 shift + 3 count + ~14 control/slave | |
| Bit controller | 18 state + 16 cnt + 14 filter cnt + 2×(2+3+1+1) line + 5 slave state + 8 slave addr + 4 slave cnt + ~15 control | |

The prescaler, filter counter and PRER (46 flops) are the largest single
item. They are fixed costs for any implementation with a runtime
programmable rate.
