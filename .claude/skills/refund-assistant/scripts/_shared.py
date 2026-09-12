"""Helpers S4-E (financeiro shadow). Reusa motor S1 (Ctx/log) + audit_log + REPO_ROOT."""
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
REPO_ROOT = Path(__file__).resolve().parents[4]


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


def get_settings(ctx, keys):
    """Lê platform_settings por chave → dict {key: value}."""
    inlist = ",".join(keys)
    r = ctx.rest("GET", f"platform_settings?key=in.({inlist})&select=key,value", ctx.service_role_key)
    return {x["key"]: x["value"] for x in (r.json() if r.status_code < 300 else [])}
