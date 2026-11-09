# -*- coding: utf-8 -*-
"""
Autorizacoes do Danilo pelo Telegram (missao m3-dipsy-acesso-total-2026-11-08). Usado pela ponte.py.

A guarda do Dipsy (plugin dsh-bora, lib/autorizacoes.js) cria ~/.dsh/aprovacoes/<id>.pedido.json quando uma acao precisa
do "sim"; o proxy cria pedidos de rede ("Posso abrir X?"). Este modulo:
  - manda a pergunta ao Danilo (texto + audio, com botoes Sim/Nao): OPERACAO + VALOR + DESTINO + o SQL/comando exato;
  - recebe a resposta (botao, "sim"/"nao" escrito ou falado), so do chat dele, dentro de 10 minutos;
  - grava <id>.resposta.json ASSINADO (HMAC; a guarda recusa respostas sem assinatura certa);
  - "sim" a um sitio -> fica na lista (rede-categorias.yml); "sim" a uma acao com dominio -> passe de 10 min no proxy;
  - regista tudo em ~/.dsh/guarda.log e no e2e_log (fluxo dipsy-autorizacoes);
  - sem resposta em 10 min -> expirado (nao se faz) e avisa.
Nunca ha autorizacao geral: cada pedido vale uma vez, para a acao exata.
"""
import json
import os
import re
import sys
import time
from datetime import datetime, timezone

HOME = os.path.expanduser("~")
DSH = os.path.join(HOME, ".dsh")
PASTA = os.path.join(DSH, "aprovacoes")
GUARDA_LOG = os.path.join(DSH, "guarda.log")
sys.path.insert(0, os.path.join(DSH, "proxy"))
import rede  # noqa: E402

FLUXO = "dipsy-autorizacoes"
PRAZO_S = 600
SIM = re.compile(r"^\s*(sim|s|pode|podes|pode sim|sim pode|permito|autorizo|autorizado|ok|okay|est[aá] bem|t[aá] bom|claro|yes|faz|podes fazer)\s*[.!]*\s*$", re.I)
NAO = re.compile(r"^\s*(n[aã]o|n|nao pode|n[aã]o podes|n[aã]o autorizo|nega|recuso|para|no|nope|cancela)\s*[.!]*\s*$", re.I)


def _ler(f):
    try:
        with open(f, encoding="utf-8") as h:
            return json.load(h)
    except Exception:
        return None


def _f(pid, ext):
    return os.path.join(PASTA, f"{pid}.{ext}")


def registar_guarda(evento, pid, extra=""):
    try:
        with open(GUARDA_LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps({"quando": datetime.now(timezone.utc).isoformat(timespec="seconds"), "ferramenta": "ponte-telegram",
                                "regra": f"autorizacao:{evento}:{pid}", "trecho": extra[:140]}, ensure_ascii=False) + "\n")
    except Exception:
        pass


def pedidos():
    out = []
    try:
        nomes = [n for n in os.listdir(PASTA) if n.endswith(".pedido.json")]
    except FileNotFoundError:
        return out
    for n in nomes:
        p = _ler(os.path.join(PASTA, n))
        if p and p.get("id"):
            out.append(p)
    return sorted(out, key=lambda p: p.get("criado", 0))


def pendentes():
    """Pedidos ja perguntados ao Danilo, ainda sem resposta e dentro do prazo."""
    agora = time.time()
    return [p for p in pedidos() if os.path.exists(_f(p["id"], "enviado.json")) and not os.path.exists(_f(p["id"], "resposta.json"))
            and agora < p.get("expira", 0)]


def texto_pergunta(p):
    expl = ""
    try:
        with open(_f(p["id"], "explicacao.txt"), encoding="utf-8") as f:
            expl = f.read().strip()
    except Exception:
        pass
    if p.get("tipo") == "rede":
        dom = (p.get("dominios") or ["?"])[0]
        linhas = [f"Permites? O Dipsy quer abrir o sítio {dom} (categoria {p.get('categoria_sugerida') or 'outros'}).",
                  "Não está em nenhuma categoria da rede dele. Se disseres sim, fica na lista e passa a abrir sempre (com registo)."]
        if expl:
            linhas.append(f"O Dipsy explica: {expl}")
    else:
        linhas = [f"Permites? {p.get('operacao', 'uma ação')}."]
        if expl:
            linhas.append(f"O Dipsy explica: {expl}")
        if p.get("valor") and p["valor"] != "-":
            linhas.append(f"Valor: {p['valor']}")
        if p.get("destino") and p["destino"] != "-":
            linhas.append(f"Destino: {p['destino']}")
        if p.get("detalhe"):
            linhas.append(f"O que vai correr, exatamente:\n{p['detalhe']}")
        if p.get("porque"):
            linhas.append(f"Porque te pergunto: {p['porque']}")
    linhas.append(f"Responde sim ou não (ou toca no botão). Se não responderes em 10 minutos, não faço. Pedido {p['id']}.")
    return "\n".join(linhas)


def botoes(pid):
    return json.dumps({"inline_keyboard": [[{"text": "Sim, permito", "callback_data": f"apr:{pid}:sim"},
                                            {"text": "Não", "callback_data": f"apr:{pid}:nao"}]]})


def responder(pid, estado, origem):
    """Grava a resposta assinada. Devolve (ok, texto para o Danilo, pedido)."""
    p = _ler(_f(pid, "pedido.json"))
    if not p:
        return False, f"Não encontrei o pedido {pid}.", None
    if os.path.exists(_f(pid, "resposta.json")):
        r = _ler(_f(pid, "resposta.json")) or {}
        return False, f"O pedido {pid} já tinha resposta ({r.get('estado')}).", p
    if time.time() > p.get("expira", 0):
        _gravar_resposta(p, "expirado", origem)
        return False, f"Chegou tarde: o pedido {pid} já tinha passado os 10 minutos, por isso não foi feito.", p
    _gravar_resposta(p, estado, origem)
    dom = (p.get("dominios") or [None])[0]
    if p.get("tipo") == "rede" and dom:
        if estado == "sim":
            rede.juntar_aprovado(dom, p.get("categoria_sugerida"), pid)
            return True, f"Combinado: {dom} fica aberto para o Dipsy (com registo).", p
        rede.juntar_recusado(dom, pid)
        return True, f"Combinado: {dom} fica fechado para o Dipsy.", p
    if estado == "sim":
        for d in p.get("dominios") or []:
            try:
                rede.dar_passe(d, pid)
            except Exception:
                pass
        return True, "Combinado: autorizado. O Dipsy faz agora, uma vez só, e diz-te o resultado.", p
    return True, "Combinado: não faço.", p


def _gravar_resposta(p, estado, origem):
    resp = {"estado": estado, "respondido_em": datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z"),
            "origem": origem}
    resp["assinatura"] = rede.assinar(f"aprovacao|{p['id']}|{p['chave']}|{resp['estado']}|{resp['respondido_em']}")
    rede.gravar_atomico(_f(p["id"], "resposta.json"), json.dumps(resp, ensure_ascii=False))
    registar_guarda(estado, p["id"], p.get("operacao", ""))
    return resp


def interpretar(texto):
    """'sim' | 'nao' | None"""
    t = (texto or "").strip()
    if SIM.match(t):
        return "sim"
    if NAO.match(t):
        return "nao"
    return None
