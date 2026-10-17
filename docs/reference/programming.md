# Programming

The C header `software/include/oc_i2c_master.h` in the core's repository
defines the register offsets and the control, command and status bits.
It has no definitions for the debug registers at 0x5 and 0x6, and its
`OC_BITCLEAR` macro is wrong: `(reg)|(~(bitmask))` should be
`(reg)&(~(bitmask))`.

The examples below poll `SR.TIP`. With interrupts, wait for IF and write
IACK together with the next command.

## Setup

```c
wr(PRERlo, prer & 0xff);
wr(PRERhi, prer >> 8);
wr(CTR, EN);               // | IEN
```

## Write bytes to a slave register

```c
wr(TXR, (sadr << 1) | 0);  wr(CR, STA | WR);  wait_tip();  check(!(rd(SR) & RXACK));
wr(TXR, reg);              wr(CR, WR);        wait_tip();  check(!(rd(SR) & RXACK));
wr(TXR, data);             wr(CR, WR | STO);  wait_tip();  check(!(rd(SR) & RXACK));
```

Do not write TXR for the next byte while a byte is in progress: see D1 in
{doc}`deviations`.

## Read bytes using a repeated START

```c
wr(TXR, (sadr << 1) | 0);  wr(CR, STA | WR);       wait_tip();
wr(TXR, reg);              wr(CR, WR);             wait_tip();
wr(TXR, (sadr << 1) | 1);  wr(CR, STA | WR);       wait_tip();   // repeated START
wr(CR, RD);                wait_tip();  b0 = rd(RXR);             // ACK
wr(CR, RD | ACK | STO);    wait_tip();  b1 = rd(RXR);             // NACK, STOP
```

## After each byte

| Check | Meaning | Action |
|---|---|---|
| `SR.AL` | arbitration lost | stop; wait for `!SR.BUSY`; restart from STA |
| `SR.RXACK` after a write | slave NACK | issue STO (0x40) |
