#!/usr/bin/env python3
"""Speed report (bench-plan E10): simulation time per test x image.

Reads the sim_stats.json each Verilator UVM case writes into its rundir
(after `dfm run tests`) and writes Markdown tables between the markers in
docs/results.md:

    <!-- speed-report:begin -->  ...  <!-- speed-report:end -->

Usage: scripts/speed_report.py [--rundir rundir] [--out docs/results.md]
       (--out - prints the tables instead)
"""
import argparse
import glob
import json
import os
import re
import sys

IMAGES = ["ref", "tlm", "wb", "ref-eq", "tlm-eq", "wb-eq"]
MATRICES = ["uvm-universal", "uvm-rand"]
BEGIN, END = "<!-- speed-report:begin -->", "<!-- speed-report:end -->"


def load(rundir):
    """{(case, image): stats} for every case run of the matrices above."""
    res = {}
    for m in MATRICES:
        for f in glob.glob(os.path.join(rundir, "org.fwip.i2c.uvm.%s.*" % m, "sim_stats.json")):
            d = json.load(open(f))
            name = d["runinfo"]["case_name"]
            d["stats"]["simtime_s"] = exact_simtime(os.path.dirname(f), d["stats"]["simtime_s"])
            # Longest image name first: "ref-eq-smoke" is ref-eq, not ref.
            for img in sorted(IMAGES, key=len, reverse=True):
                if name.startswith(img + "-"):
                    res[(name[len(img) + 1:], img)] = d["stats"]
                    break
    return res


def exact_simtime(rundir, rounded):
    """The simulated time from the test's [RESULT] line (ps), since the
    stats and Verilator's own report round it (\"2ms\")."""
    t = None
    with open(os.path.join(rundir, "sim.log"), errors="replace") as fp:
        for line in fp:
            m = re.search(r"@ (\d+): uvm_test_top \[RESULT\]", line)
            if m:
                t = int(m.group(1)) * 1e-12
    if t is None or not (rounded / 2 <= t <= rounded * 2 or rounded == 0):
        return rounded
    return t


def fmt_s(v):
    return "%.2f" % v if v < 10 else "%.1f" % v


def fmt_simtime(s):
    if s >= 1e-3:
        return "%.2f ms" % (s * 1e3)
    return "%.0f µs" % (s * 1e6)


def tables(res):
    cases = sorted({c for c, _ in res}, key=lambda c: (c.startswith("rand"), c))
    imgs = [i for i in IMAGES if any(k[1] == i for k in res)]
    out = []

    out.append("Simulation wall time, seconds (`sim_walltime_s`: the simulator "
               "process alone; image build and dfm overhead not included).\n")
    out.append("| test | simulated (`ref`) | " + " | ".join("`%s`" % i for i in imgs) + " |")
    out.append("|---|---:|" + "---:|" * len(imgs))
    tot = {i: 0.0 for i in imgs}
    tot_sim = {i: 0.0 for i in imgs}
    for c in cases:
        row = []
        for i in imgs:
            st = res.get((c, i))
            if st is None:
                row.append("–")
                continue
            row.append(fmt_s(st["sim_walltime_s"]))
            tot[i] += st["sim_walltime_s"]
            tot_sim[i] += st["simtime_s"]
        simt = res.get((c, "ref")) or next(res[(c, i)] for i in imgs if (c, i) in res)
        out.append("| %s | %s | %s |" % (c, fmt_simtime(simt["simtime_s"]), " | ".join(row)))
    out.append("| **total** | | " + " | ".join("**%s**" % fmt_s(tot[i]) for i in imgs) + " |")
    out.append("")

    out.append("Per image: total, relative to `ref`, simulation speed (simulated "
               "time per wall second) and peak memory.\n")
    out.append("| image | wall, s | × `ref` | simulated | sim speed | peak memory |")
    out.append("|---|---:|---:|---:|---:|---:|")
    for i in imgs:
        rel = tot[i] / tot["ref"] if tot.get("ref") else 0.0
        speed = tot_sim[i] / tot[i] if tot[i] else 0.0
        mem = max(st["sim_mem_mb"] for (c, j), st in res.items() if j == i)
        out.append("| `%s` | %s | %.2f | %s | %s/s | %.0f MB |" % (
            i, fmt_s(tot[i]), rel, fmt_simtime(tot_sim[i]), fmt_simtime(speed), mem))
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--rundir", default="rundir")
    ap.add_argument("--out", default="docs/results.md")
    a = ap.parse_args()
    res = load(a.rundir)
    if not res:
        sys.exit("no sim_stats.json under %s; run `dfm run tests` first" % a.rundir)
    body = tables(res)
    if a.out == "-":
        sys.stdout.write(body)
        return
    text = open(a.out).read()
    if BEGIN not in text or END not in text:
        sys.exit("%s: markers %s ... %s not found" % (a.out, BEGIN, END))
    text = re.sub(re.escape(BEGIN) + ".*?" + re.escape(END),
                  lambda _: BEGIN + "\n" + body + END, text, flags=re.S)
    open(a.out, "w").write(text)
    print("%s: %d cases, %d images" % (a.out, len({c for c, _ in res}),
                                        len({i for _, i in res})))


if __name__ == "__main__":
    main()
