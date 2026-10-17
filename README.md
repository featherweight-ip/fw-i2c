# fw-i2c

I2C controller IP written with fw-hdl, verified back-to-back against the
freecores (OpenCores) `i2c` core, lowered to Verilog and compared with it
for area.

- `docs/reference/` — specification of what the freecores `i2c` core
  actually provides (from the RTL), including suspected defects.
- `docs/design/` — the fw-i2c design (draft) and the plan/status.
- `src/rdl/` — SystemRDL register maps.
- `scripts/synth-baseline.sh` — Yosys area baseline for a freecores commit.

Build the docs:

```
ivpm update            # fetch deps into packages/ (incl. freecores i2c)
dfm run docs           # or: sphinx-build -W -b html docs docs/_build/html
```
