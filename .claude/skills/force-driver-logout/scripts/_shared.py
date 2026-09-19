"""Helpers S2 (auditorias/operações).

Reutiliza o motor S1 (onboard-partner-restaurant/scripts/_shared.py) sob nome único
(registado em sys.modules antes de exec, p/ @dataclass) e acrescenta admin helpers.
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


ACTIVE_ORDER_STATUSES = ["preparing", "callingDriver", "driverAccepted", "pickedUp", "onTheWay"]
