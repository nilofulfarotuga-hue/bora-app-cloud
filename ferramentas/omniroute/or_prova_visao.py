#!/usr/bin/env python3
"""Prova de visao por nivel: um PNG 32x32 todo vermelho, pergunta a cor. Uso: or_prova_visao.py modelo..."""
import base64
import json
import struct
import sys
import time
import urllib.error
import urllib.request
import zlib


def png_vermelho(n=32):
    linha = b"\x00" + b"\xff\x00\x00" * n
    raw = linha * n
    def bloco(tipo, dados):
        return struct.pack(">I", len(dados)) + tipo + dados + struct.pack(">I", zlib.crc32(tipo + dados) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + bloco(b"IHDR", struct.pack(">IIBBBBB", n, n, 8, 2, 0, 0, 0))
            + bloco(b"IDAT", zlib.compress(raw)) + bloco(b"IEND", b""))


URL = "data:image/png;base64," + base64.b64encode(png_vermelho()).decode()
KEY = open("/opt/omniroute/.agentes.key").read().strip()
for m in sys.argv[1:]:
    corpo = {"model": m, "max_tokens": 300, "messages": [{"role": "user", "content": [
        {"type": "text", "text": "De que cor e esta imagem? Responde com uma palavra em portugues."},
        {"type": "image_url", "image_url": {"url": URL}}]}]}
    req = urllib.request.Request("http://127.0.0.1:20128/v1/chat/completions", data=json.dumps(corpo).encode(), method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", "Bearer " + KEY)
    req.add_header("X-OmniRoute-No-Cache", "true")
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            st, txt = r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        st, txt = e.code, e.read().decode()
    except Exception as e:
        st, txt = 0, str(e)
    try:
        resp = json.loads(txt)["choices"][0]["message"]["content"][:80]
    except Exception:
        resp = txt[:160]
    print(json.dumps({"pedido": m, "http": st, "ms": int((time.time() - t0) * 1000), "resposta": resp}, ensure_ascii=False))
