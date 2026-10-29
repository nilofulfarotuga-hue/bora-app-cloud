#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
lembretes_danilo.py — os lembretes do dono, pelo WhatsApp da Bora (missao final-app-2026-10-29, 5.c).

  diario   [--dia AAAA-MM-DD] [--seco]   09:30 de Lisboa. UMA mensagem com os itens desse dia que
                                         ainda nao foram enviados nem feitos ("• texto — link"), mais os
                                         dos 7 dias anteriores que ficaram por enviar ("(do dia dd/mm)").
  urgentes [--seco]                      de 10 em 10 min. So os itens urgentes ja vencidos, ainda
                                         nao enviados nem feitos.

Os itens vivem em public.lembretes_danilo (ecra "Lembretes" do painel admin). Esta rotina NAO fala
com o WhatsApp: poe uma linha em public.whatsapp_saida (porta vps-baileys, motivo
'lembrete-danilo:...:ids=1,2,3'). Quem emite e marca 'emitida' e o servico assistente-negocio,
pela pista /opt/assistente-negocio/lembretes_lane.py, que SO deixa sair para o numero guardado
em LEMBRETES_DESTINO e nao obedece ao interruptor ENVIO_DESLIGADO (que continua a valer para todos
os outros). O numero de destino vive so no .env da VPS (chmod 600), nunca no repo.

A primeira mensagem de sempre abre com a linha que explica o que e. O texto nunca leva o nome do dono
(a trava do anonimato recusava-o); se algum item o tiver, a mensagem NAO sai e fica em erros.log.

ENSAIO: --seco mostra a mensagem e nao escreve nada.
"""
import argparse
import datetime
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from zoneinfo import ZoneInfo

sys.path.insert(0, "/opt/data/rotinas")
from comum import E, SUPA_URL, SUPA_KEY, CTX, registar_erro  # noqa: E402

TZ = ZoneInfo("Europe/Lisbon")
UTC = datetime.timezone.utc
DIAS = ["segunda", "terça", "quarta", "quinta", "sexta", "sábado", "domingo"]
# Nomes que nunca podem sair numa mensagem (anonimato do dono). A lista vem do .env
# (LEMBRETES_NOMES_DONO=nome1,nome2), nunca escrita aqui: o repositorio e publico.
_NOMES = [n.strip() for n in (E.get("LEMBRETES_NOMES_DONO") or "").split(",") if n.strip()]
RE_DONO = re.compile(r"(?i)\b(" + "|".join(re.escape(n) for n in _NOMES) + r")\b") if _NOMES else None
INTRO = "Olá, este é o lembrete diário do Bora: todos os dias às 9h30 recebes aqui o que precisa de ti."
ESTADOS_MORTOS = "(falhou,cancelada-anonimato,cancelada-fora-da-allowlist,cancelada-expirada)"


def destino():
    d = re.sub(r"\D", "", E.get("LEMBRETES_DESTINO") or "")
    return d or None


def pedir(metodo, caminho, corpo=None, prefer=None):
    h = {"apikey": SUPA_KEY, "Authorization": "Bearer " + SUPA_KEY, "Content-Type": "application/json"}
    if prefer:
        h["Prefer"] = prefer
    data = json.dumps(corpo).encode("utf-8") if corpo is not None else None
    req = urllib.request.Request("%s/rest/v1/%s" % (SUPA_URL, caminho), data=data, headers=h, method=metodo)
    try:
        with urllib.request.urlopen(req, timeout=45, context=CTX) as r:
            txt = r.read().decode("utf-8")
            return json.loads(txt) if txt else None
    except urllib.error.HTTPError as e:
        raise RuntimeError("%s %s -> %s %s" % (metodo, caminho.split("?")[0], e.code, e.read().decode("utf-8", "ignore")[:200]))


def iso_utc(dt):
    return dt.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def linha_item(it, antes_de=None):
    t = (it.get("texto") or "").strip()
    l = (it.get("link") or "").strip()
    if antes_de is not None:   # item de um dia anterior que ficou por enviar: diz-se de que dia era
        try:
            d = datetime.datetime.fromisoformat(str(it["quando"]).replace("Z", "+00:00")).astimezone(TZ)
            if d < antes_de:
                t = "%s (do dia %s)" % (t, d.strftime("%d/%m"))
        except Exception:  # noqa: BLE001
            pass
    return "• %s — %s" % (t, l) if l else "• " + t


def ja_foi_primeira():
    r = pedir("GET", "whatsapp_saida?select=id&motivo=like.lembrete-danilo*&estado=eq.emitida&limit=1")
    return bool(r)


def ids_em_voo():
    """Ids de itens que ja estao numa linha pendente ou a enviar (para nao enfileirar duas vezes)."""
    r = pedir("GET", "whatsapp_saida?select=motivo&motivo=like.lembrete-danilo*&estado=in.(pendente,a-enviar)") or []
    ids = set()
    for x in r:
        m = re.search(r"ids=([0-9,]+)", x.get("motivo") or "")
        if m:
            ids.update(m.group(1).split(","))
    return ids


def enfileirar(texto, motivo, ids, seco):
    if RE_DONO is not None and RE_DONO.search(texto):
        registar_erro("lembretes_danilo", RuntimeError("texto com o nome do dono; nao enviado (ids %s)" % ids))
        print("TRAVADO: o texto leva o nome do dono; nao enfileirei", file=sys.stderr)
        return 3
    if seco:
        print("--- ENSAIO (nada escrito) ---\nmotivo: %s\n%s" % (motivo, texto))
        return 0
    row = pedir("POST", "whatsapp_saida", {
        "numero": destino(), "texto": texto, "porta_destino": "vps-baileys",
        "motivo": "%s:ids=%s" % (motivo, ",".join(ids)), "origem": "lembretes_danilo.py", "estado": "pendente"},
        prefer="return=representation")
    print(json.dumps({"enfileirado": row[0]["id"], "estado": row[0]["estado"], "itens": ids, "criada": row[0]["created_at"]},
                     ensure_ascii=False))
    return 0


def diario(dia, seco):
    ini = datetime.datetime.combine(dia, datetime.time(0, 0), tzinfo=TZ)
    fim = ini + datetime.timedelta(days=1)
    ja = pedir("GET", "whatsapp_saida?select=id,estado&motivo=like.%s*&estado=not.in.%s&limit=1" % (
        urllib.parse.quote("lembrete-danilo:diario:%s" % dia.isoformat()), ESTADOS_MORTOS))
    if ja and not seco:
        print("SALTA: o lembrete diario de %s ja foi enfileirado (%s, %s)" % (dia, ja[0]["id"], ja[0]["estado"]))
        return 0
    # Os itens do dia e os dos ultimos 7 dias que ficaram por enviar (maquina em baixo as 09:30, ou
    # item criado no painel depois da hora): nada se perde calado. Cada item sai uma so vez.
    desde = ini - datetime.timedelta(days=7)
    itens = pedir("GET", "lembretes_danilo?select=id,texto,link,quando&feito_em=is.null&enviado_em=is.null"
                  "&quando=gte.%s&quando=lt.%s&order=quando.asc,id.asc" % (iso_utc(desde), iso_utc(fim))) or []
    voo = ids_em_voo()
    itens = [i for i in itens if str(i["id"]) not in voo]
    if not itens:
        print("SALTA: nenhum lembrete por enviar em %s" % dia)
        return 0
    cab = "Lembretes de hoje, %s %s:" % (DIAS[dia.weekday()], dia.strftime("%d/%m"))
    corpo = "\n".join([cab] + [linha_item(i, antes_de=ini) for i in itens])
    texto = (INTRO + "\n\n" + corpo) if not ja_foi_primeira() else corpo
    return enfileirar(texto, "lembrete-danilo:diario:%s" % dia.isoformat(), [str(i["id"]) for i in itens], seco)


def urgentes(seco):
    agora = datetime.datetime.now(UTC)
    itens = pedir("GET", "lembretes_danilo?select=id,texto,link,quando&urgente=is.true&feito_em=is.null&enviado_em=is.null"
                  "&quando=lte.%s&order=quando.asc,id.asc" % iso_utc(agora)) or []
    voo = ids_em_voo()
    itens = [i for i in itens if str(i["id"]) not in voo]
    if not itens:
        if seco:
            print("SALTA: nenhum urgente por enviar")
        return 0   # calado: corre de 10 em 10 min e nao enche o log
    corpo = "\n".join(["Urgente:"] + [linha_item(i) for i in itens])
    texto = (INTRO + "\n\n" + corpo) if not ja_foi_primeira() else corpo
    return enfileirar(texto, "lembrete-danilo:urgente:%s" % agora.strftime("%Y%m%dT%H%M"), [str(i["id"]) for i in itens], seco)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("modo", choices=["diario", "urgentes"])
    ap.add_argument("--dia")
    ap.add_argument("--seco", action="store_true")
    a = ap.parse_args()
    if not destino():
        registar_erro("lembretes_danilo", RuntimeError("LEMBRETES_DESTINO nao esta no .env"))
        print("ERRO: LEMBRETES_DESTINO nao esta no .env da VPS", file=sys.stderr)
        return 2
    try:
        if a.modo == "diario":
            dia = datetime.date.fromisoformat(a.dia) if a.dia else datetime.datetime.now(TZ).date()
            return diario(dia, a.seco)
        return urgentes(a.seco)
    except Exception as e:  # noqa: BLE001
        registar_erro("lembretes_danilo %s" % a.modo, e)
        print("ERRO: %s" % e, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
