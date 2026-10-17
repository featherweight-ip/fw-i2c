# Control-synthesis benchmark target — proposal

Date: 2026-10-16

## Problem statement

We need a target IP to headline **control synthesis** QoR — distinct from the
XLS-based dataflow/algorithm story (see [ai-benchmark-strategy.md](ai-benchmark-strategy.md),
[eval-vehicle-dcrc.md](eval-vehicle-dcrc.md)). Requirements:

- Control-dominated (FSM-heavy), not a dataflow pipeline — XLS is not the
  comparison point here.
- Non-trivial: not a textbook vending-machine/traffic-light FSM.
- Not so complex that hand-RTL vs. synthesized QoR becomes noisy or
  unreviewable in a first benchmark.
- A real, recognizable IP so the comparison lands with a chip-design
  audience, with a credible hand-written RTL baseline to diff against.

**Deliberately excluding HLS/XLS-style dataflow designs from this benchmark.**
A dataflow pipeline's resource/timing numbers are dominated by the datapath
(multipliers, wide adders, memories) — the control logic is a small fraction
of the design, so mediocre control synthesis can hide inside a good dataflow
result and never show up in the aggregate QoR. This benchmark exists to
isolate control logic specifically, on IP where the *entire* design is
control, so there's nowhere for a bad result to hide.

The target should also be something experienced RTL engineers already feel
confident hand-coding well — a design where "I could write this FSM myself in
an afternoon and trust it" is a reasonable reaction. That's what makes the
hand-RTL arm a fair, non-strawman baseline: we're not comparing against a
weak or rushed reference implementation, we're comparing against something
humans are genuinely good at. A believable win here is a believable win
everywhere. This benchmark is explicitly meant to round out the story once
the HLS/dataflow (XLS) side is established — "we're not just good at the
part humans find tedious (dataflow pipelining), we're also good at the part
humans already do well (control)."

## Key finding from research

Google XLS's own docs state plainly that **XLS does not do control-flow
synthesis**: "if you have a complex FSM to implement, you cannot describe the
circuit in an imperative-style language and rely on the compiler to
synthesize the control logic; instead you must explicitly instantiate all the
hardware state... and manually ensure it behaves as expected."
([How to use Procs](https://google.github.io/xls/tutorials/how_to_use_procs/))

This is useful ammunition: it sharpens the "XLS alone can't do this" framing
and makes a control-synthesis benchmark a clean, non-overlapping companion to
the XLS dataflow story rather than a competing claim.

Separately, recent LLM-RTL benchmark work (ProtocolLLM, 2026) found that
**UART and I2C expose synthesis/generation weaknesses that SPI does not**,
because of "greater temporal complexity and signal interplay" — multi-phase
bit/byte framing, clock-domain timing, start/stop condition detection,
arbitration — while SPI's fixed shift-register structure is closer to
dataflow than control. That's a useful sizing signal: SPI is too simple,
protocol-level I2C/UART sit in the right band.
([ProtocolLLM](https://arxiv.org/html/2506.07945v2))

Academic FSM benchmark suites exist (ITC'99 b01–b22, SYNTLOG's 101-FSM
corpus) but they're synthetic/anonymous circuits with no recognizable
real-world IP story — good for stress-testing a synthesis algorithm, bad for
a "here's a controller an SoC team would actually tape out" pitch.
([ITC'99](https://github.com/cad-polito-it/I99T), [SYNTLOG](https://arxiv.org/abs/2608.23288))

## Recommendation: I2C master/slave controller (multi-master, clock sync + arbitration)

Concretely: a byte-oriented I2C controller supporting both master and slave
roles, with:

- Start/repeated-start/stop condition generation and detection
- 7-bit and 10-bit addressing
- Clock stretching (slave-driven wait states on SCL)
- Multi-master bus arbitration (loss-of-arbitration detection via SDA
  mismatch during a byte)
- ACK/NACK handling per byte, including the final-byte NACK-to-stop sequence
- A register/FIFO front end (CSR block) so the design isn't *just* the
  protocol FSM in isolation — closer to how this would actually integrate

This is the sweet spot: dozens of states across master/slave/arbitration
sub-FSMs (not hundreds), every transition has real protocol-correctness
consequences (so a wrong synthesis is visibly wrong, not just slower), and
there's a 20-year-old, widely cross-checked hand-RTL baseline to diff
against: the OpenCores `i2c` master core, used as a reference design in
countless SoCs and still the implementation most engineers would recognize.
It's also squarely in "humans are good at this" territory — I2C controllers
are a design engineers write from memory, not something that takes
person-years to get right, so the hand-RTL baseline is a genuinely strong
reference rather than a strawman.

### Scope boundary: what's actually being synthesized

fw-hdl keeps signal-level protocol logic in **transactors**: the
transaction-level description only thinks in bytes. That means start/
repeated-start/stop generation and detection, clock stretching (bit-level
SCL wait-states), and bit-by-bit arbitration (SDA-mismatch detection
*within* a byte) are transactor responsibilities — they are not inputs to
fw-hdl's control synthesis and would be hand-coded (or at least held
constant) in both arms. What fw-hdl's control synthesis actually targets is
the **transaction-level control block**: byte/frame sequencing, 7-bit vs.
10-bit address-phase sequencing, repeated-start-as-a-transaction-event
sequencing, arbitration-lost-as-a-status-code handling, ACK/NACK-per-byte
sequencing into retry/abort behavior, and the CSR/FIFO front end (register
decode, FIFO fill/empty/threshold, interrupt generation).

This doesn't disqualify I2C — the transaction-level control here is still
real and non-trivial (multi-byte addressing modes, repeated-start handling,
arbitration recovery, clock-stretch-aware sequencing at the transaction
level) — but it does mean the benchmark's headline QoR numbers must be
scoped to that transaction-level block, not the full bit-banging FSM. See
"Suggested benchmark structure" below for how the two arms stay comparable
given that split. Bit-level protocol complexity (the signal-level FSM) is a
good candidate for a *later*, transactor-focused benchmark once this
byte-level one is established — starting simple and adding complexity in
later rounds is the right order of operations.

**Why this beats the alternatives below for a first benchmark:**
- vs. UART: UART's control is mostly a bit-timer + shift register; I2C adds
  genuine multi-master arbitration and bidirectional-line semantics, which is
  a better stress test for control synthesis without ballooning state count.
- vs. SPI: too dataflow-shaped (fixed shift register, no arbitration, no
  variable-length protocol phases) — doesn't exercise control synthesis.
- vs. a cache controller / DRAM controller FSM: right complexity *class* for
  a second-round benchmark, but first-round risk is too high — coherence/
  scheduling FSMs have enough combinatorial interaction with timing closure
  that a QoR delta could get misread as a tooling bug rather than a real
  result.
- vs. ITC'99/SYNTLOG synthetic FSMs: good for internal regression/stress
  testing of the control-synthesis algorithm itself (cheap to add later),
  but bad as the *headline* benchmark since there's no real IP story.

## Suggested benchmark structure

Three arms, consistent with the DCRC eval vehicle's methodology:
- **A**: hand-written SV RTL (OpenCores `i2c` core as the baseline, or a
  from-scratch equivalent if licensing is a concern for publishing results)
- **B**: fw-hdl description → fw-hdl's native control synthesis (not XLS —
  XLS explicitly doesn't apply here)

Both arms implement the same full controller (bit-level signal protocol +
transaction-level control + CSR/FIFO), so the design reads as one credible,
tapeout-shaped IP end to end — not a stripped-down fragment. Because fw-hdl
only synthesizes the transaction-level control block (see "Scope boundary"
above), the original plan was to hold the bit-level signal protocol
constant across arms by hand-coding it once and reusing it identically in
both (arm A's own bit-level FSM, with the fw-hdl transactor in B wrapping
that same logic).

**Decision: use a library I2C transactor in arm B instead.** That means the
bit-level serial logic will *not* be identical between A and B — arm A gets
a from-scratch (or OpenCores-derived) bit-level FSM, arm B gets whatever a
transactor library provides. This sacrifices the clean "bit-level held
constant" isolation above, but it's a deliberate trade: it's also the more
realistic way an fw-hdl user would actually build this IP (reach for a
library transactor rather than hand-write bit-level protocol logic), and it
surfaces a second, complementary finding alongside the headline
control-synthesis QoR — whether, and how much, using a transactor library
costs (or saves) at the bit level versus hand-written RTL. The headline
transaction-level control comparison (control synthesis proper) is
unaffected by this choice, since that block is unchanged either way; this
only changes what backs it at the bit level. The full-IP "reported but not
headlined" numbers below should now be read with that caveat: any
full-IP delta between arms may reflect transactor-library overhead/savings,
not just transaction-level control synthesis.

- **Headline metrics** (the actual control-synthesis comparison): area,
  max frequency/critical path, and state-count/logic-depth of the
  transaction-level control block only — hand-written-as-a-standalone-FSM
  in A vs. fw-hdl-synthesized in B.
- **Reported but not headlined**: full-IP totals (transactor + transaction
  control + CSR/FIFO), so readers can see the realistic whole-IP numbers and
  confirm the bit-level portion is indeed held constant across arms.

## Open question for you

With the scope boundary above, most of what slave-side support adds —
clock-stretching *response* and general-call address *detection* — is
bit-level transactor logic, held constant and not part of the headline
comparison either way. The remaining slave-side delta at the
transaction-level control layer (general-call as a recognized
transaction-level address target, slave-mode CSR/FIFO handling) is smaller
than originally framed. Given that, do you still want slave-side included
in the first pass for IP-story completeness, or start master-only since the
transaction-level control delta it adds is now modest?

## Sources

- [How to use Procs — XLS docs](https://google.github.io/xls/tutorials/how_to_use_procs/) (confirms XLS has no control-flow/FSM synthesis)
- [ProtocolLLM: RTL Benchmark for SystemVerilog Communication Protocols](https://arxiv.org/html/2506.07945v2) (UART/I2C vs SPI complexity finding)
- [RT-level ITC'99 benchmarks and first ATPG results](https://github.com/cad-polito-it/I99T)
- [SYNTLOG: FSM Benchmarks Evaluation for FPGA](https://arxiv.org/abs/2608.23288)
