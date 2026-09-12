"""Gera descrições PT-PT apetitosas (1-2 frases) para pratos sem descrição.

Estilo gastronómico: evocativo, sensorial, conciso. Ex.:
  "Bife do lombo grelhado no ponto, servido com batata a murro e legumes salteados."

Usa OpenAI se OPENAI_API_KEY estiver definida; caso contrário, fallback determinístico
(template a partir do nome). NUNCA inventa ingredientes que contradigam o nome.

Uso:
    python generate_descriptions.py --dir ".claude/.ai/onboard/belmonte-grill"
"""
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

from _shared import Ctx, log, read_pipeline_json, write_pipeline_json

SYSTEM_PROMPT = (
    "És copywriter gastronómico do Bora App (Portugal). Escreves em PT-PT. "
    "Dada o nome de um prato, devolves UMA descrição apetitosa de 1-2 frases, "
    "sensorial mas honesta, sem inventar ingredientes não implícitos, sem emojis, "
    "sem preço, máximo ~140 caracteres."
)


def _openai_describe(name: str, key: str) -> str | None:
    import requests
    try:
        r = requests.post(
            "https://api.openai.com/v1/chat/completions",
            headers={"Authorization": f"Bearer {key}"},
            json={
                "model": "gpt-4o-mini",
                "temperature": 0.7,
                "messages": [
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": f"Prato: {name}"},
                ],
            },
            timeout=30,
        )
        r.raise_for_status()
        return r.json()["choices"][0]["message"]["content"].strip().strip('"')
    except Exception as e:  # noqa: BLE001
        log(f"OpenAI falhou para '{name}' ({e}); fallback.", "WARN")
        return None


def _fallback(name: str) -> str:
    return f"{name.strip().capitalize()} — preparado na hora, com ingredientes frescos."


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    args = ap.parse_args()
    onboard_dir = Path(args.dir)
    ctx = Ctx.load()

    state = read_pipeline_json(onboard_dir)
    descriptions: dict[str, str] = {}

    with (onboard_dir / "produtos.csv").open(encoding="utf-8") as f:
        for row in csv.DictReader(f):
            name = (row.get("nome") or "").strip()
            if not name:
                continue
            existing = (row.get("descrição") or row.get("descricao") or "").strip()
            if existing:
                descriptions[name] = existing
                continue
            desc = (_openai_describe(name, ctx.openai_key) if ctx.openai_key else None)
            descriptions[name] = desc or _fallback(name)

    state["descriptions"] = descriptions
    write_pipeline_json(onboard_dir, state)
    log(f"{len(descriptions)} descrição(ões) geradas.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
