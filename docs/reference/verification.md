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
| `ref_wb32` | **passing** | The core behind the 32-bit shim, against a `fw-proto-i2c` target: register map, `sel[0]`, a write and repeated-START read, address NACK, IF/IACK ({doc}`integration`) |

## Planned confirmation tests (fw-i2c bench)

The `fw-i2c` back-to-back bench (see {doc}`../design/index`) runs this
core as a DUT next to `fwvip-i2c` agents and checks the statements marked
**(to confirm)** and the defects in {doc}`deviations`. One directed test
per defect:

| Test | Confirms | Method |
|---|---|---|
| `ref_cr_race` | D1 | Write TXR in the clock where `done` pulses (use a hierarchical probe to time it); count bytes on the bus with the monitor. |
| `ref_en_midbyte` | D6 | Clear EN in the middle of a byte; measure bit timing. |
| `ref_prer0` | D7 | PRER = 0, one byte write; count bits and STOPs. (PRER = 1 is already shown failing by `ref_wb32 +PRER=1`.) |
| `ref_timing` | D8, D10 | Monitor-measured tSU;STA, tVD;DAT and SCL period at nominal Sm/Fm PRER. |
| `ref_arb` | D9 | Two controllers (core + VIP) with identical then diverging address bytes, and a START collision. |
