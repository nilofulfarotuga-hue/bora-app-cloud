# -*- coding: utf-8 -*-
"""Cliente minimo da API do App Store Connect (chave de equipa "Bora iOS CI").

A chave .p8 vive no cofre local (~/.bora-cofre/apple) e NUNCA sai daqui; o
issuer e o key id nao sao segredos. Uso: importar e chamar get/patch/post.
"""
import json
import os
import time

import jwt
import requests

KEY_ID = "CL4QYYYP6A"
ISSUER = "212c88f0-850e-444b-bc57-8511d216d1f0"
P8 = os.path.join(os.path.expanduser("~"), ".bora-cofre", "apple", "AuthKey_%s.p8" % KEY_ID)
BASE = "https://api.appstoreconnect.apple.com"
APP = "6809954739"


def token():
    with open(P8, "r", encoding="utf-8") as f:
        chave = f.read()
    agora = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": agora, "exp": agora + 1100, "aud": "appstoreconnect-v1"},
                      chave, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})


def _h():
    return {"Authorization": "Bearer " + token(), "Content-Type": "application/json"}


def get(path, **params):
    r = requests.get(BASE + path, headers=_h(), params=params, timeout=60)
    try:
        j = r.json()
    except Exception:
        j = {"raw": r.text[:500]}
    return r.status_code, j


def patch(path, data):
    r = requests.patch(BASE + path, headers=_h(), data=json.dumps({"data": data}), timeout=60)
    try:
        j = r.json()
    except Exception:
        j = {"raw": r.text[:500]}
    return r.status_code, j


def post(path, data):
    r = requests.post(BASE + path, headers=_h(), data=json.dumps({"data": data}), timeout=60)
    try:
        j = r.json()
    except Exception:
        j = {"raw": r.text[:500]}
    return r.status_code, j
