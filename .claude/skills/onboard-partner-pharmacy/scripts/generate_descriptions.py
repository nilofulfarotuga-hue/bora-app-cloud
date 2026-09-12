"""Gera descrições PT-PT informativas para produtos de farmácia — SEM claims médicas.

Ex.: "Paracetamol 500 mg, 20 comprimidos. Tomar conforme indicação."
Acrescenta SEMPRE o disclaimer obrigatório no fim.
Usa OpenAI se OPENAI_API_KEY definida; senão fallback determinístico.

Uso: python generate_descriptions.py --dir ".claude/.ai/onboard/wells-guarda"
"""
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

from _shared import Ctx, log, read_pipeline_json, write_pipeline_json

DISCLAIMER = "Em caso de dúvida, consulte o farmacêutico."

SYSTEM_PROMPT = (
    "És redator de uma farmácia em Portugal. Escreves em PT-PT. Dado o nome de um "
    "produto OTC (venda livre), devolves UMA descrição informativa e factual de 1-2 "
    "frases (dosagem/quantidade/uso geral), SEM alegações terapêuticas, SEM promessas "
    "de cura, SEM emojis, SEM preço, máximo ~140 caracteres. NÃO incluas disclaimer "
    "(é adicionado automaticamente)."
)


def _openai(name: str, key: str) -> str | None:
    import requests
    try:
        r = requests.post(
            "https://api.openai.com/v1/chat/completions",
            headers={"Authorization": f"Bearer {key}"},
            json={"model": "gpt-4o-mini", "temperature": 0.3,
                  "messages": [{"role": "system", "content": SYSTEM_PROMPT},
                               {"role": "user", "content": f"Produto: {name}"}]},
            timeout=30,
        )
        r.raise_for_status()
        return r.json()["choices"][0]["message"]["content"].strip().strip('"')
    except Exception as e:  # noqa: BLE001
        log(f"OpenAI falhou para '{name}' ({e}); fallback.", "WARN")
        return None


def _fallback(name: str) -> str:
    return f"{name.strip()}. Leia o folheto informativo antes de utilizar."


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
            base = existing or (_openai(name, ctx.openai_key) if ctx.openai_key else None) or _fallback(name)
            # garante disclaimer único no fim
            descriptions[name] = base if DISCLAIMER in base else f"{base} {DISCLAIMER}"
    state["descriptions"] = descriptions
    write_pipeline_json(onboard_dir, state)
    log(f"{len(descriptions)} descrição(ões) geradas (com disclaimer).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
