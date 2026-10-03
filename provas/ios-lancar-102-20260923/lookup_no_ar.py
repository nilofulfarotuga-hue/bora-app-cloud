#!/usr/bin/env python3
"""Prova, refazivel, de que a App Store PT ja serve a 1.0.2.

Cicatriz (2026-09-23): a 1.0.2 foi aprovada a 22/09 as 22:44 UTC mas ficou em
PENDING_DEVELOPER_RELEASE (lancamento MANUAL) e a loja continuou a servir a 1.0.
Depois do POST /v1/appStoreVersionReleaseRequests, a API ja dizia
READY_FOR_SALE -- mas o READY_FOR_SALE e' o invólucro: quem manda para o
telemovel do cliente e' o que o lookup publico devolve. Por isso a prova sao
DUAS leituras, nao uma.

Corre-se assim:  python3 provas/ios-lancar-102-20260923/lookup_no_ar.py
Sai 0 se a loja servir a versao esperada, 1 se ainda nao (propagacao).
"""
import json
import sys
import time
import urllib.request
from datetime import datetime, timezone

APP_ID = "6809954739"
ESPERADA = "1.0.2"


def lookup(pais):
    # O t= e' anti-cache: sem ele a Apple devolve a versao antiga durante horas.
    url = "https://itunes.apple.com/lookup?id=%s&country=%s&t=%d" % (
        APP_ID, pais, int(time.time()))
    req = urllib.request.Request(url, headers={
        "Cache-Control": "no-cache",
        "User-Agent": "bora-proof/1.0",
    })
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.status, json.load(r)


def main():
    falhou = False
    for pais in ("pt", "br"):
        status, j = lookup(pais)
        res = (j.get("results") or [None])[0]
        if not res:
            print("[%s] HTTP %s mas resultCount=0" % (pais, status))
            falhou = True
            continue
        v = res.get("version")
        ok = (v == ESPERADA)
        falhou = falhou or not ok
        print("[%s] HTTP %s | version=%s (esperada %s) %s" % (
            pais, status, v, ESPERADA, "OK" if ok else "AINDA NAO"))
        print("      lancada em : %s" % res.get("currentVersionReleaseDate"))
        print("      nome       : %s" % res.get("trackName"))
        print("      categorias : %s" % ", ".join(res.get("genres") or []))
        print("      notas      : %s" % (res.get("releaseNotes") or "")[:110])
    print("lido em %s" % datetime.now(timezone.utc).isoformat())
    return 1 if falhou else 0


if __name__ == "__main__":
    sys.exit(main())
