# Results

## Simulation speed per view (bench-plan E10)

How long each common test and each random stream takes on each view of the
UVM bench (bench-plan §3.4): R76 alone (`ref`), the fw-i2c class model at
TLM (`tlm`), fw-i2c behind pins (`wb`), and each of them against R76
(`ref-eq`, `tlm-eq`, `wb-eq`).

**Setup.** Measured 2026-10-20 on a 32-CPU, 60 GB Linux host, with
Verilator 5.052 (`build: opt`, one simulation thread). Runs went through
`dfm run tests --tests "uvm-universal.,uvm-rand."` with `DFM_JOBS=2`, so
two simulations ran at a time on an otherwise idle machine. The images were
already built. A second run matched the first within 1%. The common tests
run for only 14–312 µs of simulated time and take 0.01–0.17 s, close to the
timer's resolution. The random streams (`rand-s1`…`s4`, bench-plan E9;
0.9–2.0 ms simulated) carry the comparison. Simulated time comes from each
test's `[RESULT]` line, because Verilator's own report rounds it.

Regenerate the tables after a test run:
`scripts/speed_report.py` (rewrites the block between the markers below).

<!-- speed-report:begin -->
Simulation wall time, seconds (`sim_walltime_s`: the simulator process alone; image build and dfm overhead not included).

| test | simulated (`ref`) | `ref` | `tlm` | `wb` | `ref-eq` | `tlm-eq` | `wb-eq` |
|---|---:|---:|---:|---:|---:|---:|---:|
| addr10 | 51 µs | 0.02 | 0.01 | 0.02 | 0.02 | 0.02 | 0.03 |
| irq | 20 µs | 0.01 | 0.01 | 0.01 | 0.01 | 0.01 | 0.01 |
| nack | 40 µs | 0.01 | 0.01 | 0.02 | 0.02 | 0.02 | 0.02 |
| prer | 263 µs | 0.08 | 0.06 | 0.10 | 0.10 | 0.09 | 0.14 |
| read | 72 µs | 0.02 | 0.02 | 0.03 | 0.03 | 0.03 | 0.04 |
| reg | 14 µs | 0.01 | 0.01 | 0.01 | 0.01 | 0.01 | 0.01 |
| smoke | 38 µs | 0.01 | 0.01 | 0.02 | 0.02 | 0.02 | 0.02 |
| stretch | 312 µs | 0.08 | 0.06 | 0.12 | 0.12 | 0.11 | 0.17 |
| write | 47 µs | 0.02 | 0.01 | 0.02 | 0.02 | 0.02 | 0.03 |
| rand-s1 | 1.66 ms | 0.61 | 0.38 | 0.81 | 0.75 | 0.61 | 1.00 |
| rand-s2 | 1.98 ms | 0.67 | 0.45 | 0.90 | 0.84 | 0.70 | 1.12 |
| rand-s3 | 897 µs | 0.34 | 0.21 | 0.47 | 0.42 | 0.34 | 0.57 |
| rand-s4 | 1.13 ms | 0.40 | 0.25 | 0.55 | 0.49 | 0.42 | 0.69 |
| **total** | | **2.27** | **1.48** | **3.08** | **2.85** | **2.39** | **3.86** |

Per image: total, relative to `ref`, simulation speed (simulated time per wall second) and peak memory.

| image | wall, s | × `ref` | simulated | sim speed | peak memory |
|---|---:|---:|---:|---:|---:|
| `ref` | 2.27 | 1.00 | 6.52 ms | 2.88 ms/s | 16 MB |
| `tlm` | 1.48 | 0.65 | 5.80 ms | 3.92 ms/s | 16 MB |
| `wb` | 3.08 | 1.36 | 6.60 ms | 2.14 ms/s | 16 MB |
| `ref-eq` | 2.85 | 1.26 | 6.55 ms | 2.30 ms/s | 16 MB |
| `tlm-eq` | 2.39 | 1.05 | 6.56 ms | 2.75 ms/s | 17 MB |
| `wb-eq` | 3.86 | 1.70 | 6.71 ms | 1.74 ms/s | 17 MB |
<!-- speed-report:end -->

**Observations.**

- **`tlm` is the fastest view**: 0.65 × `ref` in wall time, and 1.36 × `ref`
  in simulated time per second. It also simulates 11% less time, because
  the model finishes operations sooner: the PDF SCL formula (D10), and no
  input filter.
- **`wb` costs 1.36 × `ref`.** That is the class model plus the pin-level
  transactors, which are evaluated every clock: the WISHBONE target, the
  I2C controller, the two filters and the bus watcher. R76's RTL is cheaper
  to simulate than that stack.
- **The equivalence views add the R76 arm and the scoreboards.** `ref-eq`
  costs +0.58 s over `ref` on the same stream. `tlm-eq` costs +0.91 s over
  `tlm`, and `wb-eq` +0.78 s over `wb`. An equivalence run is 1.05–1.7 ×
  `ref`, far less than running both designs separately.
- **Memory is flat** at 16–17 MB per simulation on every view.
- **Image builds dominate a regression.** Each image takes about 7 s to
  verilate. With 8 cores (`DFM_CORES=8`) and two builds at a time, the six
  images are ready about 100 s after the start: about 47 s for the first
  pair, then 27 s for each further pair, presumably helped by ccache. The 78
  simulations measured here then take about 16 s of simulator time in
  total. Fewer images per run (`--views`) is therefore what shortens the
  development loop.
