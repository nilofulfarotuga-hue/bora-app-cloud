"""Gera (e opcionalmente aplica) a migração de cores de 1 ecrã. MODO A.

Substitui literais Color(0x..) de marca/semânticos por AppColors tokens + garante import.
Dry-run escreve _preview/<screen>.diff. --apply faz backup + escreve + flutter analyze.
NÃO altera lógica/strings/Stripe/realtime.

Uso:
  python generate_patch.py --screen cart_screen
  python generate_patch.py --screen cart_screen --apply
"""
from __future__ import annotations

import argparse
import difflib
import re
import subprocess
import sys
from pathlib import Path

from _shared import log, HEX_TOKEN, REPO_ROOT, find_screen

IMPORT_LINE = "import 'package:bora_app/config/app_colors.dart';"


def transform(text: str) -> tuple[str, int]:
    new = text
    total = 0
    for hexv, token in HEX_TOKEN.items():
        pat = re.compile(re.escape(f"Color({hexv})"), re.I)
        new, n = pat.subn(token, new)
        total += n
    if total and "AppColors." in new and "config/app_colors.dart" not in new:
        # insere import a seguir ao último import existente
        lines = new.splitlines(keepends=True)
        idx = max((i for i, l in enumerate(lines) if l.startswith("import ")), default=-1)
        if idx >= 0:
            lines.insert(idx + 1, IMPORT_LINE + "\n")
            new = "".join(lines)
    return new, total


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--screen", required=True)
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()
    p = find_screen(args.screen)
    if not p:
        log(f"Ecrã não encontrado: {args.screen}", "ERROR")
        return 1

    old = p.read_text(encoding="utf-8", errors="replace")
    new, n = transform(old)
    diff = "".join(difflib.unified_diff(old.splitlines(keepends=True), new.splitlines(keepends=True),
                                        fromfile=f"a/{p.name}", tofile=f"b/{p.name}"))
    preview = REPO_ROOT / ".claude" / "skills" / "migrate-screen-to-design" / "_preview"
    preview.mkdir(exist_ok=True)
    (preview / f"{p.stem}.diff").write_text(diff or "(sem alteração automática)\n", encoding="utf-8")
    log(f"{p.name}: {n} substituição(ões) de cor. Diff: _preview/{p.stem}.diff")
    if not diff:
        log("Sem hex de marca/semânticos reconhecidos — ver analyze_screen.py p/ sinalizações.")

    if not args.apply:
        log("[DRY-RUN] nada escrito em lib/. Use --apply para aplicar (só cores; lógica intocada).")
        return 0

    backup = preview / "backup"; backup.mkdir(exist_ok=True)
    (backup / p.name).write_text(old, encoding="utf-8")
    p.write_text(new, encoding="utf-8")
    log(f"Aplicado (backup em {backup}). A correr flutter analyze…")
    try:
        r = subprocess.run(["flutter", "analyze"], cwd=str(REPO_ROOT), capture_output=True,
                           text=True, encoding="utf-8", errors="replace", timeout=600)
        tail = "\n  ".join((r.stdout or r.stderr).strip().splitlines()[-5:])
        log("flutter analyze:\n  " + tail)
        return 0 if r.returncode == 0 else 1
    except Exception as e:  # noqa: BLE001
        log(f"flutter analyze não corrido ({e}) — correr manualmente.", "WARN")
        return 0


if __name__ == "__main__":
    sys.exit(main())
