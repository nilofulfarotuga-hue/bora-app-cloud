"""Reutiliza o motor partilhado de onboard-partner-restaurant (skills co-localizadas).

Carrega o módulo original sob um nome ÚNICO (`bora_onboard_engine`) para evitar a
colisão de nome que ocorreria com `from _shared import *` (o próprio módulo chama-se
_shared). Re-exporta os símbolos usados pelos restantes scripts desta skill.
"""
import importlib.util
import sys
from pathlib import Path

_ENGINE = (Path(__file__).resolve().parents[2]
           / "onboard-partner-restaurant" / "scripts" / "_shared.py")
_spec = importlib.util.spec_from_file_location("bora_onboard_engine", _ENGINE)
_mod = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = _mod  # registar antes de exec (necessário p/ @dataclass)
_spec.loader.exec_module(_mod)  # type: ignore

Ctx = _mod.Ctx
log = _mod.log
read_pipeline_json = _mod.read_pipeline_json
write_pipeline_json = _mod.write_pipeline_json
