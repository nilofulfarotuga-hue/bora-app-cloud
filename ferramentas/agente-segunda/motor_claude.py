#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""motor_claude.py — pede texto ao Motor Bora: Claude Haiku 5.5 (credito da API) primeiro, rotacao gratis depois.

Missao sistema-conteudo-14-11, bloco 5.2. O Motor Bora (servico motor-bora, 127.0.0.1:8792 no host) ja tem o
porteiro do credito do Claude: `perfil:claude-so-volume` = so Claude Haiku 5.5 (claude-haiku-5-5), sem reserva;
`perfil:volume` = a rotacao gratis que o radar-ia ja usa (radar_motor.py). Primeiro um, se falhar o outro.
O material que aqui passa e interno (caixa, radar, propostas); nunca dados de clientes.
"""
import json
import os
import urllib.request

URL = os.environ.get("MOTOR_URL", "http://127.0.0.1:8792/v1/chat/completions")
PERFIS = [p for p in os.environ.get("MOTOR_PERFIS", "perfil:claude-so-volume,perfil:volume").split(",") if p]


def pedir(prompt, max_tokens=1500, origem="agente-segunda", minimo=20):
    """-> (texto, modelo, perfil, tentativas). Levanta RuntimeError se todos falharem."""
    tentativas = []
    for perfil in PERFIS:
        corpo = json.dumps({"model": perfil, "messages": [{"role": "user", "content": prompt}],
                            "max_tokens": max_tokens, "temperature": 0.2}).encode("utf-8")
        req = urllib.request.Request(URL, data=corpo, headers={"Content-Type": "application/json",
                                                               "X-Motor-Origem": origem})
        try:
            with urllib.request.urlopen(req, timeout=240) as r:
                j = json.load(r)
            txt = (((j.get("choices") or [{}])[0].get("message") or {}).get("content") or "").strip()
            if len(txt) >= minimo:
                tentativas.append("%s: ok (%s)" % (perfil, j.get("model")))
                return txt, j.get("model"), perfil, tentativas
            tentativas.append("%s: curto (%d letras, %s)" % (perfil, len(txt), j.get("model")))
        except Exception as e:  # noqa: BLE001
            tentativas.append("%s: %s" % (perfil, str(e)[:120]))
    raise RuntimeError("todos os motores falharam: " + " | ".join(tentativas))


def json_de(txt):
    """Primeiro bloco JSON (lista ou objeto) dentro do texto do modelo."""
    t = txt.strip()
    if t.startswith("```"):
        t = t.strip("`")
        t = t[t.find("\n") + 1:] if "\n" in t else t
    for a, b in (("[", "]"), ("{", "}")):
        i, k = t.find(a), t.rfind(b)
        if i != -1 and k > i:
            try:
                return json.loads(t[i:k + 1])
            except ValueError:
                continue
    raise ValueError("sem JSON na resposta: " + txt[:200])


if __name__ == "__main__":
    import sys
    print(pedir(sys.argv[1] if len(sys.argv) > 1 else "Responde so: ok, motor vivo.", 50, minimo=2))
