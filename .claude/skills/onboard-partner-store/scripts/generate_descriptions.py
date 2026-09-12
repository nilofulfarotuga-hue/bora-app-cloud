"""Gera descrições PT-PT estilo RETAIL (factual, especificações) por produto de loja.

Ex.: "Auriculares Bluetooth com cancelamento de ruído ativo e 30h de bateria."
Usa OpenAI se OPENAI_API_KEY definida; senão fallback determinístico.

Uso: python generate_descriptions.py --dir ".claude/.ai/onboard/worten-guarda"
"""
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

from _shared import Ctx, log, read_pipeline_json, write_pipeline_json

SYSTEM_PROMPT = (
    "És copywriter de retalho do Bora App (Portugal). Escreves em PT-PT. Dado o nome "
    "(e marca, se houver) de um produto, devolves UMA descrição factual de 1-2 frases "
    "com características-chave, sem inventar especificações não implícitas, sem emojis, "
    "sem preço, máximo ~140 caracteres."
)


def _openai(name: str, marca: str, key: str) -> str | None:
    import requests
    prompt = f"Produto: {name}" + (f" | Marca: {marca}" if marca else "")
    try:
        r = requests.post(
            "https://api.openai.com/v1/chat/completions",
            headers={"Authorization": f"Bearer {key}"},
            json={"model": "gpt-4o-mini", "temperature": 0.5,
                  "messages": [{"role": "system", "content": SYSTEM_PROMPT},
                               {"role": "user", "content": prompt}]},
            timeout=30,
        )
        r.raise_for_status()
        return r.json()["choices"][0]["message"]["content"].strip().strip('"')
    except Exception as e:  # noqa: BLE001
        log(f"OpenAI falhou para '{name}' ({e}); fallback.", "WARN")
        return None


def _fallback(name: str, marca: str) -> str:
    pref = f"{marca} " if marca else ""
    return f"{pref}{name.strip()} — disponível na loja, com entrega Bora."


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
            marca = (row.get("marca") or "").strip()
            existing = (row.get("descrição") or row.get("descricao") or "").strip()
            if existing:
                descriptions[name] = existing
                continue
            desc = (_openai(name, marca, ctx.openai_key) if ctx.openai_key else None)
            descriptions[name] = desc or _fallback(name, marca)
    state["descriptions"] = descriptions
    write_pipeline_json(onboard_dir, state)
    log(f"{len(descriptions)} descrição(ões) retail geradas.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
