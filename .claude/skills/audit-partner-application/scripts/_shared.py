"""Helpers S2 (auditorias/operações).

Reutiliza o motor S1 (onboard-partner-restaurant/scripts/_shared.py) sob nome único
(registado em sys.modules antes de exec, p/ @dataclass) e acrescenta:
- admin_identity(): (BORA_ADMIN_USER_ID, BORA_ADMIN_EMAIL)
- get_admin_jwt(ctx): JWT de admin (app_metadata.role='admin') p/ Edge Fns admin
- audit_log(...): INSERT em admin_audit_log via service_role
"""
import importlib.util
import os
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


def admin_identity():
    return os.environ.get("BORA_ADMIN_USER_ID", ""), os.environ.get("BORA_ADMIN_EMAIL", "")


def get_admin_jwt(ctx):
    """JWT de admin (app_metadata.role='admin'). BORA_ADMIN_JWT ou sign-in admin."""
    import requests
    jwt = os.environ.get("BORA_ADMIN_JWT")
    if jwt:
        return jwt
    email = os.environ.get("BORA_ADMIN_EMAIL")
    pw = os.environ.get("BORA_ADMIN_PASSWORD")
    if not (email and pw):
        raise RuntimeError("Define BORA_ADMIN_JWT, ou BORA_ADMIN_EMAIL + BORA_ADMIN_PASSWORD.")
    r = requests.post(f"{ctx.supabase_url}/auth/v1/token?grant_type=password", timeout=30,
                      headers={"apikey": ctx.anon_key, "Content-Type": "application/json"},
                      json={"email": email, "password": pw})
    r.raise_for_status()
    return r.json()["access_token"]


def audit_log(ctx, action, entity_type, entity_id, details, *, text_id=False):
    admin_id, admin_email = admin_identity()
    row = {
        "admin_id": admin_id or None,
        "admin_email": admin_email or None,
        "action": action,
        "entity_type": entity_type,
        "details": details or {},
    }
    row["entity_id_text" if text_id else "entity_id"] = entity_id
    resp = ctx.rest("POST", "admin_audit_log", ctx.service_role_key, [row])
    if resp.status_code >= 300:
        log(f"audit_log falhou: {resp.status_code} {resp.text[:160]}", "WARN")
        return False
    return True
