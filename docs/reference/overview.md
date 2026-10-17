# Overview

The core is a byte-level I2C controller with an 8-bit WISHBONE Classic
register interface. Software issues one command per byte through the
Command register. Each command can be preceded by a START and followed by
a STOP. The core does the bit-level work: START/STOP generation, bit
timing, clock stretching, multi-master clock synchronization and
arbitration. Every byte boundary needs software: there is no FIFO, no
DMA and no transaction sequencer.

## Provenance

| Period | Author | Change |
|---|---|---|
| 2001–2009 | Richard Herveille (OpenCores) | The master core: WISHBONE top, byte controller, bit controller, multi-master support (2002), clock-synchronization fix (2009). Ends at OpenCores SVN rev 76. |
| 2013 | Hans Baier | Slave mode: `CTR.SLV_EN`, `CR.SL_CONT`, `SR[4:2]`, the SLADR register at 0x7, a slave FSM in both controllers. Also changed the default `ARST_LVL` from 0 to 1. |
| 2015–2022 | Olof Kindgren (freecores) | Syntax and width fixes, timescale removal, FuseSoC `i2c.core`, Verilator waiver, GitHub CI. Testbench reset fixed to match the new `ARST_LVL` default. |

The freecores repository holds both the Verilog and a VHDL version
(`rtl/vhdl`). Only the Verilog version has the slave mode. This
specification covers only the Verilog version.

## Features: the PDF compared with the RTL

| Feature | PDF | RTL at `3b067f0` |
|---|---|---|
| Master transmit and receive, byte by byte | Yes | Yes |
| START, repeated START, STOP generation | Yes | Yes. STA alone does nothing; see {doc}`operation` |
| START/STOP detection, bus-busy flag | Yes | Yes. Busy has no timeout |
| 7-bit and 10-bit addressing (master) | Yes | Done in software: the core sends whatever bytes it is given. 10-bit is two address bytes |
| Clock stretching by a slave | Yes | Yes. The master waits while SCL is held low |
| Multi-master: clock synchronization | Yes | Yes |
| Multi-master: arbitration | Yes | Yes, during transmitted bits only; see {doc}`operation` |
| Programmable SCL rate | f/(5·SCL)−1 | Same formula, but the real rate is lower; see {doc}`timing` |
| Speeds | 100 k / 400 k; 3.4 M with special IOs | Up to the limit set by `wb_clk_i` and the filter latency. No Hs-mode master code or current-source pull-up control |
| Input glitch filter | Not documented | 3-sample majority filter, sample rate set by PRER |
| Interrupt | IF + IEN → `wb_inta_o` | Same, plus slave sources |
| Slave (target) mode | No | 7-bit address, software byte-by-byte, SCL held low between bytes. No 10-bit address and no general call. Untested upstream |
| Debug readback of TXR and CR | No | Yes, at 0x5 and 0x6 (in the core since before rev 76) |
| FIFO, DMA, SMBus timeouts, PEC | No | No |
| Tristate pads | Outside the core | Outside the core. `*_pad_o` is constant 0 and `*_padoen_o` (active low) drives the line low |

## Block structure

```{mermaid}
flowchart LR
  WB["WISHBONE<br/>8-bit classic"] --> TOP
  subgraph TOP["i2c_master_top"]
    REGS["PRER, CTR, TXR, CR, SLADR<br/>SR / IRQ"]
  end
  REGS --> BYTE
  subgraph BYTE["i2c_master_byte_ctrl"]
    BFSM["byte FSM<br/>11 states, one-hot"]
    SR8["8-bit shift reg<br/>+ bit counter"]
  end
  BYTE --> BIT
  subgraph BIT["i2c_master_bit_ctrl"]
    CLK["prescaler,<br/>clock stretch / sync"]
    FLT["sync + glitch<br/>filter"]
    MFSM["master bit FSM<br/>18 states"]
    SFSM["slave bit FSM<br/>7 states"]
    DET["START/STOP detect,<br/>busy, arbitration"]
  end
  BIT <--> PADS["scl/sda<br/>pad_i, pad_o, padoen_o"]
```

The three modules are described in {doc}`architecture`.
