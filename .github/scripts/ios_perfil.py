# -*- coding: utf-8 -*-
"""Vai buscar o perfil de provisao "Bora App Store" a Apple e instala-o.

Porque existe (08/10/2026, C2 - notificacoes urgentes): ligar uma capacidade
no App ID invalida o perfil, e o segredo IOS_PROVISIONING_PROFILE_B64 ficava
com o perfil velho - o build passava a falhar na assinatura ate alguem trocar
o segredo a mao. Agora o CI pede o perfil ACTIVE a Apple em cada build.

Confere tambem que o perfil traz TODAS as chaves de ios/Runner/Runner.entitlements;
se faltar alguma (capacidade nao ligada no portal) falha aqui, com o nome da
chave, em vez de falhar 15 minutos depois no xcodebuild.

Usa a mesma chave de equipa do ios_publicar.py (ASC_KEY_ID, ASC_ISSUER_ID, ASC_P8).
Uso: python ios_perfil.py <destino.mobileprovision>
"""
import base64
import os
import plistlib
import re
import sys
import time

import jwt
import requests

BASE = "https://api.appstoreconnect.apple.com"
BUNDLE = "pt.boraapp.bora"
NOME = "Bora App Store"
ENTITLEMENTS = os.path.join(os.path.dirname(__file__), "..", "..", "ios", "Runner", "Runner.entitlements")


def _h():
    with open(os.environ["ASC_P8"], "r", encoding="utf-8") as f:
        chave = f.read()
    agora = int(time.time())
    tok = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": agora, "exp": agora + 1100,
                      "aud": "appstoreconnect-v1"}, chave, algorithm="ES256",
                     headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
    return {"Authorization": "Bearer " + tok}


def falhar(msg):
    print("::error::" + msg)
    sys.exit(1)


def main(destino):
    r = requests.get(BASE + "/v1/bundleIds", headers=_h(), timeout=60,
                     params={"filter[identifier]": BUNDLE, "include": "profiles", "limit[profiles]": 50})
    if r.status_code != 200:
        falhar("Apple respondeu %s ao pedir o App ID: %s" % (r.status_code, r.text[:300]))
    j = r.json()
    perfis = [i for i in j.get("included", []) if i["type"] == "profiles"
              and i["attributes"]["name"] == NOME
              and i["attributes"]["profileType"] == "IOS_APP_STORE"
              and i["attributes"]["profileState"] == "ACTIVE"]
    if not perfis:
        falhar('Nenhum perfil "%s" ACTIVE para %s na Apple.' % (NOME, BUNDLE))
    perfil = max(perfis, key=lambda p: p["attributes"]["expirationDate"])
    conteudo = base64.b64decode(perfil["attributes"]["profileContent"])

    xml = conteudo[conteudo.find(b"<?xml"):conteudo.find(b"</plist>") + len(b"</plist>")]
    dentro = plistlib.loads(xml).get("Entitlements", {})
    with open(ENTITLEMENTS, "rb") as f:
        pedidas = plistlib.load(f)
    faltam = [k for k in pedidas if k not in dentro]
    if faltam:
        falhar("O perfil da Apple nao traz: %s - ligar a capacidade no App ID." % ", ".join(faltam))

    with open(destino, "wb") as f:
        f.write(conteudo)
    uuid = re.search(rb"<key>UUID</key>\s*<string>([^<]+)</string>", xml)
    print("perfil %s (%s) instalado; expira %s; chaves conferidas: %s" % (
        NOME, uuid.group(1).decode() if uuid else "?", perfil["attributes"]["expirationDate"],
        ", ".join(pedidas)))


if __name__ == "__main__":
    main(sys.argv[1])
