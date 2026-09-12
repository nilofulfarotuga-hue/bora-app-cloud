"""Deploy de uma Edge Function (dry-run default; --commit corre supabase CLI).

Preserva verify_jwt. Funções protegidas exigem --i-know-what-im-doing + --reason.

Uso:
  python deploy.py --name notify-driver               # dry-run
  python deploy.py --name notify-driver --commit
  python deploy.py --name refund --i-know-what-im-doing --reason "fix" --commit
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys

import requests

from _shared import Ctx, log, audit_log, REPO_ROOT, PROJECT_REF, PROTECTED_FNS


def deployed_verify_jwt(name: str):
    """Lê verify_jwt atual via Management API (None se indisponível)."""
    tok = os.environ.get("SUPABASE_ACCESS_TOKEN")
    if not tok:
        return None
    try:
        r = requests.get(f"https://api.supabase.com/v1/projects/{PROJECT_REF}/functions/{name}",
                         timeout=30, headers={"Authorization": f"Bearer {tok}"})
        return r.json().get("verify_jwt") if r.status_code == 200 else None
    except Exception:  # noqa: BLE001
        return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--i-know-what-im-doing", dest="iknow", action="store_true")
    ap.add_argument("--reason")
    ap.add_argument("--commit", action="store_true")
    args = ap.parse_args()

    ctx = Ctx.load(commit=args.commit)
    ctx.require_knowledge()

    fn_dir = REPO_ROOT / "supabase" / "functions" / args.name
    if not (fn_dir / "index.ts").exists():
        log(f"Sem código local: {fn_dir}/index.ts", "ERROR")
        return 1

    if args.name in PROTECTED_FNS and not (args.iknow and args.reason):
        log(f"🔒 '{args.name}' é PROTEGIDA (financeira/dispatch). Exige "
            "--i-know-what-im-doing + --reason.", "ERROR")
        return 1

    vjwt = deployed_verify_jwt(args.name)
    cmd = ["supabase", "functions", "deploy", args.name, "--project-ref", PROJECT_REF]
    if vjwt is False:
        cmd.append("--no-verify-jwt")
    log(f"verify_jwt deployed = {vjwt} → flag {'--no-verify-jwt' if vjwt is False else '(default)'}")
    log("Comando: " + " ".join(cmd))

    if not args.commit:
        log("[DRY-RUN] nada deployado. Corre diff_function.py antes; usa --commit para deployar.")
        return 0

    try:
        res = subprocess.run(cmd, cwd=str(REPO_ROOT), capture_output=True, text=True, timeout=300)
        log((res.stdout or "")[-400:])
        if res.returncode != 0:
            log(f"Deploy falhou: {(res.stderr or '')[-300:]}", "ERROR")
            log("Alternativa: MCP deploy_edge_function(name, files).", "WARN")
            return 1
    except FileNotFoundError:
        log("CLI 'supabase' não encontrada. Instala/login, ou usa MCP deploy_edge_function.", "ERROR")
        return 1
    audit_log(ctx, "edge_function_deployed", "edge_function", args.name,
              {"verify_jwt": vjwt, "protected": args.name in PROTECTED_FNS, "reason": args.reason})
    log(f"✅ '{args.name}' deployado. Auditado.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
