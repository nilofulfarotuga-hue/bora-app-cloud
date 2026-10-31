#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
voz_cmd.py — o TTS do agente do Hermes (corre DENTRO do contentor, so biblioteca padrao).
O gateway chama-o como "provider por comando" (config.yaml: tts.providers.voz): le o texto de {input_path}, pede ao servidor de
voz do host (voz.py --servir) o audio do texto INTEIRO e escreve-o em {output_path} (OGG/Opus).
Se o servidor falhar, sai com erro (o gateway regista e o texto segue escrito; nunca silencio calado).
"""
import json
import sys
import urllib.request

URL = "http://172.16.1.1:8794/sintetizar"


def main():
    if len(sys.argv) < 3:
        print("uso: voz_cmd.py ENTRADA SAIDA", file=sys.stderr)
        return 2
    entrada, saida = sys.argv[1], sys.argv[2]
    with open(entrada, encoding="utf-8") as f:
        texto = f.read()
    req = urllib.request.Request(URL, data=json.dumps({"texto": texto}).encode("utf-8"),
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=175) as r:
            dados = r.read()
    except Exception as e:
        print("servidor de voz falhou: %s" % type(e).__name__, file=sys.stderr)
        return 1
    if not dados:
        print("servidor de voz devolveu vazio", file=sys.stderr)
        return 1
    with open(saida, "wb") as f:
        f.write(dados)
    return 0


if __name__ == "__main__":
    sys.exit(main())
