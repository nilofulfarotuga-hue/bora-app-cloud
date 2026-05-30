"""Helpers generate-skills-index-readme (S4-F). Reusa motor meta de skills-doctor.

Stdlib-only. Importa parse_frontmatter/iter_skill_dirs/log/SKILLS_ROOT (DRY).
"""
from __future__ import annotations

import importlib.util
from pathlib import Path

_DOCTOR = (Path(__file__).resolve().parents[2]
           / "skills-doctor" / "scripts" / "_shared.py")
_spec = importlib.util.spec_from_file_location("skills_doctor_shared", _DOCTOR)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)  # type: ignore

log = _mod.log
read_text = _mod.read_text
parse_frontmatter = _mod.parse_frontmatter
iter_skill_dirs = _mod.iter_skill_dirs
SKILLS_ROOT: Path = _mod.SKILLS_ROOT
