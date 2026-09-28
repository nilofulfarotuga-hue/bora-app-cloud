# -*- coding: utf-8 -*-
"""Perfil App Store do Em Dia (com.boraguarda.emdia) criado pela API do App Store Connect.

Missao pc-fecho-2026-09-28. Porque existe: as chaves da Apple (certificado de distribuicao
e chave da API) so vivem como segredos DESTE repo; o repo em-dia-app nao as tem e o GitHub
nao deixa copia-las. O certificado e da mesma equipa, por isso serve para as duas apps --
so o perfil muda. Em vez de guardar um segundo perfil como segredo, cria-se um novo em
cada corrida, preso ao certificado do .p12 (casado pelo numero de serie).

Variaveis: ASC_KEY_ID, ASC_ISSUER_ID, ASC_P8, CERT_P12, CERT_PASSWORD, BUNDLE_ID,
PERFIL_SAIDA, GITHUB_RUN_ID.
"""
import base64
import os
import sys
import time

import jwt
import requests
from cryptography.hazmat.primitives.serialization import pkcs12

BASE = "https://api.appstoreconnect.apple.com"
BUNDLE = os.environ["BUNDLE_ID"]


def h():
    agora = int(time.time())
    tok = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": agora, "exp": agora + 1100,
                      "aud": "appstoreconnect-v1"}, open(os.environ["ASC_P8"]).read(),
                     algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
    return {"Authorization": "Bearer " + tok, "Content-Type": "application/json"}


def morre(msg, r=None):
    print("::error::" + msg + ("" if r is None else " (%s) %s" % (r.status_code, r.text[:400])))
    sys.exit(1)


# 1. numero de serie do certificado que esta no .p12
_, cert, _ = pkcs12.load_key_and_certificates(open(os.environ["CERT_P12"], "rb").read(),
                                              os.environ.get("CERT_PASSWORD", "").encode())
serie = cert.serial_number
print("certificado do .p12:", cert.subject.rfc4514_string(), "serie %X" % serie)

# 2. o mesmo certificado no App Store Connect
r = requests.get(BASE + "/v1/certificates", headers=h(), params={"limit": 200}, timeout=60)
if r.status_code != 200:
    morre("nao consegui listar certificados", r)
cid = next((c["id"] for c in r.json()["data"]
            if int(c["attributes"]["serialNumber"], 16) == serie), None)
if not cid:
    morre("o certificado do .p12 nao aparece no App Store Connect")
print("certificado no ASC:", cid)

# 3. o bundle id do Em Dia (o filtro da Apple e por prefixo: confirma-se o exacto)
r = requests.get(BASE + "/v1/bundleIds", headers=h(),
                 params={"filter[identifier]": BUNDLE, "limit": 200}, timeout=60)
if r.status_code != 200:
    morre("nao consegui listar bundle ids", r)
bid = next((b["id"] for b in r.json()["data"] if b["attributes"]["identifier"] == BUNDLE), None)
if not bid:
    morre("o bundle id %s nao existe nesta equipa" % BUNDLE)
print("bundle id:", bid)

# 4. perfil novo
nome = "Em Dia App Store CI %s" % os.environ.get("GITHUB_RUN_ID", int(time.time()))
r = requests.post(BASE + "/v1/profiles", headers=h(), timeout=60, json={"data": {
    "type": "profiles",
    "attributes": {"name": nome, "profileType": "IOS_APP_STORE"},
    "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}},
                      "certificates": {"data": [{"type": "certificates", "id": cid}]}}}})
if r.status_code >= 300:
    morre("nao consegui criar o perfil", r)
at = r.json()["data"]["attributes"]
open(os.environ["PERFIL_SAIDA"], "wb").write(base64.b64decode(at["profileContent"]))
print("perfil criado: %s (%s, expira %s)" % (at["name"], at["profileState"], at.get("expirationDate")))
