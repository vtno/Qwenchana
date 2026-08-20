import os
import re
from pathlib import Path

template = Path("/app/config.template.yaml").read_text()
rendered = re.sub(
    r"\$\{([A-Za-z0-9_]+)\}",
    lambda m: os.environ.get(m.group(1), m.group(0)),
    template,
)
Path("/app/config.yaml").write_text(rendered)