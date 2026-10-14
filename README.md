# FoodBench

A benchmark for whether LLMs produce technically correct recipes under constraints. Property-based scoring: each case lists checkable properties tagged with a scoring dimension and severity; an LLM judge grades each one pass / fail / N/A; scores aggregate per dimension.

Design doc and principle bank live in the WanShiTong vault under `05 - Projects/AI & LLMs/AI & Tech Projects/Active Projects/FoodBench/`.

## Layout

```
cases/      JSONL, one case per line with its properties
tasks/      Inspect task files (pilot.py)
prompts/    system prompt for the model under test, judge template
scorer.py   property_judge scorer
analysis/   summarize.py reads .eval logs into a table
logs/       Inspect logs (gitignored)
```

## Setup (PowerShell)

```powershell
.\.venv\Scripts\Activate.ps1
```

## Smoke test, no model needed

```powershell
inspect eval tasks/pilot.py --model mockllm/model --log-dir logs/smoke
```

## Run against local Ollama (GPU 0, port 11600)

```powershell
inspect eval tasks/pilot.py --model ollama/gemma4:31b -M base_url=http://127.0.0.1:11600/v1 --model-role judge=ollama/gemma4:31b --epochs 1 --log-dir logs/
```

Then:

```powershell
inspect view --log-dir logs/
python analysis/summarize.py logs/
```

## Scoring

- dimension score = weighted fraction of applicable properties passed (critical 3, major 2, minor 1)
- a failed critical property zeroes its dimension
- dimensions with no applicable property report N/A, not 0
- the judge should be a different, stronger model than the one under test for real runs; the pilot uses the same local model for both to shake out the harness
