# freecores `i2c` reference specification

This part describes what the freecores `i2c` core **actually provides**,
taken from its Verilog RTL. It replaces the 2003 OpenCores PDF
(`i2c_specs.md` in the repository root is a text conversion of it) as the
reference for `fw-i2c`. The PDF is out of date in several places, and it
does not describe the slave mode added in 2013.

| | |
|---|---|
| Source | <https://github.com/freecores/i2c> |
| Revision described | `3b067f0` ("Prepare for release", 2022-06-01), fetched by ivpm into `packages/i2c` |
| RTL | `rtl/verilog/i2c_master_top.v`, `i2c_master_byte_ctrl.v`, `i2c_master_bit_ctrl.v`, `i2c_master_defines.v` (1619 lines) |
| Register model | `src/rdl/oc_i2c_master.rdl` (SystemRDL, written for this specification) |
| License | Original BSD-style OpenCores notice (in each RTL file) |

```{admonition} Conventions
:class: note
- "The core" means the freecores RTL at the revision above.
- "The PDF" means the OpenCores *I2C-Master Core Specification*, Rev 0.9, 2003.
- "Rev 76" means commit `dba90b2`: OpenCores SVN rev 76, the last
  master-only RTL by R. Herveille (2009), before the slave extension.
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
slave-mode
architecture
programming
verification
deviations
synthesis
```
