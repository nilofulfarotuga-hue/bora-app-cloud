"""Categoriza produtos de FARMÁCIA em:
medicamentos_otc / cosmetica / higiene / suplementos / bebés / outros.

Regras de palavras-chave PT-PT (sem API). Respeita 'categoria_sugerida' se válida.
Default: 'outros'.

Uso: python categorize_products.py --dir ".claude/.ai/onboard/wells-guarda"
"""
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

from _shared import log, read_pipeline_json, write_pipeline_json

CATEGORIES = ["medicamentos_otc", "cosmetica", "higiene", "suplementos", "bebés", "outros"]

KEYWORDS = {
    "medicamentos_otc": ["paracetamol", "ibuprofeno", "aspirina", "comprimido",
                         "xarope", "pastilha", "antigripal", "analgésico", "analgesico",
                         "antiácido", "antiacido", "ben-u-ron", "brufen", "soro",
                         "pomada", "gotas", "spray nasal", "descongestionante"],
    "cosmetica": ["creme", "sérum", "serum", "anti-rugas", "hidratante facial",
                  "protetor solar", "protector solar", "maquilhagem", "batom",
                  "esfoliante", "máscara facial", "mascara facial", "tónico", "tonico"],
    "higiene": ["champô", "champo", "gel de banho", "sabonete", "desodorizante",
                "pasta de dentes", "escova", "fio dental", "elixir", "papel higiénico",
                "fralda", "penso higiénico", "penso higienico", "toalhita"],
    "suplementos": ["vitamina", "magnésio", "magnesio", "ómega", "omega", "proteína",
                    "proteina", "colagénio", "colagenio", "suplemento", "multivitamínico",
                    "multivitaminico", "probiótico", "probiotico", "ferro", "cálcio", "calcio"],
    "bebés": ["bebé", "bebe", "infantil", "leite em pó", "leite em po", "biberão",
              "biberao", "chupeta", "creme muda fralda", "papa", "fralda bebé"],
}


def categorize(name: str) -> str:
    low = name.lower()
    for cat in ("medicamentos_otc", "suplementos", "bebés", "cosmetica", "higiene"):
        if any(k in low for k in KEYWORDS[cat]):
            return cat
    return "outros"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    args = ap.parse_args()
    onboard_dir = Path(args.dir)
    state = read_pipeline_json(onboard_dir)
    cats: dict[str, str] = {}
    with (onboard_dir / "produtos.csv").open(encoding="utf-8") as f:
        for row in csv.DictReader(f):
            name = (row.get("nome") or "").strip()
            if not name:
                continue
            suggested = (row.get("categoria_sugerida") or "").strip().lower()
            cats[name] = suggested if suggested in CATEGORIES else categorize(name)
    state["categories"] = cats
    write_pipeline_json(onboard_dir, state)
    counts = {c: sum(1 for v in cats.values() if v == c) for c in CATEGORIES}
    log(f"Categorizado (farmácia): {counts}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
