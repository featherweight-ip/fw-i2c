# fw-i2c: initial design and test bench plan

```{admonition} Decisions (2026-10-17 review)
:class: tip
- **Stimulus:** a PSS op-model, as in fw-wb-dma: peakrdl-pss register
  model, pssc `OpModelSv`. (Q1)
- **Views:** equivalence gets **separate views**. A plain view runs the DUT
  alone, so a pure-TLM run shows the speed difference. (Q2)
- **Granularity:** transaction level, not signal level. (Q3)
- **Equivalence mechanism:** the op-model drives the fw-hdl design. A
  scoreboard implements the op-model API. It calls each operation on
  both designs in parallel and compares the results (kind, in-data,
  out-data). The I2C transfers on the two interconnects are compared
  passively, and the R76 side's responder mirrors the DUT side's
  decisions. A register-access mode (forward writes, duplicate reads) is
  an optional extra (§3; settled in review 2026-10-17).
- **Registers:** add the missing support (split registers and related) to
  the fw-hdl register tooling as part of this project. (Q4)
- **`i2c_tlm_bus`:** goes in `fw-proto-i2c`. (Q5; the answer said
  "fw-proto-ic", which I read as `fw-proto-i2c`.)
- **Timing comparison:** report only, to start with. (Q6)
- **Working strategy:** tools and libraries we need to change are fetched
  by ivpm as git clones into `packages/` and edited there. That covers
  fw-hdl, peakrdl-fw-hdl, peakrdl-pss, pssc, fw-proto-i2c and so on. Each
  change is made on a branch in the package clone and pushed upstream; the
  pin in `ivpm.yaml` follows.
```

This plan expands steps 2, 5, 6 and 7 of {doc}`plan`. Status is kept in
§9.

## 1. Goal

1. Write the first `fw-i2c` design as an fw-hdl class model (SPL), following
   {doc}`index`.
2. Write one set of **common tests**, driven through a PSS op-model, and
   run them on several **views** of the design, as fw-wb-dma does.
3. Run a **simulation-based equivalence check** against the R76 RTL
   (`oc-i2c` behind the `oc_i2c_wb32` shim). In the equivalence views the
   reference runs **in parallel** with the DUT in the same simulation.
   Each operation runs on both designs, and the operation results and
   the I2C traffic are compared.

## 2. What fw-wb-dma does, and what changes here

fw-wb-dma (`~/projects/featherweight-ip/fw-wb-dma`):

| Element | fw-wb-dma | fw-i2c |
|---|---|---|
| Design | SV class model in `src/spl/` (`fw_component`s); edges are kit APIs (`wb_proto_if`, `gpio_drive_if`) | Same: `src/spl/` |
| Signal wrapper | `src/spl-rtl/wb_dma_spl.sv`, pin-compatible with `wb_dma_top`; transactors plus `` `fw_root_bind_port `` | Same: `src/spl-rtl/fw_i2c_spl.sv`, pin-compatible with `oc_i2c_wb32` |
| Registers | `src/rdl/*.rdl` → `rdl.Export` → `reg-model` (fw-hdl `fw_reg_block`) and `reg-model-pss` (peakrdl-pss) | Same, plus split-register support (§4.5) |
| Stimulus | A PSS op-model in `src/pss/`; `pssc.OpModelSv` generates SV; `wb_dma_pss_mem_adapter` implements the generated import interface (`read32`/`write32`/`yield_`) over the model | Same: `src/pss/`, `i2c_pss_mem_adapter` |
| Common tests | UVM, `tests/uvm/tests/`. They see only `wb_dma_model_base`, fetched from `uvm_config_db` under `"model"` | Same: `i2c_model_base` |
| Views | `tlm`, `wb` (signal-wrapped class model), `rtl` (**the OpenCores RTL as DUT**) | Plain: `ref`, `tlm`, `wb`; later `rtl` (fw-hdl-lowered) and `gates`. Equivalence: `tlm-eq`, `wb-eq`, later `rtl-eq`, `gates-eq` |
| Reference | Always on: a second, passive TLM model, fed by a register tee (`wb_dma_reg_tee`, a `wb_proto_if` decorator) or monitor replay; the DUT's read data is authoritative and the reference's is discarded; a comparator aligns bus-master streams | Only in the `-eq` views: the timed R76 RTL, driven by its own op-model instance; `fw_i2c_op_eq` implements the op-model API, runs each op on both designs and compares the results (§3) |
| dfm | `images: [tlm,wb,rtl]`; `uvm-universal` = `strategy.matrix` image × case → `hdlsim.vlt.SimUVMCase` | Same shape |

The reversal matters: in fw-wb-dma the new design is the reference and
the old RTL is one of the DUT views. Here the old RTL is the reference,
and the new design's views are the DUTs.

## 3. How the equivalence check works

Equivalence is checked at two levels at the same time:

- **Operations.** Each op-model operation is captured as (kind, in-data,
  out-data) on both designs, and the two are compared (§3.1).
- **The I2C interconnect.** The transfers observed on each design's bus
  are compared passively (§3.2).

A register-access scoreboard is kept as an optional, stricter mode for
later (§3.3).

### 3.1 Operation-level scoreboard (primary)

pssc already generates the op-model's programming API as SystemVerilog
interface classes, separate from the implementation. In fw-wb-dma that is
`wb_dma_c_if`/`wb_dma_ch_c_if`, implemented by
`wb_dma_c #(IMP_T)` (`wb-dma-op-model-bundle/sv/wb_dma_c_pkg.sv`). Each
operation is a task with explicit `input` and `output` arguments, for
example `transfer_single(output status, input cfg)`. For fw-i2c the API
is `fw_i2c_c_ctxt_if`.

The equivalence scoreboard, `fw_i2c_op_eq`, **is an implementation of
`fw_i2c_c_ctxt_if`**:

```
                common test (holds an fw_i2c_c_ctxt_if)
                              │
                    fw_i2c_op_eq  implements fw_i2c_c_ctxt_if
              fork ───────────┴────────── join  → compare (kind, in, out)
               │                              │
     fw_i2c_c instance A               fw_i2c_c instance B
     + i2c_pss_mem_adapter             + i2c_pss_mem_adapter
               │                              │
     DUT (tlm / wb / rtl / gates)      R76 arm (oc_i2c_wb32)
     own I2C bus, target, monitor      own I2C bus, target, monitor
               └──── passive I2C stream compare (§3.2) ────┘
```

- **Two op-model instances, one per design.** Each instance has its own
  adapter onto its own design's register path. Each runs its own wait
  loops (`wait_hint`, then re-read SR) on its own design, on its own
  timing.
- **Each call** on `fw_i2c_op_eq` is forked into both instances. When
  both have returned, it records an op record (kind, inputs, outputs) for
  each side and compares the outputs. Mismatches are reported per op,
  for example "`read_byte` #17: out data 0x3C vs 0x3D". The DUT's outputs
  are returned to the test.
- **Timing doesn't matter inside an op.** Neither side ever sees the
  other's registers, so there is no rule for status skew and no write
  pacing. A command is never forwarded to a busy design, because each
  instance waits for its own design to finish before the next operation.
  The designs are aligned at every op boundary (the join), so skew never
  builds up.
- **More flexible than register-level checking.** Two designs are
  equivalent here if they give the same results for the same operations.
  Beyond timing, that allows comparing designs whose register maps, bus
  widths or bus protocols differ, as long as each has an op-model
  realisation (an adapter, or its own register model under the same
  operation API). Examples: a later `fw-i2c` with hardware 10-bit
  headers or an APB front end, still checked against R76.
- **What it does not see.** It does not see register state that no
  operation returns. The common register tests check that directly
  against the RDL model on every view, and the register-level mode
  (§3.3) can add it.
- **Generated, not hand-written (proposal).** The dual-dispatch
  decorator and the op-record type follow mechanically from the API
  signatures. That makes them a pssc output: an `OpModelSv` option
  (`eq` / `record`), added in `packages/pssc`. A hand-written
  `fw_i2c_op_eq` for the small I2C API is the fallback while the pssc
  change is pending.
- **Recording on its own** is a useful by-product: a decorator that only
  records op traces. A trace recorded on R76 can then be compared offline
  with a later fw-i2c run, with no parallel simulation (§8, follow-up).
- **Timing report (report-only).** For each op, record the duration on
  each side and the ratio. The monitors add the SCL period and phase
  lengths.

### 3.2 The I2C interconnect: passive compare, mirrored responders

The op results show what software saw. The interconnect shows what
actually went on the wire. Each design has its own interconnect (the
open-drain SCL/SDA pair) with an `i2c_monitor_xtor`. The scoreboard
drives nothing on the I2C side. It only observes:

- **Queues.** Each monitor feeds a queue, through the `i2c_monitor_if`
  callbacks `observe_start(repeated)`,
  `observe_byte(addr_phase, data, ack)`, `observe_stop` and
  `observe_arb_lost`.
- **Matching.** Once an event is present in both queues, the pair is
  compared: kind, `repeated`, `addr_phase`, data and ack. Events are
  matched by order, never by time.
- **End of test.** Both queues must be empty. An event left over on one
  side (an extra or missing START, byte or STOP) is a mismatch.

**Targets: a pair of responders, with the R76 side mirrored.** Each
interconnect has its own target and responder. The R76 side's behaviour
is mirrored from the DUT side.

- **DUT side.** The DUT side's responder is the active one, configured by
  the test: ACK/NACK, read data, and stretch length as a sequence. Each
  decision it makes (addressed → ack; rx_byte → ack; tx_byte → data;
  stretch) is pushed into a decision queue, in sequence order.
- **R76 side.** On each callback, the R76 side's mirror responder takes
  the next decision, checks that the callback is of the same kind at the
  same position (a mismatch is reported), and gives the same answer.
- **R76 ahead.** If R76 reaches position *n* before the DUT has decided
  it, the mirror blocks. The `fw-proto-i2c` target core holds SCL low
  while its class layer decides (`i2c_target_xtor_core.sv`, UPREQ
  state). The block is therefore ordinary clock stretching on R76's bus,
  which R76 supports. The timing report subtracts these waits.
- **Deadlock guard.** A cycle bound turns a never-arriving decision into
  a report: "R76 waiting at position *n*; DUT stream ended at *m*".
- **Plain views.** In the plain views the DUT-side responder runs alone.

### 3.3 Register-access scoreboard (optional, later)

A stricter mode drives only the DUT with a single op-model instance. A
`wb_proto_if` decorator, `i2c_reg_eq`, then mirrors register traffic
onto R76's WISHBONE transactor: writes are forwarded; reads are
duplicated and compared once both return. One class works on every view.
`wb_proto_if::access()` is implemented both by the class model's register
export and by the `wb_initiator_xtor` bridge, and the decorator sits
where fw-wb-dma seats `wb_dma_reg_tee`.

Because the designs are not cycle-equivalent, this mode needs two rules:

- **Write pacing.** A forwarded CR command must not reach a busy R76.
  The decorator holds the DUT write until R76 is idle. It finds out by
  polling R76's SR privately, or by waiting for R76's IF.
- **Status skew.** SR.TIP/IF/BUSY/RXACK/AL, RXR and `wb_inta_o` can
  legitimately differ while one design is still busy.
  - **DUT done, R76 busy:** hold the DUT read and re-read R76 until it is
    done, then compare everything.
  - **R76 done, DUT busy:** compare only the fields that don't depend on
    completion. IF is sticky, so the next read still matches.

`EQ_READS=off` keeps the forwarding and pacing but compares no reads.

This mode is not in the first pass. It is worth adding if op-level
checking misses register-state bugs that the register tests don't catch.

### 3.4 Views

| View | Contents | Purpose |
|---|---|---|
| `ref` | R76 alone | The reference's own regression, and D1–D10 confirmation |
| `tlm` | `fw-i2c` class model and `i2c_tlm_bus`; no RTL, no signal-level transactors | Functional regression, and the **speed baseline** |
| `wb` | `fw_i2c_spl.sv` (class model behind pins) | Signal-level regression |
| `rtl`, `gates` (later) | fw-hdl-lowered RTL, then Yosys netlist | Regression after lowering and synthesis |
| `tlm-eq`, `wb-eq` (later `rtl-eq`, `gates-eq`) | DUT view + R76 arm + `fw_i2c_op_eq` + stream compare | **Equivalence** |

The same common tests run on every view. Tests hold an `fw_i2c_c_ctxt_if`.
In a plain view that is the op-model instance itself; in an `-eq` view it
is `fw_i2c_op_eq`. The suite report gives wall-clock time per test and
image. That compares `tlm` with `wb`/`rtl`/`ref`, and shows what
equivalence costs (`tlm` against `tlm-eq`).

**Self-test (E4), before any fw-i2c code exists.** Run R76 against a
second R76 arm, with three checks:

- **Identical arms:** every common test passes.
- **Sabotaged mirror:** the mirror inverts one ACK. The check must fail
  with a clear message.
- **Different PRER:** the second arm gets a different PRER through a test
  hook. Every test still passes, because timing doesn't matter, and the
  timing report shows the ratio.

### 3.5 Allowed differences

The allowed differences are one table of named rules
(`tests/uvm/env/i2c_allowed_diffs.svh`). Each rule cites its defect or
OI-6 item. Examples: D7 (PRER < 2), D1 (a CR write coincident with
`done`), STA+RD (the kit cannot express it, design §3.3). A rule is
enabled per test. The scoreboards count and report every rule they
apply. Tests that target a fixed defect *expect* the difference, and
fail if it does not appear.

## 4. Components

### 4.1 PSS op-model (`src/pss/`)

The op-model follows fw-wb-dma's layout and conventions (component
`fw_i2c_c`; `functions/`; `cfg` package with `HAS_EVENT_WAIT`). The
register part is generated from RDL by `reg-model-pss`, so the op-model
has no hand-written register map.

- **Operations:** `init(prer, ien)`, `start_write(addr_byte)` (STA+WR;
  any byte, so software 10-bit headers work), `write_byte(data, stop)`,
  `read_byte(ack, stop) → data`, `stop()`, and `iack`. Each returns
  `{rxack, al}`. Composite helpers `write_bytes`/`read_bytes` are
  built from these.
- **Waits:** the operations wait on TIP/IF through the `wait_hint`
  primitive (`yield` or `wake.get()` on IRQ, per profile), as fw-wb-dma
  does.
- **Specification:** `docs/design/operation-model.md`, the counterpart
  of fw-wb-dma's `wb_dma_operation_model.md`.
- **Later use:** the same model can generate C, for example as firmware
  for the iCEBreaker hardware back-to-back (design §9).

### 4.2 Test side (`tests/uvm/env/`)

| Item | Role |
|---|---|
| `i2c_model_base` | Like `wb_dma_model_base`. Provides the register access path for the adapter, the IRQ seam, the responder handle and the monitor event stream |
| `i2c_pss_mem_adapter` | Implements the generated import interface over an `i2c_model_base` |
| `fw_i2c_op_eq` | The equivalence scoreboard: implements `fw_i2c_c_ctxt_if`; forks each op to two op-model instances and compares (kind, in, out); timing report (§3.1). Generated by pssc where possible |
| `i2c_stream_cmp` | Passive in-order comparison of the two I2C event streams, applying the allowed-differences rules (§3.2) |
| `i2c_mirror_responder` | The R76-side responder that replays the DUT-side responder's decisions (§3.2) |
| `i2c_reg_eq` | Optional, later: the register-access scoreboard (§3.3) |
| `i2c_ref_model` | Model for the R76 arm |
| `i2c_tlm_model`, `i2c_wb_model` (later `i2c_rtl_model`, `i2c_gates_model`) | One model per view |

### 4.3 Reference arm (`tests/uvm/tb/oc_i2c_ref_arm.sv`)

The reference arm is one reusable module, instanced by `hdl_top_ref` and
by every `-eq` top. It contains `oc_i2c_wb32`, a `wb_initiator_xtor`, an
open-drain bus, `i2c_target_xtor` and `i2c_monitor_xtor`. Most of it
already exists in `tests/ref/oc_i2c_wb32_tb.sv`; we lift it out of that
file.

### 4.4 Design (`src/spl/`, `src/spl-rtl/`)

The design follows {doc}`index` §3:

- `fw_i2c` (top `fw_component`): the register block (generated, §4.5),
  sequencer, busy watcher and IRQ.
- **Edges:** registers on a `wb_proto_if` export; I2C on an
  `i2c_controller_if` port (with `set_prescale()` driven from PRER); IRQ
  on `gpio_drive_if`. The bus-busy input is an extra API edge: a monitor
  subscription at TLM, and the filtered lines on `wb`.
- `src/spl-rtl/fw_i2c_spl.sv` has the same pins as `oc_i2c_wb32`. It
  contains a `wb_target_xtor`, the `i2c_controller_xtor` with `T_*` set as
  in design §3.3, pad inversion, the 2-flop + 3-sample filter, and the
  START/STOP detector.

### 4.5 Register tooling (in `packages/`, edited locally)

This closes design §4.1 gaps R1–R5 in the fw-hdl register tooling, not
with a hand-written workaround.

| Gap | Change | Where |
|---|---|---|
| R1/R2: split registers (a read and a write register at one offset: TXR/RXR, CR/SR) | Allow one `sw=r` and one `sw=w` register per offset; reads route to the readable one, writes to the writable one | `fw-hdl` `fw_reg_block`/`fw_reg_base` (`src/fw_reg_block.svh`); `peakrdl-fw-hdl` exporter; `peakrdl-pss` (the op-model must see the same split map); `fw-hdl` `synth-mmio` regblock lowering (`mmio_synth.py`), so that the `rtl` view gets it too |
| R3: `hwclr`/`singlepulse` (CR command bits, IACK) | Generate the hardware-clear and pulse behaviour, instead of hand-coded write hooks | `peakrdl-fw-hdl`, `fw_reg_block`, `synth-mmio` |
| R4: interrupt (SR.IF → `wb_inta_o`) | One bit: hand-code it in the design for now. FWH-INTR support stays out of scope unless R3 makes it cheap | — |
| R5: a write gated by another field (CR written only when EN = 1) | Write hook in the design | — |

Each package change gets its own tests in that package's suite, then
fw-i2c bumps its pin. Applying the same change to fw-wb-dma's regression
shows nothing broke there.

### 4.6 TLM I2C channel (`fw-proto-i2c`)

`i2c_tlm_bus` implements `i2c_controller_if` by calling an
`i2c_target_if` and broadcasting to `i2c_monitor_if` subscribers. It is
single-master, with no arbitration, and optionally consumes
`ticks × (prescale+1)` clocks of time. It comes with a kit test, run
back-to-back against the existing target memory responder.

## 5. ivpm changes

- **Add to the `dev` dep-set as git clones:** `pssc`, `pssparser`,
  `peakrdl-pss`, `dv-flow-libpss`, `agent-skills-pss`. Copy the URLs and
  dep-sets from fw-wb-dma's `ivpm.yaml`.
- **Already git clones on `main`:** `fw-hdl`, `peakrdl-fw-hdl`,
  `fw-proto-i2c`, `fw-proto-wb`, `fwvip-i2c`, `fwvip-wb`. `oc-i2c` is on
  `fw-r76`. Work on these happens on branches in the clones.
- **Pinning:** while a package branch is unmerged, `ivpm.yaml` notes it,
  the same way the `oc-i2c` pin note does today.

## 6. Steps

| # | Step | Output | Depends on |
|---|---|---|---|
| T1 | ivpm: add the PSS toolchain (§5); `ivpm update`; check that `pssc` runs from dfm | `ivpm.yaml` | — |
| T2 | Register tooling R1 (split registers) in `fw_reg_block`, `peakrdl-fw-hdl`, `peakrdl-pss`, with per-package tests | branches in `packages/fw-hdl`, `packages/peakrdl-fw-hdl`, `packages/peakrdl-pss` | — |
| T3 | Register tooling R3 (`hwclr`/`singlepulse`) | same packages | T2 |
| T4 | `fw_i2c_regs` RDL (the R76 map, 4-byte stride); `reg-model` and `reg-model-pss` export tasks | `src/rdl/fw_i2c_regs.rdl`, `src/rdl/flow.yaml` | T2 (T3 for the clean form) |
| T5 | PSS op-model, its specification, and `op-model-sv` | `src/pss/`, `docs/design/operation-model.md` | T1, T4 |
| T6 | pssc `OpModelSv` options: generate the dual-dispatch comparator (`eq`) and an op-record/recording decorator (`record`) from the programming API | branch in `packages/pssc` | T5 (can trail E4) |
| E1 | UVM env skeleton: `i2c_model_base`, `i2c_pss_mem_adapter`; `ref` view (`hvl_top_ref`/`hdl_top_ref`); dfm `images`/`uvm-universal` matrix | `tests/uvm/{env,tests,tb}/`, `tests/uvm/flow.yaml` | T5 |
| E2 | Common tests: register map and reset, write, repeated-START read, NACK, IF/IACK/IRQ, PRER sweep (≥ 2), clock stretching, 10-bit headers sequenced by software. They replace `tests/ref/` | `tests/uvm/tests/` | E1 |
| E3 | Reference confirmation (plan step 2): D1, D6–D10 as `ref`-only tests; record the results in {doc}`../reference/deviations`; decide OI-6 | ref-only tests, updated docs | E1 |
| E4 | Equivalence harness: lift the reference arm; build `fw_i2c_op_eq` (hand-written, or from T6), `i2c_stream_cmp`, the responder pair (active + mirror), the allowed-differences table and the timing report. Then **self-test** on R76 vs R76 (§3.4): identical arms pass; a sabotaged mirror fails with a clear message; different PRER passes and reports the timing ratio | `tests/uvm/env/`, `tests/uvm/tb/oc_i2c_ref_arm.sv` | E2 |
| E5 | `i2c_tlm_bus` and its kit test | branch in `packages/fw-proto-i2c` | — |
| E6 | `fw-i2c` SPL model on the generated register block | `src/spl/` | T3, T4 |
| E7 | `tlm` and `tlm-eq` views; the common tests pass on both | `hvl_top_spl.sv`, `hdl_top_spl.sv`, `hdl_top_spl_eq.sv` | E4, E5, E6 |
| E8 | `wb` and `wb-eq` views: `fw_i2c_spl.sv` with filter and busy detector | `src/spl-rtl/`, tops | E7 |
| E9 | Random op streams: constrained-random operation sequences (legal per the R76 programming model) with random PRER and random responder behaviour. This is the main equivalence workhorse. Solve the PSS scenarios with pssc, or randomise in SV over the op surface, whichever pssc supports | `i2c_rand_ops_test` | E8 |
| E10 | Speed report: wall-clock per test × image (`tlm`, `wb`, `ref`, `tlm-eq`, `wb-eq`) | `docs/results.md` section | E8 |
| E11 | Split registers in `synth-mmio`; `rtl` and `rtl-eq` views once plan step 3 shows the design lowers; `gates`/`gates-eq` after plan step 8 | | T2, plan steps 3, 8 |
| E12 | Shared-bus multi-master bench: fw-i2c and R76 on one bus (design §6.2, method 2) | | E8 |

These tracks are independent and can run in parallel:

- **Register tooling:** T2 → T3 → T4.
- **Bench:** T1, then E1–E4 on R76 only. E1 needs T5, and T5 needs T4,
  but a provisional `reg-model-pss` over the existing
  `src/rdl/oc_i2c_master.rdl` lets T5 and E1 start before T2 is done.
- **Kit:** E5.

## 7. dfm shape

- Parameters: `images: [ref, tlm, wb, tlm-eq, wb-eq]` (plus a scoreboard self-test image for E4) (later
  `rtl`, `gates` and their `-eq`), `build: opt|dbg`, `sim: vlt`.
- Tasks: `view-src-<image>` aggregators; `sim-img` select over image ×
  build; `uvm-universal` matrix image × case; `uvm-ref-only` for E3;
  `reg-model`, `reg-model-pss`, `op-model-sv` as in fw-wb-dma.
- Commands: `dfm run tests`, `dfm run tests --views tlm,tlm-eq`,
  `-D images=ref`, `dfm run tests-info`.

## 8. Risks and follow-ups

- **P1: the op API decides what is compared.** If an operation returns
  too little (for example, `stop()` returning nothing), op-level checking
  misses state that the register-level mode would see. When designing
  the op-model (T5), make each operation return the status software
  would act on (RXACK, AL, read data). Keep §3.3 in reserve.
- **P1b: offline equivalence** (follow-up). Use the `record` decorator to
  store op traces and I2C streams from R76 once, then compare later
  fw-i2c runs against them with no parallel simulation.
- **P2: the split-register change touches four places**
  (`fw_reg_block`, `peakrdl-fw-hdl`, `peakrdl-pss`, `synth-mmio`). We
  keep them consistent with one RDL test case shared across the package
  tests, and with the fw-wb-dma regression.
- **P3: pssparser defects.** fw-wb-dma documents several (for example
  declarations inside `compile if`). We follow its workarounds, and log
  any new defect in the pssc/pssparser clone.
- **P4: `#1` delays in R76 at `dba90b2`.** These are harmless for a
  transaction-level compare, but they are noise. The fix is to push the `oc-i2c`
  `fw-r76` branch and move the pin to `r76-fw1`.
- **P5: busy detection at TLM.** SR.BUSY is not settled at every sync
  point even in single-master tests: R76 reads BUSY = 1 straight after a
  `stop` completes, until its STOP detector catches up. The `busy` field
  of `stop`'s result is therefore a likely allowed difference, and tests
  wait for BUSY with `read_status`. Multi-master BUSY is covered only by E12.
- **P6: allowed-difference creep.** Every rule is counted and reported,
  and the rules are reviewed with OI-6.

## 9. Status

| Step | Status |
|---|---|
| Plan | reviewed 2026-10-17; decisions recorded above |
| T1 | done 2026-10-17. `ivpm.yaml` adds `peakrdl-pss`, `pssc`, `pssparser`, `dv-flow-libpss`, `agent-skills-pss` (explicit `dep-set`s: these packages have no `dev` set). `pssc.Check` runs from dfm. dfm needs the ivpm environment: run it as `direnv exec . dfm ...` (or from a direnv shell); without it `IVPM_PACKAGES` is unset and `flow.yaml` fails to load |
| E5 | done 2026-10-17; committed on `main` of the `packages/fw-proto-i2c` clone (c6f82ea, pushed). `src/i2c_tlm_bus.svh`: decodes bytes as the target and monitor cores do (so raw-byte 10-bit headers behave as at signal level); optional timing via `set_timing()`. `i2c_proto_tb` reruns its stimulus over the bus and requires the identical monitor event stream (135 events, all three timing variants), and gained a raw-byte 10-bit case. Kit `tests` (5/5) and `lint-rtl` pass |
| T2 | done 2026-10-17; committed on `main` of the clones (fw-hdl a4eada1, peakrdl-fw-hdl 08c851a, peakrdl-pss bdfc8f2; pushed). fw-hdl: `fw_reg_access_e` (`FW_REG_RW`/`RO`/`WO`, trailing ctor arg, default RW), `fw_reg_block` decodes reads and writes in separate tables, `$fatal` on a same-direction collision; `reg_core` tests added; 29/30 sim cases pass (`rv_proto` fails before and after: Verilator vif-trigger limitation). peakrdl-fw-hdl: emits `.access(FW_REG_WO)` for a register with no readable field, `.access(FW_REG_RO)` for a read-only register that shares its offset; `FWH-WRITEONLY` now only for write-only fields in readable registers; `tests/rdl/split.rdl`, `test_split.py`, SV tier `split` map (all 8 maps pass; needs a local untracked `packages -> ..` symlink in the clone, do not commit it); docs updated. peakrdl-pss: already correct, golden `split` added (528 pass). Not done here: synth-mmio (E11); pssc C struct overlay rejects shared offsets (needed only for firmware) |
| T3 | done 2026-10-17, same commits. fw-hdl: `pulse_mask` (trailing ctor arg): write observers get the written word with pulse bits set, the stored value never holds them, so waiters and reads see 0 (`reg_hooks` test). `hwclr` needs nothing new: the field is hardware-writable and the design clears it with `update_val`. peakrdl-fw-hdl: `singlepulse` → `.pulse_mask(...)`, no longer `FWH-SIDEEFFECT`; `unsupported` golden regenerated; 245 pass. Baseline failures, unchanged by this work: `tests/roundtrip` (10 of 14, the fw-hdl front end recovers nothing here). Note: fw-hdl's `reg_*` benches print FAIL but exit 0, so check `sim.log`, not the dfm return code. Not done here: `pulse_mask` in synth-mmio (E11) |
| T4 | done 2026-10-17. The R76 registers moved to `src/rdl/oc_i2c_regs.rdl`, included inside two addrmaps that set width and `OC_I2C_STRIDE`: `oc_i2c_master.rdl` (R76: 8-bit, stride 1; elaborates identical to before apart from three descriptions that named byte addresses) and `fw_i2c_regs.rdl` (32-bit, stride 4). `src/rdl/flow.yaml`: `reg-model` (fw-hdl, `fw_i2c_reg_pkg`) and `reg-model-pss` (`fw_i2c_regs_pkg`); both export clean (no unsupported notes, no warnings). peakrdl-pss: `singlepulse` on a write-only field is no longer reported lossy (529 pass) |
| T5 | done 2026-10-17. `src/pss/` (types, cfg, component, four function files) and `src/pss/flow.yaml` (`pss.src`, `pss.check`, `pss.check-nonblocking`, `pss.op-model-sv`); spec `docs/design/operation-model.md`. Ops: `configure`, `shutdown`, `address`, `write_byte`, `read_byte`, `stop` (each with a `_start` half), `completion_check`, `completion_wait`, `read_status`, `notify_irq`; byte ops return `fw_i2c_result_s` (named SR bits + data). Completion is SR.IF (TIP is 0 for STO-only commands); every CR write carries IACK. Both profiles elaborate; generated `fw_i2c_c_pkg` lints clean with Verilator. This pssc (0.2.0) needs `export target function f;` and generates `fw_i2c_c_ctxt_if` + `fw_i2c_c_root #(IMP)::create(imp, base)`, not fw-wb-dma's `*_c_if`/`*_c #(IMP_T)` shape |
| E1 | done 2026-10-17. `tests/uvm/`: env package (`i2c_model_base` with target slot, monitor fan-out and IRQ seam; `i2c_ref_model`; `i2c_pss_mem_adapter` calling the model's `wb_proto_if.access()` directly, no UVM sequencer, so two can run in parallel; `i2c_mem_target`; `i2c_bus_log`; `fw_i2c_env` with the `notify_irq` pump), tests package (`fw_i2c_base_test` with `write_mem`/`read_mem` helpers, `fw_i2c_smoke_test`), tops (`oc_i2c_ref_arm`, `hdl_top_ref`, `hvl_top_ref`), `tests/uvm/flow.yaml` (`uvm-env`, `sim-img` select, `uvm-universal` matrix). The project now `uses: project.dv.uvm`, with `images`/`view_tb`/`view_top`; UVM comes from Verilator's bundled copy. `ref-smoke` passes on R76; `dfm run tests` 2/2. Finding: BUSY lags the STOP command's IF (reads 1 straight after `stop`; recorded in reference/operation.md; relevant to P5) |
| T6, E2–E4, E6–E12 | not started |
