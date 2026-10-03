# -*- coding: utf-8 -*-
"""Semeia o pending.trigger do heartbeat-desktop com a frase fixa de "fila vazia".

Chamado por fila-vazia-wake.cmd, que por sua vez e chamado pelo carteiro.sh (VPS) via
ponte SSH na transicao ocupado->vazio da fila de orquestracao (ver carteiro.sh, bloco
"FILA VAZIA / TERMINAL LIMPO"). O ficheiro pending.trigger e consumido pelo operador
existente (desktop-send.py, Peca 2 do heartbeat-desktop) -- reutiliza-se o mecanismo
ja testado (foco de janela + clipboard + Enter) em vez de duplicar logica de automacao.

Nao ha dependencia de rede/Supabase aqui (ao contrario do heartbeat-browser.py) -- o
evento "fila vazia" ja foi decidido no carteiro.sh, este script so escreve o pedido.
"""
import json
import time
from pathlib import Path

REPO = Path(r"C:\Users\danil\Desktop\projetosflutter\bora_app")
HB_BROWSER = REPO / ".claude" / ".ai" / "hermes" / "heartbeat-browser"
TRIGGER = HB_BROWSER / "pending.trigger"

FRASE = (
    "Bora Loop: fila vazia. Revisa o que correu (cortex_ler + SELECT no Supabase), "
    "dispara o que falta ou resume o que foi feito."
)


def main():
    HB_BROWSER.mkdir(parents=True, exist_ok=True)
    payload = {
        "criado": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "motivo": ["fila_vazia_evento_carteiro"],
        "acao": "abrir o app Claude (PWA) e colar a frase, enviar",
        "frase": FRASE,
    }
    TRIGGER.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"pending.trigger semeado (fila vazia) -> {TRIGGER}")


if __name__ == "__main__":
    main()
