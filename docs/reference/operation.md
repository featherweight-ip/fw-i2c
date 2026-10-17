# Operation (master)

## Enabling the core

1. Write PRERlo and PRERhi while `CTR.EN` is 0. See {doc}`timing` for the
   value to use.
2. Write `CTR.EN = 1`, and set `CTR.IEN` if you want interrupts.
3. Issue commands through CR.

CR writes are ignored while EN is 0. Clear EN only when no command is in
progress, i.e. after a command that included STO has completed. If EN is
cleared in the middle of a byte, the command bits stay set and the bit
controller keeps running with its clock enable on every clock: the byte
finishes at `wb_clk_i` speed and the bus may be left hung.

## Commands

A command is one CR write. The byte controller checks the bits in this
order: STA, then RD, then WR, then STO. It starts only when at least
one of RD, WR or STO is set.

| CR bits set | Hex (ACK = 0) | Bus sequence | Completion (`done`) |
|---|---|---|---|
| STA + WR | 0x90 | START, 8 bits of TXR, receive ACK | after the ACK bit |
| WR | 0x10 | 8 bits of TXR, receive ACK | after the ACK bit |
| WR + STO | 0x50 | 8 bits, receive ACK, STOP | after the STOP |
| STA + WR + STO | 0xD0 | START, 8 bits, receive ACK, STOP | after the STOP |
| RD (+ ACK) | 0x20 / 0x28 | 8 bits into RXR, send ACK (ACK=0) or NACK (ACK=1) | after the ACK bit |
| RD + STO (+ ACK) | 0x60 / 0x68 | 8 bits, send ACK/NACK, STOP | after the STOP |
| STA + RD | 0xA0 | START, 8 bits read, send ACK/NACK | after the ACK bit |
| STO | 0x40 | STOP | after the STOP |
| STA + STO | 0xC0 | **START, 8 bits of TXR, receive ACK, STOP** | after the STOP |
| STA | 0x80 | **nothing**: STA stays pending | never |
| RD + WR | 0x30 | treated as RD | after the ACK bit |

The last three rows are behaviours the PDF does not describe:

- **STA alone** does nothing on the bus. The STA bit stays set (it is
  visible in CR_DBG) until the next CR write. While it is set it also
  holds `SR.AL` clear.
- **STA + STO** is not a bare START followed by STOP. The START branch
  always moves on to a byte transfer, so the core writes TXR as well.
- **RD + WR**: RD takes priority.

While a command is in progress, `SR.TIP` is 1 for RD and WR commands and
0 for STO-only commands. When the command completes, the byte controller
pulses `done`. One clock later: STA, STO, RD and WR clear, TIP falls, IF
rises and RXACK is updated.

### Address bytes and 10-bit addressing

The core gives address bytes no special treatment. Software writes the
address and R/W bit to TXR and issues STA + WR. For a 10-bit address:

1. Write `11110 a9 a8 0` with STA + WR.
2. Write `a7..a0` with WR.
3. To read, issue a repeated START with `11110 a9 a8 1` (STA + WR), then
   RD commands.

### RXACK after a read

`SR.RXACK` is the bit on SDA in the last ACK slot. After a read command
that is the ACK/NACK the core itself sent, not anything from the slave.

### Ending a read

The last byte read should be NACKed: RD + ACK(=1) + STO (0x68). Any CR
write replaces the ACK bit, so set it on every RD command.

## Interrupts and status

`SR.IF` is set by:

- the completion of any command (`done`)
- arbitration loss

IF is cleared only by writing CR with IACK = 1 (EN must be 1). A command
can be issued and IF acknowledged in the same CR write. `wb_inta_o` is
`IF & IEN`, registered.

`SR.BUSY` comes from the bus, not from this core's state. It is set by
any START and cleared by any STOP, so a bus that is left with no STOP
(another master reset, a glitch) stays BUSY until reset.

## Multi-master behaviour

### Clock synchronization

When the core releases SCL and another device holds it low, the bit
controller stops its divider (`slave_wait`) until the filtered SCL reads
high. When the core is releasing SCL and SCL falls (another master drove
it low), the divider reloads and the bit FSM advances at once
(`scl_sync`). The core's SCL high time therefore ends at the first falling
edge from any master, and its low time is at least its own low count:
this is the standard wired-AND clock synchronization.

### Arbitration

The core reports arbitration lost (`SR.AL`, with IF) in two cases:

1. **SDA mismatch.** During the second half of SCL high in a transmitted
   bit (`wr_c` to `wr_d`), the core releases SDA but samples it low.
   Transmitted bits are address bits, data bits, and a NACK the core sends
   when reading.
2. **Unexpected STOP.** A STOP condition is seen while the bit FSM is
   executing a command other than STOP. A STOP seen while the core is
   idle is ignored.

Arbitration is **not** checked:

- while the core sends a START or repeated START (so two masters that
  START at the same time both continue, as I2C intends; but a START
  collision with a master already in a data phase is not detected)
- while sending a STOP
- while receiving bits
- while sending an ACK of 0 (the core is driving SDA)

When arbitration is lost, the byte and bit FSMs return to idle and
release both lines. The current command is abandoned: the command bits
clear and no `done` is generated. Software must check AL, wait for
`SR.BUSY` to fall, and start again with STA. A CR write with STA clears
AL.
