#!/bin/bash
# Synthesize the freecores i2c core at a given commit and print cell
# statistics: a generic gate mapping, and the iCEBreaker target
# (iCE40UP5K-SG48) with nextpnr place-and-route at 12 MHz.
#
# Usage: scripts/synth-baseline.sh <i2c-repo> <commit> [outdir]
#   e.g. scripts/synth-baseline.sh packages/i2c dba90b2   # R76, master-only
#        scripts/synth-baseline.sh packages/i2c 3b067f0   # HEAD, master + slave
#
# This is a stopgap until the dfm synthesis flow exists (docs/design/plan.md).
set -euo pipefail
repo=$1; rev=$2; out=${3:-rundir/synth-baseline/$rev}
YOSYS=${YOSYS:-yosys}
NEXTPNR=${NEXTPNR:-nextpnr-ice40}
mkdir -p "$out/src"
git -C "$repo" archive "$rev" rtl/verilog | tar -x -C "$out/src"
d=$out/src/rtl/verilog
read="read_verilog -I$d $d/i2c_master_bit_ctrl.v $d/i2c_master_byte_ctrl.v $d/i2c_master_top.v"
$YOSYS -q -l "$out/generic.log" -p "$read; synth -top i2c_master_top -flatten; \
  abc -g AND,NAND,OR,NOR,XOR,XNOR,MUX; opt_clean; tee -o $out/generic.stat stat"
$YOSYS -q -l "$out/ice40.log" -p "$read; synth_ice40 -device u -top i2c_master_top \
  -json $out/ice40.json; tee -o $out/ice40.stat stat"
$NEXTPNR --up5k --package sg48 --freq 12 --pcf-allow-unconstrained \
  --json "$out/ice40.json" --asc "$out/ice40.asc" > "$out/pnr.log" 2>&1
# Summarize a stat report. Handles both the older "name count" and the
# newer (Yosys >= 0.6x) "count name" cell lines.
summarize() {
  awk '
    NF == 2 && $1 ~ /^[0-9]+$/ && $2 ~ /^(\$_|SB_)/ { n = $2; c = $1 }
    NF == 2 && $2 ~ /^[0-9]+$/ && $1 ~ /^(\$_|SB_)/ { n = $1; c = $2 }
    NF == 2 && (n != "") {
      if (n ~ /DFF/) ff += c; else logic += c
      if (n == "SB_LUT4") lut += c
      if (n == "SB_CARRY") carry += c
      n = ""
    }
    END {
      printf "flops %d  logic %d", ff, logic
      if (lut) printf "  SB_LUT4 %d  SB_CARRY %d", lut, carry
      printf "\n"
    }' "$1"
}
for t in generic ice40; do
  echo "== $rev $t: $(summarize "$out/$t.stat")"
done
echo "== $rev up5k place-and-route"
grep -E 'ICESTORM_LC:' "$out/pnr.log" | tail -1
grep -E 'Max frequency' "$out/pnr.log" | tail -1
