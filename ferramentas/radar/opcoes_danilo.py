#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""opcoes_danilo.py — opcoes NUMERADAS ao Danilo e a resposta "1 3 faz" vira tarefa no despacho.

Missao sistema-conteudo-14-11 (blocos 4.1 e 5.1). Corre no HOST da VPS (/opt/data/rotinas), como root.

Porque existe: o radar e o agente de segunda tinham propostas, mas o Danilo nao recebia ESCOLHAS
(regra dele de 29/10: quando e ele a escolher, lista numerada, um item por linha, responde "1, 3, 5 faz").

  python3 opcoes_danilo.py ler                 # cron de 3 em 3 min: mensagens novas dele no Telegram -> despacho
  python3 opcoes_danilo.py ver                 # o ultimo lote enviado (numero -> tarefa)
  python3 opcoes_danilo.py simular "1 3 faz"   # trata um texto como se viesse do Telegram (prova)
  python3 opcoes_danilo.py simular "1 3 faz" --seco   # so diz o que faria, nao grava nada

Biblioteca: from opcoes_danilo import enviar_opcoes

Como a resposta chega: o Telegram do Danilo entra no gateway do Hermes (BoraHermesbot), que grava cada
mensagem em /opt/data/state.db (sessions.source='telegram', role='user'; a voz ja vem transcrita).
O `ler` le dai a partir de um cursor e reconhece "1 3 faz", "um e tres faz", "faz a 2", "faz todas".
O texto vai ao Danilo pelo PORTEIRO (skill falar-com-o-danilo), em processo, com sem_corte=True para
as 5 linhas nao serem cortadas a 3. Lotes guardados em /opt/data/rotinas/opcoes/lotes.json.
"""
import datetime as dt
import json
import os
import re
import sqlite3
import sys
import time
import urllib.request

sys.path.insert(0, "/opt/data/rotinas")
sys.path.insert(0, "/opt/data/voz")
from comum import SUPA_URL, SUPA_KEY  # noqa: E402  (service role, so no host)

PASTA = "/opt/data/rotinas/opcoes"
LOTES = os.path.join(PASTA, "lotes.json")
CURSOR = os.path.join(PASTA, "cursor.txt")
STATE_DB = "/opt/data/state.db"
VALIDADE_H = 72
MAX_OPCOES = 5


def _chat_danilo():
    try:
        import porteiro_cli
        return str(porteiro_cli.CHAT_DANILO)
    except Exception:  # noqa: BLE001
        return os.environ.get("OPCOES_CHAT", "")


# ------------------------------------------------------------------ base de dados
def rest(caminho, metodo="GET", corpo=None, prefer="return=representation"):
    h = {"apikey": SUPA_KEY, "Authorization": "Bearer " + SUPA_KEY, "Content-Type": "application/json", "Prefer": prefer}
    dados = json.dumps(corpo, ensure_ascii=False).encode("utf-8") if corpo is not None else None
    req = urllib.request.Request(SUPA_URL + "/rest/v1/" + caminho, data=dados, headers=h, method=metodo)
    with urllib.request.urlopen(req, timeout=40) as r:
        txt = r.read().decode("utf-8").strip()
        return json.loads(txt) if txt else []


def agora_iso():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def e2e(fluxo, passo, estado, detalhe, run_id=None):
    try:
        rest("e2e_log", "POST", {"fluxo": fluxo, "passo": passo, "estado": estado, "detalhe": str(detalhe)[:1500],
                                 "device": "vps", "run_id": run_id or fluxo}, prefer="return=minimal")
    except Exception as e:  # noqa: BLE001
        print("e2e_log falhou: %s" % str(e)[:120])


def criar_despacho(titulo, tarefa, para="emerson", origem="danilo-telegram", prioridade=70):
    r = rest("despacho", "POST", {"origem": origem, "para": para, "tipo": "tarefa", "titulo": titulo[:200],
                                  "tarefa": tarefa, "prioridade": prioridade, "estado": "aberta"})
    return r[0]["id"]


# ------------------------------------------------------------------ porteiro
def falar(texto, origem, ensaio=False, nivel="RESULTADO"):
    """Pelo porteiro (unica porta para o chat do Danilo). sem_corte=True: a lista vai inteira."""
    import porteiro
    return porteiro.telegram_danilo(texto, nivel, origem, sem_corte=True, ensaio=ensaio)


# ------------------------------------------------------------------ lotes
def _ler_lotes():
    try:
        return json.load(open(LOTES, encoding="utf-8"))
    except Exception:  # noqa: BLE001
        return []


def _gravar_lotes(lotes):
    os.makedirs(PASTA, exist_ok=True)
    tmp = LOTES + ".tmp"
    json.dump(lotes[-60:], open(tmp, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    os.replace(tmp, LOTES)


def montar(cabecalho, opcoes):
    linhas = [cabecalho.strip()]
    for i, o in enumerate(opcoes, 1):
        linhas.append("%d. %s: %s. Custo: %s." % (i, o["o_que_e"].rstrip(". "), o["o_que_se_faz"].rstrip(". "),
                                                   (o.get("custo") or "0 €").rstrip(". ")))
    linhas.append("Responde só com os números e faz, por exemplo: 1 3 faz. Sem resposta, nada se faz.")
    return "\n".join(linhas)


def enviar_opcoes(origem, cabecalho, opcoes, ensaio=False, run_id=None):
    """opcoes: lista de dicts {o_que_e, o_que_se_faz, custo, titulo, tarefa, para, ref}. Max 5.
    ref: {"radar": youtube_id} | {"caixa": id} | {"cortex": pid} — o que se atualiza quando ele escolhe."""
    opcoes = [o for o in opcoes if o.get("tarefa")][:MAX_OPCOES]
    if not opcoes:
        return None, {"ok": True, "vazio": True}
    msg = montar(cabecalho, opcoes)
    r = falar(msg, origem, ensaio=ensaio)
    if ensaio:
        return msg, r
    if r.get("ok"):
        lotes = _ler_lotes()
        lote = {"lote": "%s-%s" % (origem, time.strftime("%Y%m%d%H%M%S")), "origem": origem,
                "enviado_em": time.time(), "texto": msg, "porteiro": {k: r.get(k) for k in ("destino", "ids_texto", "nivel")},
                "opcoes": [dict(o, n=i) for i, o in enumerate(opcoes, 1)], "escolhidas": {}}
        lotes.append(lote)
        _gravar_lotes(lotes)
        e2e("opcoes-danilo", "enviadas", "ok", "%s: %d opcoes, destino=%s ids=%s" % (lote["lote"], len(opcoes),
                                                                                    r.get("destino"), r.get("ids_texto")), run_id)
    else:
        e2e("opcoes-danilo", "enviadas", "falhou", "%s: porteiro %s" % (origem, str(r)[:300]), run_id)
    return msg, r


# ------------------------------------------------------------------ reconhecer "1 3 faz"
PALAVRAS = {"um": "1", "uma": "1", "primeira": "1", "primeiro": "1", "dois": "2", "duas": "2", "segunda": "2",
            "segundo": "2", "tres": "3", "terceira": "3", "terceiro": "3", "quatro": "4", "quarta": "4", "quarto": "4",
            "cinco": "5", "quinta": "5", "quinto": "5"}
VERBO = r"(?:faz|faca|fazer|pode fazer|podes fazer|manda|bora|vai)"
NUMS = r"((?:[1-5](?:\s*(?:e|,)?\s*))+)"


def _limpar(texto):
    t = (texto or "").strip()
    m = re.search(r"here(?:'s| is) what they said:\s*\"(.*)\"\s*\]?\s*$", t, re.I | re.S)
    if m:
        t = m.group(1)
    t = t.strip().strip('"').strip()
    t = t.lower()
    for a, b in (("á", "a"), ("à", "a"), ("â", "a"), ("ã", "a"), ("é", "e"), ("ê", "e"), ("í", "i"), ("ó", "o"),
                 ("ô", "o"), ("õ", "o"), ("ú", "u"), ("ç", "c")):
        t = t.replace(a, b)
    t = re.sub(r"[.,!?;:\"']", " ", t)
    t = " ".join(PALAVRAS.get(w, w) for w in t.split())
    return re.sub(r"\s+", " ", t).strip()


def numeros(texto):
    """-> lista de numeros escolhidos, 'todas', ou None (nao e resposta a opcoes)."""
    t = _limpar(texto)
    if not t or len(t) > 60:
        return None
    if re.fullmatch(r"(?:" + VERBO + r" (?:todas|todos|tudo)|(?:todas|todos|tudo) " + VERBO + r")", t):
        return "todas"
    m = (re.fullmatch(r"(?:as? |os? |opc(?:ao|oes) |numeros? )?" + NUMS + r"\s*" + VERBO + r"(?: isso| essas?| esses?)?", t)
         or re.fullmatch(VERBO + r" (?:as? |os? |a opcao |as opcoes |o |os numeros? )?" + NUMS, t))
    if not m:
        return None
    return sorted({int(x) for x in re.findall(r"[1-5]", m.group(1))})


def tratar_texto(texto, fonte="telegram", seco=False):
    nums = numeros(texto)
    if nums is None:
        return None
    lotes = _ler_lotes()
    agora = time.time()
    vivos = [l for l in lotes if agora - l.get("enviado_em", 0) < VALIDADE_H * 3600]
    if not vivos:
        return {"ok": False, "porque": "sem lote de opcoes nas ultimas %dh" % VALIDADE_H, "nums": nums}
    lote = vivos[-1]
    if nums == "todas":
        nums = [o["n"] for o in lote["opcoes"]]
    feitos, ignorados = [], []
    for n in nums:
        op = next((o for o in lote["opcoes"] if o["n"] == n), None)
        if not op:
            ignorados.append("%d (nao existe)" % n)
            continue
        if str(n) in lote["escolhidas"]:
            ignorados.append("%d (ja criada: #%s)" % (n, lote["escolhidas"][str(n)]))
            continue
        if seco:
            feitos.append((n, "seco", op["titulo"]))
            continue
        tarefa = op["tarefa"] + "\n\nEscolhida pelo Danilo (%s) em %s: \"%s\". Lote %s, opcao %d." % (
            fonte, time.strftime("%d/%m %H:%M"), (texto or "")[:120], lote["lote"], n)
        did = criar_despacho(op["titulo"], tarefa, para=op.get("para") or "emerson")
        lote["escolhidas"][str(n)] = did
        feitos.append((n, did, op["titulo"]))
        _depois_de_escolher(op.get("ref") or {}, did)
    if not seco:
        _gravar_lotes(lotes)
        if feitos:
            txt = "Recebido. Criei %s: %s." % ("a tarefa" if len(feitos) == 1 else "as tarefas",
                                             "; ".join("%d) %s" % (n, t[:70]) for n, _d, t in feitos))
            falar(txt, "opcoes-danilo")
        e2e("opcoes-danilo", "resposta", "ok" if feitos else "parcial",
            "texto=%r lote=%s criadas=%s ignoradas=%s" % ((texto or "")[:80], lote["lote"],
                                                          [(n, d) for n, d, _t in feitos], ignorados))
    return {"ok": True, "lote": lote["lote"], "criadas": [(n, d) for n, d, _t in feitos], "ignoradas": ignorados}


def _depois_de_escolher(ref, did):
    marca = "[escolhida pelo Danilo %s: despacho #%s] " % (time.strftime("%d/%m"), did)
    try:
        if ref.get("radar"):
            v = rest("radar_videos?youtube_id=eq.%s&select=acao" % ref["radar"])
            acao = (v[0].get("acao") if v else "") or ""
            rest("radar_videos?youtube_id=eq.%s" % ref["radar"], "PATCH",
                 {"veredito": "despachado", "acao": marca + acao, "revisto_em": agora_iso()}, prefer="return=minimal")
        if ref.get("caixa") and int(ref["caixa"]) != 7:     # a linha 7 e a missao em curso: nunca se toca
            rest("caixa_guardados?id=eq.%d&id=neq.7" % int(ref["caixa"]), "PATCH",
                 {"estado": "em-curso", "decisao": "o Danilo escolheu no Telegram", "resultado": "despacho #%s" % did},
                 prefer="return=minimal")
    except Exception as e:  # noqa: BLE001
        e2e("opcoes-danilo", "depois-de-escolher", "falhou", "%s %s" % (ref, str(e)[:200]))


# ------------------------------------------------------------------ ler o Telegram
def ler():
    os.makedirs(PASTA, exist_ok=True)
    chat = _chat_danilo()
    c = sqlite3.connect("file:%s?mode=ro" % STATE_DB, uri=True, timeout=20)
    q = ("select m.id, m.content from messages m join sessions s on s.id = m.session_id "
         "where s.source = 'telegram' and s.user_id = ? and m.role = 'user' and m.id > ? order by m.id")
    try:
        cursor = int(open(CURSOR).read().strip())
    except Exception:  # noqa: BLE001
        # primeira vez: comeca no fim (nao se reprocessa o passado)
        cursor = c.execute("select coalesce(max(id), 0) from messages").fetchone()[0]
        open(CURSOR, "w").write(str(cursor))
        print("cursor iniciado em %d" % cursor)
        return 0
    novos = c.execute(q, (chat, cursor)).fetchall()
    for mid, conteudo in novos:
        r = tratar_texto(conteudo or "", "telegram")
        if r is not None:
            print(json.dumps({"msg": mid, "r": r}, ensure_ascii=False))
        cursor = max(cursor, mid)
    open(CURSOR, "w").write(str(cursor))
    return 0


def ver():
    lotes = _ler_lotes()
    if not lotes:
        print("sem lotes")
        return 0
    l = lotes[-1]
    print("lote %s (%s)" % (l["lote"], dt.datetime.fromtimestamp(l["enviado_em"]).strftime("%d/%m %H:%M")))
    for o in l["opcoes"]:
        print("%d -> %s [para=%s] escolhida=%s" % (o["n"], o["titulo"], o.get("para"), l["escolhidas"].get(str(o["n"]))))
    return 0


if __name__ == "__main__":
    a = sys.argv[1:] or ["ver"]
    if a[0] == "ler":
        sys.exit(ler())
    if a[0] == "ver":
        sys.exit(ver())
    if a[0] == "simular" and len(a) > 1:
        print(json.dumps(tratar_texto(a[1], "simulacao", seco="--seco" in a), ensure_ascii=False))
        sys.exit(0)
    print(__doc__)
