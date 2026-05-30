"""Helpers meta S4-F (consolidação). Stdlib-only — NÃO precisa Supabase.

Canónico para as 3 skills de consolidação (skills-doctor é a casa):
- update-bora-knowledge e generate-skills-index-readme importam daqui via importlib.
"""
from __future__ import annotations

import sys
from pathlib import Path

# scripts/_shared.py -> [0]=scripts  [1]=<skill>  [2]=skills root
SKILLS_ROOT = Path(__file__).resolve().parents[2]

# Diretórios em skills/ que NÃO são skills (sem SKILL.md ou meta).
NON_SKILL_DIRS = {"sistema", "__pycache__"}


def log(msg: str) -> None:
    """Print resiliente a consolas cp1252 (Windows)."""
    try:
        print(msg)
    except UnicodeEncodeError:
        enc = sys.stdout.encoding or "utf-8"
        sys.stdout.write(msg.encode(enc, "replace").decode(enc) + "\n")


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return path.read_text(encoding="latin-1")


def parse_frontmatter(skill_md: Path) -> dict:
    """Parser leve de frontmatter YAML (subconjunto suficiente p/ validação).

    Devolve dict com chaves de topo (name, description) e 'metadata' como sub-dict.
    Não usa PyYAML (mantém stdlib-only).
    """
    text = read_text(skill_md)
    if not text.startswith("---"):
        return {}
    parts = text.split("---", 2)
    if len(parts) < 3:
        return {}
    body = parts[1]
    data: dict = {}
    cur_parent: str | None = None
    for raw in body.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip())
        line = raw.strip()
        if ":" not in line:
            continue
        key, _, val = line.partition(":")
        key = key.strip()
        val = val.strip()
        if indent == 0:
            if val == "":
                data[key] = {}
                cur_parent = key
            else:
                data[key] = val
                cur_parent = None
        else:
            if cur_parent and isinstance(data.get(cur_parent), dict):
                data[cur_parent][key] = val
    return data


def iter_skill_dirs() -> list[Path]:
    """Lista diretórios de skill (têm SKILL.md), ordenados por nome."""
    out = []
    for child in sorted(SKILLS_ROOT.iterdir()):
        if not child.is_dir():
            continue
        if child.name in NON_SKILL_DIRS:
            continue
        if (child / "SKILL.md").exists():
            out.append(child)
    return out
