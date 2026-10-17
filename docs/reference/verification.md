# Verification status

## Upstream testbench

The repository's bench (`bench/verilog/tst_bench_top.v`,
`wb_master_model.v`, `i2c_slave_model.v`) runs under Icarus through
FuseSoC (`fusesoc run --target=sim i2c`) and in the repository's GitHub
CI. It is one directed test:

| Covered | Not covered |
|---|---|
| PRER write and read-back (0x00C8) | Interrupts (`IEN`, `wb_inta_o`, IACK) |
| Single master, one behavioral slave at 7'h10 | Multi-master: clock synchronization, arbitration, AL |
| START + address write; 3 data writes; STOP | Clock stretching by the slave |
| Repeated START, 4 reads (3 ACK, final NACK) | 10-bit addressing |
| Address NACK on an invalid address, then STOP | **Slave mode (no test at all)** |
| Polling of `SR.TIP` | Debug registers, SLADR, `CTR` reserved bits |
| | PRER corner values (0, 1, large), SCL frequency |
| | Bus timing checks (the slave model has only a small hold assumption) |
| | Reset in mid-transfer, clearing EN in mid-transfer |

It checks data by comparing RXR with the expected value. It has no
protocol monitor and no coverage collection.

## Planned confirmation tests (fw-i2c bench)

The `fw-i2c` back-to-back bench (see {doc}`../design/index`) runs the
freecores core as a DUT next to `fwvip-i2c` agents and checks the
statements marked **(to confirm)** in this specification. One directed
test per suspected defect:

| Test | Confirms | Method |
|---|---|---|
| `ref_cr_race` | D1 | Write TXR in the clock where `done` pulses (use a hierarchical probe to time it); count bytes on the bus with the monitor. |
| `ref_start_glitch` | D2 | Monitor SDA at `wb_clk_i` resolution during START; check for a release while SCL is high. Run at 2 `wb_clk_i` rates. |
| `ref_slv_mode` | D3, D4 | Address the core as a slave from the VIP controller; read SR, RXR around SL_CONT. |
| `ref_slv_abort` | D5 | VIP controller sends STOP in the middle of a byte to the slave, then a new transfer. |
| `ref_en_midbyte` | D6 | Clear EN in the middle of a byte; measure bit timing. |
| `ref_prer0` | D7 | PRER = 0, one byte write; count bits. |
| `ref_timing` | D8, D10 | Monitor-measured tSU;STA, tVD;DAT and SCL period at nominal Sm/Fm PRER. |
| `ref_arb` | D9 | Two controllers (core + VIP) with identical then diverging address bytes, and a START collision. |
