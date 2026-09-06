"""Valida um playbook de suporte: fallback humano + gate de sensibilidade.

Verifica:
- tem bloco "Escalar quando" (fallback humano) → obrigatório.
- toca $/auth/Stripe/GDPR → exige mode=write_shadow + requires_human_handoff=true.

Uso: python validate_skill.py --file _preview/check_reservation.md
Exit 0 = OK; 1 = falha (corrigir).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml  # type: ignore

from _shared import log, touches_sensitive, VALID_MODES


def parse_frontmatter(text: str) -> tuple[dict, str]:
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end != -1:
            fm = yaml.safe_load(text[3:end]) or {}
            return fm, text[end + 4:]
    return {}, text


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", required=True)
    args = ap.parse_args()
    p = Path(args.file)
    if not p.exists():
        log(f"Ficheiro não encontrado: {p}", "ERROR")
        return 1
    text = p.read_text(encoding="utf-8")
    fm, body = parse_frontmatter(text)
    problems, warns = [], []

    if fm.get("mode") not in VALID_MODES:
        problems.append(f"mode inválido: {fm.get('mode')} (usar {VALID_MODES})")
    if "escalar quando" not in body.lower():
        problems.append("falta bloco '## Escalar quando' (fallback humano obrigatório)")

    sensitive = touches_sensitive(text)
    if sensitive:
        if fm.get("mode") != "write_shadow":
            problems.append(f"toca zona sensível {sensitive} → mode deve ser write_shadow")
        if fm.get("requires_human_handoff") is not True:
            problems.append("toca zona sensível → requires_human_handoff deve ser true")
        warns.append(f"sensível: {sensitive} → shadow + aprovação Danilo (active=false).")

    for w in warns:
        log(f"⚠️ {w}", "WARN")
    if problems:
        for pr in problems:
            log(f"❌ {pr}", "ERROR")
        return 1
    log(f"✅ Playbook '{fm.get('name','?')}' válido (mode={fm.get('mode')}, "
        f"handoff={fm.get('requires_human_handoff')}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
