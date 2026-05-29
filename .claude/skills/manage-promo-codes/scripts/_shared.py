"""Helpers S4-E (operações). Reusa motor S1 (Ctx/log) + get_admin_jwt + rpc()."""
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


def get_admin_jwt(ctx):
    """JWT de admin (is_admin()=true). BORA_ADMIN_JWT ou sign-in admin."""
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


def rpc(ctx, name: str, payload: dict, token: str):
    """Chama uma RPC PostgREST com o token dado."""
    import requests
    return requests.post(f"{ctx.supabase_url}/rest/v1/rpc/{name}", timeout=60, json=payload,
                         headers={"Authorization": f"Bearer {token}", "apikey": ctx.anon_key,
                                  "Content-Type": "application/json"})
