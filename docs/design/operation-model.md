# Operation model

The operation model is the device's programming interface, stated once in
PSS (`src/pss/`) and generated as SystemVerilog for the test bench (and
later as C for firmware). It is the counterpart of fw-wb-dma's
`wb_dma_operation_model.md`. {doc}`bench-plan` §3.1 explains why it
matters beyond driving tests: the equivalence check compares designs
**per operation**. An operation's inputs and outputs are what the check
sees, so what an operation returns decides what is compared (bench-plan P1).

The model targets the R76 programming model ({doc}`../reference/programming`,
{doc}`../reference/operation`). Every design that runs it (R76 itself,
fw-i2c at every abstraction level) must give the same results.

## Scope

The operations cover what well-behaved software does: set up, then move
bytes with START, repeated START, write, read and STOP. They do **not**
expose the quirks that software should not rely on (STA alone, STA + STO,
RD + WR, CR writes while EN is 0, PRER changes while enabled). Those stay
in register-level tests ({doc}`bench-plan` E2, E3), where the reference
behaviour is confirmed and the fw-i2c behaviour is decided (OI-6). An
operation stream is therefore always legal for both designs, and a
mismatch is a real difference.

## Register map

The register part is generated from `src/rdl/fw_i2c_regs.rdl` by
`reg-model-pss` (`fw_i2c_regs_pkg`). The model contains no hand-written
offsets. TXR/RXR and CR/SR are split registers: TXR and CR are
write-only, RXR and SR read-only.

## Operations

The model follows the fixed layering of the `pss-operation-model-create`
skill. Each byte operation has a non-blocking half, `<op>_start`, which
programs the device and returns, and a blocking one, `<op>`, which is
`<op>_start` followed by `completion_wait()`. A target with no blocking
runtime (firmware, an ISR) gets the whole API through the `_start` halves
and `completion_check()`.

Every `_start` does the same two things:

1. Write TXR, if the operation sends a byte.
2. Write CR with the command bits **and IACK**. IACK clears the IF left by
   the previous operation. The command cannot complete in the same clock,
   so the acknowledge can't swallow it.

CR and TXR are always written whole. They are write-only and share their
offsets with SR and RXR, so a read-modify-write (`write_field`) would read
the wrong register.

| Operation | Inputs | Writes | Returns |
|---|---|---|---|
| `configure` | `prer` (16 bits), `ien` | PRERlo, PRERhi, then CTR = EN \| IEN | — |
| `shutdown` | — | CTR = 0 | — |
| `address[_start]` | `addr_byte` (8 bits) | TXR = `addr_byte`; CR = STA \| WR \| IACK | result |
| `write_byte[_start]` | `data` (8 bits), `stop` | TXR = `data`; CR = WR \| (STO) \| IACK | result |
| `read_byte[_start]` | `nack`, `stop` | CR = RD \| (ACK) \| (STO) \| IACK | result, with `data` = RXR |
| `stop[_start]` | — | CR = STO \| IACK | result |
| `completion_check` | — | none; one SR read | `{done, sr}` |
| `completion_wait` | — | none; loops on `completion_check` | result |
| `read_status` | — | none; one SR read | result |
| `notify_irq` | — | none; posts the wake channel | — (event-wait profile only) |

A **result** (`fw_i2c_result_s`) is the SR fields at completion, as named
bits (`rxack`, `busy`, `al`, `tip`, `irq_flag`), and `data`. `data` is the
byte read for `read_byte` and 0 otherwise. Software acts on `rxack` and
`al`. Returning all five fields also puts BUSY, TIP and IF under comparison.
The fields are named, not packed into a byte, so a failed comparison names
the bit that differs. (pssc does not lower PSS `output` parameters, so a
function that returns several values returns a struct. In SystemVerilog
that becomes a leading `output` argument, for example
`task write_byte(output fw_i2c_result_s status, input bit [7:0] data, input bit stop)`.)

Notes:

- **`address` takes the whole address byte**, R/W bit included. It is
  used for START and for repeated START alike: the bus state decides which.
  It is also used for each byte of a 10-bit header that software sequences:
  `11110 A9 A8 0`, then `A7..A0` with `write_byte`, then a repeated
  `address` with `11110 A9 A8 1` to read.
- **`read_byte`'s `nack`** is CR.ACK: 0 acknowledges the byte, 1 NACKs it
  (the last byte of a read). It is set on every read, because any CR write
  replaces it.
- **`stop`** on its own ends a write that the slave NACKed. A transfer
  usually ends with `stop = 1` on its last `write_byte` or `read_byte`.
- **Arbitration loss** ends the operation early: the core clears the
  command and sets AL and IF. The operation returns normally with `al` set;
  the caller decides what to do (wait for BUSY to clear, then restart).
- **`read_status`** is how a test observes BUSY between transfers.
- **Names:** `configure`/`shutdown` rather than `init`/`disable`. `disable`
  is a PSS keyword, and the skill warns against `init` as an identifier.

Composite operations (`write_bytes`, `read_bytes`, a register read with
repeated START) are built from these and add nothing to the comparison.

## Waiting

An operation is complete when SR.IF is 1 and SR.TIP is 0. IF is set by the
completion of every command, including STO alone, and by arbitration loss.
SR.TIP alone cannot be used: it stays 0 for a STO-only command. IF alone is
not enough either: R76 sets IF in the clock that clears the command bits,
and TIP (registered from them) falls one clock later, so a status read in
that clock sees IF = 1 with TIP = 1 (SR = 0x43 at the end of a byte). The
equivalence self-test found this (bench-plan E4): there the polling phase
shifts by one read and lands in that clock.

The wait is `completion_wait`: a loop over `completion_check` and
`wait_related_event` (fw-wb-dma's `wait_hint`). `wait_related_event`
returns when the device *may* have progressed, and the loop re-reads SR.
How it waits depends on the profile:

- **polling** (`HAS_EVENT_WAIT = false`): `yield`, so the loop polls SR.
- **interrupt** (`HAS_EVENT_WAIT = true`): wait on the `wake` channel,
  which the platform posts (`notify_irq`) on a rising edge of the
  interrupt line. The interrupt must be enabled (`configure` with
  `ien = 1`). With it disabled, the first wait never returns. There is no
  hidden fallback to polling: per the skill, an event path that isn't
  routed is an error, not a design case. A bench that wants polling uses
  a polling build.

Both profiles return the same outputs; only the number of SR reads
differs, and SR reads have no side effects in R76.

## Equivalence

The scoreboard `fw_i2c_op_eq` implements the generated API and runs each
operation on two designs, then compares the operation's name, inputs and
outputs ({doc}`bench-plan` §3.1). With the operations above, that
compares, per operation:

- SR at completion: RXACK, AL, BUSY, TIP (0), IF (1);
- for `read_byte`, the byte read;
- for `read_status`, SR between operations.

The bytes on the I2C bus, and the responder's view of them, are compared
separately and passively (bench-plan §3.2).

## Open points

- **The SR mask.** If a design difference that software cannot observe
  shows up in `sr` (for example BUSY at TLM, bench-plan P5), the
  allowed-differences table masks that field. The operation still returns
  all of them.
- **`shutdown` writes CTR = 0**, clearing IEN too. Nothing needs IEN
  without EN.
- **A polling build** (`HAVE_EVENT_WAIT=false`, a second
  `pss.op-model-sv-poll` task with its own package name) once a bench needs
  interrupt-free runs. `pss.check-nonblocking` already elaborates that
  profile.

## Files

| File | Contents |
|---|---|
| `src/pss/fw_i2c_types_pkg.pss` | `fw_i2c_sr_s`, `fw_i2c_check_s`, `fw_i2c_result_s` |
| `src/pss/fw_i2c_cfg_pkg.pss` | `HAS_EVENT_WAIT` from the injected `target_cfg_pkg` |
| `src/pss/fw_i2c_c.pss` | the component: register group, `wake` channel, `initialize(base)` |
| `src/pss/fw_i2c_c/functions/setup.pss` | `configure`, `shutdown` |
| `src/pss/fw_i2c_c/functions/byte_ops.pss` | `address`, `write_byte`, `read_byte`, `stop` and their `_start` halves |
| `src/pss/fw_i2c_c/functions/completion.pss` | `completion_check`, `completion_wait`, `read_status` |
| `src/pss/fw_i2c_c/functions/events.pss` | `wait_related_event`, `notify_irq` |
| `src/pss/flow.yaml` | `pss.src`, `pss.check`, `pss.check-nonblocking`, `pss.op-model-sv` |

The generated SystemVerilog (`pss.op-model-sv`) is the package
`fw_i2c_c_pkg`. Its API is the interface class `fw_i2c_c_ctxt_if`, and a
model is built with `fw_i2c_c_root #(IMP)::create(imp, base)`, where `imp`
implements `fw_i2c_c_imp_if` (`pss_mem_if`: `read32`/`write32` on the
register bus).
