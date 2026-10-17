# Verification status

## Upstream testbench

The repository's bench at R76 (`bench/verilog/tst_bench_top.v`,
`wb_master_model.v`, `i2c_slave_model.v`) is one directed test. At this
revision it comes with an NC-Verilog script (`sim/i2c_verilog/run/run`);
the FuseSoC target and CI were added in later freecores commits.

The bench instantiates two cores on one bus (`i2c_top` and `i2c_top2`,
selected by `adr[3]`), but every access uses a 3-bit address, so the
second core is never addressed and stays disabled. Both drive one `ack`
wire. Under Icarus that makes the bench fail (register reads return
`ff`), so the `fw-r76` patch set backports upstream's fix (ORing the two
acks); with it the bench passes with 0 errors ({doc}`integration`).

| Covered | Not covered |
|---|---|
| PRER write and read-back (0x00C8) | Interrupts (`IEN`, `wb_inta_o`, IACK) |
| Single master, one behavioral slave at 7'h10 | Multi-master: clock synchronization, arbitration, AL (the second core is idle) |
| START + address write; 3 data writes; STOP | Clock stretching by the slave |
| Repeated START, 4 reads (3 ACK, final NACK) | 10-bit addressing |
| Address NACK on an invalid address, then STOP | Debug registers, `CTR` reserved bits |
| Polling of `SR.TIP` | PRER corner values (0, 1, large), SCL frequency |
| | Bus timing checks (the slave model has only a small hold assumption) |
| | Reset in mid-transfer, clearing EN in mid-transfer |

It checks data by comparing RXR with the expected value. It has no
protocol monitor and no coverage collection.

## fw-i2c tests of the reference

| Case | Status | What |
|---|---|---|
| `ref-smoke` | **passing** | A write, a repeated-START read back, an address NACK, BUSY after STOP |
| `ref-reg` | **passing** | Register map: reset values, stride, zero-extended reads, writes take bits [7:0] and need `sel[0]`, `adr[1:0]` ignored, TXR/CR readbacks, reserved word, CR ignored while EN = 0, IACK and CR bits 2:1 self-clear, CR.ACK holds |
| `ref-write` | **passing** | Multi-byte, single-byte and pointer-only writes |
| `ref-read` | **passing** | Repeated-START reads, a current-address read, a 1-byte read |
| `ref-nack` | **passing** | Unanswered write and read addresses; a data byte NACKed by the target; STOP on its own |
| `ref-irq` | **passing** | Polled operations with IEN = 0 (line stays low); IEN with IF pending; IACK alone; clearing IEN; interrupt-driven operations |
| `ref-prer` | **passing** | PRER 2, 4, 9, 24: same data and bus events; transfer time grows with PRER (ratios 1.63, 2.87, 6.92 against PRER+1 ratios 1.67, 3.33, 8.33) |
| `ref-stretch` | **passing** | Responder latency on every decision: same data and bus events, each decision adds its latency |
| `ref-addr10` | **passing** | 10-bit write and repeated-START read sequenced by software; NACK on either header byte |

These are the common tests of the fw-i2c bench ({doc}`../design/bench-plan`
E2), run on the `ref` view (`tests/uvm/`). They replaced the directed test
`ref_wb32` (`tests/ref/`).

The same tests also run on `ref-eq`, the equivalence self-test
({doc}`../design/bench-plan` E4): two R76 arms under the equivalence
scoreboards, one standing in for the design under test.

| Case | Status | What |
|---|---|---|
| `ref-eq-<case>` (all 9) | **passing** | Identical arms: no operation, bus, register or interrupt difference |
| `ref-eq-<case>-x2` (all 9) | **passing** | R76 at PRER' = 2(PRER+1) − 1: still no difference; the timing report shows R76/DUT 1.8–2.4 |
| `ref-eq-sabotage` | **passing** | The mirror inverts R76's ACK of one data byte; both scoreboards report it (the test expects exactly that) |

## Reference confirmation tests

{doc}`../design/bench-plan` E3: one directed test per suspected defect, on
the `ref` view only (`uvm-ref-only` in `tests/uvm/flow.yaml`). The `ref`
top publishes a probe (`i2c_ref_probe`): R76's `done`, accepted WISHBONE
writes and AL each clock, the bus line timing (`i2c_line_timing`, against
UM10204 Table 10), and a second master on the bus (the kit's controller
transactor, idle unless a test drives it). Each test asserts the behaviour
recorded in {doc}`deviations`, so it fails if R76 does anything else.

| Case | Confirms | Method | Status |
|---|---|---|---|
| `ref-cr-race` | D1 | TXR writes swept across the end of a byte; the probe says which landed in the `done` clock; count bytes on the bus | **passing** |
| `ref-en-midbyte` | D6 | Clear EN after the third SCL rise of a byte at PRER 24; measure SCL; read SR | **passing** |
| `ref-prer1`, `ref-prer0` | D7 | One write with STOP at PRER 1 and 0, each command polled; SR, bus events, `done` pulses | **passing** |
| `ref-timing-sm`, `ref-timing-fm` | D8, D10 | Line timing over a write and a repeated-START read at PRER 199 and 49 | **passing** |
| `ref-arb` | D9 | R76 and the kit controller start together with the same address, then diverge either way, then R76's STOP against the other master's 0 bit | **passing** |

The results are in the status column of {doc}`deviations`.
