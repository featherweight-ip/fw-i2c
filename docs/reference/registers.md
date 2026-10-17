# Registers

The register map is described in SystemRDL in `src/rdl/oc_i2c_master.rdl`,
and the tables below are generated from it by `sphinx-peakrdl`. The
same file is the starting point for the `fw-i2c` register map; see
{doc}`../design/index`.

## Summary

The core addresses registers by byte (`wb_adr_i[2:0]`). Through the
32-bit shim that `fw-i2c` uses, register n is at byte address 4·n
({doc}`integration`).

| Core offset | Shim address | Write | Read | Reset | Notes |
|---|---|---|---|---|---|
| 0x0 | 0x00 | PRERlo | PRERlo | 0xFF | |
| 0x1 | 0x04 | PRERhi | PRERhi | 0xFF | |
| 0x2 | 0x08 | CTR | CTR | 0x00 | Bits 5:0 are reserved but stored and read back |
| 0x3 | 0x0C | TXR | RXR | 0x00 | Split register |
| 0x4 | 0x10 | CR | SR | 0x00 | Split register. CR is written only while CTR.EN is 1 |
| 0x5 | 0x14 | — (ignored) | TXR_DBG | 0x00 | Not in the PDF |
| 0x6 | 0x18 | — (ignored) | CR_DBG | 0x00 | Not in the PDF |
| 0x7 | 0x1C | — (ignored) | 0x00 | — | Reserved |

Things the RDL can only partly express:

- **CR write gating.** A CR write is ignored while `CTR.EN` is 0. That
  includes `IACK`, so IF cannot be cleared through CR while the core is
  disabled.
- **Command-bit clearing.** STA, STO, RD and WR clear together, in the
  clock where the byte controller's one-clock `done` pulse (or
  arbitration-lost pulse) is high. The clear is in the `else` branch of
  `if (wb_wacc)`, and `wb_wacc` is true for a WISHBONE write to *any*
  register. If a write (for example, loading TXR for the next byte) is
  accepted in the same clock as `done`, the clear is lost. The command
  bits then stay set, and the byte controller sees them as a new command
  and **repeats the transfer**: a new START if STA was set, a reload of
  TXR, or another read over RXR. See defect D1 in {doc}`deviations`.
  An SDA-mismatch arbitration loss is usually two clocks wide, and a write
  cannot be accepted on two clocks in a row, so in practice only `done` and
  the unexpected-STOP loss are exposed.
- **IACK priority.** `IF <= (done | i2c_al | IF) & ~IACK`: an IACK written
  in the clock where a command completes clears that completion too.

## Register reference

```{rdl:doctree} oc_i2c_master
```
