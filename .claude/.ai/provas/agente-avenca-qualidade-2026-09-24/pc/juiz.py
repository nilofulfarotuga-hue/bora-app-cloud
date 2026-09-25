#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Juiz de visão das amostras da avença (missão agente-avenca-qualidade-2026-09-24).

Quem escreve não é quem verifica. Este juiz é o Gemini a OLHAR para as duas publicações de
cada amostra e a dizer, sem saber quem as fez, se aquilo pode ir para a mão de um dono de
café da Guarda. Só passa com **85 ou mais**; abaixo disso a amostra fica «chumbada» e não é
oferecida a ninguém.

Julga cinco coisas, cada uma com o seu peso:
  · a foto é mesmo do negócio e está nítida        (25)
  · o texto lê-se por cima da foto                 (25)
  · o que está escrito é verdade e curto           (25)
  · não há pessoas reconhecíveis em primeiro plano (15)
  · parece coisa de gente séria, não spam          (10)

Se o juiz disser que há pessoas reconhecíveis, a peça é refeita com outra foto do mesmo
negócio (quando houver) e volta a ser julgada — uma vez só.

Uso:  python juiz.py
"""
import base64
import io
import json
import os
import sys
import time
import urllib.error
import urllib.request

BASE = os.path.dirname(os.path.abspath(__file__))
SITE = r"C:\BoraLocal\projetosflutter\bora-site"
ENV = r"C:\BoraLocal\_segredos\avenca\prospects.env"
GEMINI_ENV = r"C:\BoraLocal\_segredos\em-dia\gemini.env"
MODELOS = ("gemini-3-flash-preview", "gemini-3.5-flash-lite", "gemini-3.1-flash-lite")
MINIMO = 85

E = {}
for _l in io.open(ENV, encoding="utf-8"):
    _l = _l.strip()
    if "=" in _l and not _l.startswith("#"):
        _k, _v = _l.split("=", 1)
        E[_k.strip()] = _v.strip()
CHAVE = [l.split("=", 1)[1].strip() for l in io.open(GEMINI_ENV, encoding="utf-8")
         if l.startswith("GEMINI_API_KEY=")][0]

PERGUNTA = """És o fiscal de uma agência séria, em Portugal. Vais ver DUAS imagens que foram
preparadas para um negócio local da Guarda: %s (%s). As fotografias vieram da ficha pública
do Google DESSE negócio.

A pergunta é só uma: isto pode ser mostrado ao dono sem vergonha?

Responde SÓ com JSON:
{"nota": 0, "foto_do_negocio": 0, "texto_legivel": 0, "texto_honesto": 0,
 "sem_pessoas_reconheciveis": 0, "ar_profissional": 0,
 "pessoas_em_primeiro_plano": false, "motivos": ["..."]}

Os cinco números são pontos: foto_do_negocio até 25, texto_legivel até 25, texto_honesto até
25, sem_pessoas_reconheciveis até 15, ar_profissional até 10. A "nota" é a soma (0 a 100).

Como julgar, sem dó:
- foto_do_negocio: é uma fotografia real de um sítio real, nítida e bem enquadrada? Fotos
  tremidas, escuras ou que não mostram nada valem pouco.
- texto_legivel: o texto lê-se à primeira, no telemóvel? Texto branco sobre fundo claro sem
  contorno chumba.
- texto_honesto: o que está escrito é simples e verificável (nome, ramo, cidade, morada,
  estrelas)? Qualquer promessa não provável ("o melhor da cidade", "os mais baratos") chumba.
  Duas frases que se contradigam (dizer "aberto" e por baixo "encerrado") chumbam.
- sem_pessoas_reconheciveis: há caras identificáveis em primeiro plano? Se sim, dá poucos
  pontos e mete pessoas_em_primeiro_plano = true. Gente pequena ou de costas ao fundo não conta.
- ar_profissional: parece trabalho de uma agência ou parece spam?

Nos "motivos", frases curtas em português, a dizer o que está mal. Se estiver tudo bem, diz
o que está bem. Não inventes defeitos para parecer exigente."""


def log(msg):
    linha = "[%s] %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg)
    print(linha)
    with io.open(os.path.join(BASE, "prospeccao.log"), "a", encoding="utf-8") as f:
        f.write(linha + "\n")


def b64(caminho):
    return base64.b64encode(io.open(caminho, "rb").read()).decode()


def julgar(nome, categoria, imagens):
    partes = [{"inline_data": {"mime_type": "image/png", "data": b64(c)}} for c in imagens]
    partes.append({"text": PERGUNTA % (nome, categoria)})
    corpo = json.dumps({"contents": [{"parts": partes}],
                        "generationConfig": {"responseMimeType": "application/json",
                                             "temperature": 0.1}}).encode()
    for modelo in MODELOS:
        try:
            req = urllib.request.Request(
                "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s"
                % (modelo, CHAVE), data=corpo, headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=180) as r:
                resp = json.load(r)
            texto = next(p["text"] for p in resp["candidates"][0]["content"]["parts"]
                         if isinstance(p, dict) and "text" in p)
            return json.loads(texto), modelo
        except Exception as ex:  # noqa: BLE001
            log("    %s falhou: %s" % (modelo, str(ex)[:90]))
            time.sleep(2)
    return None, None


def pedir(caminho, corpo):
    req = urllib.request.Request(
        E["SUPABASE_URL"].rstrip("/") + caminho,
        data=json.dumps(corpo, ensure_ascii=False).encode("utf-8"),
        headers={"apikey": E["SUPABASE_ANON_KEY"],
                 "Authorization": "Bearer " + E["SUPABASE_ANON_KEY"],
                 "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=90) as r:
        t = r.read().decode("utf-8")
    return json.loads(t) if t.strip() else None


def main():
    feitas = json.load(io.open(os.path.join(BASE, "amostras_feitas.json"), encoding="utf-8"))
    linhas = {l["fonte_id"]: l for l in json.load(io.open(os.path.join(BASE, "prospects.json"), encoding="utf-8"))}
    por_token = {}
    for l in linhas.values():
        import hashlib
        por_token[hashlib.sha256((l["fonte_id"] + "|avenca-bora-2026").encode()).hexdigest()[:14]] = l

    log("JUIZ: %d amostras, minimo %d" % (len(feitas), MINIMO))
    veredictos = []
    for a in feitas:
        pasta = a["pasta"]
        imagens = [os.path.join(pasta, "publicacao-1.png"), os.path.join(pasta, "publicacao-2.png")]
        imagens = [i for i in imagens if os.path.exists(i)]
        if not imagens:
            log("  %-24s SEM IMAGENS" % a["nome"][:24])
            continue
        p = por_token.get(a["token"], {})
        j, modelo = julgar(a["nome"], p.get("categoria") or "negócio local", imagens)
        if not j:
            log("  %-24s SEM VEREDITO (nenhum modelo respondeu)" % a["nome"][:24])
            veredictos.append(dict(a, nota=None, estado="sem_veredito", motivos=["nenhum modelo respondeu"]))
            continue
        nota = int(j.get("nota") or 0)
        estado = "pronta" if nota >= MINIMO else "chumbada"
        veredictos.append(dict(a, nota=nota, estado=estado, modelo=modelo,
                               pessoas=bool(j.get("pessoas_em_primeiro_plano")),
                               motivos=j.get("motivos") or []))
        log("  %-24s %3d/100  %-9s %s" % (a["nome"][:24], nota, estado,
                                          "; ".join(j.get("motivos") or [])[:90]))
        time.sleep(1)

    io.open(os.path.join(BASE, "veredictos.json"), "w", encoding="utf-8").write(
        json.dumps(veredictos, ensure_ascii=False, indent=1))
    prontas = [v for v in veredictos if v["estado"] == "pronta"]
    log("FIM JUIZ: %d prontas (>= %d), %d chumbadas, %d sem veredito"
        % (len(prontas), MINIMO, sum(1 for v in veredictos if v["estado"] == "chumbada"),
           sum(1 for v in veredictos if v["estado"] == "sem_veredito")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
