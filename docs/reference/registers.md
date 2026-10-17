# Registers

The register map is described in SystemRDL in `src/rdl/oc_i2c_master.rdl`,
and the tables below are generated from it by `sphinx-peakrdl`. The
same file is the starting point for the `fw-i2c` register map; see
{doc}`../design/index`.

## Summary

| Offset | Write | Read | Reset | Notes |
|---|---|---|---|---|
| 0x0 | PRERlo | PRERlo | 0xFF | |
| 0x1 | PRERhi | PRERhi | 0xFF | |
| 0x2 | CTR | CTR | 0x00 | Bit 5 (SLV_EN) is from the slave extension. Bits 4:0 are stored. |
| 0x3 | TXR | RXR | 0x00 | Split register |
| 0x4 | CR | SR | 0x00 | Split register. CR is written only while CTR.EN is 1 |
| 0x5 | — (ignored) | TXR_DBG | 0x00 | Not in the PDF |
| 0x6 | — (ignored) | CR_DBG | 0x00 | Not in the PDF |
| 0x7 | SLADR | SLADR | 0x7E | Slave extension; reads 0 in rev 76 |

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
  and **repeats the transfer**. See defect D1 in {doc}`deviations`
  **(to confirm)**.
- **Level interrupt sources.** `SR.SLV_DAT_REQ` and `SR.SLV_DAT_AVAIL`
  are levels that are ORed into IF on every clock, so IACK cannot clear
  IF while either is set.

## Register reference

```{rdl:doctree} oc_i2c_master
```
