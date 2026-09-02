# -*- coding: utf-8 -*-
"""ferramentas_bot.py — as MAOS do cerebro. Cada ferramenta tem definicao (para o modelo) e execucao.

Principio: o bot so pode dizer o que ja verificou. O ciclo e FERRAMENTA -> RESPOSTA, nunca o
contrario. Cada uma devolve JSON com `ok` e, quando falha, `erro` verdadeiro -- nada de fallback
vazio a fingir que correu.
"""
import datetime
import json

from . import fichas, manual, supa, tarefas, telegram

DEFINICOES = [
    {"name": "ler_manual", "description": "Le a seccao do manual do Bora sobre um tema (precos, verticais, como pedir, parceiros, estafetas, reservas, pagamentos, tokens, app, cancelamentos, o Danilo...). Usa SEMPRE antes de afirmar um facto.",
     "parameters": {"type": "object", "properties": {"tema": {"type": "string", "description": "tema ou pergunta, em portugues"}}, "required": ["tema"]}},
    {"name": "ficha_contacto", "description": "A ficha viva da pessoa com quem estas a falar: nome provado, papel, o que ja pediu, o que lhe foi prometido, o que falta recolher.",
     "parameters": {"type": "object", "properties": {}}},
    {"name": "quem_e", "description": "Cruza o numero com o Supabase: e cliente (tem pedidos?), estafeta (estado), parceiro (que loja)? Nome no perfil?",
     "parameters": {"type": "object", "properties": {}}},
    {"name": "pedidos", "description": "Pedidos activos e recentes desta pessoa, com estado real, hora, estafeta e previsao pela media real de entrega. Usa quando falam de um pedido, atraso, 'onde esta'.",
     "parameters": {"type": "object", "properties": {}}},
    {"name": "loja", "description": "Dados de uma loja/restaurante do Bora pelo nome: horario, morada, categoria, se esta aberta agora, se e parceira.",
     "parameters": {"type": "object", "properties": {"nome": {"type": "string"}}, "required": ["nome"]}},
    {"name": "registar_lead", "description": "Guarda um interessado (parceiro, estafeta ou empresa) e o que ja se recolheu. Chama sempre que detectares intencao de ser parceiro/estafeta ou quando recolheres um dado novo.",
     "parameters": {"type": "object", "properties": {"tipo": {"type": "string", "enum": ["parceiro", "estafeta", "empresa"]},
                                                     "dados": {"type": "object", "description": "campos recolhidos (nome_loja, tipo, morada, horario, redes, contacto, veiculo, zona, disponibilidade, notas...)"}},
                    "required": ["tipo"]}},
    {"name": "agendar_seguimento", "description": "Cria uma tarefa com prazo para voltares a esta pessoa. OBRIGATORIO sempre que disseres 'vou ver', 'ja lhe digo' ou o Danilo tiver de responder.",
     "parameters": {"type": "object", "properties": {"minutos": {"type": "integer", "description": "prazo em minutos (3 por defeito; 30 se depende do Danilo)"},
                                                     "motivo": {"type": "string"}}, "required": ["motivo"]}},
    {"name": "avisar_danilo", "description": "Manda um aviso ao Danilo no Telegram (dinheiro, reembolso, desconto, reclamacao, estafeta/parceiro em falta, lead novo, algo que nao sabes).",
     "parameters": {"type": "object", "properties": {"texto": {"type": "string"}}, "required": ["texto"]}},
    {"name": "guardar_na_ficha", "description": "Anota na ficha da pessoa um facto que ela deu (nome, tem restaurante X, esta a abrir loja, preferencias).",
     "parameters": {"type": "object", "properties": {"campo": {"type": "string", "enum": ["nome", "nota", "falta_recolher"]}, "valor": {"type": "string"}}, "required": ["campo", "valor"]}},
]


def _media_entrega_min():
    try:
        rows = supa.select("orders", select="created_at,delivered_at", delivered_at="not.is.null",
                           is_test_order="not.is.true", order="delivered_at.desc", limit="50")
        ds = []
        for r in rows:
            a = datetime.datetime.fromisoformat(r["created_at"].replace("Z", "+00:00"))
            b = datetime.datetime.fromisoformat(r["delivered_at"].replace("Z", "+00:00"))
            m = (b - a).total_seconds() / 60
            if 3 <= m <= 240:
                ds.append(m)
        if not ds:
            return 30.0, 0
        ds.sort()
        return round(ds[len(ds) // 2], 1), len(ds)
    except Exception:
        return 30.0, 0


ESTADOS = {"created": "criado, à espera da loja", "preparing": "a ser preparado", "callingDriver": "à procura de estafeta",
           "driverAccepted": "estafeta aceitou, vai buscar", "pickedUp": "recolhido pelo estafeta",
           "onTheWay": "a caminho", "delivered": "entregue", "cancelled": "cancelado"}


ATRASO_PROVA = 0.0     # prova 6 da missao: a ferramenta e forcada a demorar; o cliente tem de ouvir algo aos 20 s


def _pedidos(ctx):
    if ATRASO_PROVA:
        import time as _t
        _t.sleep(ATRASO_PROVA)
    numero = ctx["numero"]
    n9 = numero[-9:]
    rows = supa.select("orders", select="id,status,created_at,delivered_at,vendor_name,assigned_driver_id,driver_phone,order_type,service_type,estimated_total,total",
                       client_phone="ilike.*" + n9 + "*", order="created_at.desc", limit="5")
    media, n = _media_entrega_min()
    agora = datetime.datetime.now(datetime.timezone.utc)
    out = []
    for o in rows:
        try:
            criado = datetime.datetime.fromisoformat(o["created_at"].replace("Z", "+00:00"))
            minutos = round((agora - criado).total_seconds() / 60)
        except Exception:
            minutos = None
        activo = o["status"] not in ("delivered", "cancelled")
        item = {"id": o["id"][:8], "estado": ESTADOS.get(o["status"], o["status"]), "activo": activo,
                "loja": o.get("vendor_name"), "ha_minutos": minutos, "tem_estafeta": bool(o.get("assigned_driver_id"))}
        if activo and minutos is not None:
            resto = max(0, round(media - minutos))
            item["previsao"] = ("mais %d min, pela média real" % resto) if resto > 0 else "já passou da média real (%d min) — pedir desculpa e explicar" % round(media)
        out.append(item)
    return {"ok": True, "pedidos": out, "media_real_min": media, "n_amostras": n,
            "nota": "sem pedidos neste numero" if not out else "nunca digas valores de dinheiro do pedido"}


def _loja(nome):
    rows = supa.select("restaurants", select="id,name,address,phone,category,is_partner,is_online,business_hours,reservations_enabled,takeaway_enabled",
                       name="ilike.*" + (nome or "").strip() + "*", limit="3")
    dia = datetime.datetime.now().strftime("%A").lower()
    out = []
    for r in rows:
        out.append({"nome": r["name"], "morada": r.get("address"), "categoria": r.get("category"), "parceira": r.get("is_partner"),
                    "online_agora": r.get("is_online"), "reservas": r.get("reservations_enabled"), "takeaway": r.get("takeaway_enabled"),
                    "horario_bruto": r.get("business_hours"), "hoje": dia})
    return {"ok": True, "lojas": out, "nota": "o horario certo esta na app, na pagina da loja; is_online diz se esta a receber pedidos agora"}


def executar(nome, args, ctx):
    """ctx = {numero, ficha, registar, porta}. Devolve dict serializavel."""
    args = args or {}
    f = ctx["ficha"]
    try:
        if nome == "ler_manual":
            return {"ok": True, "manual": manual.ler(str(args.get("tema") or ""))}
        if nome == "ficha_contacto":
            return {"ok": True, "ficha": {k: f.get(k) for k in ("nome", "nome_fonte", "tratamento", "registo", "lingua", "papel",
                                                                  "papel_detalhe", "o_que_pediu", "prometido", "falta_recolher", "notas")}}
        if nome == "quem_e":
            fichas.cruzar_supabase(f)
            return {"ok": True, "papel": f.get("papel"), "nome": f.get("nome"), "nome_fonte": f.get("nome_fonte"),
                    "detalhe": f.get("papel_detalhe")}
        if nome == "pedidos":
            return _pedidos(ctx)
        if nome == "loja":
            return _loja(args.get("nome"))
        if nome == "registar_lead":
            tipo = args.get("tipo") or "parceiro"
            dados = args.get("dados") or {}
            lead = None
            if f.get("lead_id"):
                try:
                    lead = supa.um("whatsapp_leads", id="eq." + str(f["lead_id"]))
                except Exception:
                    lead = None
            if lead:
                novos = dict(lead.get("dados") or {})
                novos.update({k: v for k, v in dados.items() if v})
                supa.update("whatsapp_leads", {"dados": novos, "estado": "em_recolha" if lead.get("estado") == "novo" else lead.get("estado")}, id="eq." + str(lead["id"]))
                lead["dados"] = novos
            else:
                r = supa.insert("whatsapp_leads", {"numero": ctx["numero"], "tipo": tipo, "estado": "em_recolha" if dados else "novo", "dados": dados})
                lead = r[0] if isinstance(r, list) else r
                f["lead_id"] = lead["id"]
            if f.get("papel") == "desconhecido":
                f["papel"] = "prospect_" + tipo
            falta = [c for c in ("nome_loja", "tipo", "morada", "horario", "redes_ou_fotos", "contacto") if not (lead.get("dados") or {}).get(c)] if tipo == "parceiro" else \
                    [c for c in ("nome", "veiculo", "zona", "disponibilidade") if not (lead.get("dados") or {}).get(c)]
            f["falta_recolher"] = falta
            minimo = tipo == "parceiro" and all((lead.get("dados") or {}).get(c) for c in ("nome_loja", "tipo")) and \
                ((lead.get("dados") or {}).get("redes_ou_fotos") or (lead.get("dados") or {}).get("redes") or (lead.get("dados") or {}).get("fotos"))
            return {"ok": True, "lead_id": lead["id"], "dados": lead.get("dados"), "falta_recolher": falta,
                    "minimo_para_montar": bool(minimo), "nota": "pede UMA ou DUAS coisas de cada vez, ao ritmo da conversa"}
        if nome == "agendar_seguimento":
            minutos = int(args.get("minutos") or 3)
            t = tarefas.criar(ctx["numero"], str(args.get("motivo") or "seguimento"), minutos, "agente")
            ctx.setdefault("tarefas_criadas", []).append(t["id"])
            fichas.anotar_promessa(f, str(args.get("motivo") or ""), "aberta", t["id"])
            return {"ok": True, "tarefa_id": t["id"], "prazo": t["prazo"]}
        if nome == "avisar_danilo":
            texto = "WhatsApp da loja — %s: %s" % (ctx["numero"], str(args.get("texto") or "")[:600])
            ok, det = telegram.enviar(texto, ctx.get("registar"))
            ctx["danilo_avisado"] = True
            return {"ok": ok, "detalhe": det if not ok else "enviado"}
        if nome == "guardar_na_ficha":
            campo, valor = args.get("campo"), str(args.get("valor") or "").strip()
            if campo == "nome" and valor:
                # so e nome se a PESSOA o escreveu nesta mensagem; nunca de textos antigos nem de saidas
                msg_actual = (ctx.get("msg_actual") or "").lower()
                primeiro = valor.split()[0].lower()
                if primeiro not in msg_actual or primeiro in {x.lower() for x in f.get("nomes_negados") or []} or f.get("papel") == "teste":
                    return {"ok": False, "erro": "nome recusado: nao esta na mensagem da pessoa (ou foi negado) -- nunca se apanha nome de texto antigo"}
                f["nome"], f["nome_fonte"] = valor[:80], "disse"
            elif campo == "falta_recolher" and valor:
                f["falta_recolher"] = [valor[:120]]
            elif valor:
                f["notas"] = ((f.get("notas") or "") + "\n- " + datetime.date.today().isoformat() + ": " + valor[:200]).strip()
            return {"ok": True}
        return {"ok": False, "erro": "ferramenta desconhecida: %s" % nome}
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "erro": "%s: %s" % (type(e).__name__, str(e)[:200])}


def para_json(obj):
    return json.dumps(obj, ensure_ascii=False, default=str)[:6000]
