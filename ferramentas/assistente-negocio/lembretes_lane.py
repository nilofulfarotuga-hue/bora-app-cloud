# -*- coding: utf-8 -*-
"""Pista dos lembretes do dono dentro do servidor do assistente (missao final-app-2026-10-29, 5.c).

PORQUE EXISTE: a fila normal da Bora (whatsapp_saida -> cerebro -> ligar.js) esta desligada para
TODOS (ficheiro /root/whatsapp-bora/ENVIO_DESLIGADO + whatsapp_settings.envio_ligado=false, pausa
de 13/09). O ligar.js ja pergunta de 3 em 3 segundos a /pendentes deste servidor e esse caminho nao
obedece ao interruptor da Bora. Em vez de religar o envio a toda a gente, esta pista deixa passar
SO as linhas de whatsapp_saida cujo motivo comeca por 'lembrete-danilo' e cujo numero e' igual a
LEMBRETES_DESTINO (lido do .env da VPS na hora, nunca guardado em codigo).

Ciclo de vida da linha em whatsapp_saida:
  pendente -> a-enviar (reservada aqui) -> emitida (+emitida_em, quando o ligar.js diz 'a-caminho')
  falhou / cancelada-fora-da-allowlist / cancelada-expirada (>30 min) / cancelada-anonimato
Quando sai: escreve uma linha direcao='saida' em whatsapp_messages (msg_id = 'ld-<id>') e marca
enviado_em nos itens de lembretes_danilo citados em 'ids=' no motivo. Os avisos 'entregue'/'visto'
da WhatsApp atualizam essa linha.
"""
import datetime
import re

import db

ENV = "/opt/whatsapp-bora/.env"
PREFIXO = "lembrete-danilo"
IDADE_MAX_S = 1800
def _re_dono():
    """Nomes que nunca podem sair numa mensagem (anonimato do dono). Vêm do .env
    (LEMBRETES_NOMES_DONO=nome1,nome2), nunca do código: o repositório é público."""
    nomes = []
    try:
        with open(ENV, encoding="utf-8") as fh:
            for ln in fh:
                if ln.startswith("LEMBRETES_NOMES_DONO="):
                    nomes = [n.strip() for n in ln.split("=", 1)[1].split(",") if n.strip()]
    except OSError:
        pass
    if not nomes:
        return None
    return re.compile(r"(?i)\b(" + "|".join(re.escape(n) for n in nomes) + r")\b")


RE_DONO = _re_dono()


def _digitos(x):
    return re.sub(r"\D", "", str(x or ""))


def destino():
    try:
        with open(ENV, encoding="utf-8") as fh:
            for ln in fh:
                ln = ln.strip()
                if ln.startswith("LEMBRETES_DESTINO="):
                    return _digitos(ln.split("=", 1)[1])
    except OSError:
        pass
    return ""


def _iso(dt=None):
    return (dt or datetime.datetime.now(datetime.timezone.utc)).isoformat()


def _idade_s(criada):
    try:
        d = datetime.datetime.fromisoformat(str(criada).replace("Z", "+00:00"))
        return (datetime.datetime.now(datetime.timezone.utc) - d).total_seconds()
    except Exception:  # noqa: BLE001
        return 0


def pendentes():
    dest = destino()
    if not dest:
        return []
    linhas = db.ler("whatsapp_saida",
                    "estado=eq.pendente&porta_destino=eq.vps-baileys&motivo=like.%s*&order=created_at.asc&limit=3" % PREFIXO,
                    "id,numero,texto,motivo,created_at")
    saida = []
    for r in linhas:
        rid = db.q(r["id"])
        if _digitos(r["numero"]) != dest:
            db.atualizar("whatsapp_saida", "id=eq." + rid, {"estado": "cancelada-fora-da-allowlist"})
            continue
        if RE_DONO is not None and RE_DONO.search(r.get("texto") or ""):
            db.atualizar("whatsapp_saida", "id=eq." + rid, {"estado": "cancelada-anonimato"})
            continue
        if _idade_s(r["created_at"]) > IDADE_MAX_S:
            db.atualizar("whatsapp_saida", "id=eq." + rid, {"estado": "cancelada-expirada"})
            continue
        # reserva atomica: so segue quem conseguiu mudar de 'pendente' para 'a-enviar'
        if not db.atualizar("whatsapp_saida", "id=eq.%s&estado=eq.pendente" % rid, {"estado": "a-enviar"}):
            continue
        saida.append({"id": "ld-" + str(r["id"]), "numero": r["numero"], "texto": r["texto"], "motivo": r.get("motivo")})
    return saida


def _garantir_emitida(r, rid, d, agora):
    db.atualizar("whatsapp_saida", "id=eq." + rid, {"estado": "emitida", "emitida_em": agora})
    if not db.ler("whatsapp_messages", "msg_id=eq.ld-" + rid, "id"):
        db.inserir("whatsapp_messages", {
            "msg_id": "ld-" + str(r["id"]), "numero": r["numero"], "direcao": "saida", "porta": "vps-baileys",
            "tipo": "texto", "texto": r["texto"], "decisao": (r.get("motivo") or "")[:200], "modelo": PREFIXO,
            "enviada": False, "entrega_estado": "a-caminho", "msg_id_saida": d.get("msg_id")}, devolver=False)
    m = re.search(r"ids=([0-9,]+)", r.get("motivo") or "")
    if m:
        db.atualizar("lembretes_danilo", "id=in.(%s)&enviado_em=is.null" % m.group(1), {"enviado_em": agora})


def enviado(d):
    rid = db.q(str(d.get("id") or "")[3:])
    estado = d.get("estado") or ("entregue" if d.get("ok") else "falhou")
    linhas = db.ler("whatsapp_saida", "id=eq." + rid, "id,numero,texto,motivo,estado")
    if not linhas:
        return {"ok": False, "erro": "linha desconhecida"}
    r = linhas[0]
    agora = _iso()
    if not d.get("ok") or estado == "falhou":
        db.atualizar("whatsapp_saida", "id=eq." + rid,
                     {"estado": "falhou", "motivo": ((r.get("motivo") or "") + " | erro: " + str(d.get("erro") or "?"))[:300]})
        db.atualizar("whatsapp_messages", "msg_id=eq.ld-" + rid,
                     {"entrega_estado": "falhou", "entrega_erro": str(d.get("erro") or "?")[:200]})
        return {"ok": True}
    if estado == "a-caminho" or r.get("estado") != "emitida":
        _garantir_emitida(r, rid, d, agora)
    if estado in ("entregue", "visto"):
        db.atualizar("whatsapp_messages", "msg_id=eq.ld-" + rid,
                     {"entrega_estado": estado, "enviada": True, "enviada_em": agora, "msg_id_saida": d.get("msg_id")})
    return {"ok": True}
