"""FoodBench pilot task: 12 cases across use cases 1, 4, 5, 6.

Run (from the repo root, venv active):

  inspect eval tasks/pilot.py --model ollama/gemma4:31b -M base_url=http://127.0.0.1:11600/v1 \
      --model-role judge=ollama/gemma4:31b --epochs 1 --log-dir logs/

Filter to one use case:  -T use_case=6
Smoke test with no model: --model mockllm/model
"""

import sys
from pathlib import Path

from inspect_ai import Task, task
from inspect_ai.dataset import Sample, json_dataset
from inspect_ai.model import GenerateConfig
from inspect_ai.solver import generate, system_message

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from scorer import property_judge  # noqa: E402

SYSTEM = (ROOT / "prompts" / "system.md").read_text(encoding="utf-8").strip()


def record_to_sample(rec: dict) -> Sample:
    return Sample(
        id=rec["id"],
        input=rec["prompt"],
        target="",
        metadata={"use_case": rec["use_case"], "properties": rec["properties"]},
    )


@task
def pilot(use_case: int | None = None, judge_model: str | None = None) -> Task:
    ds = json_dataset(str(ROOT / "cases" / "pilot.jsonl"), record_to_sample)
    if use_case is not None:
        ds = ds.filter(lambda s: s.metadata["use_case"] == use_case)
    return Task(
        dataset=ds,
        solver=[system_message(SYSTEM), generate()],
        scorer=property_judge(judge_model),
        config=GenerateConfig(temperature=0.0, max_tokens=2000),
    )
