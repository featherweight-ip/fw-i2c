# OpenCores I2C-Master (R76) reference specification

This part describes what the OpenCores I2C-Master core **actually
provides**, taken from its Verilog RTL at the one revision `fw-i2c` uses as
its reference. It replaces the 2003 OpenCores PDF (`i2c_specs.md` in the
repository root is a text conversion of it) as the reference for
`fw-i2c`. The PDF is out of date in several places.

| | |
|---|---|
| Source | <https://github.com/freecores/i2c> |
| Revision described | **R76**: commit `dba90b2`, "Sync rtl/verilog to OpenCores SVN rev 76" — the last master-only RTL by R. Herveille (2009). Used from the `featherweight-ip/oc-i2c` fork (tag `r76`), with a patch set that changes no behaviour (branch `fw-r76`); see {doc}`integration`. |
| RTL | `rtl/verilog/i2c_master_top.v` (300 lines), `i2c_master_byte_ctrl.v` (344), `i2c_master_bit_ctrl.v` (576), `i2c_master_defines.v` (59), `timescale.v` (2) |
| Register model | `src/rdl/oc_i2c_master.rdl` (SystemRDL, written for this specification) |
| License | Original BSD-style OpenCores notice (in each RTL file) |

```{admonition} Conventions
:class: note
- "The core" or "R76" means the RTL at `dba90b2`.
- "The PDF" means the OpenCores *I2C-Master Core Specification*, Rev 0.9, 2003.
- Later freecores commits (2013 onward) add a slave mode on top of R76.
  `fw-i2c` does not use them; {doc}`later-extension` records why.
- "Tick" means one pulse of the bit controller's internal clock enable
  (`clk_en`), which occurs every PRER+1 cycles of `wb_clk_i`.
- Statements marked **(to confirm)** come from reading the RTL and still
  need a simulation to confirm them. The plan to do this is in
  {doc}`verification`.
```

```{toctree}
:maxdepth: 2

overview
interface
registers
operation
timing
architecture
programming
verification
deviations
synthesis
integration
later-extension
```
