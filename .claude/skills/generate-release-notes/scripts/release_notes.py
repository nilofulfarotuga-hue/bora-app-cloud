"""Gera RELEASE_NOTES_v{N}.md a partir do git log desde o último tag. Read-only.

Uso:
  python release_notes.py
  python release_notes.py --since v1.0.0 --version 231
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from _shared import REPO_ROOT, log, run_git

TYPE_LABELS = {
    "feat": "✨ Novidades (feat)", "fix": "🐛 Correções (fix)",
    "refactor": "♻️ Refactor", "docs": "📝 Documentação",
    "chore": "🔧 Manutenção (chore)", "outros": "📦 Outros",
}
TYPE_RE = re.compile(r"^(feat|fix|refactor|docs|chore|perf|test|style|build|ci)(\(.+?\))?:\s*(.+)$", re.I)


def build_version() -> str:
    pub = REPO_ROOT / "pubspec.yaml"
    if pub.exists():
        m = re.search(r"^version:\s*[\d.]+\+(\d+)", pub.read_text(encoding="utf-8"), re.M)
        if m:
            return m.group(1)
    return "next"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", help="ref/tag inicial (default: último tag)")
    ap.add_argument("--version")
    args = ap.parse_args()

    since = (args.since or (run_git(["describe", "--tags", "--abbrev=0"]) or "")).strip()
    rng = f"{since}..HEAD" if since else "HEAD"
    raw = run_git(["log", rng, "--pretty=format:%s|%h|%an"]) or ""
    if not raw.strip():
        log(f"Sem commits no range '{rng}'.", "WARN")
        return 0

    groups: dict[str, list] = {k: [] for k in TYPE_LABELS}
    total = 0
    for line in raw.splitlines():
        parts = line.split("|")
        if len(parts) < 2:
            continue
        subj, sha = parts[0], parts[1]
        total += 1
        m = TYPE_RE.match(subj)
        if m:
            t = m.group(1).lower()
            t = t if t in groups else ("fix" if t == "perf" else "outros")
            groups[t].append((m.group(3).strip(), sha))
        else:
            groups["outros"].append((subj.strip(), sha))

    ver = args.version or build_version()
    lines = [f"# Notas de Versão — Bora v{ver}", "",
             f"_Desde: {since or '(início)'} · {total} commit(s)_", "", "## Resumo"]
    for t, label in TYPE_LABELS.items():
        if groups[t]:
            lines.append(f"- {label}: {len(groups[t])}")
    lines.append("")
    for t, label in TYPE_LABELS.items():
        if groups[t]:
            lines.append(f"## {label}")
            lines += [f"- {desc} (`{sha}`)" for desc, sha in groups[t]]
            lines.append("")

    feats = [d for d, _ in groups["feat"]]
    fixes = [d for d, _ in groups["fix"]]
    lines += ["## 👋 Para testers", "",
              "Olá! Esta versão traz:" if (feats or fixes) else "Esta versão é de manutenção interna.",
              ""]
    for d in feats[:6]:
        lines.append(f"- 🆕 {d}")
    for d in fixes[:6]:
        lines.append(f"- ✅ Resolvido: {d}")
    lines += ["", "**O que testar:** abre a app, confirma que login, pedido e pagamento (cash) "
              "funcionam, e experimenta as novidades acima. Reporta qualquer estranheza. Obrigado! 🛵"]

    dest = REPO_ROOT / f"RELEASE_NOTES_v{ver}.md"
    dest.write_text("\n".join(lines), encoding="utf-8")
    log(f"✅ Notas geradas: {dest} ({total} commits). Read-only — sem tag, sem push.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
