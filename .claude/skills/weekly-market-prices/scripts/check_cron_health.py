"""Verifica a saúde dos pg_cron de preço (best-effort via REST/RPC).

A tabela cron.job vive no schema `cron` (não exposto por PostgREST por defeito). Esta skill
tenta uma RPC `cron_jobs_status` se existir; caso contrário, informa como verificar via MCP.

Uso: python check_cron_health.py
"""
from __future__ import annotations

import sys

import requests

from _shared import Ctx, log


def main() -> int:
    ctx = Ctx.load()
    ctx.require_knowledge()
    # tentativa 1: RPC dedicada (se o projeto a tiver)
    try:
        r = requests.post(f"{ctx.supabase_url}/rest/v1/rpc/cron_jobs_status", timeout=30,
                          headers={"Authorization": f"Bearer {ctx.service_role_key}",
                                   "apikey": ctx.anon_key, "Content-Type": "application/json"},
                          json={})
        if r.status_code < 300:
            jobs = r.json()
            log(f"pg_cron jobs ({len(jobs)}):")
            for j in jobs:
                log(f"  - {j}")
            return 0
    except Exception:  # noqa: BLE001
        pass
    log("RPC cron_jobs_status indisponível.", "WARN")
    log("Verificar via MCP (Supabase): execute_sql →")
    log("  SELECT jobid, schedule, jobname, active FROM cron.job ORDER BY jobname;")
    log("  SELECT * FROM cron.job_run_details ORDER BY end_time DESC LIMIT 20;")
    log("Crons de preço esperados: ver memória do projeto (Continente segunda-feira).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
