# fw-i2c design (draft for review)

```{admonition} Draft
:class: warning
Written 2026-10-17 for review. Decisions that need an answer are listed
under {ref}`open-issues`. Nothing here has been implemented yet.
```

```{admonition} Decisions (2026-10-17)
:class: tip
- **Scope:** master-only first; size baseline R76 (`dba90b2`). (OI-1, OI-2)
- **Compatibility:** register-compatible with R76. (OI-3)
- **Target:** iCE40UP5K on the iCEBreaker board (12 MHz clock). (§7)
- **Repository name:** `fw-i2c`. (OI-11)
- **Runtime bit rate:** a runtime prescale setting in `fw-proto-i2c`, set by
  a method (`set_prescale()`), not a parameter on each call. (OI-4;
  implemented, see §3.3)
```

## 1. Goal

Build an I2C controller with fw-hdl that:

1. is aligned with the freecores `i2c` core, whose actual behaviour is
   documented in {doc}`../reference/index`
2. is verified back-to-back against that core, using the
   `fwvip-i2c` VIP
3. is lowered to Verilog RTL by fw-hdl
4. is synthesized with the same flow as the freecores core, and compared
   with it for area (and timing)

This is the "arm B vs. arm A" control-synthesis benchmark proposed in
`control-synthesis-benchmark.md` (repository root). Arm A is the freecores
core (hand-written RTL). Arm B is `fw-i2c`: a transaction-level control
block written with fw-hdl, over a library I2C transactor
(`fw-proto-i2c`).

### Inputs reviewed

| Input | What it gives this project |
|---|---|
| `i2c_specs.md` | The specification `fw-i2c` aligns with: a text conversion of the OpenCores I2C-Master PDF (Rev 0.9, 2003). It is out of date relative to the RTL in several places, so {doc}`../reference/index` restates it from the RTL; differences are in {doc}`../reference/deviations`. |
| `packages/i2c` (freecores, fetched by ivpm) | Arm A: the RTL that `i2c_specs.md` describes, plus the later slave extension. |
| `control-synthesis-benchmark.md` | The benchmark's goals, scope boundary, arms and metrics. |
| `featherweight-vip/fwvip-i2c` | UVM VIP (controller, target, monitor agents, a memory responder, a scoreboard) over the `fw-proto-i2c` kit. It has a back-to-back bench pattern and a `dfm`-driven layout this project copies. |
| `fw-proto-i2c` (vendored by fwvip-i2c) | Synthesizable I2C controller, target and monitor transactor cores, with formal properties. This is the "library transactor" for arm B. |
| `featherweight-hdl/fw-hdl` | The SystemVerilog class library, and the `fw-hdl synth-mmio` native FSM lowering (register block + FSM components). XLS lowering does not apply to FSM-shaped logic. |
| `featherweight-hdl/peakrdl-fw-hdl` | SystemRDL → `fw_reg_block` register model. |
| `featherweight-ip/fw-wb-dma` | The most complete fw-hdl IP project: RDL → `rdl.Export` → class model → pin binding, with one UVM environment run against several DUT images. |

## 2. Scope

| | Phase 1 (this design) | Later |
|---|---|---|
| Role | Controller (master), multi-master capable | Target (slave) mode |
| Registers | freecores map, master subset ({ref}`regs`) | Slave bits, SLADR |
| Addressing | 7-bit and 10-bit, sequenced by software as in freecores | Hardware 10-bit header (the kit already supports it) |
| Bus | WISHBONE Classic, 8-bit | APB, or a 32-bit-stride map |
| Timing | Runtime PRER, freecores-compatible formula | Separate tLOW/tHIGH/setup registers |
| Baseline for size | R76 (`dba90b2`, master-only) | HEAD (`3b067f0`) when slave mode is added |

Phase 1 is master-only. The reasons:

- The freecores slave mode is untested upstream, and it carries
  defects D2–D5. A differential bench that has HEAD as its reference
  would mostly be testing the reference.
- Master-only matches R76, the core the PDF describes, which is the
  credible hand-RTL baseline.
- `control-synthesis-benchmark.md` already notes that slave mode adds
  little to the transaction-level control comparison. That document
  leaves this as an open question, so it is repeated as **OI-1** below.

## 3. Architecture

```{mermaid}
flowchart LR
  WB["wb_* pins"] --> WBT["fw-proto-wb<br/>target xtor"]
  WBT --> RB["register block<br/>(generated from RDL)"]
  RB <--> SEQ["command sequencer<br/>(fw-hdl FSM component)"]
  SEQ --> PS["prescaler<br/>(tick enable)"]
  SEQ <--> CX["fw-proto-i2c<br/>controller xtor core"]
  PS --> CX
  CX <--> MON["bus watcher<br/>busy / START / STOP"]
  CX --> PADS["scl/sda<br/>_o / _oe / _i"]
  MON --> PADS
  RB --> IRQ["wb_inta_o"]
```

### 3.1 Layers

| Block | Implementation | Benchmark category |
|---|---|---|
| WISHBONE target | `fw-proto-wb` target transactor (library) | Glue. Reported, not headlined |
| Register block | Generated: SystemRDL → peakrdl-fw-hdl → `fw_reg_block` → `synth-mmio` `regblock.sv` | CSR front end. Part of the headline under the benchmark's scope boundary |
| Command sequencer | fw-hdl component, `wait_change` on CR, calls the transactor API; lowered by `synth-mmio` | **Headline:** transaction-level control |
| Prescaler | Small fw-hdl component or hand SV (open: OI-5) | Bit level. Reported |
| Controller transactor | `fw-proto-i2c` `i2c_controller_xtor_core` (hand SV, library) | Bit level. Reported |
| Bus watcher | START/STOP/busy detection; from the kit monitor core, or new | Bit level. Reported |
| Top wrapper | freecores-compatible port names and pad polarity | Glue |

### 3.2 Command sequencer

One process. It waits for a CR write while EN is 1, then maps the command
onto transactor operations:

| CR command | Transactor calls |
|---|---|
| STA + WR | `start(raw byte = TXR)` → ACK into RXACK |
| WR | `tx_byte(TXR)` → ACK |
| RD (+ACK) | `rx_byte(ack = CR.ACK)` → RXR |
| … + STO | then `stop()` |
| STO alone | `stop()` |

Then it clears STA/STO/RD/WR, updates RXACK/AL/TIP, and sets IF. A lost
arbitration result from any operation sets AL and IF and abandons the
command.

This is where control synthesis does its work. The FSM is small (about
8–10 states once lowered), and the hand-written equivalent is the
freecores byte controller's master half (`ST_IDLE`…`ST_STOP`).

### 3.3 Transactor fit: what `fw-proto-i2c` needs

The register interface is compatible with R76, so the sequencer has to
produce the same bus traffic from the same CR commands. Most of that can
be done in `fw-i2c` around the unchanged kit core. One item cannot.

| Item | freecores behaviour | How `fw-i2c` gets it | Kit change? |
|---|---|---|---|
| Any byte after START | STA + WR sends TXR as-is, including the `11110xx0` header that software uses for 10-bit addressing | `start(addr = TXR[7:1], read = TXR[0], addr_10b = 0)`. The core sends `{addr[6:0], read}` unchanged. Only the UVM layer rejects `11110xx`; the core does not. | No |
| START vs repeated START | The bit FSM decides from the bus state | The sequencer tracks whether it owns the bus (set by START, cleared by STOP or AL) and sets `repeated` | No |
| STA + RD | START, then a read with no address byte | The kit cannot express it, and it is not a meaningful I2C transfer. It goes on the allowed-differences list. | No |
| Bus busy (SR.BUSY) | START/STOP detector on the filtered lines | A small detector in `fw-i2c`, or the kit's monitor core | No |
| AL on an unexpected STOP | Aborts the command | Report-only or not matched (OI-6). Aborting needs a kit change. | Only if matched |
| Pad polarity | `*_padoen_o` active low, `*_pad_o` = 0 | Invert in the top wrapper | No |
| Input filter | 2-flop sync + 3-sample majority at PRER/4 | Filter in the wrapper, in front of the core | No |
| **Runtime bit rate** | Software writes PRER; SCL follows it | **Needs a change**; see below | **Yes** |

**Why the bit rate needs a change.** The kit core counts its timing in
`clock` cycles against parameters (`T_LOW`, `T_HIGH`, `T_SU_STA`, …) that
are fixed when the core is instantiated. R76 compatibility means firmware
writes PRER and expects SCL to change. A wrapper cannot slow the core
down without one of these:

- **A derived clock.** Clock the core from the PRER divider. This adds a
  second clock domain with CDC on the request/response link. On iCE40 it
  means a fabric-generated clock. fw-hdl's lowering does not support
  derived domains (PLAN.md §5). Not recommended.
- **Ignoring PRER.** Fix the timing for 100 kHz at 12 MHz and keep PRER as
  a dummy register. The register map is compatible but the behaviour is
  not. Arm B would also drop the 16-bit divider counter and its reload
  logic, which makes the area comparison unfair.

**As implemented** (2026-10-17, branch `runtime-prescale` in
`fw-proto-i2c` and `fwvip-i2c`, not yet pushed):

- **API.** `i2c_controller_if` has a new method,
  `set_prescale(bit [15:0] prescale)`. It is a runtime setting that holds
  until it is set again, not a parameter on each call. The bridge, the
  transactor interface and the fwvip-i2c agent config implement it.
- **Signals.** `i2c_controller_xtor_core` has a new level input,
  `prescale[15:0]`. The transactor interface holds it and
  `set_prescale()` drives it (default 0). The core needs no extra
  register for it, so in `fw-i2c` the PRER register is wired to the port
  directly.
- **Core.** The `T_*` parameters are counted in ticks of prescale+1
  clocks. Each phase load restarts the prescaler, so a phase of N ticks
  lasts exactly N·(prescale+1) clocks. Only the counters are gated: the
  SCL/SDA checks still run on every clock. With prescale = 0 the
  behaviour is identical to before.
- **Use in fw-i2c.** `fw-i2c` sets `T_LOW=3`, `T_HIGH=2`, `T_SU_STA=1`,
  `T_HD_STA=2`, `T_SU_STO=2` and `T_BUF=4`, which reproduces the
  freecores 5-tick bit, and wires PRER to `prescale`.
- **Verification.**
  - The kit has a new case, `i2c_proto_prescale`, with exactly those
    `T_*` values at prescale 5 (400 kHz at 12 MHz).
  - The back-to-back bench now checks the length of every
    controller-driven SCL low phase, in all cases.
  - Kit sims pass 5/5, lint shows 0 new findings, `fv-quick` BMC passes
    (harnesses at prescale 0), and the fwvip-i2c UVM suite passes 8/8.
  - There is no formal proof at prescale > 0 yet.

(regs)=
## 4. Registers

The register map is written in SystemRDL. `src/rdl/oc_i2c_master.rdl`
already describes the freecores HEAD map. `fw-i2c` gets its own top
(`fw_i2c_regs`) that reuses those definitions, minus the slave fields for
phase 1.

**Proposed phase-1 map:** the R76 map. That is: PRERlo, PRERhi, CTR (EN,
IEN), TXR/RXR, CR/SR, the TXR and CR readbacks at 0x5 and 0x6, and 0x7
reading 0. The readbacks cost 16 read-mux inputs and make the map
identical to R76, so the same firmware and the same register-level tests
run on both arms.

### 4.1 Tooling gaps (peakrdl-fw-hdl and `fw_reg_block`)

| Gap | Where | Need | Proposal |
|---|---|---|---|
| R1: split registers | TXR/RXR at 0x3, CR/SR at 0x4 | A write and a read register at one offset | `fw_reg_block` keys registers by offset. Add a read/write split: allow one `sw=r` and one `sw=w` register per offset. |
| R2: write-only | TXR, CR | Reads go to the other register | FWH-WRITEONLY today makes reads return the stored value; R1 resolves this |
| R3: hwclr / singlepulse | CR command bits, IACK | Hardware clear | FWH-SIDEEFFECT: not generated. Use `fw_reg_wr_if` hooks in the sequencer, or add support to peakrdl-fw-hdl |
| R4: interrupt | SR.IF → `wb_inta_o` | Sticky flag, enable | FWH-INTR: no OR tree. Hand-code it (one bit). |
| R5: gated write | CR written only when EN = 1 | Write qualified by another field | Use a write hook |

R1 is the only blocking gap. R1 and R3 are also the improvements other
OpenCores-style IP would gain from (see {ref}`opportunities`).

## 5. Behavioural alignment

"Aligned with freecores" has to be defined precisely, because the
reference has quirks and defects. Proposed rule:

- **Match** everything software can depend on: the register map and reset
  values, command semantics for the documented combinations, status-bit
  timing relative to IF, the PRER formula, and the IF/IACK protocol.
- **Fix** defects that well-behaved software cannot rely on: D1
  (repeated command after a coincident write), D6 (EN-cleared runaway),
  D7 (PRER = 0).
- **Decide** case by case (OI-6): STA alone, STA + STO, the exact SCL
  period (D10), the timing violations (D8), and the AL coverage (D9).

The bench's scoreboard encodes these choices as a short list of allowed
differences.

## 6. Verification

### 6.1 Benches

The bench uses one UVM environment run against several DUT images, as in
fw-wb-dma. It runs on Verilator through `hdlsim.vlt`.

| Image | DUT |
|---|---|
| `ref-r76` | freecores at `dba90b2` |
| `ref-head` | freecores at `3b067f0` |
| `fw-model` | `fw-i2c` class model (pre-lowering), through the SPL pin binding |
| `fw-rtl` | `fw-i2c` lowered RTL |
| `fw-gates` | `fw-i2c` after Yosys synthesis (gate-level simulation) |

The environment contains:

- a `fwvip-wb` initiator driving register sequences (firmware-like: the
  examples in {doc}`../reference/programming`, plus random command
  streams)
- a `fwvip-i2c` target with the memory responder (EEPROM-like, with clock
  stretching and NACK injection)
- a `fwvip-i2c` monitor and a protocol/timing checker
- a scoreboard that compares the bus transactions and the register-read
  results with a reference model

### 6.2 "Back-to-back"

There are three ways to put the two cores against each other. They answer
different questions, and the proposal is to run all three:

1. **Differential.** Same register stimulus, run separately on each
   image, each with its own target. The observed I2C transactions
   and register reads must match, up to the allowed-differences list.
   This is the main correctness argument.
2. **Shared bus, multi-master.** `fw-i2c` and freecores R76 on the same
   bus, both commanded at once. Checks clock synchronization and
   arbitration between two independent implementations. This is the case
   the fwvip-i2c bench cannot cover today (it has one controller).
3. **Interop with freecores slave mode** (phase 2). `fw-i2c` as master
   talking to freecores HEAD as a slave. Exercises D2–D5.

### 6.3 Reference confirmation

The directed tests in {doc}`../reference/verification` confirm or refute
D1–D10 against the freecores images. This comes first, because the
results decide the "match or fix" choices in §5.

### 6.4 Formal

- `fw-proto-i2c` already has BMC and cover properties for the transactor.
- Add properties for the sequencer: one command produces exactly one IF,
  command bits clear, and AL implies the command was abandoned.
- Use `fw.hdl.formal` `CodegenEquiv` (model vs. lowered RTL), if
  `synth-mmio` output is supported by it (OI-8).

## 7. Lowering and synthesis

### 7.1 Flow

```
src/rdl/*.rdl ──rdl.Export(fw-hdl)──► fw_i2c_reg_pkg.sv
src/spl/*.svh (sequencer, prescaler) ─┐
                                      ├─ fw-hdl synth-mmio ─► regblock.sv, seq.sv, top.sv
fw-proto-i2c xtor core (SV) ──────────┘
                                      └─ + wrapper ─► fw_i2c_top.v ─► Yosys / Vivado
```

### 7.2 Measurement

| Item | Choice |
|---|---|
| Target | **iCE40UP5K-SG48 (iCEBreaker), 12 MHz clock**: `synth_ice40 -device u`, `nextpnr-ice40 --up5k --package sg48 --freq 12`. Generic `abc -g` gate counts are reported as a technology-neutral cross-check. |
| Metrics | SB_LUT4, logic cells (ICESTORM_LC), flops, SB_CARRY, nextpnr Fmax. Fmax is reported over several placer seeds, because a single run varies. |
| Context | Out of context (all ports on pins) for the standalone numbers. In a board build the WISHBONE side is internal, so only the 4 I2C pad signals reach pins. |
| Granularity | Whole IP (both arms), plus per-block where the hierarchy allows it. Arm A: top / byte / bit. Arm B: regblock / sequencer / prescaler / xtor / wrapper |
| Equalization | Same WISHBONE width (8), same 16-bit PRER, same filter, same feature set (master-only vs R76); flatten for totals, keep hierarchy for the per-block breakdown |
| Baseline numbers | R76: 322 LUT4 / 368 LC / 46.0 MHz. HEAD: 436 LUT4 / 500 LC / 44.9 MHz (UP5K, Yosys 0.69, one seed); see {doc}`../reference/synthesis` |

The 12 MHz board clock gives PRER = 23 for 100 kHz and 5 for 400 kHz.
Both cores therefore run their prescaler at small values, where the input
filter samples every 6 or 2 clocks. That is worth noting in the results.

The headline number (transaction-level control) compares the arm-B
sequencer with the master half of the freecores byte controller. That
block has to be cut out of arm A. Two options: synthesize
`i2c_master_byte_ctrl` with the bit controller as a black box, or carve
out a hand-written master-only byte FSM. This is **OI-9**.

(open-issues)=
## 8. Open issues

| ID | Issue | Proposed answer |
|---|---|---|
| OI-1 | Master-only or master + slave in the first pass? | **Decided:** master-only. |
| OI-2 | Which freecores revision is "the" reference? | **Decided:** R76. HEAD is kept as a second image. |
| OI-3 | Register-compatible with freecores, or only behaviourally similar? | **Decided:** register-compatible with R76. |
| OI-4 | Runtime bit rate in the kit | **Decided and implemented:** the `set_prescale()` runtime setting; see §3.3. Push and merge of the kit branch are still to do. |
| OI-5 | Prescaler and input filter: written with fw-hdl, or hand SV? A counter is dataflow, not control. | fw-hdl if `synth-mmio` handles counters well, otherwise hand SV. Report it separately either way. |
| OI-6 | Match or fix each quirk: STA alone, STA + STO, AL on an unexpected STOP (§3.3), the SCL period (D10), timing violations (D8). | See §5; decide after the confirmation tests (§6.3). |
| OI-7 | Can `synth-mmio` lower this design? `fw-hdl/python/fw/hdl/PLAN.md` §5 lists non-goals for v1: multiple concurrent processes, sub-component hierarchy, derived clock domains, non-`put` protocols. The sequencer calls a transactor API (a non-`put` protocol) and sits in a hierarchy. | Spike first (plan step 3): the smallest sequencer that does `start`/`tx_byte`/`stop` through `synth-mmio`. |
| OI-8 | Formal equivalence of model vs. lowered RTL for `synth-mmio` output | Check whether `CodegenEquiv` supports it. |
| OI-9 | How to isolate the "transaction-level control" block in arm A for the headline comparison | Black-box the bit controller and report the byte controller (master half). Also report full-IP totals. |
| OI-10 | Reset: freecores has both async (`arst_i`, `ARST_LVL`) and sync (`wb_rst_i`) reset. fw-hdl offers `--reset-style`. | Match the port list. Use one reset style internally and tie the other off in the wrapper. Note the cost in the comparison. |
| OI-11 | Naming. NAMING.md says IP repos are `fw-ip-<proto>`. | **Decided:** `fw-i2c`. |
| OI-12 | The `i2c/` clone at the repository root duplicated the ivpm-managed `packages/i2c`. | **Done** 2026-10-17: removed; everything refers to `packages/i2c`. |

(opportunities)=
## 9. Opportunities

- **Publish the defects.** D1 and D2 (if confirmed) are real bugs in a
  widely used core. D2 affects every master START in the shipped
  freecores version. A short upstream issue or a note in the benchmark
  write-up makes the "credible baseline" point more strongly than the
  area numbers do. It also shows what the fw-hdl bench finds.
- **The benchmark needs a story about correctness as well as area.** A
  smaller arm B that matches R76 behaviour while fixing D1, D6 and D7 is a
  stronger result than area alone.
- **Shared-bus multi-master testing** (§6.2, method 2) closes the
  arbitration gap in fwvip-i2c ("one controller only") at almost no extra
  cost. The same bench can be offered back to fwvip-i2c.
- **Split-register support in `fw_reg_block` and peakrdl-fw-hdl** (R1, R3)
  helps other OpenCores-derived IP. The UART16550, for example, overlays
  RBR/THR and IIR/FCR in the same way.
- **Runtime timing in `fw-proto-i2c`** (the `tick` enable, §3.3) is also the open item in
  fwvip-i2c's `open-issues.md`. Doing it here closes it there.
- **A freecores-compatible model in fwvip-i2c.** fwvip-i2c's design §8
  item 7 proposes a "DUT register-model agent" for the OpenCores core.
  The reference model this bench needs is exactly that.
- **An area-per-feature table.** The images already separate slave mode
  (HEAD − R76 = +32% LUTs). Doing the same for `fw-i2c` (filter, debug
  readbacks, 10-bit hardware headers) gives readers a cost model, not
  just one number.
- **A protocol-timing checker.** D8 shows that the reference may violate
  UM10204. A monitor-side timing checker parameterized by speed mode
  turns this into a standing check for both arms.
- **Hardware back-to-back on the iCEBreaker.** The UP5K has room for
  both cores and a small WISHBONE driver in one bitstream (R76 uses 7% of
  the logic cells). The bench's shared-bus multi-master test can then run
  on a real open-drain bus through a PMOD with pull-ups, against a real
  I2C EEPROM or sensor. That checks the real-world behaviour, such as
  timing under real rise times and D2's glitch on a scope, which no
  simulation does.
- **The documentation pipeline** (RDL → sphinx-peakrdl, WaveDrom,
  Mermaid) built for this reference is reusable as-is for the `fw-i2c`
  register map and the benchmark report.

## 10. What I need from you

1. Review and push the `runtime-prescale` branches of `fw-proto-i2c`
   and `fwvip-i2c` (§3.3).
2. OI-6 can wait until the reference confirmation tests have run.
