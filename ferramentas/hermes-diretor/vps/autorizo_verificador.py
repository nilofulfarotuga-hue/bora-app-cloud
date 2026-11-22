#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
autorizo_verificador.py — o verificador SEM IA do "autorizo" do Danilo (missao hermes-diretor-2026-11-20, B4).

Porque existe: o Danilo pode autorizar dinheiro ou apagar dizendo "autorizo" ao Hermes no Telegram. Se fosse
o Hermes (um modelo) a registar esse autorizo, um texto de fora que o enganasse podia inventar um. Por isso
quem regista e este script: corre no HOST como root, le as mensagens que o Danilo MESMO mandou (a base do
gateway, so sessoes do Telegram do utilizador dele, so papel "user") e so entao chama a porta, com uma senha
propria que o Hermes nao tem (/root/hermes-diretor/verificador.token, modo 600, fora do contentor).

Regras:
  "autorizo" / "eu autorizo"        -> autoriza o unico pedido pendente; se houver varios, pede o numero
  "autorizo 12"                     -> autoriza o pedido n.o 12
  "nao autorizo" / "recuso [12]"    -> recusa
  "nao" sozinho, ate 10 min depois de um autorizo registado -> anula esse autorizo (se ainda nao foi usado)
  A mensagem tem de ser POSTERIOR ao pedido. Uma mensagem serve para um pedido so.

Vive em /root/hermes-diretor/ (fora do volume do contentor, para o Hermes nao lhe conseguir mexer).
Cron (host): * * * * * flock -n /var/lock/autorizo-verificador.lock python3 /root/hermes-diretor/autorizo_verificador.py
Enquanto a porta nova nao estiver publicada, a porta responde "operacao desconhecida" e isto sai calado.
  --ensaio "texto"   mostra o que faria com esse texto, sem chamar a porta nem falar com ninguem
"""
import json
import os
import re
import sqlite3
import sys
import time
import unicodedata
import urllib.error
import urllib.request

PORTA = "https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/hermes-porta"
SENHA_F = "/root/hermes-diretor/verificador.token"
CURSOR_F = "/root/hermes-diretor/verificador.cursor"
ULTIMO_F = "/root/hermes-diretor/verificador.ultimo.json"     # ultimo autorizo registado (para o "NAO")
STATE_DB = "/opt/data/state.db"
LOG = "/var/log/autorizo-verificador.log"


def _chat_danilo():
    """O chat do Danilo vem do porteiro (a unica porta para o chat dele); nunca fica escrito aqui."""
    try:
        sys.path.insert(0, "/opt/data/voz")
        import porteiro_cli
        return str(porteiro_cli.CHAT_DANILO)
    except Exception:
        return os.environ.get("DANILO_CHAT_ID", "")


CHAT_DANILO = _chat_danilo()


def registar(**o):
    o["ts"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    try:
        with open(LOG, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(o, ensure_ascii=False, default=str) + "\n")
    except Exception:
        pass


def porta(op, dados=None):
    senha = open(SENHA_F, encoding="utf-8").read().strip()
    req = urllib.request.Request(PORTA, data=json.dumps({"op": op, "dados": dados or {}}).encode(),
                                 headers={"Content-Type": "application/json", "x-hermes-token": senha})
    try:
        return json.loads(urllib.request.urlopen(req, timeout=30).read().decode())
    except urllib.error.HTTPError as e:
        try:
            return json.loads(e.read().decode())
        except Exception:
            return {"erro": "http %s" % e.code}
    except Exception as e:  # noqa: BLE001
        return {"erro": str(e)[:200]}


def limpo(texto):
    t = unicodedata.normalize("NFKD", texto or "").encode("ascii", "ignore").decode().lower()
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9 ]+", " ", t)).strip()


def interpretar(texto):
    """Devolve (acao, numero): acao em autorizar|recusar|nao|None."""
    t = limpo(texto)
    if not t or len(t) > 160:           # um autorizo e uma frase curta; texto longo nao conta
        return None, None
    m = re.search(r"\b(\d{1,9})\b", t)
    numero = int(m.group(1)) if m else None
    if re.search(r"\bnao autorizo\b|\brecuso\b|\bnao aprovo\b", t):
        return "recusar", numero
    if re.search(r"\bautorizo\b", t):
        return "autorizar", numero
    if t in ("nao", "nao fui eu", "nao foi eu", "nao fui"):
        return "nao", None
    return None, None


def mensagens_novas(cursor):
    c = sqlite3.connect("file:%s?mode=ro" % STATE_DB, uri=True, timeout=20)
    try:
        if cursor is None:              # primeira corrida: nao olha para tras
            return [], c.execute("select coalesce(max(id), 0) from messages").fetchone()[0]
        linhas = c.execute(
            "select m.id, m.content, m.timestamp from messages m join sessions s on s.id = m.session_id "
            "where s.source = 'telegram' and s.user_id = ? and m.role = 'user' and m.id > ? order by m.id",
            (CHAT_DANILO, cursor)).fetchall()
        topo = c.execute("select coalesce(max(id), 0) from messages").fetchone()[0]
        return linhas, topo
    finally:
        c.close()


def falar(texto):
    try:
        req = urllib.request.Request("http://127.0.0.1:8796/telegram_danilo",
                                     data=json.dumps({"texto": texto, "nivel": "URGENTE", "origem": "autorizo-verificador"}).encode(),
                                     headers={"Content-Type": "application/json"})
        urllib.request.urlopen(req, timeout=20).read()
    except Exception as e:  # noqa: BLE001
        registar(evento="porteiro-falhou", erro=str(e)[:200])


def epoca(iso):
    try:
        from datetime import datetime
        return datetime.fromisoformat(str(iso).replace("Z", "+00:00")).timestamp()
    except Exception:
        return 0.0


def main():
    if "--ensaio" in sys.argv:
        texto = sys.argv[sys.argv.index("--ensaio") + 1]
        print("texto: %r -> %s" % (texto, interpretar(texto)))
        return 0
    if not os.path.isfile(SENHA_F):
        return 0
    try:
        cursor = int(open(CURSOR_F).read().strip())
    except Exception:
        cursor = None
    novas, topo = mensagens_novas(cursor)
    pedidos = [(i, c, ts) for (i, c, ts) in novas if interpretar(c)[0]]
    if pedidos:
        r = porta("autorizacao_estado", {})
        if "pendentes" not in r:        # porta antiga (ainda nao publicada) ou em baixo: nao avanca o cursor
            registar(evento="porta-sem-resposta", resposta=str(r)[:200])
            if str(r.get("erro", "")).startswith(("operacao desconhecida", "senha invalida", "esta senha")):
                with open(CURSOR_F, "w") as fh:     # porta antiga ou senha por registar: nao ha pedidos possiveis
                    fh.write(str(topo))
            return 0
        pendentes = {int(p["id"]): p for p in r["pendentes"]}
        for mid, conteudo, ts in pedidos:
            acao, numero = interpretar(conteudo)
            quando = float(ts or 0)
            if acao == "nao":
                try:
                    ult = json.load(open(ULTIMO_F))
                except Exception:
                    ult = None
                if ult and time.time() - ult.get("quando", 0) < 600:
                    rr = porta("registar_autorizo", {"autorizacao_id": ult["id"], "anular": True, "texto_literal_do_danilo": conteudo, "telegram_message_id": mid})
                    registar(evento="anular", id=ult["id"], resposta=rr)
                    falar("Anulei o autorizo do pedido %s." % ult["id"] if rr.get("ok") else
                          "Nao consegui anular o pedido %s: %s" % (ult["id"], rr.get("erro", "?")))
                continue
            validos = {i: p for i, p in pendentes.items() if epoca(p.get("criada_em")) <= quando + 5}
            alvo = numero if numero in validos else (list(validos)[0] if numero is None and len(validos) == 1 else None)
            if alvo is None:
                if validos:
                    lista = "; ".join("%d: %s" % (i, (p.get("acao") or "")[:60]) for i, p in sorted(validos.items()))
                    falar("Tens %d pedidos a espera. Diz o numero, por exemplo: autorizo %d. Pedidos: %s" % (len(validos), sorted(validos)[0], lista))
                registar(evento="sem-alvo", mensagem=mid, numero=numero, pendentes=sorted(validos))
                continue
            rr = porta("registar_autorizo", {"autorizacao_id": alvo, "recusar": acao == "recusar",
                                             "texto_literal_do_danilo": conteudo[:300], "telegram_message_id": mid})
            registar(evento=acao, id=alvo, mensagem=mid, resposta=rr)
            if rr.get("ok"):
                pendentes.pop(alvo, None)
                if acao == "autorizar":
                    json.dump({"id": alvo, "quando": time.time()}, open(ULTIMO_F, "w"))
    with open(CURSOR_F, "w") as fh:
        fh.write(str(topo))
    return 0


if __name__ == "__main__":
    sys.exit(main())
