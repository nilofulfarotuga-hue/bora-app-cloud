"""update-bora-knowledge / apply_updates — MODO A.

Sincroniza factos VERIFICÁVEIS do repo para um ficheiro de knowledge
**inteiramente gerido por máquina**: knowledge/00-auto-facts.md.

Princípio de segurança (Knowledge Protocol):
- NUNCA edita os docs curados (01..12) — esses têm prosa e receitas.
- Só escreve o ficheiro auto-gerido 00-auto-facts.md (cabeçalho avisa "não editar").
- Default = preview em _preview/; `--apply` escreve o ficheiro real.

Factos sincronizados (sem credenciais DB):
- Edge Functions: contagem + lista (supabase/functions/).
- Skills: contagem total + por tipo (frontmatter).
- Drift: funções citadas no doc 08 sem pasta / em código sem doc.

Factos que precisam de MCP (tabelas, platform_settings, widgets, categorias):
- não são tocados aqui — ficam como pendência no relatório.
"""
from __future__ import annotations

import argparse
import datetime as _dt
import importlib.util
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("ubk_shared", _HERE / "_shared.py")
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)  # type: ignore
log = _mod.log
parse_frontmatter = _mod.parse_frontmatter
iter_skill_dirs = _mod.iter_skill_dirs
KNOWLEDGE_DIR = _mod.KNOWLEDGE_DIR
FUNCTIONS_DIR = _mod.FUNCTIONS_DIR

# reutiliza a deteção de drift de Edge Functions
_d_spec = importlib.util.spec_from_file_location("ubk_detect", _HERE / "detect_drift.py")
_detect = importlib.util.module_from_spec(_d_spec)
_d_spec.loader.exec_module(_detect)  # type: ignore

NON_FN_DIRS = {"_shared", "__pycache__"}
TARGET = KNOWLEDGE_DIR / "00-auto-facts.md"


def _build_facts() -> str:
    today = _dt.date.today().isoformat()

    fns = sorted(d.name for d in FUNCTIONS_DIR.iterdir()
                 if d.is_dir() and d.name not in NON_FN_DIRS) \
        if FUNCTIONS_DIR.exists() else []

    type_counts: dict[str, int] = {}
    for sd in iter_skill_dirs():
        fm = parse_frontmatter(sd / "SKILL.md")
        meta = fm.get("metadata", {}) if isinstance(fm.get("metadata"), dict) else {}
        t = meta.get("type", "outros")
        type_counts[t] = type_counts.get(t, 0) + 1
    n_skills = sum(type_counts.values())

    code_not_doc, doc_not_code = _detect._edge_fn_drift()

    L = []
    L.append("# 00 — Factos auto-gerados (NÃO EDITAR À MÃO)")
    L.append("")
    L.append(f"> Gerado por `update-bora-knowledge/apply_updates.py` em {today}.")
    L.append("> Ficheiro **gerido por máquina** — regenerar com `--apply`. Os docs 01–12")
    L.append("> são curados à mão e não são tocados por esta skill.")
    L.append("")
    L.append(f"## Edge Functions — {len(fns)} em `supabase/functions/`")
    L.append("")
    L += [f"- `{fn}`" for fn in fns]
    L.append("")
    if code_not_doc:
        L.append("**Em código mas ausentes de `08-edge-functions.md`** (rever doc curado):")
        L += [f"- `{fn}`" for fn in code_not_doc]
        L.append("")
    if doc_not_code:
        L.append("**Citadas em `08` sem pasta** (renomeada/remota/planeada — confirmar):")
        L += [f"- `{fn}`" for fn in doc_not_code]
        L.append("")
    L.append(f"## Skills — {n_skills} no total")
    L.append("")
    L.append("| Tipo | Nº |")
    L.append("|------|----|")
    for t in sorted(type_counts):
        L.append(f"| {t} | {type_counts[t]} |")
    L.append("")
    L.append("## Pendente de MCP (não sincronizado aqui)")
    L.append("- nº de tabelas, `platform_settings`, widgets públicos, categorias da home —")
    L.append("  requerem consulta live à DB/código; manter nos docs curados (04, 07, 09, 02).")
    L.append("")
    return "\n".join(L)


def main() -> int:
    ap = argparse.ArgumentParser(description="Sincroniza 00-auto-facts.md (MODO A).")
    ap.add_argument("--apply", action="store_true",
                    help="escreve knowledge/00-auto-facts.md (default: _preview/)")
    args = ap.parse_args()

    content = _build_facts()

    if args.apply:
        out = TARGET
    else:
        out_dir = _HERE.parent / "_preview"
        out_dir.mkdir(exist_ok=True)
        out = out_dir / "00-auto-facts.preview.md"
    out.write_text(content + "\n", encoding="utf-8")

    log(f"[{'aplicado' if args.apply else 'preview'}] {out}")
    if not args.apply:
        log("MODO A: revê o preview e corre com --apply para escrever na knowledge.")
        log("Lembrete: só o ficheiro auto-gerido 00-auto-facts.md é tocado (docs curados intactos).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
