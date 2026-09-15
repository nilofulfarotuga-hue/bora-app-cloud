"""skills-doctor — valida todas as skills em .claude/skills/.

Read-only. Verifica por skill:
  [X] erro  — SKILL.md ausente; frontmatter sem name/description; name != pasta;
              script .py não compila (py_compile).
  [!] aviso — sem metadata.type; sem depends_on bora-knowledge (exceto foundation/
              orchestrator/validator); sem README.md; sem requirements.txt quando
              há scripts; sem indício de dry-run em skills que escrevem.
  [OK]      — sem erros nem avisos.

Saída: relatório PT-PT + sumário. Exit code = nº de skills com erro (>0 falha).

Uso:
  python scripts/check.py                # todas
  python scripts/check.py --skill notify-broadcast
  python scripts/check.py --strict       # avisos contam como falha no exit code
"""
from __future__ import annotations

import argparse
import importlib.util
import py_compile
from pathlib import Path

_THIS = Path(__file__).resolve()
_spec = importlib.util.spec_from_file_location("skills_doctor_shared", _THIS.parent / "_shared.py")
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)  # type: ignore
log = _mod.log
read_text = _mod.read_text
parse_frontmatter = _mod.parse_frontmatter
iter_skill_dirs = _mod.iter_skill_dirs

# Skills foundation/meta que não precisam depends_on bora-knowledge.
NO_DEP_REQUIRED = {"bora-knowledge", "ceo-ai", "prompt-blindado-validator",
                   "auto-rules-sync", "skills-doctor", "update-bora-knowledge",
                   "generate-skills-index-readme"}

# Indícios de que uma skill escreve (logo deveria ter dry-run default).
WRITE_HINTS = ("--commit", "--apply", "--write", "INSERT", "UPDATE", "DELETE",
               "upsert", "rpc(", "execute_sql")
DRYRUN_HINTS = ("dry-run", "dry_run", "--commit", "--apply", "--write", "_preview")


def _check_skill(skill_dir: Path) -> tuple[str, list[str], list[str]]:
    name = skill_dir.name
    errors: list[str] = []
    warns: list[str] = []

    skill_md = skill_dir / "SKILL.md"
    if not skill_md.exists():
        return name, ["SKILL.md ausente"], []

    fm = parse_frontmatter(skill_md)
    fm_name = fm.get("name", "")
    fm_desc = fm.get("description", "")
    meta = fm.get("metadata", {}) if isinstance(fm.get("metadata"), dict) else {}

    if not fm_name:
        errors.append("frontmatter sem 'name'")
    elif fm_name != name:
        errors.append(f"name '{fm_name}' != pasta '{name}'")
    if not fm_desc:
        errors.append("frontmatter sem 'description'")
    elif len(fm_desc) < 20:
        warns.append("description muito curta (<20 chars)")

    if not meta.get("type"):
        warns.append("metadata sem 'type'")

    dep = str(meta.get("depends_on", ""))
    if name not in NO_DEP_REQUIRED and "bora-knowledge" not in dep:
        warns.append("metadata.depends_on sem 'bora-knowledge'")

    if not (skill_dir / "README.md").exists():
        warns.append("sem README.md")

    scripts_dir = skill_dir / "scripts"
    py_files = sorted(scripts_dir.glob("*.py")) if scripts_dir.exists() else []

    # py_compile de cada script.
    for py in py_files:
        try:
            py_compile.compile(str(py), doraise=True)
        except py_compile.PyCompileError as exc:
            errors.append(f"py_compile falhou: {py.name} ({exc.msg.splitlines()[-1][:80]})")

    if py_files and not (skill_dir / "requirements.txt").exists():
        warns.append("há scripts mas sem requirements.txt")

    # Heurística dry-run: se algum script tem indício de escrita, deve ter indício de dry-run.
    blob = "\n".join(read_text(p) for p in py_files)
    if any(h in blob for h in WRITE_HINTS) and not any(h in blob for h in DRYRUN_HINTS):
        warns.append("parece escrever sem indício de dry-run/--commit")

    return name, errors, warns


def main() -> int:
    ap = argparse.ArgumentParser(description="Valida skills do Bora App.")
    ap.add_argument("--skill", help="validar apenas esta skill")
    ap.add_argument("--strict", action="store_true", help="avisos também falham o exit code")
    args = ap.parse_args()

    skills = iter_skill_dirs()
    if args.skill:
        skills = [s for s in skills if s.name == args.skill]
        if not skills:
            log(f"[X] skill '{args.skill}' não encontrada.")
            return 1

    log("=" * 68)
    log("  SKILLS-DOCTOR — validação read-only")
    log("=" * 68)

    n_err = n_warn = n_ok = 0
    for skill_dir in skills:
        name, errors, warns = _check_skill(skill_dir)
        if errors:
            n_err += 1
            log(f"[X] {name}")
            for e in errors:
                log(f"      ERRO: {e}")
            for w in warns:
                log(f"      aviso: {w}")
        elif warns:
            n_warn += 1
            log(f"[!] {name}")
            for w in warns:
                log(f"      aviso: {w}")
        else:
            n_ok += 1
            log(f"[OK] {name}")

    log("-" * 68)
    log(f"  Total: {len(skills)}  |  [OK] {n_ok}  |  [!] {n_warn}  |  [X] {n_err}")
    log("=" * 68)

    return n_err + (n_warn if args.strict else 0)


if __name__ == "__main__":
    raise SystemExit(main())
