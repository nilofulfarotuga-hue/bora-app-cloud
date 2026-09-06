"""Helpers S3 (codegen/ops). Reutiliza o motor S1 + audit_log + REPO_ROOT."""
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
REPO_ROOT = Path(__file__).resolve().parents[4]  # …/skills/<skill>/scripts → bora_app


def admin_identity():
    return os.environ.get("BORA_ADMIN_USER_ID", ""), os.environ.get("BORA_ADMIN_EMAIL", "")


def audit_log(ctx, action, entity_type, entity_id, details, *, text_id=True):
    admin_id, admin_email = admin_identity()
    row = {"admin_id": admin_id or None, "admin_email": admin_email or None,
           "action": action, "entity_type": entity_type, "details": details or {}}
    row["entity_id_text" if text_id else "entity_id"] = entity_id
    try:
        resp = ctx.rest("POST", "admin_audit_log", ctx.service_role_key, [row])
        if resp.status_code >= 300:
            log(f"audit_log falhou: {resp.status_code} {resp.text[:160]}", "WARN")
            return False
        return True
    except Exception as e:  # noqa: BLE001
        log(f"audit_log indisponível (não fatal): {e}", "WARN")
        return False


def dart_files(repo_root: Path):
    """Itera ficheiros .dart sob lib/ (para grep de uso de tokens)."""
    lib = repo_root / "lib"
    return sorted(lib.rglob("*.dart")) if lib.exists() else []
