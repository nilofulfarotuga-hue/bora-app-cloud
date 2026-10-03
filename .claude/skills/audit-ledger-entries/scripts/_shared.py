"""Helpers S4-D (financeiro, read-only). Reusa motor S1 (Ctx/log) + paginação."""
import importlib.util
import sys
from pathlib import Path

_ENGINE = (Path(__file__).resolve().parents[2]
           / "onboard-partner-restaurant" / "scripts" / "_shared.py")
_spec = importlib.util.spec_from_file_location("bora_onboard_engine", _ENGINE)
_mod = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = _mod
_spec.loader.exec_module(_mod)  # type: ignore

Ctx = _mod.Ctx
log = _mod.log
REPO_ROOT = Path(__file__).resolve().parents[4]


def rest_paginate(ctx, path_no_range: str, page: int = 1000, cap: int = 200000):
    import requests
    out, start = [], 0
    while start < cap:
        url = f"{ctx.supabase_url}/rest/v1/{path_no_range}"
        r = requests.get(url, timeout=120, headers={
            "Authorization": f"Bearer {ctx.service_role_key}", "apikey": ctx.anon_key,
            "Range-Unit": "items", "Range": f"{start}-{start + page - 1}"})
        if r.status_code >= 300:
            log(f"paginate erro {r.status_code}: {r.text[:120]}", "WARN")
            break
        rows = r.json()
        out.extend(rows)
        if len(rows) < page:
            break
        start += page
    return out
