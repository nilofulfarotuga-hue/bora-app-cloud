#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""lojas_permitidas.py -- a regra unica de que lojas podem aparecer nas redes.

Escrito 2026-10-27 (missao redes-coming-soon-2026-10-27). CICATRIZ: a 26/10 o
story das 19:30 publicou outra vez a Barbearia Ouro e Prata, que esta em
coming_soon=true desde 25/09 e proibida nas redes por ordem do Danilo de 05/10.
A frase vinha de uma lista fixa no social-story.sh e ninguem perguntava a base
se a loja ainda estava aberta.

A regra, igual para story, loja do dia, reel, carrossel, formato extra e grupos:
  1. so entram lojas com coming_soon=false, is_active_admin=true e
     approval_status=approved, lidas no Supabase NA HORA (restaurants e
     service_providers);
  2. e que nao estejam na lista fixa EXCLUIR (abaixo), mesmo que a base as de
     como abertas;
  3. se o Supabase nao responder, NAO sai peca de loja nesse dia (texto
     generico, sem loja, pode sair).

B8 (2026-11-01, missao stories-em-breve-2026-11-01): a 01/11 o Danilo viu
"lojas em breve" nas stories. A decisao de "permitida" passou a vir da RPC
public.social_lojas_permitidas() (Supabase, chave anonima), que ja tira
coming_soon, inativas, nao aprovadas, demo e restaurantes SEM produtos
disponiveis. As tabelas continuam a ser lidas so para saber os NOMES de
todas as lojas (para apanhar uma loja bloqueada citada num texto). Se a RPC
ou as tabelas nao responderem: codigo 4, nao sai peca de loja.

Uso na linha de comandos (codigos de saida: 0 permitida, 3 bloqueada, 4 o
Supabase nao respondeu -- e 4 tambem bloqueia):
  lojas_permitidas.py --verificar|--verifica <id> [--tabela restaurants|service_providers]
  lojas_permitidas.py --texto "frase da peca"
  lojas_permitidas.py --filtrar-fotos < lista.txt   (imprime so as permitidas)
  lojas_permitidas.py --exclusoes                   (lista fixa, lida de volta)
  lojas_permitidas.py --listar                      (todas, PERMITIDA/BLOQUEADA e motivo)
  lojas_permitidas.py --lista                       (so as permitidas: id | nome | tipo | produtos)
"""
import argparse
import json
import os
import re
import sys
import unicodedata
import urllib.request

RAIZ = os.path.dirname(os.path.abspath(__file__))
REGISTO = os.path.join(RAIZ, "parceiros-fotos.json")

# Lista fixa de exclusao. So o Danilo manda tirar uma loja daqui.
EXCLUIR = {
    "82e3162c-0560-443a-a44a-104dc71a95ef": "Barbearia Ouro e Prata (proibida nas redes, ordem do Danilo 05/10)",
    "mr-kebab-grd1": "Mr Kebab (id escrito na ordem de 27/10)",
    "mrkebab-guarda": "Mr Kebab (id real na base)",
    "boom-burger-guarda": "Boom! Burger (ate o Danilo mandar abrir)",
}

OK, BLOQUEADA, SEM_RESPOSTA = 0, 3, 4
TABELAS = ("restaurants", "service_providers")


class SemResposta(Exception):
    pass


def sem_acentos(s):
    s = unicodedata.normalize("NFD", s or "")
    return "".join(c for c in s if unicodedata.category(c) != "Mn").lower()


def _env():
    url = os.environ.get("SUPABASE_URL", "")
    key = os.environ.get("SUPABASE_ANON_KEY", "")
    if not url or not key:
        raise SemResposta("SUPABASE_URL/SUPABASE_ANON_KEY nao carregadas")
    return url, key


_CACHE = None
RPC = "social_lojas_permitidas"


def rpc_permitidas():
    """{id: linha da RPC} -- so as lojas que podem sair nas redes agora."""
    url, key = _env()
    req = urllib.request.Request(
        "%s/rest/v1/rpc/%s" % (url, RPC), data=b"{}", method="POST",
        headers={"apikey": key, "Authorization": "Bearer " + key,
                 "Content-Type": "application/json"})
    try:
        linhas = json.load(urllib.request.urlopen(req, timeout=30))
    except Exception as e:  # rede, 401, 404, 5xx, JSON partido
        raise SemResposta("rpc %s: %s" % (RPC, e))
    if not isinstance(linhas, list) or not linhas:
        raise SemResposta("rpc %s veio vazia" % RPC)
    return {str(x.get("id")): x for x in linhas}


def lojas_vivas():
    """{id: {tabela, nome, permitida, motivo}} lido agora no Supabase."""
    global _CACHE
    if _CACHE is not None:
        return _CACHE
    url, key = _env()
    rpc = rpc_permitidas()
    vivas = {}
    for t in TABELAS:
        req = urllib.request.Request(
            "%s/rest/v1/%s?select=id,name,category,coming_soon,is_active_admin,approval_status" % (url, t),
            headers={"apikey": key, "Authorization": "Bearer " + key})
        try:
            linhas = json.load(urllib.request.urlopen(req, timeout=30))
        except Exception as e:  # rede, 401, 5xx, JSON partido
            raise SemResposta("%s: %s" % (t, e))
        if not isinstance(linhas, list) or not linhas:
            raise SemResposta("%s veio vazia" % t)
        for r in linhas:
            i = str(r.get("id"))
            motivo = ""
            if i in EXCLUIR:
                motivo = "lista de exclusao: " + EXCLUIR[i]
            elif r.get("coming_soon") is not False:
                motivo = "coming_soon=%s" % r.get("coming_soon")
            elif r.get("is_active_admin") is not True:
                motivo = "is_active_admin=%s" % r.get("is_active_admin")
            elif r.get("approval_status") != "approved":
                motivo = "approval_status=%s" % r.get("approval_status")
            elif i not in rpc:
                motivo = "fora da RPC %s (demo ou sem produtos disponiveis)" % RPC
            vivas[i] = dict(tabela=t, nome=r.get("name") or "", permitida=not motivo, motivo=motivo,
                            categoria=r.get("category") or "",
                            produtos=(rpc.get(i) or {}).get("produtos_disponiveis"))
    # a RPC manda: uma loja que ela devolve e as tabelas nao (nao devia
    # acontecer) nao entra -- so o que as duas confirmam sai nas redes.
    _CACHE = vivas
    return vivas


def verificar(slug, tabela=None):
    """(codigo, motivo)."""
    if slug in EXCLUIR:
        return BLOQUEADA, "lista de exclusao: " + EXCLUIR[slug]
    try:
        v = lojas_vivas()
    except SemResposta as e:
        return SEM_RESPOSTA, "Supabase nao respondeu (%s); hoje nao sai peca de loja" % e
    r = v.get(slug)
    if r is None or (tabela and r["tabela"] != tabela):
        return BLOQUEADA, "%s nao existe em %s" % (slug, tabela or "restaurants/service_providers")
    if not r["permitida"]:
        return BLOQUEADA, "%s (%s): %s" % (r["nome"], slug, r["motivo"])
    return OK, "%s (%s) permitida" % (r["nome"], slug)


def _registo():
    try:
        with open(REGISTO, encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return {"parceiros": []}


def _tem(alias, t):
    a = sem_acentos(alias).strip()
    return len(a) >= 4 and re.search(r"(?<![a-z0-9])%s(?![a-z0-9])" % re.escape(a), t)


def lojas_no_texto(texto, vivas=None):
    """Ids das lojas de que o texto fala (aliases do registo + nomes da base)."""
    t = sem_acentos(texto)
    achadas = set()
    for p in _registo().get("parceiros", []):
        if any(_tem(a, t) for a in [p.get("nome", "")] + p.get("aliases", [])):
            achadas.add(p["slug"])
    for i, r in (vivas or {}).items():
        if _tem(r["nome"], t):
            achadas.add(i)
    # nomes das excluidas sempre reconhecidos, mesmo sem base
    for i, nomes in (("82e3162c-0560-443a-a44a-104dc71a95ef", ["ouro e prata"]),
                     ("mrkebab-guarda", ["mr kebab", "mrkebab"]),
                     ("boom-burger-guarda", ["boom burger", "boom! burger"])):
        if any(_tem(n, t) for n in nomes):
            achadas.add(i)
    return achadas


def verificar_texto(texto):
    try:
        vivas = lojas_vivas()
    except SemResposta as e:
        vivas = None
        erro = str(e)
    lojas = lojas_no_texto(texto, vivas)
    if not lojas:
        return OK, "texto generico (nao fala de nenhuma loja)"
    for i in sorted(lojas):
        if i in EXCLUIR:
            return BLOQUEADA, "o texto fala de %s -- lista de exclusao: %s" % (i, EXCLUIR[i])
    if vivas is None:
        return SEM_RESPOSTA, "o texto fala de %s e o Supabase nao respondeu (%s)" % (", ".join(sorted(lojas)), erro)
    for i in sorted(lojas):
        c, m = verificar(i)
        if c != OK:
            return c, "o texto fala de " + m
    return OK, "o texto fala de %s, todas permitidas" % ", ".join(sorted(lojas))


# B8 (2026-11-01): logos de parceiro que as pecas antigas levam colados (talao
# <peca>.colagens.json, "logo do parceiro"). CICATRIZ: as folhas
# saidas/carrossel-2026-09-06-*-03-barbearia.jpg levam o logo da Barbearia Ouro
# e Prata (parceiros/barbearia-logo.png) e estavam na biblioteca dos grupos com
# nome "generico" para o portao -- passavam.
LOGOS = {
    "barbearia-logo": "82e3162c-0560-443a-a44a-104dc71a95ef",
    "goola-logo": "goola-acai-guarda",
    "sabores-logo": "sabores-brasil-guarda",
    "sabores-de-casa-logo": "12aa2cbb-01bd-443b-a17e-633c169d4864",
}


def dono_pelas_colagens(caminho):
    """Id do parceiro cujo logo esta colado na peca (pelo talao), ou None."""
    for c in (caminho, os.path.join(RAIZ, caminho)):
        try:
            with open(c + ".colagens.json", encoding="utf-8") as fh:
                itens = json.load(fh).get("itens", [])
            break
        except Exception:
            itens = None
    for it in itens or []:
        if "parceiro" not in (it.get("tipo") or ""):
            continue
        base = os.path.splitext(os.path.basename(it.get("ficheiro") or ""))[0]
        if base in LOGOS:
            return LOGOS[base]
        if base.startswith("logo-") and len(base) > 5:  # loja do dia: tmp/logo-<slug>.img
            return base[5:]
        for p in _registo().get("parceiros", []):
            if any(base.startswith(pref) for pref in p.get("prefixos", [])):
                return p["slug"]
        return "parceiro-desconhecido:" + base
    return None


def dono_da_foto(caminho, vivas=None):
    """Id da loja a que a foto pertence, 'generica', ou None (nao se sabe)."""
    pelo_talao = dono_pelas_colagens(caminho or "")
    if pelo_talao:
        return pelo_talao
    nome = os.path.basename(caminho or "")
    real = os.path.abspath(caminho or "")
    if nome.startswith("generico-") or "/frames-categorias/" in real:
        return "generica"
    for p in _registo().get("parceiros", []):
        for pasta in p.get("pastas", []):
            if real.startswith(os.path.abspath(os.path.join(RAIZ, pasta)) + os.sep):
                return p["slug"]
        for pref in p.get("prefixos", []):
            if nome.startswith(pref):
                return p["slug"]
    for i in sorted((vivas or {}), key=len, reverse=True):
        if nome.startswith(i + "-") or nome.startswith(i + "."):
            return i
    for i in EXCLUIR:
        if nome.startswith(i):
            return i
    return None


def filtrar_fotos(caminhos):
    """Fica so com as fotos que podem sair. Sem base: so as genericas."""
    try:
        vivas = lojas_vivas()
    except SemResposta:
        vivas = None
    saida = []
    for c in caminhos:
        dono = dono_da_foto(c, vivas)
        if dono == "generica":
            saida.append(c)
        elif vivas is None:
            continue  # sem base nao sai nada que possa ser de uma loja
        elif dono is None or verificar(dono)[0] == OK:
            saida.append(c)
    return saida, vivas is not None


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--verificar", "--verifica", dest="verificar", metavar="ID")
    g.add_argument("--texto")
    g.add_argument("--filtrar-fotos", action="store_true")
    g.add_argument("--exclusoes", action="store_true")
    g.add_argument("--listar", action="store_true")
    g.add_argument("--lista", action="store_true")
    ap.add_argument("--tabela", choices=TABELAS)
    a = ap.parse_args()

    if a.exclusoes:
        for i, m in EXCLUIR.items():
            print("%s | %s" % (i, m))
        return OK
    if a.lista:
        try:
            v = lojas_vivas()
        except SemResposta as e:
            print("SEM RESPOSTA do Supabase: %s" % e)
            return SEM_RESPOSTA
        for i, r in sorted(v.items(), key=lambda x: (x[1]["tabela"], x[1]["nome"])):
            if r["permitida"]:
                print("%s | %s | %s | %s" % (i, r["nome"], r["tabela"], r["produtos"]))
        return OK
    if a.listar:
        try:
            v = lojas_vivas()
        except SemResposta as e:
            print("SEM RESPOSTA do Supabase: %s" % e)
            return SEM_RESPOSTA
        for i, r in sorted(v.items(), key=lambda x: (x[1]["tabela"], x[1]["nome"])):
            print("%s | %s | %s | %s" % ("PERMITIDA" if r["permitida"] else "BLOQUEADA", r["tabela"], i, r["nome"] + ("" if r["permitida"] else " -- " + r["motivo"])))
        return OK
    if a.filtrar_fotos:
        lista = [l.strip() for l in sys.stdin if l.strip()]
        ok, com_base = filtrar_fotos(lista)
        try:
            for c in ok:
                print(c)
            sys.stdout.flush()
        except BrokenPipeError:  # quem le pode fechar cedo (head -3)
            os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        if not com_base:
            print("Supabase nao respondeu: so passam fotos genericas", file=sys.stderr)
            return SEM_RESPOSTA
        return OK
    if a.verificar:
        c, m = verificar(a.verificar, a.tabela)
    else:
        c, m = verificar_texto(a.texto)
    print("%s %s" % ({OK: "PERMITIDA", BLOQUEADA: "BLOQUEADA", SEM_RESPOSTA: "SEM_RESPOSTA"}[c], m))
    return c


if __name__ == "__main__":
    sys.exit(main())
