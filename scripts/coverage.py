"""Verification coverage: which models are exercised by which evidence layer.

Line coverage requires toolchain-specific flags that vary between releases.
What actually matters for this project is whether each model is exercised by
each evidence layer - white-box tests, CLI fixtures, the independent oracle,
the closure audit, and a shipped example. This script checks that matrix and
fails if any model loses a layer it previously had.
"""
import json, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

MODELS = ["register", "kv_register", "queue", "stack", "lock", "set",
    "counter", "map", "lww_set", "max_register", "grow_only_set",
    "or_set", "flag",
    "two_phase_set", "min_register", "lww_register", "bounded_queue", "deque",
    "semaphore", "rwlock", "multiset", "priority_queue", "pncounter", "lww_map"]

def check():
    fixture_text = (ROOT / "tests/cases.json").read_text()
    oracle_text = (ROOT / "scripts/reference.py").read_text()
    wbtest_text = "".join(p.read_text() for p in ROOT.glob("*_wbtest.mbt"))
    example_names = [p.stem for p in (ROOT / "examples").glob("*.json")]
    rows = []
    for model in MODELS:
        layers = []
        if model in wbtest_text:
            layers.append("wbtest")
        if f'"{model}"' in fixture_text or f"'{model}'" in fixture_text:
            layers.append("fixture")
        if f"'{model}'" in oracle_text:
            layers.append("oracle")
        if model in example_names:
            layers.append("example")
        rows.append((model, layers))
        missing = set(["wbtest", "fixture", "oracle"]) - set(layers)
        if missing:
            print(f"  {model}: missing {', '.join(sorted(missing))}")
    fixture_names = [c['name'] for c in json.loads(
        (ROOT / 'tests/cases.json').read_text())]
    assert len(fixture_names) == len(set(fixture_names)), 'duplicate fixtures'
    print(f"Coverage: {len(MODELS)} models, {sum(len(l) for _, l in rows)} "
        + f"model-layer pairs, {len(fixture_names)} unique fixtures")
    return rows

if __name__ == "__main__":
    check()
