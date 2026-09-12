"""Audita a regra '1 elemento laranja por ecrã' em lib/screens/. READ-ONLY.

Conta laranja DOMINANTE (CTA) vs SEMÂNTICO (badge/status/mapa) por ficheiro.

Uso:
  python audit.py                 # todos os ecrãs
  python audit.py --screen client_home_screen
  python audit.py --json
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from _shared import log, REPO_ROOT

# Padrões de laranja DOMINANTE (contam para o limite).
DOMINANT = [
    r"BoraAccentButton", r"AppColors\.accent\b", r"AppColors\.accentDark\b",
    r"AppColors\.secondary\b", r"AppColors\.secondaryDark\b",
    r"Color\(0xFFF97316\)", r"Color\(0xFFFB923C\)", r"Color\(0xFFEA580C\)",
]
DOMINANT_RE = re.compile("|".join(DOMINANT))
# Contextos SEMÂNTICOS (não contam): estado/aviso/marcador/mapa/gradient de tile.
SEMANTIC_HINT = re.compile(r"warning|mapPickup|tile(Restaurants|SendPackage|Promo)|"
                           r"badge|status|//\s*semantic", re.I)


def audit_file(path: Path):
    dominant, semantic = [], []
    for i, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        if DOMINANT_RE.search(line):
            (semantic if SEMANTIC_HINT.search(line) else dominant).append((i, line.strip()[:90]))
    return dominant, semantic


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--screen")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    screens_dir = REPO_ROOT / "lib" / "screens"
    if not screens_dir.exists():
        log(f"Pasta não encontrada: {screens_dir}", "ERROR")
        return 1
    files = sorted(screens_dir.rglob("*.dart"))
    if args.screen:
        files = [f for f in files if args.screen in f.stem]

    results, worst = [], 0
    for f in files:
        dom, sem = audit_file(f)
        n = len(dom)
        if n == 0 and not sem:
            continue
        level = "ok" if n <= 1 else ("warn" if n == 2 else "fail")
        worst = max(worst, {"ok": 0, "warn": 1, "fail": 2}[level])
        results.append({"screen": str(f.relative_to(REPO_ROOT)), "dominant": n,
                        "semantic": len(sem), "level": level,
                        "lines": [ln for ln, _ in dom]})

    icon = {"ok": "[OK]", "warn": "[!]", "fail": "[X]"}
    if args.json:
        print(json.dumps(results, ensure_ascii=False, indent=2))
    else:
        log(f"=== Audit '1 laranja/ecrã' — {len(results)} ecrã(s) com laranja ===")
        for r in sorted(results, key=lambda x: -x["dominant"]):
            mark = icon[r["level"]]
            log(f"{mark} {r['screen']}: {r['dominant']} dominante(s)"
                + (f", {r['semantic']} semântico(s)" if r["semantic"] else "")
                + (f" — linhas {r['lines']}" if r["dominant"] > 1 else ""))
        fails = [r["screen"] for r in results if r["level"] == "fail"]
        log(f"Resultado: {'[X] rever: ' + ', '.join(fails) if fails else '[OK] sem ecrãs 3+'}")

    out = REPO_ROOT / ".claude" / "skills" / "audit-orange-rule" / "_preview"
    out.mkdir(exist_ok=True)
    (out / "orange_audit.md").write_text(
        "# Audit 1 laranja/ecrã\n\n" + "\n".join(
            f"- {icon[r['level']]} `{r['screen']}` — {r['dominant']} dominante / {r['semantic']} semântico"
            for r in sorted(results, key=lambda x: -x["dominant"])), encoding="utf-8")
    return 1 if worst == 2 else 0


if __name__ == "__main__":
    sys.exit(main())
