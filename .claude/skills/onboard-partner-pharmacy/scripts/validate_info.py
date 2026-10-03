"""Valida info.yaml + produtos.csv de uma FARMÁCIA parceira.

Reutiliza validadores de onboard-partner-restaurant (NIF, IBAN, email, telefone, coords).
Diferenças:
- category='farmacia' + campo obrigatório 'licenca_infarmed'.
- is_prescription(): deteta produtos sujeitos a receita médica (bloqueados pelo pipeline).

Uso: python validate_info.py --dir ".claude/.ai/onboard/wells-guarda"
"""
from __future__ import annotations

import argparse
import csv
import importlib.util
import sys
from pathlib import Path

import yaml  # type: ignore

from _shared import log

_REST = Path(__file__).resolve().parents[2] / "onboard-partner-restaurant" / "scripts"
_spec = importlib.util.spec_from_file_location("rest_validate", _REST / "validate_info.py")
_rv = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_rv)  # type: ignore

REQUIRED_KEYS = ["name", "category", "address", "phone", "email", "licenca_infarmed"]
VALID_CATEGORIES = {"farmacia", "farmácia", "pharmacy"}

# Palavras-chave de medicamento sujeito a receita (MSRM) → bloquear (só OTC permitido).
RX_KEYWORDS = [
    "receita", "msrm", "sujeito a receita", "medicamento sujeito", "antibiótico",
    "antibiotico", "ansiolítico", "ansiolitico", "psicotrópico", "psicotropico",
    "opióide", "opioide", "benzodiazepina", "insulina", "corticoide injetável",
    "morfina", "tramadol", "diazepam", "amoxicilina", "alprazolam",
]


def is_prescription(name: str) -> bool:
    low = (name or "").lower()
    return any(k in low for k in RX_KEYWORDS)


def validate(onboard_dir: Path) -> list[str]:
    errors: list[str] = []
    info_path = onboard_dir / "info.yaml"
    if not info_path.exists():
        return [f"info.yaml não encontrado em {onboard_dir}"]
    data = yaml.safe_load(info_path.read_text(encoding="utf-8")) or {}
    r = data.get("restaurant", data.get("pharmacy", data))

    for key in REQUIRED_KEYS:
        if not str(r.get(key, "")).strip():
            errors.append(f"info.yaml: campo obrigatório vazio: {key}")
    if str(r.get("category", "")).lower() not in VALID_CATEGORIES:
        errors.append("info.yaml: category deve ser 'farmacia' nesta skill")
    if r.get("email") and not _rv.EMAIL_RE.match(str(r["email"])):
        errors.append(f"info.yaml: email inválido: {r['email']}")
    if r.get("phone") and not _rv.PHONE_PT_RE.match(str(r["phone"]).replace(" ", "")):
        errors.append(f"info.yaml: telefone PT inválido: {r['phone']}")
    if r.get("nif") and not _rv.valid_nif(str(r["nif"])):
        errors.append(f"info.yaml: NIF inválido: {r['nif']}")
    if r.get("iban") and not _rv.valid_iban_pt(str(r["iban"])):
        errors.append(f"info.yaml: IBAN inválido (^PT+21 dígitos): {r['iban']}")
    lat, lng = r.get("lat"), r.get("lng")
    if lat is not None and not (36.9 <= float(lat) <= 42.2):
        errors.append(f"info.yaml: lat fora do continente PT: {lat}")
    if lng is not None and not (-9.6 <= float(lng) <= -6.2):
        errors.append(f"info.yaml: lng fora do continente PT: {lng}")

    for asset in ("logo", "capa"):
        if not any((onboard_dir / f"{asset}{e}").exists() for e in (".png", ".jpg", ".jpeg")):
            errors.append(f"imagem obrigatória em falta: {asset}.(png|jpg)")

    csv_path = onboard_dir / "produtos.csv"
    if not csv_path.exists():
        errors.append("produtos.csv não encontrado")
    else:
        rx = []
        with csv_path.open(encoding="utf-8") as f:
            for i, row in enumerate(csv.DictReader(f), start=2):
                name = (row.get("nome") or "").strip()
                if not name:
                    errors.append(f"produtos.csv linha {i}: nome vazio")
                try:
                    if float(str(row.get("preço", row.get("preco", "0"))).replace(",", ".")) <= 0:
                        errors.append(f"produtos.csv linha {i}: preço deve ser > 0")
                except ValueError:
                    errors.append(f"produtos.csv linha {i}: preço não numérico")
                foto = (row.get("fotos") or "").strip()
                if foto and not (onboard_dir / "fotos" / foto).exists():
                    errors.append(f"produtos.csv linha {i}: foto não existe: fotos/{foto}")
                if is_prescription(name):
                    rx.append(name)
        if rx:
            log(f"⚠️ {len(rx)} produto(s) MSRM (receita) serão BLOQUEADOS (só OTC): {rx}", "WARN")
    return errors


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    args = ap.parse_args()
    errors = validate(Path(args.dir))
    if errors:
        log(f"{len(errors)} erro(s) de validação:", "ERROR")
        for e in errors:
            log(f"  - {e}", "ERROR")
        return 1
    log("Validação OK (ver avisos de MSRM acima, se existirem).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
