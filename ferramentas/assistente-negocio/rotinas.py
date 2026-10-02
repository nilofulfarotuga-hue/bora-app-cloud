"""Rotinas do Assistente de Negocio — corre de minuto a minuto dentro do servidor.

Tudo e idempotente pela base de dados (colunas *_sent_at / tarefas), por isso pode correr em
qualquer maquina sem mandar a mesma coisa duas vezes. Em modo teste so escreve para a allowlist
(a rede de seguranca esta em assistente.enfileirar)."""
import datetime as dt
import json
import os
import urllib.parse
import urllib.request

import assistente as A
import db


# ----------------------------------------------------------------------------- telegram (texto simples)
def _env_hermes(chave):
    for f in ("/opt/data/.env", "/docker/hermes-agent-fvnc/data/.env"):
        try:
            for l in open(f, encoding="utf-8", errors="ignore"):
                if l.startswith(chave + "="):
                    return l.split("=", 1)[1].strip().strip('"')
        except OSError:
            continue
    return os.environ.get(chave, "")


def telegram(txt):
    tok, ch = _env_hermes("TELEGRAM_BOT_TOKEN"), _env_hermes("TELEGRAM_HOME_CHANNEL")
    if not tok or not ch:
        return False
    try:
        req = urllib.request.Request(f"https://api.telegram.org/bot{tok}/sendMessage",
                                     json.dumps({"chat_id": ch, "text": txt}).encode(), {"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=15) as r:
            return bool(json.load(r).get("ok"))
    except Exception:
        return False


# ----------------------------------------------------------------------------- marcacoes
def _marcacoes(t, desde, ate):
    return db.ler("appointments",
                  f"assistant_tenant_id=eq.{t['id']}&status=in.(confirmed,completed,awaiting_confirmation)"
                  f"&scheduled_at=gte.{db.q(A.iso(desde))}&scheduled_at=lte.{db.q(A.iso(ate))}",
                  "id,service_id,client_name,client_phone,scheduled_at,duration_minutes,created_at,status,"
                  "assistant_reminder_sent_at,assistant_review_sent_at,is_test")


def _nome_servico(t, sid):
    return next((s["name"] for s in A.servicos(t) if s["id"] == sid), "o serviço")


def _ola(nome):
    return f"Olá {nome.split()[0]}!" if nome and nome != "Cliente WhatsApp" else "Olá!"


def lembretes(t, agora):
    for a in _marcacoes(t, agora, agora + dt.timedelta(days=2)):
        if a.get("assistant_reminder_sent_at"):
            continue
        s, criada = A.hora_local(a["scheduled_at"]), A.hora_local(a["created_at"])
        vespera = dt.datetime.combine(s.date() - dt.timedelta(days=1), dt.time(18, 0), A.LX)
        envio = vespera if criada < vespera else s - dt.timedelta(hours=2)
        if criada >= envio:  # marcada em cima da hora: nao ha lembrete que faca sentido
            db.rpc("assistente_aviso_enviado", {"p_appointment_id": a["id"], "p_tipo": "lembrete"})
            continue
        if not (envio <= agora < s):
            continue
        quando = "amanhã" if s.date() != agora.date() else "hoje"
        f = (t.get("knowledge") or {}).get("ficha", {})
        txt = (f"{_ola(a.get('client_name'))} Lembrete: {quando} às {s.strftime('%H:%M')} tem {_nome_servico(t, a['service_id'])} "
               f"na {t['nome']} ({f.get('morada', '')}). Se precisar de mudar, diga-me aqui.")
        A.enfileirar(t, A.so_digitos(a["client_phone"]), txt, f"lembrete:{a['id']}")
        db.rpc("assistente_aviso_enviado", {"p_appointment_id": a["id"], "p_tipo": "lembrete"})


def avaliacoes(t, agora):
    link = t.get("link_avaliacao") or ("https://www.google.com/maps/search/?api=1&query="
                                       + urllib.parse.quote(t["nome"] + " Guarda"))
    for a in _marcacoes(t, agora - dt.timedelta(days=1), agora):
        if a.get("assistant_review_sent_at"):
            continue
        fim = A.hora_local(a["scheduled_at"]) + dt.timedelta(minutes=a.get("duration_minutes") or 30)
        if agora < fim + dt.timedelta(hours=1):
            continue
        numero = A.so_digitos(a["client_phone"])
        if agora < fim + dt.timedelta(hours=24) and 9 <= agora.hour < 21:
            txt = (f"{_ola(a.get('client_name'))} Obrigado pela visita à {t['nome']}. "
                   f"Se gostou, ajudava-nos muito uma avaliação no Google: {link}")
            A.enfileirar(t, numero, txt, f"avaliacao:{a['id']}")
        elif agora < fim + dt.timedelta(hours=24):
            continue  # fora de horas: espera pela manha
        db.rpc("assistente_aviso_enviado", {"p_appointment_id": a["id"], "p_tipo": "avaliacao"})
        A.contacto(t, numero)
        A.gravar_contacto(t, numero, {"ultima_visita": a["scheduled_at"], "ultimo_servico": _nome_servico(t, a["service_id"])})


def reativacao(t, agora):
    if agora.weekday() == 6 or not (10 <= agora.hour < 19):
        return
    limite = agora - dt.timedelta(days=35)
    for c in db.ler("assistant_contacts", f"tenant_id=eq.{t['id']}&ultima_visita=lt.{db.q(A.iso(limite))}&pessoal=eq.false"):
        if c.get("reativacao_enviada_em") and c["reativacao_enviada_em"] > c["ultima_visita"]:
            continue
        if db.rpc("assistente_minhas_marcacoes", {"p_tenant": t["id"], "p_telefone": c["numero"]}):
            continue
        txt = (f"{_ola(c.get('nome'))} Já passou mais de um mês desde o último {c.get('ultimo_servico') or 'corte'} na {t['nome']}. "
               f"Quer marcar? Diga-me o dia que lhe dá jeito e eu vejo as vagas.")
        A.enfileirar(t, c["numero"], txt, "reativacao")
        A.gravar_contacto(t, c["numero"], {"reativacao_enviada_em": A.iso(agora),
                                           "a_espera_de": {"o_que": "reativação enviada — se responder, propor vagas"}})


def vigia_perguntas(t, agora):
    for k in db.ler("assistant_tasks", f"tenant_id=eq.{t['id']}&tipo=eq.pergunta_dono&estado=eq.aberta&prazo=lt.{db.q(A.iso(agora))}"):
        sim = bool(k.get("simulado"))
        if k["tentativas"] == 0:
            A.enfileirar(t, A.so_digitos(t["dono_destino"]),
                         f"⏰ Ainda à espera da tua resposta ({k['codigo']}): «{k['pergunta']}». Responde a citar a pergunta ou com {k['codigo']} e a resposta.",
                         f"pergunta_dono_lembrete:{k['id']}", sim)
            db.atualizar("assistant_tasks", f"id=eq.{k['id']}", {"tentativas": 1, "prazo": A.iso(agora + dt.timedelta(minutes=60))})
        elif k["tentativas"] == 1:
            tel = (t.get("knowledge") or {}).get("ficha", {}).get("telefone", "")
            A.enfileirar(t, k["numero"], f"Ainda não tive resposta do Ernando à sua pergunta. Assim que tiver, digo-lhe. Se for urgente, pode ligar para {tel}.",
                         f"pergunta_dono_ponto:{k['id']}", sim)
            db.atualizar("assistant_tasks", f"id=eq.{k['id']}", {"tentativas": 2, "prazo": A.iso(agora + dt.timedelta(hours=12))})
        else:
            db.atualizar("assistant_tasks", f"id=eq.{k['id']}", {"estado": "expirada"})
            if not sim:
                telegram(f"Assistente {t['nome']}: a pergunta {k['codigo']} («{k['pergunta']}») ficou sem resposta do dono 13 h. Cliente +{k['numero']}.")


def resumo_semanal(t, agora):
    if agora.weekday() != 6 or agora.hour < 20:
        return
    semana = agora.strftime("%G-W%V")
    if db.ler("assistant_tasks", f"tenant_id=eq.{t['id']}&tipo=eq.resumo_semanal&codigo=eq.{semana}"):
        return
    desde = agora - dt.timedelta(days=7)
    ent = db.ler("assistant_messages", f"tenant_id=eq.{t['id']}&direcao=eq.entrada&simulado=eq.false&created_at=gte.{db.q(A.iso(desde))}",
                 "numero,created_at")
    bh = (A.negocio(t).get("business_hours") or {})

    def fora(iso_):
        h = A.hora_local(iso_)
        d = bh.get(A.DIAS_BH[h.weekday()]) or {}
        return d.get("closed") or not d or not (d.get("open", "00:00") <= h.strftime("%H:%M") < d.get("close", "23:59"))

    marc = db.ler("appointments", f"assistant_tenant_id=eq.{t['id']}&created_at=gte.{db.q(A.iso(desde))}&status=neq.cancelled",
                  "client_phone,service_price_cents,is_test")
    reat = db.ler("assistant_contacts", f"tenant_id=eq.{t['id']}&reativacao_enviada_em=gte.{db.q(A.iso(desde))}", "numero")
    rec = {A.so_digitos(m["client_phone"]) for m in marc} & {c["numero"] for c in reat}
    valor = sum(m.get("service_price_cents") or 0 for m in marc)
    teste = " (modo teste)" if t["mode"] == "teste" else ""
    txt = (f"📊 {t['nome']} — resumo da semana{teste}\n"
           f"Conversas: {len({e['numero'] for e in ent})}\n"
           f"Marcações feitas pelo assistente: {len(marc)} ({A.euros(valor)})\n"
           f"Mensagens fora de horas atendidas: {sum(1 for e in ent if fora(e['created_at']))}\n"
           f"Clientes recuperados (voltaram depois do lembrete de 35 dias): {len(rec)}")
    A.enfileirar(t, A.so_digitos(t["dono_destino"]), txt, "resumo_semanal")
    db.inserir("assistant_tasks", {"tenant_id": t["id"], "tipo": "resumo_semanal", "codigo": semana, "estado": "cumprida",
                                   "resposta": txt, "cumprida_em": A.iso(agora)}, devolver=False)


def orcamento(t, agora):
    gasto, tecto = A.custo_mes(t), float(t["orcamento_mensal_eur"])
    mes = agora.strftime("%Y-%m")
    if gasto >= 0.8 * tecto and t.get("aviso_orcamento_mes") != mes:
        if telegram(f"Assistente {t['nome']}: já gastou {gasto:.2f} € dos {tecto:.2f} € do mês ({gasto / tecto:.0%}). "
                    f"Ao chegar aos 100 % passa sozinho para os motores grátis."):
            db.atualizar("assistant_tenants", f"id=eq.{t['id']}", {"aviso_orcamento_mes": mes})


def limpar_vozes(dias=7):
    """Notas de voz geradas (.ogg) com mais de N dias: ja foram entregues; a transcricao/texto fica na base."""
    import glob
    import time as _t
    for f in glob.glob(os.path.join(A.voz.PASTA_VOZ, "*.ogg")):
        if _t.time() - os.path.getmtime(f) > dias * 86400:
            os.unlink(f)


def ciclo():
    agora = A.agora()
    feitos = {}
    if agora.minute == 0:
        try:
            limpar_vozes()
        except Exception as e:
            feitos["limpar_vozes_erro"] = str(e)[:200]
    for t in db.ler("assistant_tenants", "mode=neq.desligado"):
        for f in (lembretes, avaliacoes, reativacao, vigia_perguntas, resumo_semanal, orcamento):
            try:
                f(t, agora)
                feitos[f.__name__] = feitos.get(f.__name__, 0) + 1
            except Exception as e:  # uma rotina partida nao pode parar as outras
                feitos[f.__name__ + "_erro"] = str(e)[:200]
    return feitos
