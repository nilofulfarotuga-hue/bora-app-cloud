"""Gera (e opcionalmente aplica) o patch para adicionar uma categoria à home.

Modo A: por defeito NÃO toca lib/ — escreve diffs/snippets em _preview/.
--apply: backup + escreve app_colors.dart (inserção determinística do gradient) +
tenta inserir o descritor em client_home_screen.dart (heurística; senão deixa snippet) +
flutter analyze (best-effort) + admin_audit_log.

Uso:
  python generate_patch.py --label "Flores" --gradient-start "#16A34A" --gradient-end "#22C55E" \
    --asset "assets/images/categories/flores.png" --screen "StoresScreen(category: BusinessCategory.store)"
  (... --apply  para aplicar)
"""
from __future__ import annotations

import argparse
import difflib
import re
import sys
from pathlib import Path

from _shared import Ctx, log, audit_log, REPO_ROOT

ORANGE_HEXES = {"#F97316", "#FB923C", "#EA580C", "#F9731", "#FFA726"}
ORANGE_TOKENS = {"tileRestaurants", "tileSendPackage"}


def token_name(label: str) -> str:
    parts = re.findall(r"[A-Za-zÀ-ÿ0-9]+", label)
    cc = "".join(p.capitalize() for p in parts) or "Nova"
    return "tile" + cc


def is_orange(start: str | None, end: str | None, gtoken: str | None) -> bool:
    if gtoken and gtoken in ORANGE_TOKENS:
        return True
    return any((c or "").upper() in ORANGE_HEXES for c in (start, end))


def build_gradient_block(token: str, start: str, end: str) -> str:
    return (f"  static const LinearGradient {token} = LinearGradient(\n"
            f"    colors: [Color(0xFF{start.lstrip('#').upper()}), Color(0xFF{end.lstrip('#').upper()})],\n"
            f"    begin: Alignment.topLeft,\n"
            f"    end: Alignment.bottomRight,\n"
            f"  );\n")


def insert_before_last_brace(text: str, block: str) -> str:
    idx = text.rstrip().rfind("}")
    if idx == -1:
        raise RuntimeError("não encontrei o fecho da classe AppColors")
    return text[:idx] + block + text[idx:]


def descriptor_snippet(label: str, token: str, asset: str, screen: str) -> str:
    safe_label = label.replace("'", "\\'")
    return ("_HomeTile(  // <-- confirmar nome do construtor/record usado no ficheiro\n"
            f"  label: '{safe_label}',\n"
            f"  gradient: AppColors.{token},\n"
            f"  imageAsset: '{asset}',\n"
            f"  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const {screen})),\n"
            "),")


def try_insert_home(text: str, snippet: str) -> tuple[str, bool]:
    """Heurística: inserir o descritor antes do `].map(` da lista de tiles."""
    m = re.search(r"\]\s*\.map\(", text)
    if not m:
        return text, False
    insert_at = m.start()  # antes do ']'
    indent = "      "
    block = indent + snippet.replace("\n", "\n" + indent) + "\n" + indent
    return text[:insert_at] + block + text[insert_at:], True


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--label", required=True)
    ap.add_argument("--gradient-start")
    ap.add_argument("--gradient-end")
    ap.add_argument("--gradient-token", help="reutilizar gradient existente (ex.: tileSupermarkets)")
    ap.add_argument("--asset", required=True)
    ap.add_argument("--screen", required=True, help="widget/rota de destino (ex.: 'RestaurantsScreen()')")
    ap.add_argument("--colors-file", default=str(REPO_ROOT / "lib/config/app_colors.dart"))
    ap.add_argument("--home-file", default=str(REPO_ROOT / "lib/screens/client_home_screen.dart"))
    ap.add_argument("--confirm-orange", action="store_true")
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    ctx = Ctx.load(commit=args.apply)
    ctx.require_knowledge()

    if not args.gradient_token and not (args.gradient_start and args.gradient_end):
        log("Indica --gradient-token OU (--gradient-start e --gradient-end).", "ERROR")
        return 2
    if is_orange(args.gradient_start, args.gradient_end, args.gradient_token) and not args.confirm_orange:
        log("⚠️ Gradient LARANJA viola a regra '1 laranja/ecrã' (já há tiles laranja: "
            "Restaurantes, Enviar Encomenda). Reexecuta com --confirm-orange se for mesmo intencional.", "ERROR")
        return 1

    token = args.gradient_token or token_name(args.label)
    colors_path = Path(args.colors_file)
    home_path = Path(args.home_file)
    preview = Path("_preview"); preview.mkdir(exist_ok=True)

    if not colors_path.exists():
        log(f"app_colors não encontrado: {colors_path}", "ERROR")
        return 1
    colors_text = colors_path.read_text(encoding="utf-8")

    # app_colors: só insere gradient novo se não for reutilização de token existente
    colors_new = colors_text
    if not args.gradient_token:
        if f" {token} " in colors_text or f"{token}=" in colors_text or f"{token} =" in colors_text:
            log(f"Token {token} já existe em app_colors — a reutilizar.", "WARN")
        else:
            block = "\n" + build_gradient_block(token, args.gradient_start, args.gradient_end)
            colors_new = insert_before_last_brace(colors_text, block)

    colors_diff = "".join(difflib.unified_diff(
        colors_text.splitlines(keepends=True), colors_new.splitlines(keepends=True),
        fromfile="a/app_colors.dart", tofile="b/app_colors.dart"))
    (preview / "app_colors.proposed.dart").write_text(colors_new, encoding="utf-8")
    (preview / "app_colors.diff").write_text(colors_diff or "(sem alteração)\n", encoding="utf-8")

    snippet = descriptor_snippet(args.label, token, args.asset, args.screen)
    (preview / "client_home_screen.snippet.dart").write_text(snippet + "\n", encoding="utf-8")

    home_text = home_path.read_text(encoding="utf-8") if home_path.exists() else ""
    home_new, home_auto = (try_insert_home(home_text, snippet) if home_text else (home_text, False))

    # Relatório
    rep = [f"# Adicionar categoria — {args.label}", "",
           f"- token gradient: `AppColors.{token}`" + (" (reutilizado)" if args.gradient_token else " (novo)"),
           f"- asset: `{args.asset}` (⚠️ criar o PNG + registar em pubspec.yaml — manual)",
           f"- destino (onTap): `{args.screen}`",
           f"- laranja? {'SIM (confirmado)' if is_orange(args.gradient_start, args.gradient_end, args.gradient_token) else 'não'}",
           "", "## Ficheiros gerados em _preview/",
           "- `app_colors.proposed.dart` + `app_colors.diff`",
           "- `client_home_screen.snippet.dart` (descritor a inserir na lista de tiles)",
           "", "## Passos manuais",
           "1. Criar o PNG do tile em assets/images/categories/ e garantir pubspec.yaml.",
           "2. Inserir o descritor (snippet) na lista de tiles de client_home_screen.dart, antes de `].map(`.",
           f"3. Confirmar o nome do construtor/record do descritor (o snippet usa `_HomeTile` placeholder).",
           "4. `flutter analyze` (0 erros) + smoke visual.", ""]
    if home_auto:
        (preview / "client_home_screen.proposed.dart").write_text(home_new, encoding="utf-8")
        home_diff = "".join(difflib.unified_diff(
            home_text.splitlines(keepends=True), home_new.splitlines(keepends=True),
            fromfile="a/client_home_screen.dart", tofile="b/client_home_screen.dart"))
        (preview / "client_home_screen.diff").write_text(home_diff, encoding="utf-8")
        rep.append("> Heurística inseriu o descritor antes de `].map(` — **REVER o diff** (construtor `_HomeTile` é placeholder).")
    else:
        rep.append("> Não foi possível localizar `].map(` automaticamente — inserir o snippet manualmente.")

    (preview / "relatorio.md").write_text("\n".join(rep), encoding="utf-8")
    log(f"Diffs gerados em {preview}/ (relatorio.md). Modo: {'APPLY' if args.apply else 'gerar (dry)'}")

    if not args.apply:
        log("Sem --apply: nada escrito em lib/.")
        return 0

    # ── APPLY ──
    backup = preview / "backup"; backup.mkdir(exist_ok=True)
    (backup / "app_colors.dart").write_text(colors_text, encoding="utf-8")
    colors_path.write_text(colors_new, encoding="utf-8")
    log(f"app_colors.dart atualizado (backup em {backup}).")
    if home_auto:
        (backup / "client_home_screen.dart").write_text(home_text, encoding="utf-8")
        home_path.write_text(home_new, encoding="utf-8")
        log("client_home_screen.dart atualizado (REVER — construtor placeholder).")
    else:
        log("client_home_screen.dart NÃO alterado — inserir snippet manualmente.", "WARN")
    audit_log(ctx, "home_category_added", "design_system", f"home:{token}",
              {"label": args.label, "token": token, "asset": args.asset,
               "screen": args.screen, "home_auto_inserted": home_auto})
    log("✅ Aplicado + auditado. Corre verify.py e flutter analyze.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
