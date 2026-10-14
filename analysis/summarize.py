"""Summarize FoodBench .eval logs into a cases x dimensions x models table.

  python analysis/summarize.py logs/
"""

import sys
from pathlib import Path

import pandas as pd
from inspect_ai.log import list_eval_logs, read_eval_log

DIMS = ["constraint", "ingredient", "technique", "quantity", "safety", "scaling", "feasibility", "flavor"]


def rows_from_log(path: str):
    log = read_eval_log(path)
    model = log.eval.model
    for s in log.samples or []:
        sc = (s.scores or {}).get("property_judge")
        if not sc:
            continue
        row = {"model": model, "case": s.id, "epoch": s.epoch, "use_case": s.metadata.get("use_case")}
        for d in DIMS:
            row[d] = sc.value.get(d) if isinstance(sc.value, dict) else None
        yield row
        for v in sc.metadata.get("verdicts", []):
            yield {"model": model, "case": s.id, "epoch": s.epoch, "_verdict": True, **{k: v[k] for k in ("id", "dimension", "severity", "verdict", "evidence")}}


def main(log_dir: str):
    rows = [r for p in list_eval_logs(log_dir) for r in rows_from_log(p.name)]
    df = pd.DataFrame(rows)
    scores = df[df.get("_verdict").isna()] if "_verdict" in df else df
    verdicts = df[df.get("_verdict").notna()] if "_verdict" in df else pd.DataFrame()
    pd.set_option("display.width", 200)
    print("\n== Per-dimension mean by model (N/A skipped)")
    print(scores.groupby("model")[DIMS].mean(numeric_only=True).round(2).T)  # NaN = N/A, excluded from mean
    print("\n== Per-case scores")
    print(scores.set_index(["model", "case", "epoch"])[DIMS].round(2))
    if not verdicts.empty:
        print("\n== Failed properties")
        f = verdicts[verdicts.verdict == "fail"][["model", "case", "id", "severity", "evidence"]]
        print(f.to_string(index=False, max_colwidth=80))
    out = Path(log_dir) / "summary.csv"
    scores.to_csv(out, index=False)
    print(f"\nwrote {out}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "logs/")
