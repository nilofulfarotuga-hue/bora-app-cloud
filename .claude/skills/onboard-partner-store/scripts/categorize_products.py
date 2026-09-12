"""Categoriza produtos de LOJA em: electrónica / vestuário / casa / beleza / brinquedos / outros.

Regras de palavras-chave PT-PT (sem API). Respeita 'categoria_sugerida' do CSV se válida.
Default: 'outros'.

Uso: python categorize_products.py --dir ".claude/.ai/onboard/worten-guarda"
"""
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

from _shared import log, read_pipeline_json, write_pipeline_json

CATEGORIES = ["electrónica", "vestuário", "casa", "beleza", "brinquedos", "outros"]

KEYWORDS = {
    "electrónica": ["telemóvel", "telemovel", "smartphone", "portátil", "portatil",
                    "tablet", "auricular", "headphone", "tv", "televisão", "televisao",
                    "carregador", "cabo", "rato", "teclado", "monitor", "consola",
                    "câmara", "camara", "coluna", "bluetooth", "usb", "ssd", "router"],
    "vestuário": ["camisola", "t-shirt", "calças", "calcas", "casaco", "vestido",
                  "saia", "ténis", "tenis", "sapato", "meias", "boné", "bone",
                  "camisa", "blusa", "calção", "calcao", "fato", "roupa"],
    "casa": ["panela", "tacho", "lençol", "lencol", "toalha", "almofada", "candeeiro",
             "cadeira", "mesa", "prato", "copo", "talher", "edredão", "edredao",
             "cortina", "tapete", "aspirador", "ferro", "decoração", "decoracao"],
    "beleza": ["creme", "perfume", "maquilhagem", "batom", "champô", "champo",
               "shampoo", "máscara", "mascara", "verniz", "hidratante", "sérum",
               "serum", "gel de banho", "desodorizante", "esfoliante"],
    "brinquedos": ["brinquedo", "lego", "boneca", "puzzle", "jogo", "peluche",
                   "carrinho", "bola", "lança", "lego", "playmobil", "figura"],
}


def categorize(name: str) -> str:
    low = name.lower()
    for cat in ("electrónica", "vestuário", "casa", "beleza", "brinquedos"):
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
    log(f"Categorizado (loja): {counts}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
