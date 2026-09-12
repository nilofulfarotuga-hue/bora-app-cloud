"""Helpers S4-A (mercados). Reutiliza o motor S1 + helpers de mercado.

Carrega onboard-partner-restaurant/scripts/_shared.py sob nome único (registado em
sys.modules antes de exec, p/ @dataclass).
"""
import importlib.util
import os
import sys
import time
from pathlib import Path

_ENGINE = (Path(__file__).resolve().parents[2]
           / "onboard-partner-restaurant" / "scripts" / "_shared.py")
_spec = importlib.util.spec_from_file_location("bora_onboard_engine", _ENGINE)
_mod = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = _mod
_spec.loader.exec_module(_mod)  # type: ignore

Ctx = _mod.Ctx
log = _mod.log

# Lojas de mercado (não-parceiras). Fast-food e partner-*/uuid ficam de fora de propósito.
MARKET_STORES = [
    "continente-guarda", "pingodoce-guarda", "mercadona-guarda", "auchan-guarda",
    "intermarche-guarda", "lidl-guarda", "leroy-merlin-guarda", "wells-guarda",
    "kiwoko-guarda", "worten-guarda", "zippy-guarda",
]
DEFAULT_RATE = 3.5  # s/request (rate limit cortês)


def is_market_store(rid: str) -> bool:
    return rid in MARKET_STORES


def require_market(rid: str) -> None:
    if not is_market_store(rid):
        log(f"'{rid}' não é loja de mercado (allowlist MARKET_STORES). Recusado.", "ERROR")
        sys.exit(2)


def rate_sleep(seconds: float = DEFAULT_RATE) -> None:
    try:
        time.sleep(max(0.0, float(seconds)))
    except Exception:  # noqa: BLE001
        pass


def head_ok(url: str, timeout: int = 15) -> bool:
    import requests
    try:
        r = requests.head(url, timeout=timeout, allow_redirects=True)
        if r.status_code == 405:
            r = requests.get(url, timeout=timeout, stream=True)
        return r.status_code == 200
    except Exception:  # noqa: BLE001
        return False


def admin_identity():
    return os.environ.get("BORA_ADMIN_USER_ID", ""), os.environ.get("BORA_ADMIN_EMAIL", "")


def audit_log(ctx, action, entity_type, entity_id, details, *, text_id=True):
    admin_id, admin_email = admin_identity()
    row = {"admin_id": admin_id or None, "admin_email": admin_email or None,
           "action": action, "entity_type": entity_type, "details": details or {}}
    row["entity_id_text" if text_id else "entity_id"] = str(entity_id)
    try:
        resp = ctx.rest("POST", "admin_audit_log", ctx.service_role_key, [row])
        if resp.status_code >= 300:
            log(f"audit_log falhou: {resp.status_code} {resp.text[:160]}", "WARN")
            return False
        return True
    except Exception as e:  # noqa: BLE001
        log(f"audit_log indisponível (não fatal): {e}", "WARN")
        return False


def rest_paginate(ctx, path_no_range: str, page: int = 1000, cap: int = 100000):
    """GET paginado via Range. path_no_range já inclui ?select=...&filtros. Devolve lista."""
    import requests
    out, start = [], 0
    while start < cap:
        url = f"{ctx.supabase_url}/rest/v1/{path_no_range}"
        r = requests.get(url, timeout=60, headers={
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
