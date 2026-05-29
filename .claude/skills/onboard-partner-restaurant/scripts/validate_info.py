"""Valida info.yaml + produtos.csv de um restaurante parceiro.

Regras (alinhadas com a Edge Fn register-partner — ver bora-knowledge 08):
- NIF: 9 dígitos com check-digit mód-11 (primeiro dígito 1/2/3/5/6/8/9).
- IBAN: ^PT\\d{21}$ (23 chars) + validação mód-97.  ⚠️ NÃO é PT50.
- Email: regex padrão. Telefone PT: ^\\+?351?[29]\\d{8}$.
- Coordenadas (se presentes): lat 36.9–42.2, lng -9.6…-6.2 (continente PT).
- info.yaml: chaves obrigatórias preenchidas.
- produtos.csv: nome ≠ vazio, preço numérico > 0, ficheiro de foto existe.

Uso:
    python validate_info.py --dir ".claude/.ai/onboard/belmonte-grill"
Devolve exit 0 se válido, 1 se houver erros (lista impressa).
"""
from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path

import yaml  # type: ignore

from _shared import log

EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
PHONE_PT_RE = re.compile(r"^\+?351?[29]\d{8}$")
IBAN_PT_RE = re.compile(r"^PT\d{21}$")

REQUIRED_KEYS = ["name", "category", "address", "phone", "email"]
VALID_CATEGORIES = {"restaurante", "restaurant"}  # esta skill: restaurante


def valid_nif(nif: str) -> bool:
    if not re.fullmatch(r"\d{9}", nif or ""):
        return False
    if nif[0] not in "12356889":
        return False
    digits = [int(d) for d in nif]
    s = sum(digits[i] * (9 - i) for i in range(8))
    check = (11 - (s % 11)) % 11
    check = 0 if check == 10 else check
    return digits[8] == check


def valid_iban_pt(iban: str) -> bool:
    iban = (iban or "").upper().replace(" ", "")
    if not IBAN_PT_RE.match(iban):
        return False
    rearr = iban[4:] + iban[:4]
    num = "".join(str(int(c, 36)) for c in rearr)  # letras → números
    return int(num) % 97 == 1


def validate(onboard_dir: Path) -> list[str]:
    errors: list[str] = []
    info_path = onboard_dir / "info.yaml"
    if not info_path.exists():
        return [f"info.yaml não encontrado em {onboard_dir}"]

    data = yaml.safe_load(info_path.read_text(encoding="utf-8")) or {}
    r = data.get("restaurant", data)  # aceita raiz ou sob 'restaurant:'

    for key in REQUIRED_KEYS:
        if not str(r.get(key, "")).strip():
            errors.append(f"info.yaml: campo obrigatório vazio: {key}")

    if str(r.get("category", "")).lower() not in VALID_CATEGORIES:
        errors.append("info.yaml: category deve ser 'restaurante' nesta skill")

    if r.get("email") and not EMAIL_RE.match(str(r["email"])):
        errors.append(f"info.yaml: email inválido: {r['email']}")
    if r.get("phone") and not PHONE_PT_RE.match(str(r["phone"]).replace(" ", "")):
        errors.append(f"info.yaml: telefone PT inválido: {r['phone']}")
    if r.get("nif") and not valid_nif(str(r["nif"])):
        errors.append(f"info.yaml: NIF inválido (9 dígitos mód-11): {r['nif']}")
    if r.get("iban") and not valid_iban_pt(str(r["iban"])):
        errors.append(f"info.yaml: IBAN inválido (^PT+21 dígitos, mód-97): {r['iban']}")

    lat, lng = r.get("lat"), r.get("lng")
    if lat is not None and not (36.9 <= float(lat) <= 42.2):
        errors.append(f"info.yaml: lat fora do continente PT: {lat}")
    if lng is not None and not (-9.6 <= float(lng) <= -6.2):
        errors.append(f"info.yaml: lng fora do continente PT: {lng}")

    for asset in ("logo", "capa"):
        if not any((onboard_dir / f"{asset}{ext}").exists()
                   for ext in (".png", ".jpg", ".jpeg")):
            errors.append(f"imagem obrigatória em falta: {asset}.(png|jpg)")

    csv_path = onboard_dir / "produtos.csv"
    if not csv_path.exists():
        errors.append("produtos.csv não encontrado")
    else:
        with csv_path.open(encoding="utf-8") as f:
            for i, row in enumerate(csv.DictReader(f), start=2):
                if not (row.get("nome") or "").strip():
                    errors.append(f"produtos.csv linha {i}: nome vazio")
                try:
                    if float(str(row.get("preço", row.get("preco", "0"))).replace(",", ".")) <= 0:
                        errors.append(f"produtos.csv linha {i}: preço deve ser > 0")
                except ValueError:
                    errors.append(f"produtos.csv linha {i}: preço não numérico")
                foto = (row.get("fotos") or "").strip()
                if foto and not (onboard_dir / "fotos" / foto).exists():
                    errors.append(f"produtos.csv linha {i}: foto não existe: fotos/{foto}")
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
    log("Validação OK.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
