# -*- coding: utf-8 -*-
"""Fecha o comboio do iPhone sozinho, depois do `altool --upload-app`.

Missao `ios-lancar-102-2026-09-23`. Porque existe: a 1.0.2 foi APROVADA pela
Apple a 22/09 e mesmo assim a App Store continuou a servir a 1.0 durante um dia
inteiro, porque a versao tinha sido criada com lancamento MANUAL e faltava
alguem carregar num botao. O Android ja se publica sozinho; o iPhone passa a
fazer o mesmo.

O que faz, por esta ordem, e tudo lido de volta (nada se da por bom por um 201):
  1. espera que a build acabada de enviar apareca e fique VALID;
  2. escolhe o nome da proxima versao (maior versionString existente + 1 no
     patch) e reaproveita a versao editavel se ja houver uma;
  3. cria/poe a versao com releaseType = AFTER_APPROVAL -- e' ISTO que faz a
     app ir para a loja sozinha assim que a Apple aprovar;
  4. liga a build a essa versao;
  5. escreve "O que ha de novo" em cada idioma que a ficha tiver;
  6. submete para revisao (reviewSubmissions + item + submitted=true).

Nao toca em preco, disponibilidade por pais, nem no estatuto de comerciante.
Se alguma coisa nao estiver como devia, sai com codigo != 0 e diz porque.

Variaveis: ASC_KEY_ID, ASC_ISSUER_ID, ASC_APP_ID, ASC_P8 (caminho do .p8),
BUILD_NUMBER, e opcionalmente SUBMETER_REVISAO=0 para so preparar.
"""
import json
import os
import sys
import time

import jwt
import requests

BASE = "https://api.appstoreconnect.apple.com"
KEY_ID = os.environ["ASC_KEY_ID"]
ISSUER = os.environ["ASC_ISSUER_ID"]
P8 = os.environ["ASC_P8"]
APP = os.environ.get("ASC_APP_ID", "6809954739")
BUILD_NUMBER = os.environ["BUILD_NUMBER"]
SUBMETER = os.environ.get("SUBMETER_REVISAO", "1") != "0"
NOTAS = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                     "..", "..", "ios", "notas_de_versao.json")

# Estados em que a versao ainda se pode editar/submeter.
EDITAVEL = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
            "METADATA_REJECTED", "INVALID_BINARY"}


def _token():
    with open(P8, "r", encoding="utf-8") as f:
        chave = f.read()
    agora = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": agora, "exp": agora + 1100,
                       "aud": "appstoreconnect-v1"}, chave,
                      algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})


def _h():
    return {"Authorization": "Bearer " + _token(), "Content-Type": "application/json"}


def _resp(r):
    try:
        return r.status_code, r.json()
    except Exception:
        return r.status_code, {"raw": r.text[:500]}


def get(path, **params):
    return _resp(requests.get(BASE + path, headers=_h(), params=params, timeout=60))


def post(path, data):
    return _resp(requests.post(BASE + path, headers=_h(),
                               data=json.dumps({"data": data}), timeout=60))


def patch(path, data):
    return _resp(requests.patch(BASE + path, headers=_h(),
                                data=json.dumps({"data": data}), timeout=60))


def morre(msg):
    print("::error::" + msg)
    sys.exit(1)


def erro_apple(j):
    return "; ".join("%s: %s" % (e.get("title"), e.get("detail"))
                     for e in j.get("errors", [])) or json.dumps(j)[:300]


# -- 1. esperar a build ----------------------------------------------------
def esperar_build(minutos=40):
    """A Apple demora a processar o IPA. Sem VALID nao se liga nada."""
    limite = time.time() + minutos * 60
    visto = None
    while time.time() < limite:
        c, j = get("/v1/builds", **{"filter[app]": APP,
                                    "filter[version]": BUILD_NUMBER,
                                    "fields[builds]": "version,processingState,uploadedDate"})
        if c != 200:
            morre("nao consegui listar builds (%s): %s" % (c, erro_apple(j)))
        for b in j.get("data", []):
            estado = b["attributes"].get("processingState")
            if estado != visto:
                print("build %s: %s" % (BUILD_NUMBER, estado))
                visto = estado
            if estado == "VALID":
                return b["id"]
            if estado in ("INVALID", "FAILED"):
                morre("a build %s voltou %s da Apple - nao ha o que submeter."
                      % (BUILD_NUMBER, estado))
        if visto is None:
            print("build %s ainda nao apareceu no App Store Connect..." % BUILD_NUMBER)
        time.sleep(60)
    morre("passaram %d min e a build %s nao ficou VALID." % (minutos, BUILD_NUMBER))


# -- 2. que versao usar ----------------------------------------------------
def proximo_nome(nomes):
    """Nome superior ao maior que ja existe - a Apple recusa repetir ou descer."""
    def chave(v):
        partes = (v.split(".") + ["0", "0"])[:3]
        return tuple(int(p) if p.isdigit() else 0 for p in partes)
    maior = max(nomes, key=chave) if nomes else "1.0.0"
    a, b, c = (list(chave(maior)) + [0, 0, 0])[:3]
    return "%d.%d.%d" % (a, b, c + 1)


def versao_alvo():
    c, j = get("/v1/apps/%s/appStoreVersions" % APP,
               **{"fields[appStoreVersions]": "versionString,appStoreState,releaseType",
                  "limit": "50"})
    if c != 200:
        morre("nao consegui listar as versoes (%s): %s" % (c, erro_apple(j)))
    todas = j.get("data", [])
    for d in todas:
        print("versao existente:", d["attributes"].get("versionString"),
              d["attributes"].get("appStoreState"), d["attributes"].get("releaseType"))

    # Ja ha uma versao editavel? Reaproveita-se - criar outra dava 409.
    for d in todas:
        if d["attributes"].get("appStoreState") in EDITAVEL:
            print("reaproveito a versao editavel", d["attributes"]["versionString"])
            return d["id"], d["attributes"]["versionString"]

    nome = proximo_nome([d["attributes"]["versionString"] for d in todas])
    c, j = post("/v1/appStoreVersions", {
        "type": "appStoreVersions",
        "attributes": {"platform": "IOS", "versionString": nome,
                       "releaseType": "AFTER_APPROVAL"},
        "relationships": {"app": {"data": {"type": "apps", "id": APP}}},
    })
    if c >= 300:
        morre("nao consegui criar a versao %s (%s): %s" % (nome, c, erro_apple(j)))
    print("versao %s criada" % nome)
    return j["data"]["id"], nome


# -- 3. lancamento automatico ----------------------------------------------
def por_automatica(vid):
    c, j = patch("/v1/appStoreVersions/" + vid,
                 {"type": "appStoreVersions", "id": vid,
                  "attributes": {"releaseType": "AFTER_APPROVAL"}})
    if c >= 300:
        morre("nao consegui por releaseType=AFTER_APPROVAL (%s): %s" % (c, erro_apple(j)))
    c, j = get("/v1/appStoreVersions/" + vid,
               **{"fields[appStoreVersions]": "versionString,appStoreState,releaseType"})
    lido = j.get("data", {}).get("attributes", {})
    print("lido de volta:", json.dumps(lido, ensure_ascii=False))
    if lido.get("releaseType") != "AFTER_APPROVAL":
        morre("a Apple ficou com releaseType=%s - a app NAO se lancaria sozinha."
              % lido.get("releaseType"))


# -- 4. ligar a build ------------------------------------------------------
def ligar_build(vid, bid):
    c, j = patch("/v1/appStoreVersions/%s/relationships/build" % vid,
                 {"type": "builds", "id": bid})
    if c >= 300:
        morre("nao consegui ligar a build (%s): %s" % (c, erro_apple(j)))
    c, j = get("/v1/appStoreVersions/%s/build" % vid, **{"fields[builds]": "version"})
    lido = (j.get("data") or {}).get("attributes", {}).get("version")
    print("build ligada a versao:", lido)
    if lido != BUILD_NUMBER:
        morre("liguei a build mas a Apple devolveu %s em vez de %s."
              % (lido, BUILD_NUMBER))


# -- 5. "O que ha de novo" -------------------------------------------------
def escrever_notas(vid, nome):
    try:
        with open(NOTAS, "r", encoding="utf-8") as f:
            textos = json.load(f)
    except Exception as e:
        print("::warning::sem notas_de_versao.json (%s) - nao escrevo nada." % e)
        return
    padrao = textos.get("padrao", {})
    c, j = get("/v1/appStoreVersions/%s/appStoreVersionLocalizations" % vid,
               **{"fields[appStoreVersionLocalizations]": "locale,whatsNew"})
    if c != 200:
        morre("nao consegui ler as localizacoes (%s): %s" % (c, erro_apple(j)))
    locs = j.get("data", [])
    if not locs:
        print("::warning::a versao nao tem nenhum idioma - nada para escrever.")
        return
    for d in locs:
        loc = d["attributes"]["locale"]
        # pt-PT/pt-BR caem no portugues; o resto no ingles.
        texto = textos.get(loc) or padrao.get(
            "pt" if loc.lower().startswith("pt") else "en")
        if not texto:
            print("::warning::sem texto para o idioma %s - deixo como esta." % loc)
            continue
        texto = texto.replace("{versao}", nome)
        c, r = patch("/v1/appStoreVersionLocalizations/" + d["id"],
                     {"type": "appStoreVersionLocalizations", "id": d["id"],
                      "attributes": {"whatsNew": texto}})
        if c >= 300:
            morre("nao consegui escrever as notas em %s (%s): %s"
                  % (loc, c, erro_apple(r)))
    c, j = get("/v1/appStoreVersions/%s/appStoreVersionLocalizations" % vid,
               **{"fields[appStoreVersionLocalizations]": "locale,whatsNew"})
    for d in j.get("data", []):
        at = d["attributes"]
        print("notas %s -> %r" % (at["locale"], (at.get("whatsNew") or "")[:70]))


# -- 6. submeter para revisao ----------------------------------------------
def submeter(vid):
    """reviewSubmissions e' a via actual; appStoreVersionSubmissions e' a velha."""
    c, j = get("/v1/reviewSubmissions", **{"filter[app]": APP,
                                           "filter[state]": "READY_FOR_REVIEW",
                                           "fields[reviewSubmissions]": "state,platform"})
    aberta = (j.get("data") or [None])[0] if c == 200 else None
    if aberta:
        sid = aberta["id"]
        print("reaproveito a submissao aberta", sid)
    else:
        c, j = post("/v1/reviewSubmissions", {
            "type": "reviewSubmissions",
            "attributes": {"platform": "IOS"},
            "relationships": {"app": {"data": {"type": "apps", "id": APP}}},
        })
        if c >= 300:
            morre("nao consegui abrir a submissao (%s): %s" % (c, erro_apple(j)))
        sid = j["data"]["id"]
        print("submissao aberta:", sid)

    c, j = post("/v1/reviewSubmissionItems", {
        "type": "reviewSubmissionItems",
        "relationships": {
            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}},
            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}},
        },
    })
    if c >= 300 and "already" not in json.dumps(j).lower():
        morre("nao consegui por a versao na submissao (%s): %s" % (c, erro_apple(j)))
    print("versao metida na submissao")

    c, j = patch("/v1/reviewSubmissions/" + sid,
                 {"type": "reviewSubmissions", "id": sid,
                  "attributes": {"submitted": True}})
    if c >= 300:
        morre("nao consegui carregar em Submeter (%s): %s" % (c, erro_apple(j)))

    c, j = get("/v1/reviewSubmissions/" + sid,
               **{"fields[reviewSubmissions]": "state,submittedDate"})
    estado = j.get("data", {}).get("attributes", {})
    print("submissao lida de volta:", json.dumps(estado, ensure_ascii=False))
    if estado.get("state") in ("READY_FOR_REVIEW", None):
        morre("a submissao ficou em %s - NAO foi submetida." % estado.get("state"))


def main():
    bid = esperar_build()
    print("build VALID:", bid)
    vid, nome = versao_alvo()
    por_automatica(vid)
    ligar_build(vid, bid)
    escrever_notas(vid, nome)
    if not SUBMETER:
        print("SUBMETER_REVISAO=0 - versao %s pronta, mas nao submetida." % nome)
        return 0
    submeter(vid)
    print("")
    print("Versao %s submetida com lancamento automatico apos aprovacao." % nome)
    print("Quando a Apple aprovar, a App Store serve-a sozinha.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
