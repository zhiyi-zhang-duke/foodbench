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

## Open-model lineup (local, GPU 0 only)

| Model | Ollama tag | Size | Role |
|---|---|---|---|
| Gemma 4 31B | `gemma4:31b` | 20 GB | pilot generator + judge |
| Qwen3.8 27B | `qwen3.8:27b` | 18 GB | generator |
| gpt-oss 20B | `gpt-oss:20b` | 14 GB | generator |
| DeepSeek-R1 32B (Qwen 2.5 distill) | `deepseek-r1:32b` | 20 GB | generator; reasoning-trained contrast |

Run one model at a time; Ollama unloads the previous one. Never point Ollama at GPU 1 (the display card); it blue-screens under sustained inference.

```powershell
$env:OLLAMA_BASE_URL="http://127.0.0.1:11600/v1"
.\.venv\Scripts\inspect.exe eval tasks/pilot.py --model ollama/qwen3.8:27b --model-role judge=ollama/gemma4:31b --max-connections 1 --log-dir logs/qwen-pilot
```

Note: using Gemma as judge for a Qwen run means Ollama swaps models between every generate and judge call. For a 12-case pilot that is acceptable; for the full run, generate all recipes first with one model, then judge in a second pass.
