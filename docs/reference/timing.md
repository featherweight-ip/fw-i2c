# Bit timing

## Prescaler and ticks

The bit controller has a 16-bit down counter that reloads from PRER. Each
reload produces one clock enable, called a *tick*. With no stretching, a
tick occurs every PRER+1 cycles of `wb_clk_i`. The counter also reloads,
and produces a tick at once, when:

- `wb_rst_i` is high
- `CTR.EN` is 0 (so the bit FSM ticks on every clock while the core is
  disabled)
- another master pulls SCL low while this core is releasing it (`scl_sync`)

The counter **holds** (no ticks) from the clock after the core releases
SCL until the filtered SCL input reads high (`slave_wait`). This is how
the core honours clock stretching. It applies on every release, not only
when a slave stretches.

A data or ACK bit takes 5 ticks, so the nominal setting is:

```
PRER = f(wb_clk_i) / (5 * f(SCL)) - 1
```

This is the PDF formula. (The comment `// 4x SCL` on `clk_cnt` in the
byte controller is wrong.) Example: 32 MHz and 100 kHz give PRER = 63.

### Effective SCL frequency

Because the counter holds after every release, each bit lasts 5 ticks
plus *L*. *L* is the time for SCL to rise, pass the two-flop synchronizer
and pass the glitch filter:

```
T(SCL) ≈ 5·(PRER+1)·T(clk) + L
L ≈ t_rise + (3 + 2·(floor(PRER/4)+1))·T(clk)        (≈ PRER/2 + 5 clocks)
```

For large PRER this makes SCL about 10% slower than nominal, for example
about 91 kHz when programmed for 100 kHz **(to confirm)**. Software that
needs a true 100 kHz or 400 kHz must program a smaller PRER.

### Minimum PRER

PRER must be at least 2:

- **PRER = 0:** the bit FSM's idle tick falls on the clock straight after
  `cmd_ack`, before the byte controller has changed the command, so the
  previous bit command runs again.
- **PRER = 1:** a tick is 2 clocks, which is shorter than the input sync
  and filter latency. The arbitration check sees SDA from the previous
  bit, and the core reports arbitration lost against a single slave.
  This is confirmed in simulation.

See D7 in {doc}`deviations`.

## Input filter

`scl_pad_i` and `sda_pad_i` each go through:

1. a two-flop synchronizer
2. a 3-bit shift register, sampled once every `floor(PRER/4)+1` clocks
   (on every clock when PRER < 4 or EN is 0)
3. a 2-of-3 majority vote, registered

Pulses shorter than about one sample period are rejected. That is about
1/20 of an SCL period at the nominal setting, compared with the 50 ns
spike-suppression requirement of Fast-mode. The filter latency is part of
*L* above.

## Bit-level sequences

Each command runs as a sequence of bit-FSM states, one state per tick.
The first tick is the idle tick, at which the FSM samples the command.
Each column shows the core's own outputs (1 = released) after the tick
taken in the named state; x means unchanged from the previous command. `cmd_ack` is high for one clock after the last tick.

### START / repeated START (6 ticks)

```{wavedrom}
{ "signal": [
  { "name": "tick",  "wave": "p.....", "node": "" },
  { "name": "state", "wave": "======", "data": ["idle", "start_a", "start_b", "start_c", "start_d", "start_e"] },
  { "name": "scl",   "wave": "x.1..0" },
  { "name": "sda",   "wave": "x1.0.." },
  { "name": "cmd_ack", "wave": "0....1" }
],
  "head": { "text": "START: SDA released, SCL released, SDA falls, SCL falls" },
  "foot": { "text": "For a repeated START, SCL is low at idle and start_a; SDA is released while SCL is low." }
}
```

### Data bit, transmit (5 ticks)

```{wavedrom}
{ "signal": [
  { "name": "tick",  "wave": "p...." },
  { "name": "state", "wave": "=====", "data": ["idle", "wr_a", "wr_b", "wr_c", "wr_d"] },
  { "name": "scl",   "wave": "0.1.0" },
  { "name": "sda",   "wave": "x=...", "data": ["din"] },
  { "name": "sda_chk", "wave": "0..10" }
],
  "head": { "text": "WRITE bit: SDA set at wr_a, SCL high wr_b..wr_d, arbitration checked in wr_d" }
}
```

A READ bit has the same SCL shape, with SDA released. The received bit is
taken at the first rising edge of the filtered SCL.

### STOP (5 ticks)

```{wavedrom}
{ "signal": [
  { "name": "tick",  "wave": "p...." },
  { "name": "state", "wave": "=====", "data": ["idle", "stop_a", "stop_b", "stop_c", "stop_d"] },
  { "name": "scl",   "wave": "x01.." },
  { "name": "sda",   "wave": "x0..1" },
  { "name": "cmd_ack", "wave": "0...1" }
],
  "head": { "text": "STOP: SDA driven low, SCL released, SDA released" }
}
```

## I2C timing parameters

In ticks, with *L* as above. The Sm and Fm columns use the nominal
PRER for 100 kHz and 400 kHz (one tick is 2 µs and 0.5 µs) and ignore
*L*, except where it is added explicitly. The limits are from UM10204.

| Parameter | Core (ticks) | At 100 kHz | Sm limit | At 400 kHz | Fm limit |
|---|---|---|---|---|---|
| tLOW | 3 | 6 µs | ≥ 4.7 µs | 1.5 µs | ≥ 1.3 µs |
| tHIGH | 2 + L | ≥ 4 µs | ≥ 4.0 µs | ≥ 1 µs | ≥ 0.6 µs |
| tHD;STA | 2 | 4 µs | ≥ 4.0 µs | 1 µs | ≥ 0.6 µs |
| tSU;STA (repeated START) | 1 + L | ≈ 3 µs | **≥ 4.7 µs** | ≈ 0.75 µs | ≥ 0.6 µs |
| tSU;STO | 2 + L | ≥ 4 µs | ≥ 4.0 µs | ≥ 1 µs | ≥ 0.6 µs |
| tBUF (STOP to next START) | ≥ 4 | ≥ 8 µs | ≥ 4.7 µs | ≥ 2 µs | ≥ 1.3 µs |
| tSU;DAT | 1 | 2 µs | ≥ 250 ns | 0.5 µs | ≥ 100 ns |
| tVD;DAT (SCL low to data valid) | 2 | 4 µs | **≤ 3.45 µs** | 1 µs | **≤ 0.9 µs** |

The two bold entries suggest that the core, used at the nominal setting,
violates Standard-mode repeated-START setup time and the data-valid time
in both modes **(to confirm)**. Neither matters to a typical slave (data
still meets setup before SCL rises), but a protocol-checking monitor will
flag them. They are also the values `fw-i2c` must decide whether to match
or fix; see {doc}`../design/index`.
