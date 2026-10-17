# Slave mode

Slave mode was added in 2013 (commit `4ed851d`, H. Baier). The PDF does
not describe it, and neither the VHDL version nor the upstream testbench
covers it. This page describes what the Verilog RTL implements. Treat all
of it as **(to confirm)** until the bench in {doc}`verification` exercises
it.

## What it supports

- One 7-bit address, set in SLADR. The compare is exact: no mask, no
  second address.
- Slave receive (master writes) and slave transmit (master reads),
  byte by byte under software control.
- SCL is held low between bytes until software writes `CR.SL_CONT`.
- The core always ACKs received bytes. `CR.ACK` has no effect in slave
  mode, so the core cannot NACK a write.
- In slave transmit, a NACK from the master ends the transfer.

It does not support:

- 10-bit slave addresses
- the general call address (0x00) or START byte
- stretching SCL between the address and its ACK, or within a byte. It
  relies on software reaching the byte boundary before the master's next
  edge, which holds only because SCL is already held low there.

## Software sequence

1. Write SLADR, then set `CTR.EN` and `CTR.SLV_EN` (and IEN).
2. Wait for IF. After the address ACK, the core holds SCL low and sets:
   - `SR.SLV_DAT_AVAIL` if the master is writing (R/W = 0), or
   - `SR.SLV_DAT_REQ` if the master is reading (R/W = 1).
3. Master writing: read RXR, then write `CR.SL_CONT`. After 8 bits the
   core ACKs, holds SCL and sets SLV_DAT_AVAIL again.
4. Master reading: write the byte to TXR, then write `CR.SL_CONT`. After
   8 bits the core samples the master's ACK into `SR.RXACK`. On ACK it
   holds SCL and sets SLV_DAT_REQ again. On NACK it returns to idle.
5. A STOP or a repeated START ends the transfer.

SLV_DAT_AVAIL and SLV_DAT_REQ are levels: they stay set, and keep IF set,
until SL_CONT is written. Writing IACK alone does not clear IF in this
state.

```{mermaid}
stateDiagram-v2
  [*] --> IDLE
  IDLE --> SL_ACK: START + address == SLADR,\nSLV_EN = 1
  SL_ACK --> SL_WAIT: ACK slot done, ACK\n(set DAT_AVAIL or DAT_REQ)
  SL_ACK --> IDLE: master NACK
  SL_WAIT --> SL_PRELOAD: CR.SL_CONT\n(TXR → shift register)
  SL_PRELOAD --> SL_RD: R/W = 1 (master reads)
  SL_PRELOAD --> SL_WR: R/W = 0 (master writes)
  SL_RD --> SL_ACK: 8 bits sent
  SL_WR --> SL_ACK: 8 bits received
  note right of SL_WAIT: SCL held low
```

All states return to IDLE on reset, on arbitration loss, and on any START
or STOP condition (`slave_reset`).

## Observations from the RTL

- **SR.SLV_MODE is always 0.** It is loaded from `slave_act` only when a
  master command completes (`done`), and `slave_act` is 0 whenever a
  master command is running. Software cannot use it to tell slave
  activity from master activity.
- **SL_CONT overwrites RXR.** SL_CONT loads TXR into the shift register,
  which is also RXR. In slave receive, read RXR before writing SL_CONT.
- **RXR holds the address after addressing.** After the address phase,
  RXR holds `{address, 0}`. The R/W bit position reads 0, whatever the
  master sent.
- **Address snooping.** The bit controller shifts in the first byte after
  every START, including the core's own START as a master. The byte
  controller compares it only while it is idle, so the core does not
  answer its own address in normal use **(to confirm for a master that
  addresses SLADR)**.
- **Master commands are blocked while the slave is active.** The byte
  controller ignores RD, WR and STO while `slave_act` is 1. They stay
  pending in CR and run after the slave transfer.
- **No STOP reset of the slave bit FSM.** The slave bit FSM is reset by
  START but not STOP. After an aborted transfer it can wait in a receive
  or transmit state until the next START.
- **SDA can stay low.** If a master stops clocking while the slave is
  driving SDA low, the bus hangs; there is no timeout.
