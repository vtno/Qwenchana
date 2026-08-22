import os
import re
from pathlib import Path

# Claude model classes routed to the anthropic passthrough backend
# (vLLM's native /v1/messages). Claude Code "auto mode" makes side calls
# for claude-sonnet-* (decisions) and claude-haiku-* (quick tasks); listing
# every known class name keeps them from 400-ing as unknown models.
CLAUDE_ALIAS_MODELS = [
    # opus class
    "claude-opus-4-5",
    "claude-opus-4-5-20251101",
    "claude-opus-4-1",
    "claude-opus-4-1-20250805",
    "claude-opus-4",
    "claude-opus-4-20250514",
    "claude-3-opus",
    "claude-3-opus-20240229",
    # sonnet class
    "claude-sonnet-5",
    "claude-sonnet-4-6",
    "claude-sonnet-4-5",
    "claude-sonnet-4-5-20250929",
    "claude-sonnet-4",
    "claude-sonnet-4-20250514",
    "claude-3-7-sonnet",
    "claude-3-7-sonnet-20250219",
    "claude-3-5-sonnet",
    "claude-3-5-sonnet-20241022",
    "claude-3-sonnet",
    "claude-3-sonnet-20240229",
    # haiku class
    "claude-haiku-4-5",
    "claude-haiku-4-5-20251001",
    "claude-haiku-3-5",
    "claude-haiku-3-5-20241022",
    "claude-3-haiku",
    "claude-3-haiku-20240307",
]

template = Path("/app/config.template.yaml").read_text()
rendered = re.sub(
    r"\$\{([A-Za-z0-9_]+)\}",
    lambda m: os.environ.get(m.group(1), m.group(0)),
    template,
)

alias_block = "\n".join(
    "  - model_name: " + name + "\n"
    "    litellm_params:\n"
    "      model: anthropic/" + os.environ.get("VLLM_MODEL_ID", "") + "\n"
    "      api_base: " + os.environ.get("VLLM_ANTHROPIC_BASE_URL", "") + "\n"
    "      api_key: " + os.environ.get("VLLM_API_KEY", "") + "\n"
    for name in CLAUDE_ALIAS_MODELS
)
rendered = rendered.replace("CLAUDE_ALIAS_DEPLOYMENTS", alias_block.rstrip("\n"))

Path("/app/config.yaml").write_text(rendered)
