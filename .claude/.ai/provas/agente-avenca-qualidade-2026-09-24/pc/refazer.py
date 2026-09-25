#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Refaz o que o juiz chumbou, até haver 10 amostras prontas (agente-avenca-qualidade).

O juiz chumbou três: duas por terem uma cara identificável em primeiro plano e uma por a
composição ser amadora. Aqui tenta-se, por esta ordem:

  1. a MESMA casa com OUTRA foto dela (as fichas do Google trazem várias);
  2. se nenhuma foto dela passar, a casa sai da lista de amostras — fica no funil com o
     motivo escrito — e entra a melhor casa seguinte que ainda não foi usada.

Repete-se até haver 10 prontas ou acabarem os candidatos. Nenhuma amostra chumbada fica no
ar: a pasta é apagada.

Uso:  python refazer.py [--alvo 10]
"""
import argparse
import hashlib
import importlib.util
import io
import json
import os
import shutil
import sys
import time

BASE = os.path.dirname(os.path.abspath(__file__))
SITE = r"C:\BoraLocal\projetosflutter\bora-site"


def carregar(nome, ficheiro):
    spec = importlib.util.spec_from_file_location(nome, os.path.join(BASE, ficheiro))
    m = importlib.util.module_from_spec(spec)
    sys.modules[nome] = m
    sys.argv = [ficheiro]
    spec.loader.exec_module(m)
    return m


A = carregar("amostras2", "amostras2.py")
J = carregar("juiz", "juiz.py")
log = A.log


def token_de(fonte_id):
    return hashlib.sha256((fonte_id + "|avenca-bora-2026").encode()).hexdigest()[:14]


def construir(p, g, ordem_fotos=0):
    """Escreve a pasta da amostra. `ordem_fotos` roda qual foto vai para cada peça."""
    tok = token_de(p["fonte_id"])
    pasta = os.path.join(SITE, "avenca", tok)
    os.makedirs(pasta, exist_ok=True)
    fotos = A.baixar_fotos(g, tok, quantas=6)
    if not fotos:
        return None
    if ordem_fotos:
        fotos = fotos[ordem_fotos:] + fotos[:ordem_fotos]
    for i, f in enumerate(fotos[:3], 1):
        A.quadrado(f, 900).save(os.path.join(pasta, "foto%d.jpg" % i), "JPEG", quality=86)
    pecas = A.pecas_do_negocio(p, g, fotos, pasta, tok)
    io.open(os.path.join(pasta, "index.html"), "w", encoding="utf-8", newline="\n").write(
        A.pagina(p, g, pecas, min(3, len(fotos))))
    return {"nome": p["nome"], "token": tok, "pasta": pasta,
            "link": "https://boraguarda.com/avenca/%s/" % tok,
            "fotos": len(fotos), "pecas": pecas}


def julgar_pasta(nome, categoria, pasta):
    imagens = [os.path.join(pasta, "publicacao-%d.png" % i) for i in (1, 2)]
    imagens = [i for i in imagens if os.path.exists(i)]
    j, modelo = J.julgar(nome, categoria, imagens)
    if not j:
        return None, None, []
    return int(j.get("nota") or 0), modelo, (j.get("motivos") or [])


def registar(p, g, amostra, nota):
    ids = registar.ids
    pid = ids.get(p["fonte_id"])
    if not pid:
        return
    A.pedir("/rest/v1/rpc/prospect_amostra_registar", {
        "p_chave": A.E["PROSPECTS_KEY"], "p_prospect": pid,
        "p_linha": {"link_unico": amostra["link"], "mini_site": "avenca/%s/index.html" % amostra["token"],
                    "publicacoes": amostra["pecas"],
                    "diagnostico_google": dict(g, nota_do_juiz=nota)}})
    A.pedir("/rest/v1/rpc/prospect_proposta_registar", {
        "p_chave": A.E["PROSPECTS_KEY"], "p_prospect": pid,
        "p_linha": {"canal": "whatsapp" if g.get("telefone") else "presencial",
                    "assunto": "Fizemos isto para %s — vejam" % p["nome"],
                    "texto": A.proposta(p, g, amostra["link"]), "preco_mes_eur": A.PRECO}})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--alvo", type=int, default=10)
    a = ap.parse_args()

    linhas = json.load(io.open(os.path.join(BASE, "prospects.json"), encoding="utf-8"))
    fichas = json.load(io.open(os.path.join(BASE, "fichas_boas.json"), encoding="utf-8"))
    veredictos = json.load(io.open(os.path.join(BASE, "veredictos.json"), encoding="utf-8"))
    por_fonte = {l["fonte_id"]: l for l in linhas}
    por_token = {token_de(f): f for f in por_fonte}
    registar.ids = {l["fonte_id"]: l["id"] for l in
                    (A.pedir("/rest/v1/rpc/prospects_ler", {"p_chave": A.E["PROSPECTS_KEY"]}) or [])}

    prontas = {v["token"]: v for v in veredictos if v["estado"] == "pronta"}
    chumbadas = [v for v in veredictos if v["estado"] != "pronta"]
    usados = {v["token"] for v in veredictos}
    log("REFAZER: %d prontas, %d por resolver, alvo %d" % (len(prontas), len(chumbadas), a.alvo))

    # 1) segunda oportunidade, com outra foto da MESMA casa
    for v in chumbadas:
        fonte = por_token.get(v["token"])
        p, g = por_fonte.get(fonte), fichas.get(fonte)
        if not p or not g:
            continue
        resolvida = False
        for ordem in (1, 2):
            if ordem >= (g.get("n_fotos") or 1):
                break
            log("  %-22s outra foto (ordem %d)..." % (p["nome"][:22], ordem))
            am = construir(p, g, ordem_fotos=ordem)
            if not am:
                break
            nota, modelo, motivos = julgar_pasta(p["nome"], p.get("categoria") or "negócio", am["pasta"])
            log("     -> %s/100 %s" % (nota, "; ".join(motivos)[:80]))
            if nota and nota >= J.MINIMO:
                registar(p, g, am, nota)
                prontas[am["token"]] = dict(am, nota=nota, estado="pronta", motivos=motivos)
                resolvida = True
                break
            time.sleep(1)
        if not resolvida:
            pasta = os.path.join(SITE, "avenca", v["token"])
            if os.path.isdir(pasta):
                shutil.rmtree(pasta)
            if p:
                p["estado"] = "descartado"
                p["notas"] = ("Amostra chumbada pelo juiz de visao (%s/100): %s"
                              % (v.get("nota"), "; ".join(v.get("motivos") or [])))[:900]
                A.pedir("/rest/v1/rpc/prospect_registar", {"p_chave": A.E["PROSPECTS_KEY"], "p_linha": p})
            log("  %-22s SAI da lista (nenhuma foto passou)" % (p["nome"][:22] if p else "?"))

    # 2) completar com casas novas ate ao alvo
    pool = [l for l in linhas if l["fonte_id"] in fichas
            and fichas[l["fonte_id"]].get("telefone")
            and (fichas[l["fonte_id"]].get("n_fotos") or 0) >= 2
            and token_de(l["fonte_id"]) not in usados
            and l.get("estado") != "descartado"]
    pool.sort(key=lambda x: -(x.get("pontuacao") or 0))
    log("  candidatos por usar: %d" % len(pool))
    i = 0
    while len(prontas) < a.alvo and i < len(pool):
        p = pool[i]; i += 1
        g = fichas[p["fonte_id"]]
        log("  novo: %-22s" % p["nome"][:22])
        am = construir(p, g)
        if not am:
            continue
        nota, modelo, motivos = julgar_pasta(p["nome"], p.get("categoria") or "negócio", am["pasta"])
        log("     -> %s/100 %s" % (nota, "; ".join(motivos)[:80]))
        if nota and nota >= J.MINIMO:
            registar(p, g, am, nota)
            prontas[am["token"]] = dict(am, nota=nota, estado="pronta", motivos=motivos)
        else:
            shutil.rmtree(am["pasta"], ignore_errors=True)
            p["estado"] = "descartado"
            p["notas"] = ("Amostra chumbada pelo juiz de visao (%s/100): %s"
                          % (nota, "; ".join(motivos)))[:900]
            A.pedir("/rest/v1/rpc/prospect_registar", {"p_chave": A.E["PROSPECTS_KEY"], "p_linha": p})
        time.sleep(1)

    io.open(os.path.join(BASE, "prospects.json"), "w", encoding="utf-8").write(
        json.dumps(linhas, ensure_ascii=False, indent=1))
    finais = sorted(prontas.values(), key=lambda v: -(v.get("nota") or 0))
    io.open(os.path.join(BASE, "amostras_prontas.json"), "w", encoding="utf-8").write(
        json.dumps(finais, ensure_ascii=False, indent=1))
    log("FIM REFAZER: %d amostras prontas" % len(finais))
    for v in finais:
        log("  %3d  %-24s %s" % (v.get("nota") or 0, v["nome"][:24], v["link"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
