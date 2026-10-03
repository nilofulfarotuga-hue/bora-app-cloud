"""Mostra o diff entre o código local de uma Edge Function e a versão deployed.

Corpo deployed via Management API (SUPABASE_ACCESS_TOKEN). Sem token → instrui MCP.
Read-only. Escreve _preview/<name>.diff.

Uso: python diff_function.py --name notify-driver
"""
from __future__ import annotations

import argparse
import difflib
import os
import sys
from pathlib import Path

import requests

from _shared import Ctx, log, REPO_ROOT, PROJECT_REF


def local_source(name: str) -> str | None:
    p = REPO_ROOT / "supabase" / "functions" / name / "index.ts"
    return p.read_text(encoding="utf-8") if p.exists() else None


def deployed_source(name: str) -> str | None:
    tok = os.environ.get("SUPABASE_ACCESS_TOKEN")
    if not tok:
        return None
    try:
        r = requests.get(
            f"https://api.supabase.com/v1/projects/{PROJECT_REF}/functions/{name}/body",
            timeout=30, headers={"Authorization": f"Bearer {tok}"})
        return r.text if r.status_code == 200 else None
    except Exception as e:  # noqa: BLE001
        log(f"Management API erro: {e}", "WARN")
        return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    args = ap.parse_args()
    Ctx.load().require_knowledge()

    loc = local_source(args.name)
    if loc is None:
        log(f"Sem código local: supabase/functions/{args.name}/index.ts", "ERROR")
        return 1
    dep = deployed_source(args.name)
    if dep is None:
        log("Corpo deployed indisponível (sem SUPABASE_ACCESS_TOKEN).", "WARN")
        log(f"Alternativa: MCP get_edge_function(function_slug='{args.name}') e comparar manualmente.")
        log(f"Local: {len(loc)} chars em supabase/functions/{args.name}/index.ts")
        return 0

    diff = "".join(difflib.unified_diff(
        dep.splitlines(keepends=True), loc.splitlines(keepends=True),
        fromfile=f"deployed/{args.name}", tofile=f"local/{args.name}"))
    out = Path("_preview"); out.mkdir(exist_ok=True)
    (out / f"{args.name}.diff").write_text(diff or "(igual)\n", encoding="utf-8")
    if not diff:
        log("Local == deployed (sem diferenças).")
    else:
        adds = sum(1 for l in diff.splitlines() if l.startswith("+") and not l.startswith("+++"))
        dels = sum(1 for l in diff.splitlines() if l.startswith("-") and not l.startswith("---"))
        log(f"Diff: +{adds} / -{dels} linhas. Ver _preview/{args.name}.diff")
    return 0


if __name__ == "__main__":
    sys.exit(main())
