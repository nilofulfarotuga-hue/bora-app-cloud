# -*- coding: utf-8 -*-
"""revisor.py — a revisao diaria do atendimento do WhatsApp da loja (bot da loja + robos dos parceiros).

Quem a lanca: o `servidor_cerebro.py` (VPS e PC), na thread `_cron`, todos os dias entre as 06:00 e as
06:05 da hora do servidor. Chama `correr(avisar, registar)`, que manda o resumo ao Danilo (Telegram).
As duas portas leem o mesmo banco; a `tranca` do servidor deixa sair so uma revisao por dia.

A mao, SEM enviar nem gravar nada (so imprime):
    cd /opt/whatsapp-bora && python3 -m cerebro.revisor --ensaio --dia 2026-10-29
    (--dia D = as 24 h que a revisao das 06:00 do dia seguinte le; --ate ISO para outra hora;
     --sem-modelo mostra so o que iria ao modelo, sem o chamar)

O que mudou a 30/10/2026 (dois falsos alarmes na revisao do dia 29/10):
  1. As respostas dos robos dos parceiros (assistente de negocio) vivem em `assistant_messages`; o revisor
     so lia `whatsapp_messages` e dizia "nao respondeu" quando o robo tinha respondido. Agora junta as
     duas tabelas por numero e por hora. Ficam de fora as conversas simuladas e os avisos que o robo
     manda ao dono da loja (passar_dono, pergunta_dono, resumo_semanal...), que nao sao atendimento.
  2. Cortava cada mensagem aos 200 caracteres e o modelo acusava o bot de mandar mensagens cortadas.
     Agora vai tudo inteiro. Se for mesmo preciso encurtar, fica escrito "[cortado pelo revisor]".
  3. Os lembretes ao Danilo (decisao 'lembrete-danilo:...') e as conversas da loja com parceiros e com
     o dono nao sao atendimento: ficam de fora e o resumo diz quantas. Os numeros leem-se da base
     (assistant_tenants, whatsapp_contacts, restaurants, service_providers) e do .env (LEMBRETES_DESTINO);
     nenhum numero fica escrito neste ficheiro (o repo e publico).
     Nota: o Danilo a testar um robo como cliente (allowlist do robo) conta como atendimento DO ROBO,
     porque e ai que se ve se o robo responde bem; as mensagens dele com a loja Bora e que saem.
  4. A mesma mensagem chega por duas portas (VPS e extensao do PC, as vezes 50 min depois) e, nos
     robos, fica tambem em assistant_messages. As copias saem, para nao parecer que ficou sem resposta.
"""
import argparse
import datetime
import json
import os
import re
import sys

if __package__ in (None, ""):          # python3 cerebro/revisor.py
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from cerebro import manual, modelos, supa  # noqa: E402

try:
    from zoneinfo import ZoneInfo
    LISBOA = ZoneInfo("Europe/Lisbon")
except Exception:  # noqa: BLE001  (Windows sem tzdata: fica em UTC, que no inverno e igual)
    LISBOA = datetime.timezone.utc

CORTE = "[cortado pelo revisor]"
LIMITE_MODELO = int(os.environ.get("REVISOR_LIMITE_CHARS") or 14000)   # tudo o que vai ao modelo
LIMITE_DIGEST = 3400                    # o telegram.enviar corta, calado, aos 3500
JANELA_COPIA_S = 90 * 60                # a extensao do PC chegou a apanhar a mesma mensagem 52 min depois
MOTIVO_PARA_O_DONO = re.compile(r"dono|resumo_semanal|prova", re.I)    # assistant_messages.motivo
SOMBRAS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_sombras.jsonl")   # = agente.SOMBRAS
SISTEMA = ("Es o revisor do atendimento do Bora. Para cada resposta do BOT diz: boa / fraca / errada + uma "
           "linha porque. No fim, 3 licoes curtas e accionaveis. Portugues, sem markdown. "
           "As mensagens vem inteiras: so onde aparece " + CORTE + " foi o revisor que encurtou, nao o bot. "
           "BOT e a resposta automatica (da loja Bora ou do robo do parceiro dito no titulo da conversa); "
           "a hora de Lisboa vem entre parenteses rectos.")


# --- ajudas ----------------------------------------------------------------------
def _digitos(n):
    return re.sub(r"\D", "", str(n or ""))


def _chave(n):
    """Os ultimos 9 digitos: o mesmo telemovel com e sem 351 e o mesmo numero."""
    d = _digitos(n)
    return d[-9:] if len(d) >= 9 else d


def _norm(t):
    return re.sub(r"\s+", " ", (t or "").strip().lower())


def _quando(iso):
    return datetime.datetime.fromisoformat(str(iso).replace("Z", "+00:00"))


def _ler(tabela, **params):
    params.setdefault("limit", "5000")
    return supa.select(tabela, **params)


# --- quem fica de fora -------------------------------------------------------------
def numeros_de_fora(linhas_wa, avisos):
    """{chave9: 'dono' | 'parceiro'}. Le da base e do .env; nenhum numero vive no codigo."""
    fora = {}

    def por(numero, papel):
        k = _chave(numero)
        if len(k) >= 9:
            fora.setdefault(k, papel)        # o dono ganha ao parceiro (le-se primeiro)

    por(supa.ENV.get("LEMBRETES_DESTINO") or os.environ.get("LEMBRETES_DESTINO"), "dono")
    for r in linhas_wa:                     # quem recebe os lembretes do Danilo e o Danilo
        if (r.get("decisao") or "").startswith("lembrete-danilo:"):
            por(r.get("numero"), "dono")
    fontes = [
        ("assistant_tenants", {"select": "dono_destino,owner_number"}, (("dono_destino", "dono"), ("owner_number", "parceiro"))),
        ("whatsapp_contacts", {"select": "numero", "or": "(papel.eq.parceiro,supabase_restaurant_id.not.is.null)"}, (("numero", "parceiro"),)),
        ("restaurants", {"select": "phone,whatsapp,mbway_phone", "or": "(phone.not.is.null,whatsapp.not.is.null,mbway_phone.not.is.null)"},
         (("phone", "parceiro"), ("whatsapp", "parceiro"), ("mbway_phone", "parceiro"))),
        ("service_providers", {"select": "phone,mbway_phone", "or": "(phone.not.is.null,mbway_phone.not.is.null)"},
         (("phone", "parceiro"), ("mbway_phone", "parceiro"))),
    ]
    for tabela, params, colunas in fontes:
        try:
            for r in _ler(tabela, **params):
                for col, papel in colunas:
                    por(r.get(col), papel)
        except Exception as e:  # noqa: BLE001
            avisos.append("nao consegui ler %s (%s): quem estiver so la pode entrar na revisao" % (tabela, str(e)[:120]))
    return fora


# --- recolha -------------------------------------------------------------------------
def recolher(desde, ate, avisos):
    """Le as 24 h das duas tabelas e devolve (linhas de atendimento, contagem do que ficou de fora)."""
    janela = "(created_at.gt.%s,created_at.lte.%s)" % (desde.isoformat(), ate.isoformat())
    wa = _ler("whatsapp_messages", **{"select": "id,numero,direcao,porta,tipo,texto,transcricao,decisao,created_at",
                                      "and": janela, "order": "created_at.asc"})
    try:
        robo = _ler("assistant_messages", **{"select": "id,tenant_id,numero,direcao,texto,motivo,decisao,simulado,created_at",
                                             "and": janela, "order": "created_at.asc"})
    except Exception as e:  # noqa: BLE001
        robo = []
        avisos.append("nao consegui ler assistant_messages (%s): as respostas dos robos nao entram" % str(e)[:120])
    try:
        robos = {t["id"]: (t.get("nome") or t.get("slug") or "robo") for t in _ler("assistant_tenants", select="id,slug,nome")}
    except Exception:  # noqa: BLE001
        robos = {}
    fora = numeros_de_fora(wa, avisos)
    conta = {"lidas_loja": len(wa), "lidas_robos": len(robo), "lembretes_danilo": 0, "com_o_dono": 0,
             "com_parceiros": 0, "simuladas": 0, "avisos_ao_dono_da_loja": 0, "copias": 0}
    linhas = []
    for r in wa:
        if (r.get("decisao") or "").startswith("lembrete-danilo:"):
            conta["lembretes_danilo"] += 1
            continue
        papel = fora.get(_chave(r.get("numero")))
        if papel:
            conta["com_o_dono" if papel == "dono" else "com_parceiros"] += 1
            continue
        texto = r.get("texto") or r.get("transcricao") or ""
        linhas.append({"numero": r.get("numero"), "chave": _chave(r.get("numero")), "quando": _quando(r["created_at"]),
                       "quem": "BOT" if r.get("direcao") == "saida" else "PESSOA", "texto": texto,
                       "vazio": "(%s sem texto)" % (r.get("tipo") or "mensagem"),
                       "origem": "loja:" + (r.get("porta") or "?"), "robo": None, "decisao": r.get("decisao") or ""})
    for r in robo:
        if r.get("simulado"):
            conta["simuladas"] += 1
            continue
        if r.get("direcao") == "saida" and MOTIVO_PARA_O_DONO.search(r.get("motivo") or ""):
            conta["avisos_ao_dono_da_loja"] += 1
            continue
        if fora.get(_chave(r.get("numero"))) == "parceiro":     # o dono da loja a falar com o proprio robo
            conta["com_parceiros"] += 1
            continue
        linhas.append({"numero": r.get("numero"), "chave": _chave(r.get("numero")), "quando": _quando(r["created_at"]),
                       "quem": "BOT" if r.get("direcao") == "saida" else "PESSOA", "texto": r.get("texto") or "",
                       "vazio": "(mensagem sem texto)", "origem": "robo:%s" % r.get("tenant_id"),
                       "robo": robos.get(r.get("tenant_id"), "robo"), "decisao": r.get("decisao") or ""})
    # copias: mesma pessoa, mesmo sentido, mesmo texto, outra origem, ate 90 min. Fica a do robo (a
    # conversa e dele e traz a decisao dele); entre as duas portas da loja fica a primeira.
    vistas, unicas = {}, []
    for l in sorted(linhas, key=lambda l: (l["robo"] is None, l["quando"])):
        n = _norm(l["texto"])
        if n:
            k = (l["chave"], l["quem"], n)
            if any(o != l["origem"] and abs((l["quando"] - q).total_seconds()) <= JANELA_COPIA_S for o, q in vistas.get(k, [])):
                conta["copias"] += 1
                continue
            vistas.setdefault(k, []).append((l["origem"], l["quando"]))
        unicas.append(l)
    unicas.sort(key=lambda l: l["quando"])
    return unicas, conta


# --- texto para o modelo -------------------------------------------------------------
def _linha_txt(l):
    hora = l["quando"].astimezone(LISBOA).strftime("%H:%M")
    nota = ""
    if l["robo"] and l["quem"] == "PESSOA" and l["decisao"].startswith("silencio"):
        # so nos robos (ex.: o dono assumiu a conversa). Na loja nao se diz: o 'silencio-missao' deixa o
        # cliente sem resposta e isso o revisor TEM de apontar.
        nota = " (o robo ficou calado de proposito: %s)" % l["decisao"]
    return "[%s] %s: %s%s" % (hora, l["quem"], l["texto"] or l["vazio"], nota)


def montar_texto(linhas):
    """Uma seccao por numero, por ordem de hora. Nada se corta; se passar do limite do modelo, saem
    as mensagens MAIS ANTIGAS da conversa mais comprida, e fica escrito quantas e que saiu."""
    conversas = {}
    for l in linhas:
        conversas.setdefault(l["chave"], []).append(l)
    blocos = []
    for chave, ls in conversas.items():
        nomes = sorted({l["robo"] for l in ls if l["robo"]})
        titulo = "### %s%s" % (chave[-3:], (" (robo: %s)" % ", ".join(nomes)) if nomes else " (bot da loja Bora)")
        blocos.append({"titulo": titulo, "linhas": [_linha_txt(l) for l in ls], "fora": 0})

    def total():
        return sum(len(b["titulo"]) + 2 + sum(len(x) + 1 for x in b["linhas"]) + (60 if b["fora"] else 0) for b in blocos)

    while blocos and total() > LIMITE_MODELO:
        com_varias = [b for b in blocos if len(b["linhas"]) > 1]
        if com_varias:
            b = max(com_varias, key=lambda b: len(b["linhas"]))
            b["linhas"].pop(0)
            b["fora"] += 1
            continue
        # so ficou uma mensagem por conversa e ainda nao cabe: encurta-se a mais comprida, e diz-se
        b = max(blocos, key=lambda b: len(b["linhas"][0]))
        linha = b["linhas"][0]
        novo = max(200, len(linha) - (total() - LIMITE_MODELO) - len(CORTE) - 1)
        if novo >= len(linha) or linha.endswith(CORTE):
            break
        b["linhas"][0] = linha[:novo] + " " + CORTE
    partes = []
    for b in blocos:
        cab = [b["titulo"]]
        if b["fora"]:
            cab.append("%s %d mensagens mais antigas desta conversa ficaram de fora (limite do modelo)" % (CORTE, b["fora"]))
        partes.append("\n".join(cab + b["linhas"]))
    return "\n\n".join(partes), len(conversas)


# --- a revisao ---------------------------------------------------------------------
def _proposta_da_sombra(desde_iso, avisos):
    """Das comparacoes Danilo-vs-bot do dia sai UMA regra de tom para ele aprovar (igual a antes)."""
    sombras = []
    if os.path.exists(SOMBRAS):
        for ln in open(SOMBRAS, encoding="utf-8"):
            try:
                s = json.loads(ln)
                if s.get("ts", "") > desde_iso and s.get("regra"):
                    sombras.append(s)
            except Exception:  # noqa: BLE001
                pass
    if not sombras:
        return "", 0
    try:
        r2 = modelos.chat([{"role": "system", "content": "Destas comparacoes entre o dono (Danilo) e o bot, escolhe ou funde UMA regra de tom, curta (max 160 caracteres), a mais util. So a regra."},
                           {"role": "user", "content": "\n".join("DONO: %s | BOT: %s | REGRA: %s" % (s["danilo"], s["bot"], s["regra"]) for s in sombras[-12:])}],
                          max_tokens=120, perfil="raciocinio")
        return (r2.get("texto") or "").strip().split("\n")[0][:160], len(sombras)
    except Exception as e:  # noqa: BLE001
        avisos.append("sombra: %s" % str(e)[:120])
        return "", len(sombras)


def _cabeca_de_fora(conta):
    """So o que o Danilo reconhece de ouvido; o resto (simuladas, copias, avisos ao dono) fica no log."""
    partes = []
    if conta["lembretes_danilo"]:
        partes.append("%d lembretes teus" % conta["lembretes_danilo"])
    if conta["com_o_dono"]:
        partes.append("%d mensagens tuas" % conta["com_o_dono"])
    if conta["com_parceiros"]:
        partes.append("%d de parceiros" % conta["com_parceiros"])
    if not partes:
        return ""
    lista = partes[0] if len(partes) == 1 else ", ".join(partes[:-1]) + " e " + partes[-1]
    return " Ficaram de fora, por não serem atendimento: " + lista + "."


def _encurtar_digest(texto):
    if len(texto) <= LIMITE_DIGEST:
        return texto
    corte = texto.rfind("\n", 0, LIMITE_DIGEST - len(CORTE) - 2)
    corte = corte if corte > LIMITE_DIGEST // 2 else LIMITE_DIGEST - len(CORTE) - 2
    return texto[:corte].rstrip() + "\n" + CORTE


def correr(avisar=None, registar=None, ensaio=False, ate=None, horas=24, chamar_modelo=True, mostrar=print):
    """A revisao. Em ensaio nada sai (Telegram) e nada se grava (manual, log): so `mostrar`."""
    registar = registar or (lambda _o: None)
    ate = ate or datetime.datetime.now(datetime.timezone.utc)
    desde = ate - datetime.timedelta(hours=horas)
    avisos = []
    try:
        linhas, conta = recolher(desde, ate, avisos)
    except Exception as e:  # noqa: BLE001
        registar({"evento": "auto-revisao-erro", "erro": str(e)[:200]})
        if ensaio:
            mostrar("ERRO a ler o banco: %s" % e)
        return None
    texto, n_conversas = montar_texto(linhas)
    if ensaio:
        mostrar("=== REVISOR (ENSAIO: nada e enviado a ninguem, nada se grava) ===")
        mostrar("janela: %s -> %s (UTC)" % (desde.isoformat(timespec="seconds"), ate.isoformat(timespec="seconds")))
        mostrar("lidas: %d da loja (whatsapp_messages) + %d dos robos (assistant_messages)" % (conta["lidas_loja"], conta["lidas_robos"]))
        mostrar("de fora: " + json.dumps({k: v for k, v in conta.items() if not k.startswith("lidas")}, ensure_ascii=False))
        for a in avisos:
            mostrar("AVISO: " + a)
        mostrar("conversas de atendimento: %d, mensagens: %d" % (n_conversas, len(linhas)))
        mostrar("===== ENTRADA DO MODELO =====")
        mostrar("--[system]--\n" + SISTEMA)
        mostrar("--[user]--\n" + (texto or "(nada)"))
    if not linhas:
        digest = "WhatsApp da loja — revisão diária: nenhuma conversa de atendimento nas últimas 24 h." + _cabeca_de_fora(conta)
        if ensaio:
            mostrar("===== DIGEST QUE IRIA AO DANILO (NAO ENVIADO) =====\n" + digest)
        else:
            avisar and avisar(digest)
            registar({"evento": "auto-revisao", "conversas": 0, "mensagens": 0, "de_fora": conta})
        return digest
    if ensaio and not chamar_modelo:
        mostrar("(--sem-modelo: o modelo nao foi chamado)")
        return None
    r = modelos.chat([{"role": "system", "content": SISTEMA}, {"role": "user", "content": texto}], max_tokens=700)
    saida = (r.get("texto") or ("(revisor sem resposta: %s)" % r.get("erro"))).strip()
    licoes = [l.strip("-• ").strip() for l in saida.split("\n") if l.strip()][-3:] if r.get("texto") else []
    rep = manual.perguntas_repetidas(2)
    proposta, n_sombras = _proposta_da_sombra(desde.isoformat(timespec="seconds"), avisos)
    digest = "Revisão diária do WhatsApp da loja: %d conversas, %d mensagens.%s\n\n%s%s%s" % (
        n_conversas, len(linhas), _cabeca_de_fora(conta), saida,
        ("\n\nPerguntas que se repetem e precisam de ti: " + "; ".join(p for _n, p in rep[:5])) if rep else "",
        ("\n\nPERGUNTAR AO DANILO — regra de tom proposta pela sombra (%d comparações de hoje): \"%s\". Responde 'aprovo regra' para entrar no manual." % (n_sombras, proposta)) if proposta else "")
    digest = _encurtar_digest(digest)
    if ensaio:
        mostrar("===== SAIDA DO MODELO (%s) =====\n%s" % (r.get("modelo"), saida))
        mostrar("===== LICOES QUE IRIAM PARA O MANUAL (NAO GRAVADAS) =====\n" + "\n".join(licoes))
        mostrar("===== DIGEST QUE IRIA AO DANILO (NAO ENVIADO) =====\n" + digest)
        return digest
    for ln in licoes:
        manual.registar_licao(ln[:220])
    avisar and avisar(digest)
    registar({"evento": "auto-revisao", "conversas": n_conversas, "mensagens": len(linhas), "de_fora": conta,
              "avisos": avisos[:5]})
    return digest


def main(argv=None):
    p = argparse.ArgumentParser(description="Revisao diaria do WhatsApp da loja -- a mao e sempre em ensaio (nada sai).")
    p.add_argument("--ensaio", "--dry-run", action="store_true", help="obrigatorio: so imprime, nada se envia nem grava")
    p.add_argument("--dia", help="AAAA-MM-DD: as 24 h que a revisao das 06:00 (UTC) do dia seguinte le")
    p.add_argument("--ate", help="fim da janela em ISO (por omissao: agora)")
    p.add_argument("--horas", type=int, default=24)
    p.add_argument("--sem-modelo", action="store_true", help="nao chama o modelo; mostra so o que lhe iria")
    a = p.parse_args(argv)
    if not a.ensaio:
        p.error("a mao so corre em ensaio: junta --ensaio (a revisao a serio sai do servidor_cerebro as 06:00)")
    ate = None
    if a.dia:
        d = datetime.date.fromisoformat(a.dia) + datetime.timedelta(days=1)
        ate = datetime.datetime(d.year, d.month, d.day, 6, 0, tzinfo=datetime.timezone.utc)
    elif a.ate:
        ate = _quando(a.ate)
        ate = ate if ate.tzinfo else ate.replace(tzinfo=datetime.timezone.utc)
    correr(ensaio=True, ate=ate, horas=a.horas, chamar_modelo=not a.sem_modelo)


if __name__ == "__main__":
    main()
