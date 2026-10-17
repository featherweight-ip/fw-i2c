# Synthesis baseline

## Published results (PDF, Appendix A, 2003)

The PDF reports the following for the master-only core of 2003, using
Synplify Pro:

| Technology | Device | Speed grade | Fmax | Resources |
|---|---|---|---|---|
| Actel | A54SX16ATQ100 | std | 58 MHz | 352 modules |
| Altera | EP10K50ETC144 | -3 | 82 MHz | 294 LCs |
| Altera | EP20K30ETC144 | -3 | 74 MHz | 257 ATOMs |
| Xilinx | 2s15CS144 | -5 | 82 MHz | 229 LUTs |
| Xilinx | XCV50ECS144 | -8 | 118 MHz | 230 LUTs |

These numbers cannot be compared with anything built today: the tools,
the devices, and the RTL (2009 clock-synchronization changes, the 2013
slave mode) are all different.

## Repository synthesis setup

- `i2c.core` has a `sky130` target that uses OpenLANE
  (`data/openlane.tcl`: `CLOCK_PERIOD` 10 ns, `CLOCK_PORT` `wb_clk_i`).
  In the repository's CI the job is disabled ("hangs OpenLANE during
  routing").
- `data/verilator_waiver.vlt` is used for the lint target.

## Baselines to measure

Two versions of the core are useful as baselines. Both should be
synthesized with the same flow as `fw-i2c`:

| Baseline | Commit | Why |
|---|---|---|
| **R76** — master-only | `dba90b2` | The Herveille core most engineers know, and the one the PDF describes. It is the fair comparison for a master-only `fw-i2c`. |
| **HEAD** — master + slave | `3b067f0` | What freecores ships today. Needed if `fw-i2c` implements slave mode. |

The measurement flow is defined in the design document; see
{doc}`../design/index`.

## Measurements (2026-10-17)

Run with `scripts/synth-baseline.sh packages/i2c <commit>`, using the
ivpm-provided tools: Yosys 0.69 (`packages/yosys`) and nextpnr 0.11.1
(`packages/nextpnr`). These numbers are area and one-seed Fmax, out of
context (all ports on pins). They are a starting point, not the
benchmark result.

- **Generic:** `synth -flatten`, then `abc -g` to 2-input gates and MUX.
- **iCE40:** `synth_ice40 -device u`, then `nextpnr-ice40 --up5k --package
  sg48 --freq 12`. This is the iCEBreaker target.

| Baseline | Flops | Generic gates | iCE40 SB_LUT4 | SB_CARRY | Logic cells (of 5280) | Fmax |
|---|---|---|---|---|---|---|
| R76 (`dba90b2`) | 154 | 607 | 322 | 27 | 368 (6%) | 46.0 MHz |
| HEAD (`3b067f0`) | 202 | 824 | 436 | 29 | 500 (9%) | 44.9 MHz |
| HEAD vs. R76 | +31% | +36% | +35% | | +36% | |

Both versions meet the 12 MHz board clock by a wide margin, so on this
target the comparison that matters is area. The slave extension adds
about a third to the core, so the choice of baseline moves the comparison
more than most synthesis-tool settings do.

The numbers depend on the Yosys version. An earlier run with Yosys 0.56
gave 336 LUT4 for R76, 4% more than 0.69. Both arms must be measured with
the same tool versions, pinned by ivpm.
