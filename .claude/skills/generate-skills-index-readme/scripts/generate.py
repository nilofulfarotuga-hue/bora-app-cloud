"""generate-skills-index-readme — gera um README tabular a partir do frontmatter.

Lê o SKILL.md de cada skill (name, metadata.type, description) e produz uma tabela
Markdown ordenada. NÃO toca no INDEX.md (curado à mão).

Modos:
  default (dry-run)  → escreve _preview/SKILLS_README.generated.md + sumário
  --write            → escreve SKILLS_README.md na raiz das skills

Uso:
  python scripts/generate.py
  python scripts/generate.py --write
"""
from __future__ import annotations

import argparse
import datetime as _dt
import importlib.util
import re
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    "gsr_shared", Path(__file__).resolve().parent / "_shared.py")
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)  # type: ignore
log = _mod.log
parse_frontmatter = _mod.parse_frontmatter
iter_skill_dirs = _mod.iter_skill_dirs
SKILLS_ROOT = _mod.SKILLS_ROOT


def _short_desc(desc: str, limit: int = 160) -> str:
    desc = re.sub(r"\s+", " ", desc).strip()
    # primeira frase, sem ultrapassar o limite
    first = re.split(r"(?<=[.!?])\s", desc, maxsplit=1)[0]
    out = first if len(first) <= limit else desc[:limit].rstrip() + "…"
    return out.replace("|", "\\|")


def _build() -> tuple[str, int]:
    rows = []
    for skill_dir in iter_skill_dirs():
        fm = parse_frontmatter(skill_dir / "SKILL.md")
        name = fm.get("name") or skill_dir.name
        meta = fm.get("metadata", {}) if isinstance(fm.get("metadata"), dict) else {}
        stype = meta.get("type", "—")
        desc = _short_desc(fm.get("description", ""))
        rows.append((name, stype, desc))

    rows.sort(key=lambda r: r[0])
    lines = [
        "# Skills — README gerado automaticamente",
        "",
        f"> Gerado por `generate-skills-index-readme` em {_dt.date.today().isoformat()}.",
        "> Fonte: frontmatter de cada `SKILL.md`. **Não editar à mão** — regenerar.",
        f"> Total: **{len(rows)} skills**. (O `INDEX.md` curado é a referência rica.)",
        "",
        "| Skill | Tipo | Descrição |",
        "|-------|------|-----------|",
    ]
    for name, stype, desc in rows:
        lines.append(f"| **{name}** | {stype} | {desc} |")
    lines.append("")
    return "\n".join(lines), len(rows)


def main() -> int:
    ap = argparse.ArgumentParser(description="Gera README tabular das skills.")
    ap.add_argument("--write", action="store_true",
                    help="escreve SKILLS_README.md na raiz das skills (default: _preview/)")
    args = ap.parse_args()

    content, n = _build()

    if args.write:
        out = SKILLS_ROOT / "SKILLS_README.md"
    else:
        out_dir = Path(__file__).resolve().parents[1] / "_preview"
        out_dir.mkdir(exist_ok=True)
        out = out_dir / "SKILLS_README.generated.md"

    out.write_text(content + "\n", encoding="utf-8")
    log(f"[gerado] {n} skills -> {out}")
    if not args.write:
        log("dry-run: preview em _preview/. Usa --write para gravar SKILLS_README.md.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
