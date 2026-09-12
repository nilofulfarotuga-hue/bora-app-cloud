"""Helpers S4-D (design codegen). Reusa motor S1 (log) + mapa hex→token."""
import importlib.util
import sys
from pathlib import Path

_ENGINE = (Path(__file__).resolve().parents[2]
           / "onboard-partner-restaurant" / "scripts" / "_shared.py")
_spec = importlib.util.spec_from_file_location("bora_onboard_engine", _ENGINE)
_mod = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = _mod
_spec.loader.exec_module(_mod)  # type: ignore

log = _mod.log
REPO_ROOT = Path(__file__).resolve().parents[4]  # …/skills/<skill>/scripts → bora_app

# Hex inequívocos (marca/semânticos) → token AppColors. Branco/preto excluídos (ambíguos).
HEX_TOKEN = {
    "0xFF16A34A": "AppColors.primary", "0xFF065F46": "AppColors.primaryDark",
    "0xFF053D28": "AppColors.primaryDeep", "0xFF15803D": "AppColors.primaryMid",
    "0xFFF97316": "AppColors.accent", "0xFFEA580C": "AppColors.accentDark",
    "0xFFFB923C": "AppColors.accentLight", "0xFFF0F2EF": "AppColors.background",
    "0xFF6B7280": "AppColors.textSecondary", "0xFF111111": "AppColors.textPrimary",
    "0xFF9CA3AF": "AppColors.textSubtle", "0xFFE5E7EB": "AppColors.divider",
    "0xFFD1D5DB": "AppColors.dividerStrong", "0xFFDC2626": "AppColors.error",
    "0xFFF59E0B": "AppColors.warning", "0xFF2563EB": "AppColors.info",
}


def find_screen(stem_or_path: str) -> Path | None:
    sd = REPO_ROOT / "lib" / "screens"
    cand = sd / stem_or_path
    if cand.exists():
        return cand
    hits = [f for f in sd.rglob("*.dart") if f.stem == stem_or_path or stem_or_path in str(f)]
    return hits[0] if hits else None
