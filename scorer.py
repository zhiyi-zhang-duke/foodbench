"""FoodBench property scorer.

Each benchmark case carries a list of properties in Sample.metadata. The judge
model evaluates every property as pass / fail / na against the recipe the model
under test produced. Scores are aggregated per scoring dimension:

  dimension score = weighted fraction of applicable properties passed
                    (critical=3, major=2, minor=1)
  any failed critical property zeroes its dimension
  dimensions with no applicable property are reported as NaN, which Inspect
  treats as "not scored" and excludes from metrics (so N/A is never a 0)

The Score value is a dict {dimension: float|nan}; Inspect reports one metric
column per dimension. Raw per-property verdicts live in Score.metadata.
"""

import json
import math
import re
from pathlib import Path

from inspect_ai.model import GenerateConfig, get_model
from inspect_ai.scorer import Score, Scorer, Target, mean, scorer
from inspect_ai.solver import TaskState

DIMENSIONS = [
    "constraint",
    "ingredient",
    "technique",
    "quantity",
    "safety",
    "scaling",
    "feasibility",
    "flavor",
]
SEVERITY_WEIGHT = {"critical": 3, "major": 2, "minor": 1}

JUDGE_TEMPLATE = (Path(__file__).parent / "prompts" / "judge.md").read_text(encoding="utf-8")


def _parse_verdict(text: str) -> tuple[str, str]:
    """Pull {"verdict": ..., "evidence": ...} out of judge output. Tolerant of fences and prose."""
    m = re.search(r"\{.*\}", text, re.DOTALL)
    if m:
        try:
            obj = json.loads(m.group(0))
            v = str(obj.get("verdict", "")).strip().lower()
            if v in ("pass", "fail", "na", "n/a", "not applicable"):
                return ("na" if v.startswith("n") else v, str(obj.get("evidence", "")))
        except json.JSONDecodeError:
            pass
    low = text.lower()
    for v in ("pass", "fail"):
        if re.search(rf"\b{v}\b", low):
            return v, text.strip()[:300]
    if "n/a" in low or "not applicable" in low:
        return "na", text.strip()[:300]
    return "fail", "UNPARSEABLE: " + text.strip()[:300]


def aggregate(verdicts: list[dict]) -> dict[str, float]:
    """Fold per-property verdicts into per-dimension scores. NaN means not applicable."""
    out: dict[str, float] = {d: math.nan for d in DIMENSIONS}
    for dim in DIMENSIONS:
        rows = [v for v in verdicts if v["dimension"] == dim and v["verdict"] != "na"]
        if not rows:
            continue
        if any(v["verdict"] == "fail" and v["severity"] == "critical" for v in rows):
            out[dim] = 0.0
            continue
        total = sum(SEVERITY_WEIGHT[v["severity"]] for v in rows)
        got = sum(SEVERITY_WEIGHT[v["severity"]] for v in rows if v["verdict"] == "pass")
        out[dim] = round(got / total, 4)
    return out


@scorer(metrics={d: [mean()] for d in DIMENSIONS})
def property_judge(judge_model: str | None = None) -> Scorer:
    """Judge each case property with an LLM and aggregate per dimension.

    The judge is resolved from, in order: the `judge_model` argument, the
    `judge` model role (`--model-role judge=<model>`), or the model under test.
    """

    async def score(state: TaskState, target: Target) -> Score:
        judge = get_model(judge_model, role="judge", default=str(state.model), config=GenerateConfig(temperature=0, max_tokens=1500, reasoning_effort="none"))
        # reasoning_effort="none": Gemma 4 thinks by default and a tight token cap left the
        # visible answer empty. max_tokens stays generous in case a model ignores it.
        # Reasoning models (deepseek-r1, gpt-oss) may return their scratchpad inline.
        # Judge only the answer the user would see.
        recipe = re.sub(r"<think>.*?</think>\s*", "", state.output.completion, flags=re.DOTALL).strip()
        props = state.metadata.get("properties", [])
        verdicts = []
        for p in props:
            prompt = JUDGE_TEMPLATE.format(
                prompt=state.input_text,
                recipe=recipe,
                check=p["check"],
                dimension=p["dimension"],
            )
            resp = await judge.generate(prompt)
            verdict, evidence = _parse_verdict(resp.completion)
            verdicts.append({**p, "verdict": verdict, "evidence": evidence})

        dims = aggregate(verdicts)
        summary = ", ".join(f"{d}={v:.2f}" for d, v in dims.items() if not math.isnan(v))
        return Score(
            value=dims,  # type: ignore[arg-type]
            answer=recipe[:500],
            explanation=summary or "no applicable properties",
            metadata={"verdicts": verdicts, "judge": str(judge.name)},
        )

    return score
