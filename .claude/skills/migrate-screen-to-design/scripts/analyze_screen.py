"""Lista as mudanças propostas para migrar 1 ecrã ao design system. READ-ONLY.

Uso: python analyze_screen.py --screen cart_screen
"""
from __future__ import annotations

import argparse
import re
import sys

from _shared import log, HEX_TOKEN, find_screen

WHITE_BLACK = re.compile(r"Color\(0x(FF)?(FFFFFF|000000)\)", re.I)


def analyze(text: str):
    subs, flags = [], []
    for hexv, token in HEX_TOKEN.items():
        n = len(re.findall(re.escape(f"Color({hexv})"), text, re.I))
        if n:
            subs.append((f"Color({hexv})", token, n))
    if WHITE_BLACK.search(text):
        flags.append("branco/preto Color(0xFFFFFFFF/000000) — usar surface/textPrimary (decisão humana)")
    if re.search(r"AppBar\(", text) and "BoraScreenAppBar" not in text:
        flags.append("AppBar custom presente — considerar BoraScreenAppBar")
    if "AppColors." in text and "config/app_colors.dart" not in text:
        flags.append("usa AppColors mas falta import app_colors.dart")
    if re.search(r"_SummaryRow|accent", text, re.I):
        flags.append("possível accent row / uso de accent — confirmar regra 1 laranja/ecrã")
    return subs, flags


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--screen", required=True)
    args = ap.parse_args()
    p = find_screen(args.screen)
    if not p:
        log(f"Ecrã não encontrado: {args.screen}", "ERROR")
        return 1
    subs, flags = analyze(p.read_text(encoding="utf-8", errors="replace"))
    log(f"Ecrã: {p.name}")
    log("Substituições automáticas propostas (hex→token):")
    for old, new, n in subs:
        log(f"  - {old} → {new}  ({n}x)")
    if not subs:
        log("  (nenhuma — sem hex de marca/semânticos reconhecidos)")
    log("Sinalizações (decisão humana, não auto):")
    for f in flags:
        log(f"  - {f}")
    if not flags:
        log("  (nenhuma)")
    log("Próximo: generate_patch.py --screen %s  (dry; --apply p/ aplicar)" % args.screen)
    return 0


if __name__ == "__main__":
    sys.exit(main())
