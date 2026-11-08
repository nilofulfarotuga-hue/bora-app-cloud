# -*- coding: utf-8 -*-
"""
Politica de rede do Dipsy (missao m3-dipsy-acesso-total-2026-11-08). Codigo nosso, so biblioteca padrao + PyYAML.

Um so sitio decide se um dominio pode abrir: o proxy (proxy.py) e a ponte do Telegram (ponte.py) usam este modulo; a guarda
do dsh (JS) le o ficheiro compilado ~/.dsh/proxy/politica.json, que este modulo escreve sempre que a lista muda.

decidir(host) -> (decisao, categoria, motivo, so_leitura)
  decisao: "permitido" | "barrado" | "pergunta"  (pergunta = fora das categorias: o Danilo decide pelo Telegram)
"""
import hashlib
import hmac
import json
import os
import re
import threading
import time
from datetime import datetime, timezone

import yaml

HOME = os.path.expanduser("~")
DSH = os.path.join(HOME, ".dsh")
CATEGORIAS = os.path.join(DSH, "rede-categorias.yml")
PASTA_PROXY = os.path.join(DSH, "proxy")
POLITICA_JSON = os.path.join(PASTA_PROXY, "politica.json")
PASSES = os.path.join(PASTA_PROXY, "passes.json")
REGISTO = os.path.join(PASTA_PROXY, "registo.jsonl")
APROVACOES = os.path.join(DSH, "aprovacoes")
CHAVE_APROVACOES = os.path.join(DSH, "secrets", "aprovacoes.key")
LIMITE_SO_LEITURA = 1024 * 1024          # bytes que uma ligacao "so leitura" pode mandar para fora
PASSE_MINUTOS = 10

_trinco = threading.Lock()
_cache = {"mtime": None, "dados": None, "passes_mtime": None, "passes": []}


def agora_iso():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def gravar_atomico(caminho, texto):
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    tmp = f"{caminho}.{os.getpid()}.{threading.get_ident()}.tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(texto)
    os.replace(tmp, caminho)


# ---------------------------------------------------------------- chave das assinaturas (aprovações e passes)
def chave_assinatura():
    """32 bytes aleatorios em ~/.dsh/secrets/aprovacoes.key (criados na 1.a vez). So a ponte, o proxy e o plugin a leem."""
    try:
        with open(CHAVE_APROVACOES, "rb") as f:
            k = f.read().strip()
            if len(k) >= 32:
                return k
    except FileNotFoundError:
        pass
    os.makedirs(os.path.dirname(CHAVE_APROVACOES), exist_ok=True)
    k = os.urandom(32).hex().encode()
    with open(CHAVE_APROVACOES, "wb") as f:
        f.write(k)
    return k


def assinar(texto):
    return hmac.new(chave_assinatura(), texto.encode("utf-8"), hashlib.sha256).hexdigest()


def assinatura_ok(texto, assinatura):
    try:
        return hmac.compare_digest(assinar(texto), str(assinatura or ""))
    except Exception:
        return False


# ---------------------------------------------------------------- ler e compilar a lista
def _norm(d):
    return str(d or "").strip().lower().rstrip(".")


def carregar():
    """Le rede-categorias.yml (com cache por mtime). Se o ficheiro estiver estragado, mantem a ultima versao boa."""
    with _trinco:
        try:
            m = os.path.getmtime(CATEGORIAS)
        except OSError:
            m = None
        if _cache["dados"] is not None and m == _cache["mtime"]:
            return _cache["dados"]
        try:
            with open(CATEGORIAS, encoding="utf-8") as f:
                dados = yaml.safe_load(f) or {}
            if not isinstance(dados.get("categorias"), dict):
                raise ValueError("falta a secao categorias")
        except Exception:
            if _cache["dados"] is not None:
                return _cache["dados"]
            dados = {"categorias": {"bora": {"estado": "aberta", "so_leitura": False,
                                             "dominios": ["boraguarda.com", "ojykpzwqrtusfeakzrna.supabase.co", "localhost", "127.0.0.1"]}},
                     "sempre_bloqueado": {}, "aprovados_pelo_danilo": [], "recusados_pelo_danilo": []}
        _cache["dados"] = dados
        _cache["mtime"] = m
    try:
        compilar(dados)
    except Exception:
        pass
    return dados


def _bate(host, dominio):
    dominio = _norm(dominio)
    if not dominio:
        return False
    if dominio.endswith(".*"):
        return host.startswith(dominio[:-1])
    return host == dominio or host.endswith("." + dominio)


def _lista_dominios(lista):
    out = []
    for x in lista or []:
        if isinstance(x, dict):
            x = x.get("dominio")
        if x:
            out.append(_norm(x))
    return out


def compilar(dados=None):
    """Escreve ~/.dsh/proxy/politica.json, a versao que a guarda (JS) le."""
    dados = dados or carregar()
    cats = {}
    for nome, c in (dados.get("categorias") or {}).items():
        c = c or {}
        cats[nome] = {"estado": str(c.get("estado", "aberta")).lower(), "so_leitura": bool(c.get("so_leitura", True)),
                      "dominios": _lista_dominios(c.get("dominios"))}
    bloq = {}
    for nome, g in (dados.get("sempre_bloqueado") or {}).items():
        g = g or {}
        bloq[nome] = {"com_sim": bool(g.get("com_sim", False)), "dominios": _lista_dominios(g.get("dominios"))}
    pol = {"gerado": agora_iso(), "categorias": cats, "sempre_bloqueado": bloq,
           "aprovados": _lista_dominios(dados.get("aprovados_pelo_danilo")),
           "recusados": _lista_dominios(dados.get("recusados_pelo_danilo"))}
    try:
        with open(POLITICA_JSON, encoding="utf-8") as f:
            antiga = json.load(f)
        antiga.pop("gerado", None)
        if antiga == {k: v for k, v in pol.items() if k != "gerado"}:
            return pol
    except Exception:
        pass
    gravar_atomico(POLITICA_JSON, json.dumps(pol, ensure_ascii=False, indent=1))
    return pol


# ---------------------------------------------------------------- passes de 10 minutos (acoes aprovadas)
def passes_validos():
    agora = time.time()
    try:
        m = os.path.getmtime(PASSES)
    except OSError:
        return []
    if m != _cache["passes_mtime"]:
        try:
            with open(PASSES, encoding="utf-8") as f:
                _cache["passes"] = json.load(f) or []
        except Exception:
            _cache["passes"] = []
        _cache["passes_mtime"] = m
    out = []
    for p in _cache["passes"]:
        try:
            if p["ate"] > agora and assinatura_ok(f"passe|{_norm(p['dominio'])}|{p['ate']}|{p.get('pedido','')}", p.get("assinatura")):
                out.append(p)
        except Exception:
            continue
    return out


def dar_passe(dominio, pedido_id, minutos=PASSE_MINUTOS):
    """So a ponte chama isto, depois do "sim" do Danilo a uma acao concreta."""
    dominio = _norm(dominio)
    ate = int(time.time() + minutos * 60)
    try:
        with open(PASSES, encoding="utf-8") as f:
            atuais = json.load(f) or []
    except Exception:
        atuais = []
    atuais = [p for p in atuais if p.get("ate", 0) > time.time()]
    atuais.append({"dominio": dominio, "ate": ate, "pedido": pedido_id,
                   "assinatura": assinar(f"passe|{dominio}|{ate}|{pedido_id}")})
    gravar_atomico(PASSES, json.dumps(atuais, ensure_ascii=False, indent=1))
    return ate


# ---------------------------------------------------------------- a decisao
def decidir(host):
    """(decisao, categoria, motivo, so_leitura)."""
    h = _norm(host).strip("[]")
    if not h:
        return "barrado", None, "endereço vazio", True
    dados = carregar()
    # 1) sempre bloqueado (mas um passe de 10 min, dado pelo "sim" do Danilo, abre os grupos com_sim)
    for nome, g in (dados.get("sempre_bloqueado") or {}).items():
        g = g or {}
        if any(_bate(h, d) for d in _lista_dominios(g.get("dominios"))):
            # a excecao: dashboard.stripe.com vive numa categoria propria de leitura
            if any(_bate(h, d) for d in _lista_dominios(((dados.get("categorias") or {}).get("stripe_leitura") or {}).get("dominios"))):
                break
            if g.get("com_sim") and any(_bate(h, p["dominio"]) for p in passes_validos()):
                return "permitido", f"passe:{nome}", "aberto 10 min pelo sim do Danilo", False
            return "barrado", f"sempre_bloqueado:{nome}", (g.get("descricao") or f"{nome} está sempre bloqueado"), True
    # 2) o Danilo disse que nao a este sitio
    if any(_bate(h, d) for d in _lista_dominios(dados.get("recusados_pelo_danilo"))):
        return "barrado", "recusado", "o Danilo disse que não a este sítio", True
    # 3) categorias
    fechada = None
    for nome, c in (dados.get("categorias") or {}).items():
        c = c or {}
        if any(_bate(h, d) for d in _lista_dominios(c.get("dominios"))):
            if str(c.get("estado", "aberta")).lower() != "aberta":
                fechada = nome
                continue
            return "permitido", nome, "", bool(c.get("so_leitura", True))
    if fechada:
        return "barrado", fechada, f"a categoria {fechada} está fechada (abre-se com /rede abrir {fechada})", True
    # 4) aprovados pelo Danilo, um a um
    if any(_bate(h, d) for d in _lista_dominios(dados.get("aprovados_pelo_danilo"))):
        return "permitido", "aprovado", "", True
    return "pergunta", None, "fora das categorias: o Danilo decide pelo Telegram", True


def categoria_sugerida(host):
    h = _norm(host)
    if re.search(r"(^|\.)(gov|edu)\.[a-z]{2,3}$|\.gov\.pt$", h):
        return "noticias_lei"
    if h.startswith(("docs.", "developer.", "dev.", "api.")) or "doc" in h:
        return "documentacao"
    if re.search(r"(news|noticia|jornal|publico\.pt|observador|sapo\.pt|rtp\.pt|cmjornal|expresso|dn\.pt|jn\.pt)", h):
        return "noticias_lei"
    return "outros"


# ---------------------------------------------------------------- mudar a lista (so a ponte, pelo Telegram)
def _gravar_yaml(dados):
    """Reescreve rede-categorias.yml mantendo o cabecalho de comentarios."""
    try:
        with open(CATEGORIAS, encoding="utf-8") as f:
            original = f.read()
    except FileNotFoundError:
        original = ""
    cabeca = []
    for linha in original.splitlines():
        if linha.startswith("#") or not linha.strip():
            cabeca.append(linha)
        else:
            break
    corpo = yaml.safe_dump(dados, allow_unicode=True, sort_keys=False, default_flow_style=False, width=140)
    gravar_atomico(CATEGORIAS, "\n".join(cabeca).rstrip("\n") + "\n\n" + corpo)
    with _trinco:
        _cache["mtime"] = None
    compilar(carregar())


def mudar_categoria(nome, estado):
    dados = carregar()
    cats = dados.get("categorias") or {}
    alvo = next((k for k in cats if k.lower() == nome.strip().lower()), None)
    if not alvo:
        return None
    cats[alvo]["estado"] = estado
    _gravar_yaml(dados)
    return alvo


def juntar_aprovado(dominio, categoria, pedido_id, quem="Danilo pelo Telegram"):
    dados = carregar()
    lista = dados.setdefault("aprovados_pelo_danilo", []) or []
    dados["aprovados_pelo_danilo"] = lista
    d = _norm(dominio)
    if d not in _lista_dominios(lista):
        lista.append({"dominio": d, "categoria": categoria or "outros", "quando": agora_iso(), "pedido": pedido_id, "quem": quem})
    rec = dados.get("recusados_pelo_danilo") or []
    dados["recusados_pelo_danilo"] = [x for x in rec if _norm(x.get("dominio") if isinstance(x, dict) else x) != d]
    _gravar_yaml(dados)


def juntar_recusado(dominio, pedido_id, quem="Danilo pelo Telegram"):
    dados = carregar()
    lista = dados.setdefault("recusados_pelo_danilo", []) or []
    dados["recusados_pelo_danilo"] = lista
    d = _norm(dominio)
    if d not in _lista_dominios(lista):
        lista.append({"dominio": d, "quando": agora_iso(), "pedido": pedido_id, "quem": quem})
    _gravar_yaml(dados)


def resumo_categorias():
    dados = carregar()
    linhas = []
    for nome, c in (dados.get("categorias") or {}).items():
        c = c or {}
        linhas.append(f"{nome}: {c.get('estado', 'aberta')}"
                      f"{' (só leitura)' if c.get('so_leitura', True) else ''} — {c.get('descricao', '')}")
    ap = _lista_dominios(dados.get("aprovados_pelo_danilo"))
    rc = _lista_dominios(dados.get("recusados_pelo_danilo"))
    linhas.append(f"Aprovados por ti, um a um: {', '.join(ap) if ap else 'nenhum'}.")
    linhas.append(f"Recusados por ti: {', '.join(rc) if rc else 'nenhum'}.")
    return "\n".join(linhas)


# ---------------------------------------------------------------- pedidos de rede (o proxy cria; a ponte pergunta)
def criar_pedido_rede(host, origem="proxy"):
    """Cria (uma vez por dominio e por 10 min) o pedido "Posso abrir X?". Devolve o id ou None se ja havia."""
    h = _norm(host)
    os.makedirs(APROVACOES, exist_ok=True)
    chave = "rede:" + h
    agora = time.time()
    for nome in os.listdir(APROVACOES):
        if not nome.endswith(".pedido.json"):
            continue
        try:
            with open(os.path.join(APROVACOES, nome), encoding="utf-8") as f:
                p = json.load(f)
        except Exception:
            continue
        if p.get("chave") == chave and p.get("expira", 0) > agora and \
           not os.path.exists(os.path.join(APROVACOES, p["id"] + ".resposta.json")):
            return None
    pid = "r" + hashlib.sha256(f"{chave}|{agora}".encode()).hexdigest()[:7]
    cat = categoria_sugerida(h)
    p = {"id": pid, "tipo": "rede", "chave": chave, "criado": agora, "expira": agora + 600, "origem": origem,
         "regra": "rede-fora-da-lista", "dominios": [h], "operacao": f"Abrir o sítio {h} (categoria {cat})",
         "valor": "-", "destino": h, "detalhe": f"O Dipsy quer ler o sítio {h}, que não está em nenhuma categoria.",
         "categoria_sugerida": cat}
    gravar_atomico(os.path.join(APROVACOES, pid + ".pedido.json"), json.dumps(p, ensure_ascii=False, indent=1))
    return pid
