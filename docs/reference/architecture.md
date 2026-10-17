# Architecture

The core is three modules, each one level below the last. All of them are
clocked by `wb_clk_i`.

| Module | Lines | Contents |
|---|---|---|
| `i2c_master_top` | 300 | WISHBONE slave, PRER/CTR/TXR/CR registers, SR assembly, IRQ |
| `i2c_master_byte_ctrl` | 344 | Byte FSM, 8-bit shift register (TXR load / RXR), 3-bit bit counter |
| `i2c_master_bit_ctrl` | 576 | Prescaler, synchronizer and filter, START/STOP detection, busy, arbitration, bit FSM |
| `i2c_master_defines` | 59 | Bit-command encodings |

## Top level

The WISHBONE logic is described in {doc}`interface` and the registers in
{doc}`registers`. Status bits are registered here:

```verilog
al       <= i2c_al | (al & ~sta);
rxack    <= irxack;
tip      <= rd | wr;
irq_flag <= (done | i2c_al | irq_flag) & ~iack;
wb_inta_o <= irq_flag && ien;
```

## Byte controller

The byte controller turns one CR command into a sequence of bit commands
(`START`, `WRITE`, `READ`, `STOP`, one-hot 4 bits). Its state register is
5 bits wide and one-hot, with `IDLE` all-zeros: six states. It is reset by
`wb_rst_i` and by arbitration loss.

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
  note left of IDLE: any state → IDLE on\nreset or AL
```

- **Shift register and RXR.** The shift register is loaded from TXR when a
  command starts (`ld`) and shifts left on each bit, taking in the
  received bit. It is RXR. After a write it holds the bits sampled from
  SDA during the write, which equal TXR unless arbitration was lost.
- **Bit counter.** `dcnt` loads 7 and counts down once per bit.
- **ACK slot.** After a write the ACK slot is a READ bit command; after a
  read it is a WRITE of `CR.ACK`. Either way `ack_out` (SR.RXACK) takes
  the bit seen on SDA.

## Bit controller

### Bit FSM

The 18-bit state register holds 17 one-hot states plus all-zeros for
`idle`. Bit 17 is never set (the `wr_d` literal is 17 bits wide), so one
flop is dead and is removed by synthesis. Each state lasts one tick. The
per-state outputs and the sequences are in {doc}`timing`.

### Shared logic

- Input synchronizer and filter: see {doc}`timing`.
- START/STOP detection: registered, on the filtered lines:
  `sta = ~sSDA & dSDA & sSCL`, `sto = sSDA & ~dSDA & sSCL`.
- `busy <= (sta | busy) & ~sto`
- `al <= (sda_chk & ~sSDA & sda_oen) | (|c_state & sto & ~cmd_stop)`

## Size by module

Yosys 0.69, `synth_ice40 -device u -noflatten` (hierarchy kept, so the
total is a little above the flattened 322 LUT4 in {doc}`synthesis`):

| Module | Flops | SB_LUT4 | SB_CARRY |
|---|---|---|---|
| `i2c_master_top` | 54 | 90 | 0 |
| `i2c_master_byte_ctrl` | 26 | 57 | 1 |
| `i2c_master_bit_ctrl` | 74 | 191 | 26 |
| Total | 154 | 338 | 27 |

The byte controller, the block that does transaction-level control, is
about a sixth of the core. Most of the area is the bit controller, which
holds the 16-bit prescaler, the 14-bit filter counter and the bit FSM, and
the top level, which holds the registers and the read mux.
