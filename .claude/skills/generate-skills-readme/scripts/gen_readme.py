"""generate-skills-readme — gera o README.md mestre, agrupado por categoria.

Lê o frontmatter + corpo de cada SKILL.md e produz uma tabela navegável PT-PT,
agrupada por `metadata.type`. Para cada skill: nome, o que faz (1ª frase),
comando exemplo (1º bloco ```bash) e dry-run (sim/não).

NÃO toca no INDEX.md (curado à mão).

Modos:
  default (dry-run) → _preview/README.generated.md
  --write           → README.md na raiz das skills
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
read_text = _mod.read_text
parse_frontmatter = _mod.parse_frontmatter
iter_skill_dirs = _mod.iter_skill_dirs
SKILLS_ROOT = _mod.SKILLS_ROOT

# Ordem e rótulos amigáveis dos grupos (metadata.type → título da secção).
GROUP_LABELS = {
    "foundation": "Foundation", "orchestrator": "Orquestração", "validator": "Validação",
    "sync": "Sincronização", "onboarder": "Onboarding", "auditor": "Auditoria",
    "operator": "Operação", "operacoes": "Operações", "codegen": "Codegen",
    "config": "Configuração", "data": "Dados / Mercados", "support": "Suporte",
    "qa": "QA", "devops": "DevOps", "design": "Design", "financeiro": "Financeiro",
    "finance": "Financeiro", "ops": "Ops / Storage", "debug": "Debug", "meta": "Consolidação (meta)",
}
GROUP_ORDER = ["foundation", "orchestrator", "validator", "sync", "onboarder",
               "auditor", "operator", "operacoes", "codegen", "config", "data",
               "support", "qa", "devops", "design", "financeiro", "finance",
               "ops", "debug", "meta"]


def _short_desc(desc: str, limit: int = 150) -> str:
    desc = re.sub(r"\s+", " ", desc).strip()
    first = re.split(r"(?<=[.!?])\s", desc, maxsplit=1)[0]
    out = first if len(first) <= limit else desc[:limit].rstrip() + "…"
    return out.replace("|", "\\|")


def _first_bash_cmd(text: str) -> str:
    m = re.search(r"```bash\s*\n(.+?)\n", text, re.S)
    if not m:
        return "—"
    return ("`" + m.group(1).strip().replace("|", "\\|") + "`")[:90]


def _has_dryrun(text: str) -> str:
    return "sim" if re.search(r"dry-run|dry_run", text, re.I) else "não"


def _collect() -> dict[str, list[tuple]]:
    groups: dict[str, list[tuple]] = {}
    for skill_dir in iter_skill_dirs():
        md = skill_dir / "SKILL.md"
        fm = parse_frontmatter(md)
        text = read_text(md)
        name = fm.get("name") or skill_dir.name
        meta = fm.get("metadata", {}) if isinstance(fm.get("metadata"), dict) else {}
        gtype = meta.get("type", "outros")
        row = (name, _short_desc(fm.get("description", "")),
               _first_bash_cmd(text), _has_dryrun(text))
        groups.setdefault(gtype, []).append(row)
    return groups


def _build() -> tuple[str, int]:
    groups = _collect()
    total = sum(len(v) for v in groups.values())
    lines = [
        "# Skills do Bora App — Guia navegável",
        "",
        f"> Gerado por `generate-skills-readme` em {_dt.date.today().isoformat()}.",
        "> **Não editar à mão** — regenerar. O `INDEX.md` curado é a referência rica.",
        f"> Total: **{total} skills**.",
        "",
        "Consulta obrigatória: **`bora-knowledge`** antes de qualquer ação.",
        "",
    ]
    seen = set()
    ordered = [g for g in GROUP_ORDER if g in groups] + \
              [g for g in sorted(groups) if g not in GROUP_ORDER]
    for g in ordered:
        if g in seen:
            continue
        seen.add(g)
        label = GROUP_LABELS.get(g, g.capitalize())
        rows = sorted(groups[g], key=lambda r: r[0])
        lines.append(f"## {label} ({len(rows)})")
        lines.append("")
        lines.append("| Skill | O que faz | Comando exemplo | Dry-run |")
        lines.append("|-------|-----------|-----------------|---------|")
        for name, desc, cmd, dry in rows:
            lines.append(f"| **{name}** | {desc} | {cmd} | {dry} |")
        lines.append("")
    return "\n".join(lines), total


def main() -> int:
    ap = argparse.ArgumentParser(description="Gera README.md mestre das skills.")
    ap.add_argument("--write", action="store_true",
                    help="grava README.md na raiz das skills (default: _preview/)")
    args = ap.parse_args()

    content, n = _build()
    if args.write:
        out = SKILLS_ROOT / "README.md"
    else:
        out_dir = Path(__file__).resolve().parents[1] / "_preview"
        out_dir.mkdir(exist_ok=True)
        out = out_dir / "README.generated.md"
    out.write_text(content + "\n", encoding="utf-8")
    log(f"[gerado] {n} skills -> {out}")
    if not args.write:
        log("dry-run: preview em _preview/. Usa --write para gravar README.md.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
