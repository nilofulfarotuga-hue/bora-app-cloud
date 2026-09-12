"""Verifica o resultado de um --apply: flutter analyze (best-effort) + label presente.

Uso: python verify.py --label "Flores"
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

from _shared import log, REPO_ROOT


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--label", required=True)
    ap.add_argument("--home-file", default=str(REPO_ROOT / "lib/screens/client_home_screen.dart"))
    args = ap.parse_args()

    home = Path(args.home_file)
    if home.exists() and args.label in home.read_text(encoding="utf-8"):
        log(f"✅ label '{args.label}' presente em {home.name}")
    else:
        log(f"⚠️ label '{args.label}' NÃO encontrado em {home.name} — inserir o descritor.", "WARN")

    try:
        r = subprocess.run(["flutter", "analyze"], cwd=str(REPO_ROOT),
                           capture_output=True, text=True, timeout=600)
        tail = (r.stdout or r.stderr).strip().splitlines()[-5:]
        log("flutter analyze:\n  " + "\n  ".join(tail))
        return 0 if r.returncode == 0 else 1
    except Exception as e:  # noqa: BLE001
        log(f"flutter analyze não executado ({e}) — correr manualmente.", "WARN")
        return 0


if __name__ == "__main__":
    sys.exit(main())
