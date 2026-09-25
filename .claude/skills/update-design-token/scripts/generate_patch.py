"""Gera (e opcionalmente aplica) a alteração de um token de cor.

Modo A: por defeito NÃO toca lib/ — escreve diff + ecrãs afetados em _preview/.
--apply: backup + escreve o ficheiro + admin_audit_log.

Uso:
  python generate_patch.py --token warning --new-value "#F59E0B"
  python generate_patch.py --token primary --new-value "#16A34A" --confirm-brand --apply
"""
from __future__ import annotations

import argparse
import difflib
import re
import sys
from pathlib import Path

from _shared import Ctx, log, audit_log, REPO_ROOT
import preview_token

BRAND_TOKENS = {"primary", "secondary", "accent"}
ORANGE = {"FB923C", "F97316", "EA580C"}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--token", required=True)
    ap.add_argument("--new-value", required=True, help="hex #RRGGBB (ou #AARRGGBB)")
    ap.add_argument("--confirm-brand", action="store_true")
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    ctx = Ctx.load(commit=args.apply)
    ctx.require_knowledge()

    hexv = args.new_value.lstrip("#").upper()
    if len(hexv) == 6:
        hexv = "FF" + hexv
    if not re.fullmatch(r"[0-9A-F]{8}", hexv):
        log("--new-value inválido. Usa #RRGGBB ou #AARRGGBB.", "ERROR")
        return 2

    if args.token in BRAND_TOKENS and not args.confirm_brand:
        log(f"⚠️ '{args.token}' é cor de MARCA (impacto global). Reexecuta com --confirm-brand.", "ERROR")
        return 1

    rel, line, val = preview_token.find_definition(args.token)
    if not rel:
        log(f"Token '{args.token}' não encontrado como Color(0x..).", "ERROR")
        return 1
    path = REPO_ROOT / rel
    old_text = path.read_text(encoding="utf-8")
    new_color = f"Color(0x{hexv})"
    new_text = re.sub(rf"(\b{re.escape(args.token)}\s*=\s*)Color\(0x[0-9A-Fa-f]{{8}}\)",
                      rf"\g<1>{new_color}", old_text, count=1)
    if new_text == old_text:
        log("Sem alteração (valor já igual?).", "WARN")

    diff = "".join(difflib.unified_diff(
        old_text.splitlines(keepends=True), new_text.splitlines(keepends=True),
        fromfile=f"a/{Path(rel).name}", tofile=f"b/{Path(rel).name}"))
    preview = Path("_preview"); preview.mkdir(exist_ok=True)
    (preview / f"{args.token}.diff").write_text(diff or "(sem alteração)\n", encoding="utf-8")

    hits = preview_token.count_usages(args.token)
    total = sum(hits.values())
    rep = [f"# Alterar token — {args.token}", "",
           f"- ficheiro: `{rel}:{line}` · {val} → **{new_color}**",
           f"- ecrãs/ficheiros afetados: **{total}** usos em **{len(hits)}** ficheiro(s)", ""]
    if args.token in BRAND_TOKENS:
        rep.append("> ⚠️ **Cor de MARCA** — impacto global. Rever cuidadosamente.")
    if hexv[2:] in ORANGE or args.token in {"secondary", "accent"}:
        rep.append("> 🟠 Token laranja/accent — lembrar **'1 laranja por ecrã'** (não multiplicar CTAs laranja).")
    rep += ["", "## Ficheiros afetados (top 30)"]
    rep += [f"- {f}: {n}" for f, n in sorted(hits.items(), key=lambda x: -x[1])[:30]] or ["- (nenhum)"]
    rep += ["", f"Diff: `_preview/{args.token}.diff`", ""]
    (preview / "relatorio.md").write_text("\n".join(rep), encoding="utf-8")
    log(f"Diff + relatório em {preview}/. Modo: {'APPLY' if args.apply else 'gerar (dry)'} · afetados: {total}")

    if not args.apply:
        log("Sem --apply: nada escrito em lib/.")
        return 0

    backup = preview / "backup"; backup.mkdir(exist_ok=True)
    (backup / Path(rel).name).write_text(old_text, encoding="utf-8")
    path.write_text(new_text, encoding="utf-8")
    audit_log(ctx, "design_token_updated", "design_system", f"token:{args.token}",
              {"file": rel, "old": val, "new": new_color, "affected_files": len(hits), "affected_uses": total})
    log(f"✅ {args.token} → {new_color} aplicado (backup em {backup}). Corre flutter analyze.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
