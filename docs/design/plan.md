# Plan and status

A fresh session should be able to pick up from this file alone. Update
the status column as each step finishes.

| # | Step | Output | Status |
|---|---|---|---|
| 0 | Review sources; write the reference spec of freecores `i2c` (as-built RTL), register map in SystemRDL; first baseline synthesis | `docs/reference/`, `src/rdl/oc_i2c_master.rdl`, `scripts/synth-baseline.sh` | **done** 2026-10-17 |
| 1 | Review this design; answer OI-1..OI-4, OI-11 | decisions recorded in `docs/design/index.md` | **done** 2026-10-17 |
| 2 | dfm flow for the reference image (R76 + `fw-r76` patches + 32-bit shim, `packages/oc-i2c`) on Verilator with fwvip-wb + fwvip-i2c; reference confirmation tests D1–D10 | `tests/uvm/`, results in `docs/reference/deviations.md` (status column) | confirmation tests done (bench-plan E3: D1, D6–D10 confirmed by simulation; OI-6 proposal in design §8.1 awaits review). Also: `oc-i2c` fork + `fw-r76` patch set and tags `r76`, `r76-fw1` (local only: the Forgejo repo is a read-only pull mirror and refuses pushes; `ivpm.yaml` pins `dba90b2` until then), shim `src/ref/oc_i2c_wb32.sv`, common tests (bench-plan E2) passing on `ref` (replaced the directed test `ref_wb32`), `dfm run lint-rtl` clean (4 waivers); D7 confirmed at PRER = 1 |
| 3 | Spike: smallest fw-hdl sequencer (start/tx_byte/stop on the kit API) through `synth-mmio` (OI-7) | `spikes/synth-mmio/`, a go/no-go note | not started |
| 4 | `fw-proto-i2c`: runtime `set_prescale()` on the controller (design §3.3), with kit tests; fwvip-i2c config + docs | branch `runtime-prescale` in `fwvip-i2c/packages/fw-proto-i2c` and `fwvip-i2c` | implemented and tested 2026-10-17; **not committed/pushed**; open: formal at prescale > 0 |
| 5 | Register block: R1 split-register support in peakrdl-fw-hdl / `fw_reg_block`; `fw_i2c_regs` RDL | PRs; `src/rdl/fw_i2c_regs.rdl` | not started |
| 6 | `fw-i2c` class model: sequencer, prescaler, filter, busy, wrapper | `src/spl/`, `src/spl-rtl/` | not started |
| 7 | Differential bench on `fw-model`, then `fw-rtl`; shared-bus multi-master tests | `tests/uvm/` | in progress: equivalence harness and its R76-vs-R76 self-test done (bench-plan E4, view `ref-eq`) |
| 8 | dfm synthesis flow for iCE40UP5K (iCEBreaker): Yosys `synth_ice40 -device u` + nextpnr, multi-seed Fmax; generic gate cross-check; per-block and whole-IP reports for both arms | `flow.yaml` tasks, `docs/results.md` | not started |
| 9 | Gate-level sim of `fw-gates`; formal (sequencer properties, CodegenEquiv) | | not started |

## Notes

- Steps 2, 5, 6 and 7 are expanded in {doc}`bench-plan` (T1–T6, E1–E12;
  reviewed 2026-10-17). Status for those steps is kept there. The kit's `set_prescale()` (step 4) is on
  `fw-proto-i2c` `origin/main` (930dafb) as fetched in `packages/`.

- Setup: `ivpm update` (done 2026-10-17; fetches into `packages/`, with
  Forgejo-hosted repos mapped to the local Forgejo), then once
  `uv pip install --python packages/python/bin/python -e packages/fw-hdl/python`
  (fw-hdl's dfm plugin, which ivpm does not install). `.envrc` loads
  `packages/packages.envrc` (needs `direnv allow`).
- Docs: `dfm run docs` (sphinx-build -W).
- Area baseline: `scripts/synth-baseline.sh packages/i2c <commit>`, with the
  ivpm Yosys (0.69) and nextpnr.
- Optional step after 9: hardware back-to-back on the iCEBreaker (design §9).
