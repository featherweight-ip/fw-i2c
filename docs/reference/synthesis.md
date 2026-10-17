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
the devices, and the RTL (the 2004 and 2009 fixes) are all different.

## Repository synthesis setup

At R76 the repository has no synthesis scripts. (Later freecores commits
add a FuseSoC `sky130` target using OpenLANE, disabled in their CI.)

## Measurements (2026-10-17)

Run with `scripts/synth-baseline.sh packages/i2c dba90b2`, using the
ivpm-provided tools: Yosys 0.69 (`packages/yosys`) and nextpnr 0.11.1
(`packages/nextpnr`). These numbers are area and one-seed Fmax, out of
context (all ports on pins). They are a starting point, not the
benchmark result.

- **Generic:** `synth -flatten`, then `abc -g` to 2-input gates and MUX.
- **iCE40:** `synth_ice40 -device u`, then `nextpnr-ice40 --up5k --package
  sg48 --freq 12`. This is the iCEBreaker target.

| Flops | Generic gates | iCE40 SB_LUT4 | SB_CARRY | Logic cells (of 5280) | Fmax |
|---|---|---|---|---|---|
| 154 | 607 | 322 | 27 | 368 (6%) | 46.0 MHz |

The breakdown by module is in {doc}`architecture`. Behind the 32-bit
shim, with `arst_i` tied inactive, the core is 285 LUT4. That is the form
`fw-i2c` compares against; see {doc}`integration`. The core meets the
12 MHz board clock with a wide margin, so on this target the comparison
that matters is area.

The numbers depend on the Yosys version: Yosys 0.56 gave 336 LUT4, 4% more
than 0.69. Both arms must be measured with the same tool versions, pinned
by ivpm.
