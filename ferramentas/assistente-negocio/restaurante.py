"""Assistente de WhatsApp para RESTAURANTES — encomendas (missao-geral-2026-10-28, Bloco 4; 1.o cliente: Boom! Burger).

Mesma entrada (assistente.atender), mesma fila de saida, mesma voz e mesma rede de seguranca da barbearia
(allowlist, blocklist, grupos, mensagens pessoais, dono que escreve a mao). Muda o prompt e as ferramentas.

Regras de ouro:
  - menu, opcoes, precos, horario e morada vem SEMPRE da base, ao vivo (nunca do prompt fixo nem do modelo);
  - as CONTAS sao do servidor: subtotal, entrega, taxas e total vem das funcoes da base que o create_order usa
    (pricing_calculate_loja, small_order_fee_calc, order_line_options_extras). O quote_order_pricing da app exige
    sessao de cliente (auth.uid()) e recusa a chave de servico, por isso o robo chama as mesmas pecas, pela mesma
    ordem; depois de criar, compara com o total que o create_order devolveu e regista qualquer diferenca;
  - so dinheiro: na entrega com o tecto platform_settings.max_cash_amount_cents (o gatilho do servidor e o mesmo);
    ir buscar paga-se na loja, sem tecto (como na app);
  - o pedido SO se cria com um "sim" do cliente a um resumo com total mostrado numa mensagem ANTERIOR, e se o
    carrinho nao mudou desde esse resumo (verificado em codigo, nao pelo modelo);
  - o pedido e um pedido normal (create_order, com user_id da conta ligada ao numero); a origem fica em order_origem;
  - numero sem conta ligada: conversa e menu sim, encomenda nao (link da app). Nada de contas novas nesta fase.
"""
import datetime as dt
import hashlib
import json
import os
import re
from decimal import ROUND_HALF_UP, Decimal

import assistente as A
import db
import morada as M

TERMINAIS = {"delivered", "cancelled", "rejected"}
SIM_RE = re.compile(r"^\W*(sim|s|confirmo|confirmar|confirma|confirmado|pode(\s+ser)?|pode\s+(fazer|avan[cç]ar|mandar|"
                    r"encomendar|confirmar|seguir|pedir)|avan[cç]a|avance|ok(ay)?|est[aá]\s+bem|t[aá]\s+bem|isso|certo|claro|"
                    r"bora|vamos|fechado|quero|exato|exactamente|perfeito|siga|manda)\b", re.I)
NAO_RE = re.compile(r"\b(n[aã]o|nao|espera|afinal|mudar|muda|trocar|troca|tira|tirar|cancela|cancelar|menos|acrescenta|"
                    r"acrescentar|junta|mais\s+um|mais\s+uma)\b", re.I)


# ----------------------------------------------------------------------------- dinheiro (so mostrar)
def D(x):
    return Decimal(str(x if x not in (None, "") else 0))


def r2(x):
    return D(x).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def euros(v):
    return f"{r2(v):.2f}".replace(".", ",") + " €"


# O cliente quer MAIS do que ja esta no carrinho? (palavras que um motor fraco nao pode inventar)
MAIS_RE = re.compile(r"\b(mais|outr[oa]s?|tamb[eé]m|acrescent\w*|junt\w*|adicion\w*|repet\w*|igual|iguais|extra|"
                     r"dois|duas|tr[eê]s|quatro|cinco|seis)\b", re.I)
SEM_NOME = {"boom", "de", "com", "o", "a", "um", "uma", "da", "do"}


def e_sim(texto):
    t = (texto or "").strip()
    return bool(SIM_RE.search(t)) and not NAO_RE.search(t)


# "Sim" e mais nada (so estas palavras, no maximo 6): confirma-se em codigo, sem esperar por um motor. "Sim, e com bacon" nao conta.
_SIM_NUCLEO = {"sim", "s", "confirmo", "confirma", "confirmar", "confirmado", "pode", "ok", "okay", "fechado", "claro", "perfeito",
               "exato", "exatamente", "isso", "certo", "correto", "bora", "vamos", "manda", "avance", "avanca", "siga", "quero"}
_SIM_RESTO = _SIM_NUCLEO | {"ser", "esta", "bem", "ta", "mesmo", "obrigado", "obrigada", "por", "favor", "pedido", "encomenda", "o", "a"}


def e_sim_puro(texto):
    toks = re.sub(r"[^a-z0-9]+", " ", A.sem_acentos(texto or "").lower()).split()
    if not (0 < len(toks) <= 6 and all(w in _SIM_RESTO for w in toks)):
        return False
    return any(w in _SIM_NUCLEO for w in toks) or ("bem" in toks and ("esta" in toks or "ta" in toks))  # "esta bem"


def norm(s):
    return re.sub(r"[^a-z0-9]+", " ", A.sem_acentos(s)).strip()


# ----------------------------------------------------------------------------- base (so leitura)
def loja(t):
    r = db.ler("restaurants", f"id=eq.{db.q(t['restaurant_id'])}")
    return r[0] if r else None


def esgotado(p):
    e = p.get("esgotado_ate")
    return bool(e) and A.hora_local(e) > A.agora()


def produtos(t):
    """Produtos que a app mostra: da loja, disponiveis e nao esgotados."""
    rows = db.ler("products", f"restaurant_id=eq.{db.q(t['restaurant_id'])}",
                  "id,name,price,category,description,allergens,is_available,esgotado_ate,sort_order,restaurant_id")
    rows = [p for p in rows if p.get("is_available") is not False and not esgotado(p)]
    rows.sort(key=lambda p: (p.get("category") or "", p.get("sort_order") if p.get("sort_order") is not None else 9999, p["name"]))
    return rows


def grupos_de(pids):
    """{product_id: [grupo com itens]} — product_option_groups / product_option_items, como a app."""
    pids = list(pids)
    if not pids:
        return {}
    gs = db.ler("product_option_groups", f"product_id=in.({','.join(db.q(p) for p in pids)})",
                "id,product_id,name,is_required,min_choices,max_choices,sort_order")
    its = db.ler("product_option_items", f"group_id=in.({','.join(db.q(g['id']) for g in gs)})",
                 "id,group_id,name,price_add,is_available,sort_order") if gs else []
    out = {}
    for g in sorted(gs, key=lambda g: (g.get("sort_order") or 0, g["name"])):
        g = dict(g, itens=sorted([i for i in its if i["group_id"] == g["id"]], key=lambda i: (i.get("sort_order") or 0, i["name"])))
        out.setdefault(g["product_id"], []).append(g)
    return out


def definicao(chave, padrao=None):
    r = db.ler("platform_settings", f"key=eq.{db.q(chave)}", "value")
    return r[0]["value"] if r else padrao


def max_dinheiro_cents():
    try:
        return int(definicao("max_cash_amount_cents", 4000))
    except (TypeError, ValueError):
        return 4000


def max_km():
    try:
        return float(definicao("delivery_max_distance_km", 15))
    except (TypeError, ValueError):
        return 15.0


def link_app(t):
    f = ((t.get("knowledge") or {}).get("ficha") or {})
    return f.get("link_app") or f"https://www.boraguarda.com/baixar?de=whatsapp-{str(t.get('slug') or 'loja').split('-')[0]}"


def conta_do_cliente(t, numero):
    """Conta da app ligada a este numero: knowledge.contas_clientes do tenant ou env ASSISTENTE_CONTAS_CLIENTES
    ("numero:uuid,numero:uuid"). Nunca por procura do telefone nos perfis (telefone de perfil nao e verificado)."""
    numero = A.so_digitos(numero)
    k = (t.get("knowledge") or {}).get("contas_clientes") or {}
    uid = k.get(numero) or k.get("+" + numero)
    if not uid:
        for par in os.environ.get("ASSISTENTE_CONTAS_CLIENTES", "").split(","):
            n, _, u = par.strip().partition(":")
            if n and A.so_digitos(n) == numero:
                uid = u.strip()
    return uid if uid and re.fullmatch(r"[0-9a-fA-F-]{36}", uid) else None


def demo_ativo(rid, uid=None):
    """Janela do modo demonstracao (platform_settings.modo_demo_loja) — a mesma funcao que os gatilhos do servidor usam."""
    try:
        args = {"p_rid": rid}
        if uid:
            args["p_uid"] = uid
        return bool(db.rpc("_modo_demo_loja", args))
    except db.ErroDB:
        d = definicao("modo_demo_loja") or {}
        try:
            dentro = A.hora_local(d["inicio"]) <= A.agora() < A.hora_local(d["fim"])
        except (KeyError, ValueError, TypeError):
            return False
        return d.get("restaurant_id") == rid and dentro and (not uid or d.get("cliente_user_id") == uid)


def estado_loja(t, uid=None):
    """{pode, motivo, loja, demo, aberta}. motivo: em_breve | pausa | fechada | sem_loja."""
    L = loja(t)
    if not L:
        return {"pode": False, "motivo": "sem_loja"}
    if L.get("coming_soon"):
        if demo_ativo(L["id"], uid):
            return {"pode": True, "demo": True, "loja": L}  # o servidor deixa passar o pedido demo mesmo de caixa fechada
        return {"pode": False, "motivo": "em_breve", "loja": L}
    if L.get("pausa_ate") and A.hora_local(L["pausa_ate"]) > A.agora():
        return {"pode": False, "motivo": "pausa", "ate": L["pausa_ate"], "loja": L}
    ab = db.rpc("is_partner_open", {"p_restaurant_id": L["id"], "p_at": A.iso(A.agora())}) or {}
    if not ab.get("is_open"):
        return {"pode": False, "motivo": "fechada", "abertura": ab, "loja": L}
    return {"pode": True, "loja": L, "aberta": ab}


def resposta_fora_da_janela(t, numero):
    """Loja ainda 'abre em breve' (coming_soon) e fora da janela demo: resposta fixa, sem motor."""
    e = estado_loja(t, conta_do_cliente(t, numero))
    if e.get("motivo") == "em_breve":
        return (f"Olá! A {t['nome']} abre em breve na Bora. Assim que abrir, pode fazer a sua encomenda aqui "
                f"pelo WhatsApp. Obrigado pela paciência!")
    return None


# ----------------------------------------------------------------------------- resposta rapida (sem motor)
# Adendo 4 (29/10/2026): a primeira resposta tem de sair em menos de 5 s. Um pedido simples de menu/lista/precos
# responde-se em codigo, da base, sem esperar por um motor. Tudo o que parece encomenda ou pergunta segue para o motor.
MENU_RE = re.compile(r"\b(menu|lista|cardapio|ementa|carta|precos?|precario|hamburg\w*|burgu?er\w*|"
                     r"o que (e que )?(tem|teem|ha|vendem|fazem|servem)|quais (sao )?(os|as))\b", re.I)
PEDIDO_RE = re.compile(r"\b(quero|queria|queriamos|encomend\w*|pedir|peco|vou querer|\d+\s*x|dois|duas|tres|quatro|"
                       r"opcoes|opcao|ingredientes|leva|tem (bacon|queijo|picante|cebola)|alerg\w*|entrega|morada|horario|"
                       r"aberto|abrem|fecham|quanto (fica|custa|e))\b", re.I)


def menu_texto(t, so_hamburgueres=False):
    """Menu da base (o que a app mostra), por categoria, com precos; marca os produtos com opcoes."""
    prods = produtos(t)
    if not prods:
        return None
    if so_hamburgueres:
        hb = [p for p in prods if re.search(r"hamb|burg", norm(p.get("category") or ""))]
        prods = hb or prods
    com_opcoes = set(grupos_de([p["id"] for p in prods]).keys())
    linhas, cat = [], None
    for p in prods:
        if p.get("category") != cat:
            cat = p.get("category")
            linhas.append(f"\n*{cat or 'Outros'}*")
        linhas.append(f"• {p['name']} — {euros(p['price'])}" + (" (com opções)" if p["id"] in com_opcoes else ""))
    return "\n".join(linhas).strip()


def resposta_rapida(t, ct, texto):
    """Menu/lista/precos pedidos de forma simples -> texto pronto, da base. None = segue para o motor."""
    tx = A.sem_acentos(texto or "")
    if len(tx) > 120 or not MENU_RE.search(tx) or PEDIDO_RE.search(tx):
        return None
    L = loja(t) or {}
    so_hb = bool(re.search(r"hamburg|burgu?er", tx)) and not re.search(r"\b(menu|carta|ementa|cardapio|tudo|completo)\b", tx)
    corpo = menu_texto(t, so_hamburgueres=so_hb)
    if not corpo:
        return None
    h = A.agora().hour
    sauda = "Bom dia" if h < 12 else ("Boa tarde" if h < 20 else "Boa noite")
    gratis = euros(D(L["free_delivery_min_cents"]) / 100) if L.get("free_delivery_min_cents") else None
    rodape = ("Os hambúrgueres têm opções (pão, carne, extras, batata): diga-me o que quer e eu trato do resto. "
              "Pagamento em dinheiro na entrega" + (f"; entrega grátis a partir de {gratis} em produtos." if gratis else "."))
    cabeca = "a nossa lista de hambúrgueres" if so_hb else "o nosso menu"
    return f"{sauda}! Aqui está {cabeca}:\n{corpo}\n\n{rodape}"


# ----------------------------------------------------------------------------- produtos e opcoes
def resolver_produto(nome, lista):
    """-> (produto, candidatos). Igual > contido > palavras em comum. Empate = pergunta ao cliente."""
    alvo = norm(nome)
    if not alvo:
        return None, []
    for p in lista:
        if norm(p["name"]) == alvo or p["id"] == nome:
            return p, []
    toks = set(alvo.split()) - {"boom", "de", "com", "o", "a", "um", "uma"}
    pont = []
    for p in lista:
        st = set(norm(p["name"]).split()) - {"boom"}
        comum = len(toks & st)
        if comum:
            pont.append((comum - 0.1 * len(st - toks), p))
    if not pont:
        return None, []
    pont.sort(key=lambda x: -x[0])
    empatados = [p for s, p in pont if abs(s - pont[0][0]) < 1e-9]
    return (pont[0][1], []) if len(empatados) == 1 else (None, empatados[:6])


def _achar(nome, opcoes, campo="name"):
    alvo = norm(nome)
    for o in opcoes:
        if norm(o[campo]) == alvo:
            return o
    toks = set(alvo.split()) - {"de", "com", "o", "a", "por", "trocar", "mais"}
    melhor, pts = None, 0
    for o in opcoes:
        c = len(toks & set(norm(o[campo]).split()))
        if c > pts:
            melhor, pts = o, c
    return melhor


def validar_opcoes(grupos, pedidas):
    """pedidas = [{grupo, itens:[...]}] -> (opcoes com os nomes exatos da base, erro)."""
    escolhidas = {}
    for o in pedidas or []:
        itens = o.get("itens") or ([o["item"]] if o.get("item") else [])
        g = _achar(o.get("grupo") or "", grupos) if o.get("grupo") else None
        for it in itens:
            alvo_g, item = g, (_achar(it, g["itens"]) if g else None)
            if not item:  # o cliente disse so o item ("com pao brioche"): procura em todos os grupos
                for gg in grupos:
                    item = _achar(it, gg["itens"])
                    if item:
                        alvo_g = gg
                        break
            if not item:
                return None, {"erro": "opcao_nao_existe", "pedido": it,
                              "opcoes_possiveis": {gg["name"]: [i["name"] for i in gg["itens"] if i.get("is_available") is not False] for gg in grupos}}
            if item.get("is_available") is False:
                return None, {"erro": "opcao_indisponivel", "opcao": item["name"]}
            lst = escolhidas.setdefault(alvo_g["name"], [])
            if item["name"] not in lst:
                lst.append(item["name"])
    for g in grupos:
        n = len(escolhidas.get(g["name"], []))
        mn = g.get("min_choices") or (1 if g.get("is_required") else 0)
        if g.get("max_choices") and n > g["max_choices"]:
            return None, {"erro": "demasiadas_opcoes", "grupo": g["name"], "maximo": g["max_choices"]}
        if n < mn:
            return None, {"erro": "falta_escolher", "grupo": g["name"], "minimo": mn,
                          "opcoes": [f"{i['name']} (+{euros(i['price_add'])})" if D(i.get("price_add")) > 0 else i["name"]
                                     for i in g["itens"] if i.get("is_available") is not False]}
    return [{"grupo": g["name"], "itens": escolhidas[g["name"]]} for g in grupos if escolhidas.get(g["name"])], None


def extras_da_linha(product_id, opcoes):
    """Preco das opcoes de UMA unidade, pela funcao do servidor (a mesma do create_order)."""
    if not opcoes:
        return Decimal(0)
    r = db.rpc("order_line_options_extras", {"p_product_id": product_id,
                                             "p_selected_options": [{"group": o["grupo"], "items": o["itens"]} for o in opcoes]})
    row = (r[0] if isinstance(r, list) and r else r) or {}
    return D(row.get("extras_total"))


# ----------------------------------------------------------------------------- contas (do servidor)
def assinatura(payload):
    """Muda se o carrinho, o modo ou a morada mudarem: um 'sim' a um resumo antigo nao vale."""
    base = {"itens": [{k: l.get(k) for k in ("product_id", "quantidade", "opcoes")} for l in payload.get("itens") or []],
            "modo": payload.get("modo"), "destino": payload.get("destino")}
    return hashlib.sha1(json.dumps(base, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:16]


def divida_da_carteira(uid):
    if not uid:
        return Decimal(0)
    r = db.ler("client_wallets", f"user_id=eq.{db.q(uid)}", "free_balance_cents")
    s = int((r[0].get("free_balance_cents") if r else 0) or 0)
    return r2(D(-s) / 100) if s < 0 else Decimal(0)


def cotar(L, payload, uid=None):
    """As contas do servidor para este carrinho. Mesma ordem que o create_order:
    subtotal = soma(preco da base x qtd) + soma(opcoes x qtd)  [loja parceira: sem markup]
    entrega/servico/saco = pricing_calculate_loja(...)          [entrega gratis a partir do minimo da loja: do servidor]
    total = customer_total + small_order_fee_calc(...)          [ir buscar: total = subtotal + taxa pequena]"""
    itens = payload.get("itens") or []
    if not itens:
        return {"ok": False, "erro": "carrinho_vazio"}
    modo = payload.get("modo")
    if modo not in ("entrega", "buscar"):
        return {"ok": False, "erro": "falta_modo", "instrucao": "Pergunta se vem buscar ou se é para entregar."}
    if modo == "entrega" and not payload.get("destino"):
        return {"ok": False, "erro": "falta_morada", "instrucao": "Pede a morada de entrega."}
    if not L.get("is_partner"):
        return {"ok": False, "erro": "loja_nao_parceira"}
    ids = sorted({l["product_id"] for l in itens})
    base = {p["id"]: p for p in db.ler("products", f"id=in.({','.join(db.q(i) for i in ids)})",
                                       "id,name,price,is_available,esgotado_ate,restaurant_id")}
    sub, linhas = Decimal(0), []
    for l in itens:
        p = base.get(l["product_id"])
        if not p or p.get("restaurant_id") != L["id"] or p.get("is_available") is False or esgotado(p):
            return {"ok": False, "erro": "produto_indisponivel", "produto": l["nome"],
                    "instrucao": "Diz que esse produto acabou de ficar indisponível e pergunta se quer outro."}
        q = int(l["quantidade"])
        extra = extras_da_linha(p["id"], l.get("opcoes"))
        valor = (D(p["price"]) + extra) * q
        sub += valor
        linhas.append({"nome": p["name"], "quantidade": q, "opcoes": l.get("opcoes") or [], "valor": r2(valor)})
    sub = r2(sub)
    buscar = modo == "buscar"
    if buscar:
        entrega = servico = saco = Decimal(0)
        base_total = sub
    else:
        pr = db.rpc("pricing_calculate_loja", {
            "p_service_type": "restaurant", "p_subtotal": float(sub), "p_distance_km": float(payload["distancia_km"]),
            "p_is_partner_store": True, "p_apartment_delivery": False, "p_is_stacked_partner": False,
            "p_bag_count": 1, "p_restaurant_id": L["id"]})
        pr = (pr[0] if isinstance(pr, list) else pr) or {}
        entrega, servico, saco = D(pr.get("delivery_fee")), D(pr.get("service_fee")), D(pr.get("bag_fee"))
        base_total = D(pr.get("customer_total"))
    pequeno = D(db.rpc("small_order_fee_calc", {"p_service_type": "takeaway" if buscar else "restaurant",
                                                "p_subtotal": float(sub), "p_restaurant_id": L["id"]}) or 0)
    total = r2(base_total + pequeno)
    divida = divida_da_carteira(uid)
    a_pagar = r2(total + divida)
    acima = (not buscar) and int(r2(total) * 100) > max_dinheiro_cents()
    q = {"ok": not acima, "modo": modo, "linhas": linhas, "subtotal": sub, "entrega": r2(entrega), "taxa_servico": r2(servico),
         "saco": r2(saco), "taxa_pedido_pequeno": r2(pequeno), "total": total, "divida": divida, "a_pagar": a_pagar,
         "gratis_a_partir_de": (D(L.get("free_delivery_min_cents")) / 100) if L.get("free_delivery_min_cents") else None}
    if acima:
        q.update({"erro": "acima_do_maximo_em_dinheiro", "maximo": euros(D(max_dinheiro_cents()) / 100),
                  "instrucao": "Em dinheiro, a entrega só aceita pedidos até ao máximo indicado. Sugere tirar alguma coisa, "
                               "dividir em dois pedidos ou vir buscar à loja."})
    return q


def resumo_texto(q, L, payload):
    out = ["Resumo do pedido:"]
    for l in q["linhas"]:
        ops = "; ".join(", ".join(o["itens"]) for o in l["opcoes"])
        out.append(f"• {l['quantidade']}x {l['nome']}" + (f" ({ops})" if ops else "") + f" — {euros(l['valor'])}")
    out.append(f"Produtos: {euros(q['subtotal'])}")
    if q["modo"] == "entrega":
        out.append("Entrega: " + ("grátis" if q["entrega"] == 0 else euros(q["entrega"])))
        if q["taxa_servico"] > 0:
            out.append(f"Taxa de serviço: {euros(q['taxa_servico'])}")
        if q["saco"] > 0:
            out.append(f"Saco: {euros(q['saco'])}")
    if q["taxa_pedido_pequeno"] > 0:
        out.append(f"Taxa de pedido pequeno: {euros(q['taxa_pedido_pequeno'])}")
    out.append(f"Total: {euros(q['total'])}")
    if q["divida"] > 0:
        out.append(f"Acerto de saldo em atraso da sua conta: {euros(q['divida'])} (a pagar: {euros(q['a_pagar'])})")
    if q["modo"] == "entrega":
        out.append(f"Entrega em: {payload['destino']['morada']}. Paga em dinheiro ao estafeta.")
    else:
        out.append(f"Vem buscar à loja ({L.get('address')}). Paga na loja, em dinheiro.")
    out.append("Confirma a encomenda?")
    return "\n".join(out)


# ----------------------------------------------------------------------------- carrinho (assistant_tasks tipo 'pedido')
def _tarefas_pedido(t, numero):
    return db.ler("assistant_tasks", f"tenant_id=eq.{t['id']}&numero=eq.{db.q(numero)}&tipo=eq.pedido&estado=eq.aberta"
                                     f"&order=created_at.desc", "id,payload,codigo,created_at,simulado")


def carrinho(t, numero, criar=False, simulado=False):
    for k in _tarefas_pedido(t, numero):
        if (k.get("payload") or {}).get("fase") == "carrinho":
            return k
    if not criar:
        return None
    return db.inserir("assistant_tasks", {"tenant_id": t["id"], "numero": numero, "tipo": "pedido", "estado": "aberta",
                                          "payload": {"fase": "carrinho", "itens": []}, "simulado": simulado})


def gravar(tarefa, payload, **campos):
    tarefa["payload"] = payload
    db.atualizar("assistant_tasks", f"id=eq.{tarefa['id']}", dict(campos, payload=payload))


def linhas_do_carrinho(payload):
    out = []
    for i, l in enumerate(payload.get("itens") or [], 1):
        ops = "; ".join(", ".join(o["itens"]) for o in l.get("opcoes") or [])
        out.append(f"{i}. {l['quantidade']}x {l['nome']}" + (f" ({ops})" if ops else "") + (f" — nota: {l['nota']}" if l.get("nota") else ""))
    return out


# ----------------------------------------------------------------------------- ferramentas do modelo
def _f(nome, desc, props=None, req=None):
    return {"type": "function", "function": {"name": nome, "description": desc,
                                             "parameters": {"type": "object", "properties": props or {}, **({"required": req} if req else {})}}}


FERRAMENTAS_R = [
    _f("ver_opcoes", "Opções de um produto (trocar o pão, a carne, extras, batata...) com o preço de cada uma.",
       {"produto": {"type": "string"}}, ["produto"]),
    _f("alergenios", "Alergénios de um produto, da ficha da loja.", {"produto": {"type": "string"}}, ["produto"]),
    _f("ver_horario_loja", "Se a loja está aberta agora, quando abre, horário da semana, morada, tempo de preparação, se dá para ir buscar."),
    _f("adicionar_ao_pedido", "Junta um produto ao pedido do cliente (com as opções que ele escolheu).", {
        "produto": {"type": "string"}, "quantidade": {"type": "integer"},
        "opcoes": {"type": "array", "description": "Ex.: [{\"grupo\": \"Trocar o pão\", \"itens\": [\"Pão brioche\"]}]",
                   "items": {"type": "object", "properties": {"grupo": {"type": "string"}, "itens": {"type": "array", "items": {"type": "string"}}}}},
        "nota": {"type": "string", "description": "Ex.: sem cebola"}}, ["produto"]),
    _f("remover_do_pedido", "Tira uma linha do pedido (número da linha de ver_pedido).", {"linha": {"type": "integer"}}, ["linha"]),
    _f("ver_pedido", "O que está no pedido em curso."),
    _f("esquecer_pedido", "Apaga o pedido em curso (o cliente desistiu)."),
    _f("escolher_entrega", "Entrega ou ir buscar. Para entrega, a morada escrita pelo cliente (rua, número, localidade).", {
        "modo": {"type": "string", "enum": ["entrega", "buscar"]}, "morada": {"type": "string"},
        "complemento": {"type": "string", "description": "Andar, porta, referência"}}, ["modo"]),
    _f("orcamento", "Contas do servidor para o pedido em curso. Devolve resumo_texto para mostrar ao cliente TAL E QUAL."),
    _f("confirmar_pedido", "Cria a encomenda. SÓ depois de o cliente responder SIM ao resumo com o total (numa mensagem anterior).", {
        "nome": {"type": "string", "description": "Nome do cliente, se o disse"}, "notas": {"type": "string"}}),
    _f("meu_pedido", "Estado da última encomenda deste cliente."),
    _f("perguntar_ao_dono", "Quando não sabes (e não está na ficha): cria uma pergunta à loja com prazo; a resposta chega ao cliente.",
       {"pergunta": {"type": "string"}}, ["pergunta"]),
    _f("passar_ao_dono", "Reclamações, problemas com um pedido já feito, descontos, pedidos fora do menu: a loja fala com o cliente.",
       {"motivo": {"type": "string"}}, ["motivo"]),
    _f("guardar_nome", "Guarda o nome SÓ quando a própria pessoa o disse.", {"nome": {"type": "string"}}, ["nome"]),
    _f("guardar_fio", "Guarda o que ficou pendente na conversa. Vazio = nada pendente.", {"a_espera_de": {"type": "string"}}, ["a_espera_de"]),
]


ESTADOS_PT = {
    "created": "recebido, à espera que a loja o aceite",
    "preparing": "aceite, a ser preparado",
    "readyForPickup": "pronto, pode vir buscar",
    "callingDriver": "a ser preparado; estamos a chamar o estafeta",
    "driverAccepted": "o estafeta já vai a caminho da loja",
    "pickedUp": "já saiu da loja, a caminho de si",
    "onTheWay": "a caminho de si",
    "delivered": "entregue",
    "cancelled": "cancelado",
    "rejected": "não foi aceite pela loja",
}


class TurnoRestaurante(A.Turno):
    FERRAMENTAS = FERRAMENTAS_R

    def __init__(self, t, numero, ct, simular, texto_cliente=""):
        super().__init__(t, numero, ct, simular)
        self.texto_cliente = texto_cliente or ""
        self.inicio = A.agora()
        self._loja = None
        self._prods = None
        self._juntados = set()   # o que ESTE turno ja juntou (um motor que repete a chamada nao duplica)
        self._antes = None       # linhas que o carrinho ja tinha quando o turno comecou

    def executar(self, nome, args):
        """Uma ferramenta partida nunca pode deixar o cliente sem resposta (nem rebentar o /evento)."""
        try:
            return super().executar(nome, args)
        except Exception as e:  # noqa: BLE001
            r = {"ok": False, "erro": "interno", "detalhe": f"{type(e).__name__}: {str(e)[:160]}",
                 "instrucao": "Pede desculpa e diz que vais confirmar com a loja; não digas que o pedido foi feito."}
            self.usadas.append({"ferramenta": nome, "args": args, "resultado": r})
            return r

    def passar_ao_dono(self, motivo):
        """Dinheiro, reclamacoes e reembolsos vao para uma pessoa: a loja (WhatsApp) e o Telegram do Danilo."""
        r = super().passar_ao_dono(motivo)
        if not self.simular:
            try:
                import rotinas  # aqui e nao no topo: o rotinas importa este modulo a pedido
                rotinas.telegram(f"{self.t['nome']} (robô de WhatsApp): cliente +{self.numero} precisa de uma pessoa — {motivo}")
            except Exception:  # noqa: BLE001 — o aviso por Telegram nunca pode partir a conversa
                pass
        return r

    def sim_direto(self, hist):
        """O cliente respondeu so "sim" a um resumo que acabou de ver (a ultima mensagem do robo foi o resumo, ha menos de 30 min):
        confirma-se aqui, em codigo (as mesmas verificacoes do confirmar_pedido), sem esperar por um motor — os motores de reserva
        voltavam a mostrar o resumo em vez de confirmar. Devolve o texto a enviar, ou None (segue para o motor)."""
        ult = hist[-1] if hist else None
        if not ult or ult.get("r") != "assistant" or "Confirma a encomenda?" not in (ult.get("t") or ""):
            return None
        try:
            if A.agora() - A.hora_local(ult["ts"]) > dt.timedelta(minutes=30):
                return None
        except (KeyError, ValueError, TypeError):
            return None
        if not e_sim_puro(self.texto_cliente):
            return None
        r = self.executar("confirmar_pedido", {})
        if r.get("ok") and r.get("mensagem") and not r.get("ja_estava_feito"):
            return r["mensagem"]
        return None

    def ajustar_resposta(self, resposta):
        """Os numeros e o estado que o cliente le sao os do servidor, nunca os que um motor (de reserva) reescreveu.
        Medido a 29/10: depois do pedido feito, um motor fraco escreveu 'ja esta a caminho'. Chamado por assistente._fechar."""
        ult = {}
        for u in self.usadas:
            r = u.get("resultado") or {}
            if u["ferramenta"] in ("adicionar_ao_pedido", "remover_do_pedido", "escolher_entrega", "esquecer_pedido"):
                ult.pop("orcamento", None)  # o carrinho mexeu depois do resumo: o resumo ja nao vale
            elif u["ferramenta"] in ("orcamento", "confirmar_pedido") and r.get("ok"):
                ult[u["ferramenta"]] = r
        c = ult.get("confirmar_pedido")
        if c and c.get("mensagem") and not c.get("ja_estava_feito"):
            fiel = c["pedido"] in resposta and c["total"] in resposta and not re.search(
                r"a caminho|j[aá] saiu|entregue|a chegar|chega ", resposta, re.I)
            return resposta if fiel else c["mensagem"]
        o = ult.get("orcamento")
        if o and o.get("resumo_texto") and o["resumo_texto"] not in resposta:
            return o["resumo_texto"]
        return resposta

    # --- dados
    def L(self):
        if self._loja is None:
            self._loja = loja(self.t) or {}
        return self._loja

    def prods(self):
        if self._prods is None:
            self._prods = produtos(self.t)
        return self._prods

    def _produto(self, nome):
        p, cand = resolver_produto(nome, self.prods())
        if p:
            return p, None
        if cand:
            return None, {"ok": False, "erro": "qual_destes", "candidatos": [f"{c['name']} {euros(c['price'])}" for c in cand]}
        return None, {"ok": False, "erro": "nao_ha_no_menu", "pedido": nome,
                      "instrucao": "Diz que não há isso no menu e sugere o mais parecido do MENU."}

    # --- ferramentas
    def ver_opcoes(self, produto):
        p, err = self._produto(produto)
        if err:
            return err
        gs = grupos_de([p["id"]]).get(p["id"], [])
        return {"produto": p["name"], "preco": euros(p["price"]), "grupos": [
            {"grupo": g["name"], "obrigatorio": bool(g.get("is_required") or (g.get("min_choices") or 0) > 0),
             "maximo": g.get("max_choices"),
             "opcoes": [f"{i['name']} (+{euros(i['price_add'])})" if D(i.get("price_add")) > 0 else i["name"]
                        for i in g["itens"] if i.get("is_available") is not False]} for g in gs]}

    def alergenios(self, produto):
        p, err = self._produto(produto)
        if err:
            return err
        a = [x for x in (p.get("allergens") or []) if x]
        if not a:
            return {"produto": p["name"], "sem_dados": True,
                    "instrucao": "Diz que não tens a informação de alergénios deste prato e que o melhor é perguntar à loja; "
                                 "oferece perguntar (perguntar_ao_dono). Nunca digas que não tem alergénios."}
        return {"produto": p["name"], "alergenios": a}

    def ver_horario_loja(self):
        L = self.L()
        ab = db.rpc("is_partner_open", {"p_restaurant_id": L["id"], "p_at": A.iso(A.agora())}) or {}
        bh = L.get("business_hours") or {}
        horas = {}
        for i, k in enumerate(A.DIAS_BH):
            d = bh.get(k) or {}
            if d.get("closed") or not d:
                horas[A.DIAS[i]] = "fechado"
            elif d.get("break_start") and d.get("break_end"):
                horas[A.DIAS[i]] = f"{d['open']}–{d['break_start']} e {d['break_end']}–{d['close']}"
            else:
                horas[A.DIAS[i]] = f"{d.get('open')}–{d.get('close')}"
        return {"aberta_agora": bool(ab.get("is_open")), "fecha_dentro_de_min": ab.get("closes_in_minutes"),
                "abre": (f"{ab.get('opens_dia') or ''} às {ab['opens_at']}".strip() if ab.get("opens_at") else None),
                "horario": horas, "morada": L.get("address"), "tempo_preparacao_min": L.get("phone_prep_minutes"),
                "ir_buscar": bool(L.get("takeaway_enabled")),
                "entrega_gratis_a_partir_de": euros(D(L["free_delivery_min_cents"]) / 100) if L.get("free_delivery_min_cents") else None,
                "pagamento": "só dinheiro"}

    def adicionar_ao_pedido(self, produto, quantidade=1, opcoes=None, nota=None):
        p, err = self._produto(produto)
        if err:
            return err
        try:
            q = int(quantidade or 1)
        except (TypeError, ValueError):
            q = 1
        if not 1 <= q <= 20:
            return {"ok": False, "erro": "quantidade_invalida"}
        gs = grupos_de([p["id"]]).get(p["id"], [])
        ops, err = validar_opcoes(gs, opcoes)
        if err:
            return dict(err, ok=False, produto=p["name"])
        extra = extras_da_linha(p["id"], ops)  # preco das opcoes de 1 unidade, pelo servidor (so para mostrar)
        k = carrinho(self.t, self.numero, criar=True, simulado=self.simular)
        pl = dict(k.get("payload") or {"fase": "carrinho", "itens": []})
        itens = list(pl.get("itens") or [])
        linha = json.dumps([p["id"], ops, nota or None], sort_keys=True, ensure_ascii=False)
        if self._antes is None:
            self._antes = {json.dumps([l["product_id"], l.get("opcoes") or [], l.get("nota") or None], sort_keys=True, ensure_ascii=False)
                           for l in itens}
        if self._repetido(p, linha, q, ops, nota):
            return {"ok": True, "ja_estava": True, "pedido": linhas_do_carrinho(pl),
                    "instrucao": "Isto JÁ estava no pedido: não juntes outra vez. Continua: se ainda não sabes, pergunta se vem buscar "
                                 "ou é para entregar / pede a morada; senão chama orcamento."}
        self._juntados.add(json.dumps([linha, q]))
        for l in itens:
            if l["product_id"] == p["id"] and (l.get("opcoes") or []) == ops and (l.get("nota") or None) == (nota or None):
                l["quantidade"] += q
                break
        else:
            itens.append({"product_id": p["id"], "nome": p["name"], "quantidade": q, "opcoes": ops, "extras_unit": str(r2(extra)),
                          **({"nota": nota} if nota else {})})
        pl["itens"] = itens
        pl.pop("orcamento", None)
        gravar(k, pl)
        return {"ok": True, "pedido": linhas_do_carrinho(pl),
                "instrucao": "Confirma em 1 frase o que juntaste. Se ainda não sabes, pergunta se quer mais alguma coisa e depois "
                             "se vem buscar ou é para entregar."}

    def _repetido(self, p, linha, q, ops, nota):
        """Um motor de reserva (mais fraco) pode voltar a juntar o que o carrinho JA tem — medido a 29/10 (2+2 virou 4+4,
        64,98 EUR). So se junta outra vez se o cliente o disse: nomeou o produto ou falou em 'mais/outro/...'.
        Regras (em codigo, nao no modelo): (1) a mesma chamada repetida no mesmo turno nao conta; (2) uma linha que o
        carrinho ja tinha antes deste turno so volta a somar se a mensagem do cliente a nomeia ou pede mais."""
        texto = self.texto_cliente or ""
        pede_mais = bool(MAIS_RE.search(texto))
        if json.dumps([linha, q]) in self._juntados:
            return not pede_mais
        if linha in (self._antes or set()):
            toks = [t for t in norm(p["name"]).split() if t not in SEM_NOME and len(t) >= 3]
            palavras = norm(texto).split()
            nomeou = any(t[:5] in w for t in toks for w in palavras)
            return not (nomeou or pede_mais)
        return False

    def remover_do_pedido(self, linha):
        k = carrinho(self.t, self.numero)
        if not k:
            return {"ok": False, "erro": "sem_pedido_em_curso"}
        pl = dict(k["payload"])
        itens = list(pl.get("itens") or [])
        try:
            fora = itens.pop(int(linha) - 1)
        except (IndexError, ValueError, TypeError):
            return {"ok": False, "erro": "linha_nao_existe", "pedido": linhas_do_carrinho(pl)}
        pl["itens"] = itens
        pl.pop("orcamento", None)
        gravar(k, pl)
        return {"ok": True, "tirado": fora["nome"], "pedido": linhas_do_carrinho(pl)}

    def ver_pedido(self):
        k = carrinho(self.t, self.numero)
        pl = (k or {}).get("payload") or {}
        return {"pedido": linhas_do_carrinho(pl), "modo": pl.get("modo"), "morada": (pl.get("destino") or {}).get("morada")}

    def esquecer_pedido(self):
        k = carrinho(self.t, self.numero)
        if k:
            db.atualizar("assistant_tasks", f"id=eq.{k['id']}", {"estado": "cancelada", "cumprida_em": A.iso(A.agora()),
                                                                  "resposta": "cliente desistiu do carrinho"})
        return {"ok": True}

    def escolher_entrega(self, modo, morada=None, complemento=None):
        k = carrinho(self.t, self.numero, criar=True, simulado=self.simular)
        pl = dict(k.get("payload") or {"fase": "carrinho", "itens": []})
        L = self.L()
        if modo == "buscar":
            if not L.get("takeaway_enabled"):
                return {"ok": False, "erro": "loja_sem_ir_buscar",
                        "instrucao": "Diz que, por agora, esta loja só faz entregas pela Bora, e pede a morada."}
            pl.update({"modo": "buscar", "destino": None, "distancia_km": 0})
        else:
            if not morada:
                return {"ok": False, "erro": "falta_morada", "instrucao": "Pede a morada completa (rua, número e localidade)."}
            g = M.geocodificar(morada)
            if not g:
                return {"ok": False, "erro": "morada_nao_encontrada",
                        "instrucao": "Diz que não encontraste a morada e pede rua, número e localidade (ex.: freguesia), ou um ponto de referência."}
            km, como = M.km_estrada(float(L["lat"]), float(L["lng"]), g["lat"], g["lng"])  # como a app: estrada, senao linha reta
            if km > max_km():
                return {"ok": False, "erro": "fora_da_zona", "morada_encontrada": g["morada"], "distancia_km": round(km, 1),
                        "instrucao": "Diz com simpatia que essa morada fica fora da zona de entregas da loja e sugere vir buscar (se der)."}
            destino = {"lat": g["lat"], "lng": g["lng"], "morada": g["morada"], "rua": g.get("rua"),
                       "codigo_postal": g.get("codigo_postal"), "cidade": g.get("cidade") or "Guarda",
                       "escrita": morada, "complemento": complemento or None}
            pl.update({"modo": "entrega", "destino": destino, "distancia_km": round(km, 2), "distancia_como": como})
        pl.pop("orcamento", None)
        gravar(k, pl)
        r = {"ok": True, "modo": pl["modo"]}
        if pl["modo"] == "entrega":
            r.update({"morada_encontrada": pl["destino"]["morada"], "instrucao": "Diz a morada encontrada; a seguir chama orcamento."})
        return r

    def orcamento(self):
        k = carrinho(self.t, self.numero)
        if not k or not (k.get("payload") or {}).get("itens"):
            return {"ok": False, "erro": "carrinho_vazio"}
        pl = dict(k["payload"])
        uid = conta_do_cliente(self.t, self.numero)
        q = cotar(self.L(), pl, uid)
        if not q.get("linhas"):
            return q
        if not q["ok"]:
            pl.pop("orcamento", None)
            gravar(k, pl)
            return {"ok": False, "erro": q.get("erro"), "total": euros(q["total"]), "maximo": q.get("maximo"),
                    "instrucao": q.get("instrucao")}
        txt = resumo_texto(q, self.L(), pl)
        pl["orcamento"] = {"assinatura": assinatura(pl), "mostrado_em": A.iso(A.agora()), "total": str(q["total"]),
                           "a_pagar": str(q["a_pagar"]), "subtotal": str(q["subtotal"]), "entrega": str(q["entrega"]),
                           "taxa_servico": str(q["taxa_servico"]), "saco": str(q["saco"]),
                           "taxa_pedido_pequeno": str(q["taxa_pedido_pequeno"])}
        gravar(k, pl)
        return {"ok": True, "total": euros(q["total"]), "resumo_texto": txt,
                "instrucao": "Envia o resumo_texto TAL E QUAL e espera pelo sim. Não chames confirmar_pedido nesta resposta."}

    def confirmar_pedido(self, nome=None, notas=None):
        k = carrinho(self.t, self.numero)
        if not k:
            feito = self._ultimo_feito(minutos=30)
            if feito:
                return {"ok": True, "ja_estava_feito": True, "pedido": feito.get("codigo"),
                        "instrucao": "O pedido já estava feito: não digas que houve erro."}
            return {"ok": False, "erro": "sem_pedido_em_curso"}
        pl = dict(k["payload"])
        orc = pl.get("orcamento")
        if not orc or orc.get("assinatura") != assinatura(pl):
            return {"ok": False, "erro": "falta_resumo",
                    "instrucao": "Chama orcamento, mostra o resumo com o total e pergunta se confirma. Ainda NÃO há pedido."}
        if A.hora_local(orc["mostrado_em"]) >= self.inicio:
            return {"ok": False, "erro": "resumo_ainda_nao_visto",
                    "instrucao": "O cliente ainda não viu o resumo: mostra-o e pergunta se confirma. Ainda NÃO há pedido."}
        if not e_sim(self.texto_cliente):
            return {"ok": False, "erro": "sem_sim_explicito",
                    "instrucao": "O cliente não respondeu sim ao resumo. Pergunta: «Confirma a encomenda?». Ainda NÃO há pedido."}
        uid = conta_do_cliente(self.t, self.numero)
        if not uid:
            return {"ok": False, "erro": "sem_conta", "link_app": link_app(self.t),
                    "instrucao": "Diz que, por agora, as encomendas pelo WhatsApp são só para clientes com conta na app Bora "
                                 "e deixa o link da app. Ainda NÃO há pedido."}
        e = estado_loja(self.t, uid)
        if not e["pode"]:
            return {"ok": False, "erro": "loja_" + e.get("motivo", "fechada"), "abertura": e.get("abertura"),
                    "instrucao": "Diz que a loja não está a aceitar pedidos agora e, se souberes, quando abre. Ainda NÃO há pedido."}
        L = e["loja"]
        q = cotar(L, pl, uid)
        if not q["ok"]:
            return {"ok": False, "erro": q.get("erro"), "instrucao": q.get("instrucao")}
        if str(q["total"]) != orc["total"]:  # o preco mudou entre o resumo e o sim: mostra outra vez
            pl.pop("orcamento", None)
            gravar(k, pl)
            return {"ok": False, "erro": "preco_mudou", "instrucao": "Os preços mudaram: chama orcamento e mostra o novo resumo."}
        nome = (nome or self.ct.get("nome") or "").strip()[:60] or "Cliente WhatsApp"
        # Rede contra pedidos duplicados: se uma tentativa anterior caiu a meio (ex.: tempo esgotado) o pedido
        # pode ter nascido na mesma; antes de criar outra vez, procura-o.
        r = None
        if pl.get("a_criar_em"):
            ja = db.ler("orders", f"user_id=eq.{db.q(uid)}&restaurant_id=eq.{db.q(L['id'])}"
                                  f"&created_at=gte.{db.q(pl['a_criar_em'])}&order=created_at.desc&limit=1",
                        "id,customer_total,price,takeaway_pickup_code")
            if ja:
                r = {"order_id": ja[0]["id"], "customer_total": ja[0].get("customer_total") or ja[0].get("price"),
                     "takeaway_pickup_code": ja[0].get("takeaway_pickup_code")}
        if r is None:
            pl["a_criar_em"] = A.iso(A.agora() - dt.timedelta(seconds=5))
            gravar(k, pl)
            p_input = montar_p_input(L, pl, uid, self.numero, nome, notas)
            try:
                r = db.rpc("create_order", {"p_input": p_input}) or {}
            except db.ErroDB as ex:
                pl.pop("a_criar_em", None)
                gravar(k, pl)
                return {"ok": False, "erro": "servidor_recusou", "detalhe": traduzir_erro(str(ex)),
                        "instrucao": "Pede desculpa, diz o motivo em palavras simples e não digas que o pedido foi feito."}
        oid = r.get("order_id")
        if not oid:
            return {"ok": False, "erro": "servidor_sem_id", "instrucao": "Pede desculpa e diz que vais confirmar com a loja."}
        origem_erro = None
        try:
            db.inserir("order_origem", {"order_id": oid, "origem": "whatsapp", "client_phone": "+" + self.numero,
                                        "tenant_slug": self.t.get("slug")}, devolver=False)
        except Exception as ex:  # noqa: BLE001 — o pedido ja existe; a etiqueta falha sem o partir
            origem_erro = str(ex)[:200]
        total_srv = r2(r.get("customer_total") if r.get("customer_total") is not None else q["total"])
        a_pagar = r2(r.get("charge_total") if r.get("charge_total") is not None else total_srv)
        cod = oid[:6].upper()
        pl.update({"fase": "feito", "order_id": oid, "total_servidor": str(total_srv), "a_pagar": str(a_pagar),
                   "criado_em": A.iso(A.agora()), "avisados": ["recebido"], "nome": nome,
                   "takeaway_pickup_code": r.get("takeaway_pickup_code")})
        if str(total_srv) != orc["total"]:
            pl["divergencia"] = {"mostrado": orc["total"], "servidor": str(total_srv)}
        if origem_erro:
            pl["origem_erro"] = origem_erro
        try:  # o pedido JA existe: daqui para baixo nada pode dizer ao cliente que falhou
            gravar(k, pl, codigo=cod)
            if nome != "Cliente WhatsApp":
                A.gravar_contacto(self.t, self.numero, {"nome": nome})
        except Exception as ex:  # noqa: BLE001
            self.usadas.append({"ferramenta": "gravar_pedido_feito", "args": {"order_id": oid}, "resultado": {"erro": str(ex)[:160]}})
        msg = (f"Pedido #{cod} feito! A {self.t['nome']} já o recebeu. Total: {euros(total_srv)}"
               + (f" (a pagar: {euros(a_pagar)})" if a_pagar != total_srv else "")
               + (", em dinheiro ao estafeta." if pl["modo"] == "entrega" else ", paga na loja quando vier buscar.")
               + " Vou avisando por aqui quando a loja aceitar e quando sair.")
        return {"ok": True, "pedido": cod, "total": euros(total_srv), "mensagem": msg,
                "instrucao": "Responde com a mensagem (podes encurtar, nunca mudes valores)."}

    def meu_pedido(self):
        k = self._ultimo_feito(minutos=24 * 60)
        if not k:
            return {"ok": False, "erro": "sem_pedidos_recentes"}
        o = db.ler("orders", f"id=eq.{db.q(k['payload']['order_id'])}", "id,status,cancel_reason")
        st = o[0]["status"] if o else None
        return {"ok": True, "pedido": k.get("codigo"), "estado": ESTADOS_PT.get(st, st)}

    def _ultimo_feito(self, minutos):
        desde = A.iso(A.agora() - dt.timedelta(minutes=minutos))
        r = db.ler("assistant_tasks", f"tenant_id=eq.{self.t['id']}&numero=eq.{db.q(self.numero)}&tipo=eq.pedido"
                                      f"&created_at=gte.{db.q(desde)}&order=created_at.desc", "id,payload,codigo,estado,created_at")
        return next((x for x in r if (x.get("payload") or {}).get("order_id")), None)


def traduzir_erro(txt):
    pares = [("STORE_COMING_SOON", "a loja ainda não abriu na Bora"), ("STORE_PAUSED", "a loja está em pausa"),
             ("CASH_LIMIT_EXCEEDED", "em dinheiro só até ao máximo permitido"), ("delivery_distance_exceeded", "a morada fica fora da zona"),
             ("TAKEAWAY_NOT_ENABLED", "a loja não tem ir buscar"), ("STORE_CLOSED", "a loja está fechada"),
             ("fechad", "a loja está fechada")]
    for k, v in pares:
        if k.lower() in txt.lower():
            return v
    return "o sistema não aceitou o pedido"


def montar_p_input(L, pl, uid, numero, nome, notas=None):
    """O p_input que a app manda (order_store.dart, pedido de restaurante parceiro a dinheiro), com user_id
    (create_order aceita-o da chave de servico — R1, 21/10). O servidor recalcula tudo."""
    buscar = pl["modo"] == "buscar"
    itens, linhas, sub = [], [], Decimal(0)
    for l in pl["itens"]:
        o = l.get("opcoes") or []
        it = {"productId": l["product_id"], "name": l["nome"], "quantity": l["quantidade"], "purchaseStatus": "pending"}
        if o:
            it["selected_options"] = [{"group": x["grupo"], "items": x["itens"]} for x in o]
        itens.append(it)
        linhas.append({"product_id": l["product_id"], "quantity": l["quantidade"], "name": l["nome"]})
    ids = sorted({l["product_id"] for l in pl["itens"]})
    precos = {p["id"]: D(p["price"]) for p in db.ler("products", f"id=in.({','.join(db.q(i) for i in ids)})", "id,price")}
    for it, ln, l in zip(itens, linhas, pl["itens"]):
        unit = precos.get(it["productId"], Decimal(0))
        extra = D(l.get("extras_unit"))
        # como o CartItem da app: price = unidade com opcoes; basePrice = preco puro de catalogo (unit_price das linhas)
        it.update({"price": float(r2(unit + extra)), "basePrice": float(unit)})
        ln["unit_price"] = float(unit)
        sub += (unit + extra) * it["quantity"]
    dest = pl.get("destino") or {}
    notas_txt = "[WhatsApp] " + " | ".join(filter(None, [
        notas, dest.get("complemento"), "; ".join(f"{l['nome']}: {l['nota']}" for l in pl["itens"] if l.get("nota"))]))
    p = {
        "service_type": "takeaway" if buscar else "restaurant",
        "vendor_name": L["name"],
        "is_partner_store": True,
        "distance_km": 0 if buscar else pl["distancia_km"],
        "payment_method": "cash",
        "subtotal": float(r2(sub)),
        "apartment_delivery": False,
        "order_type": "takeaway" if buscar else "partnerRestaurant",
        "bag_count": 0 if buscar else 1,
        "requires_car": False,
        "wallet_applied_cents": 0,
        "pickup_lat": float(L["lat"]), "pickup_lng": float(L["lng"]), "pickup_address": L.get("address"),
        "dropoff_lat": float(L["lat"]) if buscar else dest["lat"],
        "dropoff_lng": float(L["lng"]) if buscar else dest["lng"],
        "dropoff_address": L.get("address") if buscar else dest["morada"],
        "customer_name": nome,
        "customer_notes": notas_txt.strip(),
        "client_phone": "+" + A.so_digitos(numero),
        "items": itens,
        "product_lines": linhas,
        "user_id": uid,
    }
    if not buscar:
        p.update({k: v for k, v in {"dropoff_street": dest.get("rua"), "dropoff_city": dest.get("cidade"),
                                    "dropoff_postal_code": dest.get("codigo_postal")}.items() if v})
    return p


# ----------------------------------------------------------------------------- prompt
def prompt_restaurante(t, ct):
    L = loja(t) or {}
    agora_ = A.agora()
    k = t.get("knowledge") or {}
    f = k.get("ficha") or {}
    prods = produtos(t)
    com_opcoes = set(grupos_de([p["id"] for p in prods]).keys()) if prods else set()
    menu, cat = [], None
    for p in prods:
        if p.get("category") != cat:
            cat = p.get("category")
            menu.append(f"\n[{cat or 'Outros'}]")
        menu.append(f"- {p['name']} {euros(p['price'])}" + (" (tem opções)" if p["id"] in com_opcoes else ""))
    aprendidas = "\n".join(f"- P: {x.get('pergunta')} → R: {x.get('resposta')}" for x in (k.get("perguntas_aprendidas") or [])[-30:]) or "(nenhuma ainda)"
    fio = (ct.get("a_espera_de") or {}).get("o_que") if isinstance(ct.get("a_espera_de"), dict) else None
    numero = ct.get("numero") or ""
    kc = carrinho(t, numero) if numero else None
    em_curso = linhas_do_carrinho((kc or {}).get("payload") or {})
    ir_buscar = "sim" if L.get("takeaway_enabled") else "NÃO (só entregas)"
    gratis = euros(D(L["free_delivery_min_cents"]) / 100) if L.get("free_delivery_min_cents") else None
    menu_txt = "".join(m if m.startswith("\n") else "\n" + m for m in menu)
    passo2 = ('"Vem buscar ou é para entregar?"' if L.get("takeaway_enabled")
              else "pede a morada de entrega (esta loja, por agora, só faz entregas)")
    nota_gratis = f" Entrega grátis a partir de {gratis} em produtos." if gratis else ""
    em_curso_txt = "; ".join(em_curso) if em_curso else "nenhum"
    cliente_txt = ("chama-se " + ct["nome"]) if ct.get("nome") else "nome desconhecido (não inventes)"
    fio_txt = ("FIO DA CONVERSA: " + fio) if fio else ""
    return f"""És a pessoa que atende o WhatsApp da {t['nome']} (restaurante na Guarda, Portugal). As encomendas são feitas pela Bora: entrega por estafeta ou ir buscar à loja.
Agora: {A.DIAS[agora_.weekday()]}, {agora_.strftime('%Y-%m-%d %H:%M')} (hora de Lisboa).

Tom: {t.get('tom') or 'Português de Portugal, curto, simpático e despachado.'}
Escreves SEMPRE em português de Portugal (nunca do Brasil): "encomenda", "telemóvel", "está bem". Tratas o cliente por "você". 1 a 3 frases (o resumo do pedido é a exceção). Nada de listas longas: no máximo 6 produtos de cada vez.

MENU (da base de dados agora; é a verdade): {menu_txt}

Morada da loja: {L.get('address')}. Ir buscar: {ir_buscar}. Pagamento: só dinheiro (na entrega ao estafeta, ou na loja).{nota_gratis}
Notas da loja: {' '.join(f.get('notas') or [])}
CONHECIMENTO DA CASA (ingredientes, história, perguntas frequentes; os preços são só os do MENU acima):
{f.get('conhecimento') or '(sem ficha de conhecimento)'}
Perguntas já respondidas pela loja:
{aprendidas}

Cliente: {cliente_txt}.
Pedido em curso: {em_curso_txt}.
{fio_txt}

COMO SE FAZ UMA ENCOMENDA:
1. Para cada produto que o cliente pedir, chama adicionar_ao_pedido. Produto com "(tem opções)": se o cliente não disse, pergunta UMA vez se quer trocar alguma coisa (usa ver_opcoes para dizer as opções e os preços). Se não percebeste o produto ou a ferramenta devolver candidatos, pergunta qual.
2. Pergunta "Mais alguma coisa?" e depois {passo2}. Entrega: escolher_entrega com a morada que o cliente escreveu; diz a morada encontrada.
3. Chama orcamento e envia o resumo_texto TAL E QUAL (são as contas do servidor; nunca faças contas tu).
4. Só quando o cliente responder SIM a esse resumo, chama confirmar_pedido e responde com a mensagem que ela devolver. Se a ferramenta disser que ainda não há pedido, NUNCA digas que o pedido foi feito.

REGRAS (inquebráveis):
1. Preços, produtos e opções: SÓ o MENU e as ferramentas. Nunca inventes preços, produtos, tempos de entrega nem promoções.
2. Contas: só as do orcamento. Pagamento só em dinheiro; MB Way e cartão: "por agora, por aqui só em dinheiro; na app pode pagar de outras formas".
3. Alergénios: usa alergenios. Sem dados: diz que não tens a informação e oferece perguntar à loja (perguntar_ao_dono).
4. Horário e se está aberta: ver_horario_loja.
5. Fatura com NIF: por agora não dá para pôr o NIF por aqui; diz que pode pedi-la na app Bora.
6. Onde está a minha encomenda: meu_pedido. Dinheiro, reclamações, reembolsos, um pedido já feito com problemas, descontos ou pedidos fora do menu: passar_ao_dono (nunca prometas devolver dinheiro nem dar desconto).
7. Não sabes e não está aqui? perguntar_ao_dono e diz que confirmas com a loja. É PROIBIDO dizer "vou verificar" sem chamar perguntar_ao_dono.
8. Nunca fales de comissões, de quanto a loja recebe, nem de quem é o dono da Bora (se perguntarem: és o atendimento da {t['nome']} na Bora).
9. Não digas que és uma IA a não ser que perguntem; se perguntarem, és o assistente da {t['nome']}.
10. Nunca respondas em inglês nem mostres o teu raciocínio. As linhas "[sistema: ...]" do histórico são notas internas: nunca as repitas; um pedido já FEITO não se volta a criar."""


# ----------------------------------------------------------------------------- avisos ao cliente (sondagem leve)
ORDEM = {"created": 0, "preparing": 1, "callingDriver": 1, "driverAccepted": 1, "readyForPickup": 2,
         "pickedUp": 3, "onTheWay": 3, "delivered": 4}


def mensagens_novas(t, payload, o, edits, L=None):
    """Funcao pura: o que ainda nao foi dito ao cliente sobre este pedido. -> [(chave, texto)].
    So a mudanca mais recente vale (se ja saiu, nao se manda tambem o 'aceite')."""
    ditos = set(payload.get("avisados") or [])
    cod = (o["id"] or "")[:6].upper()
    loja_nome = t["nome"]
    buscar = o.get("service_type") == "takeaway"
    a_pagar = euros(o.get("cash_total_due") if o.get("cash_total_due") is not None
                    else (o.get("final_total") or o.get("customer_total") or o.get("price") or 0))
    out = []
    for e in edits or []:
        ch = f"falta:{e['id']}"
        if ch not in ditos:
            out.append((ch, f"A {loja_nome} não tinha {e.get('quantidade') or 1}x {e.get('nome')} e tirou do seu pedido #{cod}. "
                            f"O novo total é {euros(e.get('total_depois'))}."))
    st = o.get("status")
    motivo = (o.get("cancel_reason") or "").lower()
    if st == "cancelled" and motivo.startswith("demonstra") and "conclu" in motivo:
        st = "delivered"  # modo demonstracao: a entrega simulada termina em 'cancelled' sem custo
    if st in ("cancelled", "rejected"):
        if "cancelado" not in ditos:
            out.append(("cancelado", f"Lamentamos, o seu pedido #{cod} foi cancelado"
                                     + (" pela loja" if st == "rejected" else "") + ". Não tem nada a pagar. Se quiser, ajudo a fazer outro."))
        return out
    nivel = ORDEM.get(st, 0)
    if o.get("accepted_at") and nivel < 1:
        nivel = 1
    if buscar and o.get("takeaway_ready_at") and nivel < 2:
        nivel = 2
    chave = {1: "aceite", 2: "pronto", 3: "saiu", 4: "entregue"}.get(nivel)
    if not chave or chave in ditos or (buscar and chave == "saiu"):
        return out
    if chave == "aceite":
        prep = o.get("takeaway_prep_minutes") if buscar else o.get("prep_time_minutes")
        tempo = f" Fica pronto em cerca de {prep} min." if prep else ""
        out.append(("aceite", f"A {loja_nome} aceitou o seu pedido #{cod}.{tempo}"
                              + (" Aviso-o quando puder vir buscar." if buscar else " Depois segue com o estafeta.")))
    elif chave == "pronto" and buscar:
        cod_lev = o.get("takeaway_pickup_code") or payload.get("takeaway_pickup_code")
        out.append(("pronto", f"O seu pedido #{cod} está pronto, pode vir buscar à {loja_nome}"
                              + (f" ({L.get('address')})" if L and L.get("address") else "") + "."
                              + (f" Código de levantamento: {cod_lev}." if cod_lev else "") + f" Paga na loja: {a_pagar}."))
    elif chave == "saiu":
        out.append(("saiu", f"O seu pedido #{cod} já saiu para entrega. Tenha {a_pagar} em dinheiro para pagar ao estafeta."))
    elif chave == "entregue":
        out.append(("entregue", "Pedido entregue. Bom apetite e obrigado!" if not buscar else "Pedido levantado. Bom apetite e obrigado!"))
    return out


def avisos_pedidos(t):
    """Para cada pedido feito pelo WhatsApp e ainda aberto: le o estado (orders) e as faltas (order_edits) e avisa.
    Idempotente por payload.avisados. Corre a cada ~20 s no servidor. Devolve quantas mensagens pos na fila."""
    abertas = db.ler("assistant_tasks", f"tenant_id=eq.{t['id']}&tipo=eq.pedido&estado=eq.aberta",
                     "id,numero,payload,codigo,created_at,simulado")
    agora = A.agora()
    for k in abertas:  # carrinhos esquecidos ha mais de 6 h
        pl = k.get("payload") or {}
        if pl.get("fase") == "carrinho" and agora - A.hora_local(k["created_at"]) > dt.timedelta(hours=6):
            db.atualizar("assistant_tasks", f"id=eq.{k['id']}", {"estado": "expirada", "cumprida_em": A.iso(agora)})
    feitos = [k for k in abertas if (k.get("payload") or {}).get("order_id")]
    if not feitos:
        return 0
    ids = ",".join(db.q(k["payload"]["order_id"]) for k in feitos)
    ords = {o["id"]: o for o in db.ler("orders", f"id=in.({ids})",
                                       "id,status,service_type,accepted_at,prep_time_minutes,takeaway_prep_minutes,"
                                       "takeaway_pickup_code,takeaway_ready_at,price,customer_total,final_total,"
                                       "cash_total_due,cancel_reason")}
    edits = db.ler("order_edits", f"order_id=in.({ids})&tipo=eq.remove&estado=eq.aplicado", "id,order_id,nome,quantidade,total_depois")
    L = loja(t)
    n = 0
    for k in feitos:
        pl = dict(k["payload"])
        o = ords.get(pl["order_id"])
        if not o:
            continue
        novas = mensagens_novas(t, pl, o, [e for e in edits if e["order_id"] == o["id"]], L)
        for chave, texto in novas:
            A.enfileirar(t, k["numero"], texto, f"pedido:{o['id']}:{chave}", bool(k.get("simulado")))
            n += 1
        st = o.get("status")
        fim = st in TERMINAIS
        if novas or fim:
            pl["avisados"] = list(dict.fromkeys((pl.get("avisados") or []) + [c for c, _ in novas]))
            campos = {}
            if fim:
                entregue = st == "delivered" or "entregue" in pl["avisados"]
                campos = {"estado": "cumprida" if entregue else "cancelada", "cumprida_em": A.iso(agora), "resposta": st}
                if entregue and _link_app_uma_vez(t, k["numero"], bool(k.get("simulado"))):
                    n += 1
            gravar(k, pl, **campos)
    return n


def _link_app_uma_vez(t, numero, simulado):
    """Uma linha com o link da app, uma unica vez por numero (sem insistir)."""
    if db.ler("assistant_messages", f"tenant_id=eq.{t['id']}&numero=eq.{db.q(numero)}&motivo=eq.link_app", "id"):
        return False
    A.enfileirar(t, numero, f"Se lhe der jeito, da próxima vez também pode pedir pela app Bora: {link_app(t)}", "link_app", simulado)
    return True
