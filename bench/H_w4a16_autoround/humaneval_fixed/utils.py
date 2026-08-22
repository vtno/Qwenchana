import re

import evaluate as hf_evaluate

try:
    compute_ = hf_evaluate.load("code_eval")
    test_cases = ["assert add(2, 3)==5"]
    candidates = [["def add(a,b): return a*b"]]
    compute_.compute(references=test_cases, predictions=candidates, k=[1])
except Exception as e:
    raise e


def pass_at_k(references: list[str], predictions: list[list[str]], k: list[int] = None):
    global compute_
    assert k is not None
    if isinstance(k, int):
        k = [k]
    res = compute_.compute(references=references, predictions=predictions, k=k)
    return res[0]


def extract_code(resp: str) -> str:
    """Strip markdown code fences; chat models wrap solutions in ```python blocks."""
    m = re.search(r"```(?:python|py)?[ \t]*\n(.*?)(?:```|\Z)", resp, re.DOTALL)
    if m:
        return m.group(1)
    return resp


def build_predictions(resps: list[list[str]], docs: list[dict]) -> list[list[str]]:
    # like upstream lm_eval humaneval build_predictions, but fence-aware
    return [[doc["prompt"] + extract_code(r) for r in resp] for resp, doc in zip(resps, docs)]
