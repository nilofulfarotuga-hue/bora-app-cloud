"""Mostra o valor atual de um token e os ecrãs/ficheiros que o usam.

Uso: python preview_token.py --token warning
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from _shared import Ctx, log, REPO_ROOT, dart_files

CONFIG_FILES = ["lib/config/app_theme.dart", "lib/config/app_colors.dart"]


def find_definition(token: str):
    """(ficheiro, linha, valor) onde o token é definido como Color(0x..)."""
    pat = re.compile(rf"\b{re.escape(token)}\s*=\s*(Color\(0x[0-9A-Fa-f]{{8}}\))")
    for rel in CONFIG_FILES:
        p = REPO_ROOT / rel
        if not p.exists():
            continue
        for i, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
            m = pat.search(line)
            if m:
                return rel, i, m.group(1)
    return None, None, None


def count_usages(token: str):
    pat = re.compile(rf"\b(AppColors|AppTheme)\.{re.escape(token)}\b")
    hits = {}
    for f in dart_files(REPO_ROOT):
        n = len(pat.findall(f.read_text(encoding="utf-8", errors="ignore")))
        if n:
            hits[str(f.relative_to(REPO_ROOT))] = n
    return hits


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--token", required=True)
    args = ap.parse_args()
    ctx = Ctx.load()
    ctx.require_knowledge()

    rel, line, val = find_definition(args.token)
    if not rel:
        log(f"Token '{args.token}' não encontrado como Color(0x..) em app_theme/app_colors.", "ERROR")
        return 1
    log(f"Definição: {rel}:{line} → {val}")
    hits = count_usages(args.token)
    total = sum(hits.values())
    log(f"Usos de AppColors/AppTheme.{args.token}: {total} em {len(hits)} ficheiro(s).")
    for f, n in sorted(hits.items(), key=lambda x: -x[1])[:30]:
        log(f"  - {f}: {n}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
