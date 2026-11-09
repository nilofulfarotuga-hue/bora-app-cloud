#!/usr/bin/env python3
# -*- coding: ascii -*-
"""
estado_operacao.py -- escreve num ficheiro o estado real da operacao, para os
agentes o poderem LER.

PORQUE EXISTE
  A torre e o vigia dos pedidos presos. A 2026-09-08 descobriu-se que ela NAO
  CONSEGUE ver a base de dados: a unica credencial ao seu alcance e a chave
  anonima, e com essa a tabela orders devolve HTTP 200 com zero linhas quando
  tem quinze. Um vigia que nao ve o que vigia diz "esta tudo bem" para sempre.

  Dar-lhe a chave de servico resolvia a leitura e punha uma chave que salta TODA
  a RLS ao alcance de um agente com linha de comandos. Nao se faz.

  Este caminho nao abre nada: a VPS, que JA tem a chave de servico e ja corre
  como root, escreve um ficheiro de texto; o agente le o ficheiro. Zero
  superficie publica nova.

O QUE ESCREVE
  Factos, nao juizos. Contagens por estado e o que esta pendente ha mais de 30
  minutos. Nao decide o que e "preso" -- mostra o que ha e deixa quem le julgar.
  Se uma consulta falhar, escreve que falhou. Nunca inventa um numero.

  Corre de 10 em 10 minutos. Ficheiro: /opt/data/estado-operacao.txt
"""
import datetime
import sys

sys.path.insert(0, "/opt/data/rotinas")
import emerson as E  # noqa: E402

SAIDA = "/opt/data/estado-operacao.txt"
MINUTOS_PARADO = 30

# Estados de fim de linha: o que estiver neles nao esta a espera de ninguem.
TERMINAIS = dict(
    orders=("delivered", "cancelled", "canceled", "rejected", "refunded"),
    tvde_rides=("finalizada", "cancelada_cliente", "cancelada_motorista", "cancelada"),
    appointments=("completed", "cancelled", "canceled", "no_show", "blocked"),
    cleaning_bookings=("completed", "cancelled_client", "cancelled", "no_show"),
)


def agora_utc():
    """UTC sem fuso, para as comparacoes ficarem simples.

    Nao se usa datetime.utcnow(): esta descontinuado e escrevia um aviso no
    ficheiro de erros a cada 10 minutos. Ruido que esconde sinal.
    """
    return datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)


def olhar(tabela):
    """Devolve (linhas, erro). Consulta falhada NAO e o mesmo que zero linhas."""
    desde = (agora_utc() - datetime.timedelta(days=7)).strftime("%Y-%m-%dT%H:%M:%S")
    r = E.rest("%s?select=id,status,created_at&created_at=gte.%s&limit=2000" % (tabela, desde))
    if r is None:
        return [], "a consulta falhou"
    return r, None


def contar(tabela, linhas):
    corte = agora_utc() - datetime.timedelta(minutes=MINUTOS_PARADO)
    por_estado = dict()
    parados = []
    for x in linhas:
        est = x.get("status") or "sem estado"
        por_estado[est] = por_estado.get(est, 0) + 1
        if est in TERMINAIS.get(tabela, ()):
            continue
        try:
            quando = datetime.datetime.strptime((x.get("created_at") or "")[:19], "%Y-%m-%dT%H:%M:%S")
        except (ValueError, TypeError):
            continue
        if quando < corte:
            parados.append((est, x.get("id"), x.get("created_at")))
    return por_estado, parados


def mensagem_sem_acesso():
    return "  NAO CONSEGUI LER as mensagens. Nao tomes o silencio por sossego."


def olhar_whatsapp():
    """Quem ficou a espera de resposta, e o que nao chegou a sair.

    O atendimento e um dos agentes que nao ve a base. Aqui ficam os factos de
    que ele precisa: por numero, comparar a ultima mensagem que ENTROU com a
    ultima que SAIU. Se a de entrada e mais recente, aquela pessoa esta a
    espera. E contam-se as entregas falhadas, que sao mensagens que ninguem
    recebeu -- silencio do lado de la que ninguem ve deste lado.
    """
    out = []
    r = E.rest("whatsapp_messages?select=numero,direcao,entrega_estado,created_at"
               "&order=created_at.desc&limit=1000")
    if r is None:
        return ([mensagem_sem_acesso()], 0, 0)
    if not r:
        return (["  sem mensagens registadas"], 0, 0)

    ultima_entrada = dict()
    ultima_saida = dict()
    falhadas = 0
    for x in r:
        num = x.get("numero") or "sem numero"
        quando = x.get("created_at") or ""
        if x.get("entrega_estado") == "falhou":
            falhadas += 1
        if x.get("direcao") == "entrada":
            if quando > ultima_entrada.get(num, ""):
                ultima_entrada[num] = quando
        elif x.get("direcao") == "saida":
            if quando > ultima_saida.get(num, ""):
                ultima_saida[num] = quando

    corte = (agora_utc() - datetime.timedelta(minutes=MINUTOS_PARADO)).strftime(
        "%Y-%m-%dT%H:%M:%S")
    a_espera = []
    for num, quando in ultima_entrada.items():
        if quando > ultima_saida.get(num, "") and quando < corte:
            a_espera.append((num, quando))
    a_espera.sort(key=lambda p: p[1])

    out.append("  mensagens lidas: %d  (numeros distintos: %d)"
               % (len(r), len(set(list(ultima_entrada) + list(ultima_saida)))))
    out.append("  entregas FALHADAS: %d" % falhadas)
    out.append("  pessoas SEM RESPOSTA ha mais de %d min: %d" % (MINUTOS_PARADO, len(a_espera)))
    for num, quando in a_espera[:10]:
        out.append("    - %s  ultima mensagem dela: %s" % (num, quando[:19]))
    return out, len(a_espera), falhadas


# ---------------------------------------------------------------------------
# 18/09 (missao sistema-redondo): os agentes ligados ao relogio (gestor-parceiros,
# cobrador, qualidade) nao tinham fonte nenhuma para abrir e respondiam NAO SEI.
# Passam a ler daqui. Factos, nao juizos; se a consulta falhar, esta escrito.

def _ok(r):
    return isinstance(r, list)


def olhar_parceiros():
    out = ["== parceiros =="]
    lojas = E.rest("restaurants?select=id,name,is_active_admin,approval_status,category"
                   "&is_partner=is.true&limit=200")
    if not _ok(lojas):
        out.append("  NAO CONSEGUI LER restaurants. Nao tomes o silencio por 'esta tudo bem'.")
        return out, True
    ids = [l["id"] for l in lojas]
    out.append("  lojas parceiras: %d (%s)" % (len(lojas), ", ".join(
        "%s%s" % (l.get("name"), "" if l.get("is_active_admin", True) else " [INACTIVA]") for l in lojas)[:600]))
    pend = [l.get("name") for l in lojas if (l.get("approval_status") or "") not in ("approved", "")]
    if pend:
        out.append("  com aprovacao pendente/recusada: " + ", ".join(str(x) for x in pend))
    if not ids:
        return out, False
    filtro_ids = ",".join('"%s"' % i for i in ids)
    prods = E.rest("products?select=restaurant_id,price,photo_url,is_available"
                   "&restaurant_id=in.(%s)&limit=5000" % filtro_ids)
    if _ok(prods):
        por = {}
        for p in prods:
            d = por.setdefault(p.get("restaurant_id"), {"n": 0, "sem_foto": 0, "sem_preco": 0, "fora": 0})
            d["n"] += 1
            if not (p.get("photo_url") or "").strip():
                d["sem_foto"] += 1
            try:
                if float(p.get("price") or 0) <= 0:
                    d["sem_preco"] += 1
            except (TypeError, ValueError):
                d["sem_preco"] += 1
            if p.get("is_available") is False:
                d["fora"] += 1
        nomes = {l["id"]: l.get("name") for l in lojas}
        for rid, d in por.items():
            out.append("  %s: %d produtos, %d sem foto, %d sem preco, %d indisponiveis"
                       % (nomes.get(rid, rid), d["n"], d["sem_foto"], d["sem_preco"], d["fora"]))
    else:
        out.append("  NAO CONSEGUI LER products.")
    desde = (agora_utc() - datetime.timedelta(days=7)).strftime("%Y-%m-%dT%H:%M:%S")
    peds = E.rest("orders?select=restaurant_id,status,is_test_order&restaurant_id=in.(%s)"
                  "&created_at=gte.%s&limit=2000" % (filtro_ids, desde))
    if _ok(peds):
        por = {}
        for o in peds:
            if o.get("is_test_order"):
                continue
            d = por.setdefault(o.get("restaurant_id"), {})
            d[o.get("status") or "?"] = d.get(o.get("status") or "?", 0) + 1
        nomes = {l["id"]: l.get("name") for l in lojas}
        if not por:
            out.append("  pedidos reais nos ultimos 7 dias: 0 em todas as lojas parceiras")
        for rid, d in por.items():
            out.append("  pedidos 7 dias em %s: " % nomes.get(rid, rid) +
                       ", ".join("%s %d" % (k, v) for k, v in sorted(d.items(), key=lambda p: -p[1])))
    else:
        out.append("  NAO CONSEGUI LER orders das lojas parceiras.")
    return out, False


def olhar_cobranca():
    out = ["== cobranca =="]
    erro = False
    for tabela, quem in (("partner_weekly_settlements", "partner_id"),
                         ("driver_weekly_settlements", "driver_id")):
        r = E.rest("%s?select=%s,week_start_at,net_balance,direction,status"
                   "&status=neq.paid&order=week_start_at.asc&limit=100" % (tabela, quem))
        if not _ok(r):
            out.append("  NAO CONSEGUI LER %s." % tabela)
            erro = True
            continue
        total = 0.0
        for x in r:
            try:
                total += float(x.get("net_balance") or 0)
            except (TypeError, ValueError):
                pass
        out.append("  %s por pagar/receber: %d acerto(s), soma liquida %.2f EUR" % (tabela, len(r), total))
        for x in r[:8]:
            out.append("    - %s semana %s: %s %s EUR, estado=%s" % (
                str(x.get(quem))[:8], str(x.get("week_start_at"))[:10], x.get("direction"),
                x.get("net_balance"), x.get("status")))
    r = E.rest("client_wallets?select=user_id,free_balance_cents&free_balance_cents=lt.0&limit=100")
    if _ok(r):
        out.append("  clientes com carteira NEGATIVA (divida): %d, soma %.2f EUR" % (
            len(r), sum(int(x.get("free_balance_cents") or 0) for x in r) / 100.0))
    else:
        out.append("  NAO CONSEGUI LER client_wallets.")
        erro = True
    r = E.rest("payouts?select=id,user_type,amount,status,created_at&status=neq.paid&limit=100")
    if _ok(r):
        out.append("  payouts nao pagos: %d" % len(r))
    return out, erro


def olhar_qualidade():
    out = ["== qualidade =="]
    erro = False
    desde = (agora_utc() - datetime.timedelta(days=7)).strftime("%Y-%m-%dT%H:%M:%S")
    r = E.rest("ratings?select=stars,rating,subject_type,comment,created_at&created_at=gte.%s&limit=500" % desde)
    if _ok(r):
        vals = []
        baixas = []
        for x in r:
            v = x.get("stars") if x.get("stars") is not None else x.get("rating")
            try:
                v = float(v)
            except (TypeError, ValueError):
                continue
            vals.append(v)
            if v <= 2:
                baixas.append("%s %s: %s" % (str(x.get("created_at"))[:10], x.get("subject_type"),
                                              (x.get("comment") or "sem comentario")[:80]))
        out.append("  avaliacoes nos ultimos 7 dias: %d, media %.2f" % (
            len(vals), (sum(vals) / len(vals)) if vals else 0.0))
        out.append("  avaliacoes de 1-2 estrelas: %d" % len(baixas))
        for b in baixas[:5]:
            out.append("    - " + b)
    else:
        out.append("  NAO CONSEGUI LER ratings.")
        erro = True
    r = E.rest("orders?select=id,status,cancellation_reason,is_test_order&status=in.(cancelled,rejected)"
               "&created_at=gte.%s&limit=500" % desde)
    if _ok(r):
        reais = [x for x in r if not x.get("is_test_order")]
        out.append("  pedidos cancelados/recusados (reais) nos ultimos 7 dias: %d" % len(reais))
    else:
        r2 = E.rest("orders?select=id,status,is_test_order&status=in.(cancelled,rejected)"
                    "&created_at=gte.%s&limit=500" % desde)
        if _ok(r2):
            out.append("  pedidos cancelados/recusados (reais) nos ultimos 7 dias: %d"
                       % len([x for x in r2 if not x.get("is_test_order")]))
        else:
            out.append("  NAO CONSEGUI LER orders cancelados.")
            erro = True
    r = E.rest("support_tickets?select=id,status,created_at&status=in.(open,pending,aberto)&limit=200")
    if _ok(r):
        out.append("  tickets de suporte abertos: %d" % len(r))
    return out, erro


def olhar_prospecao():
    """Prospecao (missao m6 08/11): a lista do vendedor vive na base (caca-clientes), nao no disco."""
    out = ["== prospecao (caca-clientes: prospects_presenca e prospect_propostas) =="]
    erro = False
    r = E.rest("prospects_presenca?select=estado,ultimo_contacto_em,resposta,nome&limit=3000")
    if _ok(r):
        por = dict()
        for x in r:
            k = x.get("estado") or "sem estado"
            por[k] = por.get(k, 0) + 1
        corte = (agora_utc() - datetime.timedelta(days=7)).strftime("%Y-%m-%dT%H:%M:%S")
        c7 = len([x for x in r if (x.get("ultimo_contacto_em") or "")[:19] >= corte])
        resp = [x for x in r if (x.get("resposta") or "").strip() or x.get("estado") in ("respondeu", "recusou", "interessado")]
        out.append("  negocios na lista: %d" % len(r))
        out.append("  por estado: " + ", ".join("%s %d" % (k, v) for k, v in sorted(por.items(), key=lambda p: -p[1])))
        out.append("  contactados nos ultimos 7 dias: %d" % c7)
        out.append("  com resposta (desde o inicio): %d" % len(resp))
        for x in resp[:5]:
            out.append("    - %s (%s): %s" % (x.get("nome"), x.get("estado"), " ".join((x.get("resposta") or "").split())[:80]))
    else:
        out.append("  NAO CONSEGUI LER prospects_presenca.")
        erro = True
    r = E.rest("prospect_propostas?select=estado,enviado_em&limit=3000")
    if _ok(r):
        d1 = (agora_utc() - datetime.timedelta(days=1)).strftime("%Y-%m-%dT%H:%M:%S")
        d7 = (agora_utc() - datetime.timedelta(days=7)).strftime("%Y-%m-%dT%H:%M:%S")
        saidas = [x for x in r if x.get("enviado_em")]
        out.append("  propostas enviadas: total %d, ultimas 24 h %d, ultimos 7 dias %d" % (
            len(saidas), len([x for x in saidas if x["enviado_em"][:19] >= d1]),
            len([x for x in saidas if x["enviado_em"][:19] >= d7])))
        out.append("  propostas prontas por enviar: %d, rascunhos: %d, responderam: %d" % (
            len([x for x in r if x.get("estado") == "pronta"]), len([x for x in r if x.get("estado") == "rascunho"]),
            len([x for x in r if x.get("estado") == "respondeu"])))
        out.append("  rotina: cacador 07:30, redator 08:00, envio 09:40, so dias uteis (sabado e domingo param de proposito).")
    else:
        out.append("  NAO CONSEGUI LER prospect_propostas.")
        erro = True
    return out, erro


def main():
    agora = agora_utc().strftime("%Y-%m-%d %H:%M:%S")
    out = []
    out.append("ESTADO DA OPERACAO -- escrito as %s UTC" % agora)
    out.append("Factos lidos da base com a chave de servico. Se algo falhou, esta escrito.")
    out.append("Pendente = fora dos estados de fim de linha e criado ha mais de %d minutos." % MINUTOS_PARADO)
    out.append("Janela: ultimos 7 dias.")
    out.append("")

    total_parados = 0
    houve_erro = False
    for tabela in ("orders", "tvde_rides", "appointments", "cleaning_bookings"):
        linhas, erro = olhar(tabela)
        out.append("== %s ==" % tabela)
        if erro:
            houve_erro = True
            out.append("  NAO CONSEGUI LER: %s. Nao tomes o silencio por 'esta tudo bem'." % erro)
            out.append("")
            continue
        por_estado, parados = contar(tabela, linhas)
        out.append("  linhas nos ultimos 7 dias: %d" % len(linhas))
        if por_estado:
            pares = sorted(por_estado.items(), key=lambda p: -p[1])
            out.append("  por estado: " + ", ".join("%s %d" % (k, v) for k, v in pares))
        out.append("  PENDENTES ha mais de %d min: %d" % (MINUTOS_PARADO, len(parados)))
        for est, ident, criado in parados[:10]:
            out.append("    - %s  estado=%s  criado=%s" % (ident, est, criado))
        total_parados += len(parados)
        out.append("")

    for fn in (olhar_parceiros, olhar_cobranca, olhar_qualidade, olhar_prospecao):
        try:
            linhas_x, erro_x = fn()
        except Exception as e:  # noqa: BLE001
            linhas_x, erro_x = ["== %s ==" % fn.__name__, "  REBENTOU: %s" % str(e)[:160]], True
        out.extend(linhas_x)
        out.append("")
        houve_erro = houve_erro or erro_x

    aviso = " E houve consultas que falharam." if houve_erro else ""
    out.append("== whatsapp ==")
    linhas_wa, sem_resposta, entregas_falhadas = olhar_whatsapp()
    out.extend(linhas_wa)
    out.append("")

    # O resumo TEM de somar tudo o que o corpo mostra. Escrever 0 pendentes
    # com quatro pessoas a espera no paragrafo de cima seria a mesma mentira
    # que este ficheiro existe para impedir.
    partes = ["%d pendentes na operacao" % total_parados]
    if sem_resposta:
        partes.append("%d pessoa(s) sem resposta no whatsapp" % sem_resposta)
    if entregas_falhadas:
        partes.append("%d entrega(s) de mensagem falhadas" % entregas_falhadas)
    out.append("RESUMO: " + ", ".join(partes) + "." + aviso)
    texto = "\n".join(out) + "\n"

    fh = open(SAIDA, "w", encoding="ascii", errors="replace")
    fh.write(texto)
    fh.close()
    print(texto)
    return 1 if houve_erro else 0


if __name__ == "__main__":
    sys.exit(main())
