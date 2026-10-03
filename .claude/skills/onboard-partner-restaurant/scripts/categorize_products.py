"""Categoriza pratos de restaurante em: entrada / principal / sobremesa / bebida.

Regras de palavras-chave PT-PT (sem API, determinístico). Precedência:
bebida > sobremesa > entrada > principal (default). Respeita 'categoria_sugerida'
do CSV se já preenchida.

Uso:
    python categorize_products.py --dir ".claude/.ai/onboard/belmonte-grill"
"""
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

from _shared import log, read_pipeline_json, write_pipeline_json

CATEGORIES = ["entrada", "principal", "sobremesa", "bebida"]

KEYWORDS = {
    "bebida": ["água", "agua", "sumo", "refrigerante", "cerveja", "vinho", "café",
               "cafe", "chá", "cha", "coca", "ice tea", "bebida", "imperial", "fino",
               "sangria", "gin", "whisky", "licor", "batido", "smoothie"],
    "sobremesa": ["sobremesa", "mousse", "bolo", "tarte", "gelado", "pudim", "doce",
                  "panqueca", "cheesecake", "brownie", "fruta", "salada de fruta",
                  "leite-creme", "arroz doce", "baba de camelo"],
    "entrada": ["entrada", "sopa", "couvert", "petisco", "rissol", "croquete",
                "bolinho", "pataniscas", "amêijoas", "ameijoas", "tábua", "tabua",
                "queijo", "presunto", "azeitonas", "pão", "pao", "starter", "salada"],
}


def categorize(name: str) -> str:
    low = name.lower()
    for cat in ("bebida", "sobremesa", "entrada"):
        if any(k in low for k in KEYWORDS[cat]):
            return cat
    return "principal"


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
    log(f"Categorizado: {counts}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
