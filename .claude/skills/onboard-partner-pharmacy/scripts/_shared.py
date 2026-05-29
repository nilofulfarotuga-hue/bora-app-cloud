"""Reutiliza o motor partilhado de onboard-partner-restaurant (skills co-localizadas)."""
import sys
from pathlib import Path

_REST = Path(__file__).resolve().parents[2] / "onboard-partner-restaurant" / "scripts"
if str(_REST) not in sys.path:
    sys.path.insert(0, str(_REST))

from _shared import *  # noqa: F401,F403,E402
from _shared import Ctx, log, read_pipeline_json, write_pipeline_json  # noqa: F401,E402
