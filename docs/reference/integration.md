# Integration: patch set and 32-bit shim

`fw-i2c` uses the core in the form described here: R76 with a small patch
set that changes no behaviour, behind a 32-bit WISHBONE shim. This
combination is arm A of the comparison.

## Source: featherweight-ip/oc-i2c

The core comes from `featherweight-ip/oc-i2c`, a fork of the freecores
mirror (`master` tracks freecores). ivpm fetches it into
`packages/oc-i2c`.

| Ref | Commit | Content |
|---|---|---|
| tag `r76` | `dba90b2` | OpenCores SVN rev 76, unmodified: the baseline |
| branch `fw-r76` | on `r76` | the patch set below |

| Patch | Change | Check |
|---|---|---|
| `3042498` | Bench only: cherry-pick of upstream `5372bde`, which ORs the two cores' `wb_ack_o` in `tst_bench_top.v` | Without it the upstream bench fails under Icarus (register reads return `ff`, then it hangs). With it: 0 errors |
| `cf0b314` | RTL: removes all 234 `#1` delays and the `timescale.v` includes | Yosys equivalence against R76: 270/270 points proven. Upstream bench messages identical. Synthesis output identical (322 LUT4) |

The one remaining Verilator `-Wall` warning (WIDTHTRUNC on the filter
counter reload) is **waived**, not patched: rewriting `clk_cnt >> 2` as
`clk_cnt[15:2]` is logically identical, but it changes the Yosys/ABC
mapping (−3 LUT4), and the baseline must keep R76's area. The waiver is in
`lint-waivers.yaml`.

Bug fixes (D1, D6, D7) are deliberately **not** in the patch set; see
{doc}`deviations`.

## The 32-bit WISHBONE shim

`src/ref/oc_i2c_wb32.sv` gives the core the fw-XXX bus convention: a
32-bit data bus with one register per 32-bit word, only the low byte valid.

| Signal | Width | Behaviour |
|---|---|---|
| `wb_adr_i` | 5 | Byte address. Bits [4:2] select the register; bits [1:0] are ignored |
| `wb_dat_i` | 32 | Bits [7:0] are written; bits [31:8] are ignored |
| `wb_dat_o` | 32 | `{24'b0, register}` |
| `wb_sel_i` | 4 | A write takes effect only if `wb_sel_i[0]` is 1. A write without it reaches the core as a read: acknowledged, and without effect, because no core register has a read side effect |
| `wb_we_i`, `wb_stb_i`, `wb_cyc_i`, `wb_ack_o` | 1 | Passed through. Every access takes 2 clocks, as in the core |
| `wb_err_o` | 1 | Constant 0 |
| `wb_rst_i` | 1 | The only reset (synchronous, active high). The core's `arst_i` is tied inactive |
| `wb_inta_o`, pads | | Passed through |

The only logic in the shim is the AND gate `wb_we_i & wb_sel_i[0]`.

### Register map through the shim

| Byte address | Write | Read |
|---|---|---|
| 0x00 | PRERlo | PRERlo |
| 0x04 | PRERhi | PRERhi |
| 0x08 | CTR | CTR |
| 0x0C | TXR | RXR |
| 0x10 | CR | SR |
| 0x14 | — | TXR (readback) |
| 0x18 | — | CR (readback) |
| 0x1C | — | 0 |

This is the layout Linux's `i2c-ocores` driver uses with `reg-shift = <2>`
and `reg-io-width = <4>`.

### Reset

Tying `arst_i` inactive removes the core's asynchronous reset. On iCE40
the synchronous `wb_rst_i` then maps into the flops' own synchronous reset
(SB_DFFSR/SB_DFFESR) instead of into LUTs in front of async-reset flops,
which saves about 11% of the core's LUTs (below). `fw-i2c` must use the
same synchronous-only reset, or the reset style rather than the design
would decide the comparison.

### Size

Yosys 0.69, `synth_ice40 -device u` (`scripts/synth-baseline.sh --shim`):

| Configuration | Flops | SB_LUT4 | SB_CARRY | Generic gates |
|---|---|---|---|---|
| Core alone (`fw-r76`, `arst_i` a pin) | 154 | 322 | 27 | 607 |
| Core + shim (`arst_i` tied inactive) | 154 | 285 | 27 | 505 |

The shim's 32-bit bus needs more pins than the iCE40UP5K-SG48 package has
(39), so this configuration is not placed and routed out of context. Its
P&R and Fmax come from a board-level top where WISHBONE is internal.

### Test

The common tests of the UVM bench on the `ref` view (`tests/uvm/`,
`dfm run tests`; cases `ref-reg`, `ref-write`, ... in {doc}`verification`)
drive the shim with a `fw-proto-wb` initiator. The core's pads connect to a
`fw-proto-i2c` target with a memory responder. It checks:

- the stride, the zero-extended reads, and the reset values
- writes gated by `sel[0]`, and `adr[1:0]` ignored
- the TXR and CR readbacks and the reserved word
- a two-byte write and a repeated-START read back
- an address NACK
- IF, IACK and `wb_inta_o`

`+PRER=<n>` sets the prescaler (default 4); `ref-prer` sweeps PRER = 2, 4, 9
and 24. The earlier directed test passed for PRER = 2, 3, 4, 5 and 23 and
failed for PRER = 1 (see D7 in {doc}`deviations`).
