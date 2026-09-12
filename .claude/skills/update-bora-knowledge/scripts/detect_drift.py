"""update-bora-knowledge — deteta drift entre a knowledge e a realidade do repo.

READ-ONLY sobre a knowledge. NUNCA edita bora-knowledge/. Em vez disso escreve uma
PROPOSTA em _preview/ (Knowledge Protocol: propor ao Danilo, não escrever).

Verificações (repo-only, sem credenciais DB):
  1. Edge Functions — pastas em supabase/functions/ vs nomes citados em
     knowledge/08-edge-functions.md (ambos os sentidos).
  2. Skills — pastas de skill reais vs tabela em INDEX.md + contagem declarada.

Saída: relatório no terminal + ficheiro _preview/knowledge-drift-<data>.md.
Sem --apply: NÃO existe modo de escrita na knowledge (por design).
"""
from __future__ import annotations

import argparse
import datetime as _dt
import importlib.util
import re
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    "ubk_shared", Path(__file__).resolve().parent / "_shared.py")
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)  # type: ignore
log = _mod.log
read_text = _mod.read_text
iter_skill_dirs = _mod.iter_skill_dirs
KNOWLEDGE_DIR = _mod.KNOWLEDGE_DIR
FUNCTIONS_DIR = _mod.FUNCTIONS_DIR
INDEX_MD = _mod.INDEX_MD

# Pastas em supabase/functions que não são Edge Functions deployáveis.
NON_FN_DIRS = {"_shared", "__pycache__"}


def _edge_fn_drift() -> tuple[list[str], list[str]]:
    """Devolve (em_codigo_sem_doc, no_doc_sem_pasta)."""
    if not FUNCTIONS_DIR.exists():
        return [], []
    actual = sorted(d.name for d in FUNCTIONS_DIR.iterdir()
                    if d.is_dir() and d.name not in NON_FN_DIRS)
    doc = read_text(KNOWLEDGE_DIR / "08-edge-functions.md") if \
        (KNOWLEDGE_DIR / "08-edge-functions.md").exists() else ""

    code_not_doc = [fn for fn in actual if fn not in doc]

    # nomes tipo-função citados no doc (têm hífen) que não têm pasta
    cited = set(re.findall(r"`([a-z][a-z0-9]+(?:-[a-z0-9]+)+)`", doc))
    actual_set = set(actual)
    doc_not_code = sorted(fn for fn in cited if fn not in actual_set)
    return code_not_doc, doc_not_code


def _skills_drift() -> tuple[list[str], list[str], str]:
    """Devolve (pastas_sem_index, index_sem_pasta, nota_contagem)."""
    real = sorted(d.name for d in iter_skill_dirs())
    index_txt = read_text(INDEX_MD) if INDEX_MD.exists() else ""
    listed = set(re.findall(r"^\|\s*\*\*([a-z0-9-]+)\*\*\s*\|", index_txt, re.M))

    pastas_sem_index = [s for s in real if s not in listed]
    index_sem_pasta = sorted(s for s in listed if s not in set(real))

    m = re.search(r"\*\*(\d+)\s+skills", index_txt)
    declared = int(m.group(1)) if m else None
    if declared is None:
        nota = f"contagem não declarada no INDEX (reais={len(real)})"
    elif declared == len(real):
        nota = f"contagem OK ({declared})"
    else:
        nota = f"contagem DESALINHADA: INDEX diz {declared}, reais={len(real)}"
    return pastas_sem_index, index_sem_pasta, nota


def main() -> int:
    ap = argparse.ArgumentParser(description="Deteta drift knowledge vs repo (read-only).")
    ap.add_argument("--no-file", action="store_true", help="só terminal, não grava _preview/")
    args = ap.parse_args()

    code_not_doc, doc_not_code = _edge_fn_drift()
    pastas_sem_index, index_sem_pasta, nota_cont = _skills_drift()

    lines: list[str] = []
    lines.append("# PROPOSTA — Knowledge Drift (Bora App)")
    lines.append("")
    lines.append(f"> Gerado: {_dt.date.today().isoformat()} · **read-only** · "
                 "knowledge NÃO foi alterada. Rever e aplicar manualmente se concordares.")
    lines.append("")
    lines.append("## 1. Edge Functions (supabase/functions/ vs 08-edge-functions.md)")
    if code_not_doc:
        lines.append("**Em código mas NÃO documentadas em 08** (considerar documentar):")
        lines += [f"- `{fn}`" for fn in code_not_doc]
    else:
        lines.append("- (todas as funções em código estão referidas no doc) ✔")
    lines.append("")
    if doc_not_code:
        lines.append("**Citadas no doc mas SEM pasta** (renomeada / remota / planeada?):")
        lines += [f"- `{fn}` — confirmar estado" for fn in doc_not_code]
    else:
        lines.append("- (nenhuma referência órfã no doc) ✔")
    lines.append("")
    lines.append("## 2. Skills (pastas reais vs INDEX.md)")
    lines.append(f"- Contagem: {nota_cont}")
    if pastas_sem_index:
        lines.append("**Pastas de skill ausentes da tabela do INDEX:**")
        lines += [f"- `{s}`" for s in pastas_sem_index]
    if index_sem_pasta:
        lines.append("**Linhas do INDEX sem pasta correspondente:**")
        lines += [f"- `{s}`" for s in index_sem_pasta]
    if not pastas_sem_index and not index_sem_pasta:
        lines.append("- (INDEX e pastas alinhados) ✔")
    lines.append("")
    report = "\n".join(lines)

    log(report)

    if not args.no_file:
        out_dir = Path(__file__).resolve().parents[1] / "_preview"
        out_dir.mkdir(exist_ok=True)
        out = out_dir / f"knowledge-drift-{_dt.date.today().isoformat()}.md"
        out.write_text(report + "\n", encoding="utf-8")
        log("")
        log(f"[proposta escrita] {out}")
        log("LEMBRETE: aplica as mudanças à knowledge manualmente (Knowledge Protocol).")

    drift = len(code_not_doc) + len(doc_not_code) + len(pastas_sem_index) + len(index_sem_pasta)
    return 0 if drift == 0 else 0  # informativo: nunca falha o exit (read-only)


if __name__ == "__main__":
    raise SystemExit(main())
