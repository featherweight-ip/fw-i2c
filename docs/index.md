# fw-i2c — I2C Controller IP

`fw-i2c` is an I2C controller written with fw-hdl (Featherweight Hardware
Description Library), lowered to Verilog RTL, verified back-to-back
against the freecores (OpenCores) `i2c` core, and compared with that core
for area and timing.

```{admonition} Status
:class: note
Reference specification written. Design document in draft, for review.
No fw-hdl source yet. See {doc}`design/plan`.
```

## Where to start

- {doc}`reference/index` — what the freecores `i2c` core actually
  provides, written from the RTL rather than the 2003 PDF. This is the
  behavioral and register reference that `fw-i2c` is aligned with and
  tested against.
- {doc}`design/index` — the `fw-i2c` design: architecture, registers,
  verification, lowering and the size comparison. Includes open issues.
- {doc}`design/plan` — step plan and status.

```{toctree}
:maxdepth: 2
:caption: Reference
:hidden:

reference/index
```

```{toctree}
:maxdepth: 2
:caption: fw-i2c
:hidden:

design/index
design/plan
```
