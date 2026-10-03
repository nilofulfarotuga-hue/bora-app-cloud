"""Helpers S4-B (suporte/QA). Reutiliza o motor S1 + audit_log."""
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

# Palavras que forçam shadow-mode + handoff (zonas sensíveis).
SENSITIVE_TERMS = ["refund", "reembols", "estorno", "cancel", "stripe", "payment", "pagamento",
                   "wallet", "carteira", "token", "auth", "password", "palavra-passe",
                   "gdpr", "rgpd", "dados pessoais", "delete-account", "charge", "cobr"]
VALID_MODES = ["read_only", "write_shadow", "escalate"]


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


def touches_sensitive(text: str) -> list[str]:
    low = (text or "").lower()
    return sorted({t for t in SENSITIVE_TERMS if t in low})
