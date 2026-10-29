"""Testes do modo RESTAURANTE do assistente (missao final-app-2026-10-29, bloco 2). Sem rede e sem Supabase:
uma base falsa em memoria (FakeDB) que fala o mesmo "dialecto" de filtros que o db.py usa, um servidor falso que
calcula os totais POR OUTRO CAMINHO (para a igualdade robo = servidor nao ser uma tautologia) e um modelo falso que
segue um guiao.

Correr (PC ou VPS):   python -m unittest -v test_restaurante     (dentro de ferramentas/assistente-negocio)
"""
import copy
import datetime as dt
import json
import os
import sys
import time
import unittest
import urllib.parse
from decimal import ROUND_HALF_UP, Decimal

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
os.environ.setdefault("SUPABASE_URL", "http://fake.invalid")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "fake")

import assistente as A  # noqa: E402
import db  # noqa: E402
import morada as M  # noqa: E402
import motores  # noqa: E402
import restaurante as R  # noqa: E402

DANILO = "351900000002"       # numero de teste inventado (so em memoria)
ESTRANHO = "351912345678"
CLIENTE_DEMO = "bb9ff342-416d-4360-a378-5de5d0a48295"
SESSAO = "vps-baileys:" + os.environ.get("BORA_WHATSAPP_NUMERO", "")  # número da Bora fora do código (repo público)
D2 = Decimal("0.01")
_DORMIR = time.sleep  # o teste desliga o time.sleep global (o assistente dorme 8 s entre voltas de motor); este e o verdadeiro


def d(x):
    return Decimal(str(x))


def _dt(v):
    return dt.datetime.fromisoformat(str(v).replace("Z", "+00:00"))


def _comparavel(a, b):
    try:
        return _dt(a), _dt(b)
    except (ValueError, TypeError):
        pass
    try:
        return float(a), float(b)
    except (ValueError, TypeError):
        return str(a), str(b)


class FakeDB:
    TABELAS = ("restaurants", "products", "product_option_groups", "product_option_items", "platform_settings",
               "assistant_tenants", "assistant_contacts", "assistant_messages", "assistant_tasks", "orders",
               "order_origem", "order_edits", "client_wallets")

    def __init__(self):
        self.t = {k: [] for k in self.TABELAS}
        self.seq = 0
        self.criados = []            # p_input de cada create_order recebido
        self.rpcs = []               # (nome, args) de todas as chamadas
        self.create_depois_de_criar = None  # excecao a levantar DEPOIS de o pedido nascer (rede caiu)
        self.loja_aberta = True

    # --- filtros no dialecto PostgREST usado pelo db.py
    @staticmethod
    def _partir(filtros):
        conds, ordem, limite = [], [], None
        for parte in (filtros or "").split("&"):
            if not parte:
                continue
            col, _, resto = parte.partition("=")
            if col == "select":
                continue
            if col == "order":
                ordem = [x.split(".") for x in resto.split(",")]
                continue
            if col == "limit":
                limite = int(resto)
                continue
            op, _, val = resto.partition(".")
            conds.append((col, op, val))
        return conds, ordem, limite

    @staticmethod
    def _casa(row, conds):
        for col, op, val in conds:
            v = row.get(col)
            if op == "in":
                lista = [urllib.parse.unquote(x) for x in val.strip("()").split(",") if x != ""]
                if str(v) not in lista:
                    return False
                continue
            val = urllib.parse.unquote(val)
            if isinstance(v, bool):
                v = str(v).lower()
            if op == "eq":
                if str(v) != val:
                    return False
            elif op == "neq":
                if str(v) == val:
                    return False
            elif op in ("gt", "gte", "lt", "lte"):
                if v is None:
                    return False
                a, b = _comparavel(v, val)
                if not {"gt": a > b, "gte": a >= b, "lt": a < b, "lte": a <= b}[op]:
                    return False
            else:
                raise AssertionError("filtro nao suportado no FakeDB: " + op)
        return True

    def ler(self, tabela, filtros="", seleciona="*"):
        conds, ordem, limite = self._partir(filtros)
        rows = [copy.deepcopy(r) for r in self.t[tabela] if self._casa(r, conds)]
        for campo, sentido in reversed(ordem):
            rows.sort(key=lambda r, c=campo: (r.get(c) is None, str(r.get(c)) if not isinstance(r.get(c), (int, float)) else r.get(c)),
                      reverse=(sentido == "desc"))
        return rows[:limite] if limite else rows

    def _novo_ts(self):
        self.seq += 1
        return (A.agora() + dt.timedelta(microseconds=self.seq)).isoformat()

    def inserir(self, tabela, linha, devolver=True):
        row = copy.deepcopy(linha)
        if tabela == "order_origem":
            if any(r["order_id"] == row["order_id"] for r in self.t[tabela]):
                raise db.ErroDB("duplicado")
        else:
            row.setdefault("id", self.seq + 1 if tabela != "orders" else row.get("id"))
        row.setdefault("created_at", self._novo_ts())
        if tabela == "assistant_tasks":
            row.setdefault("estado", "aberta")
            row.setdefault("tentativas", 0)
            row.setdefault("simulado", False)
            row.setdefault("payload", {})
        if tabela == "assistant_messages":
            row.setdefault("simulado", False)
        self.seq += 1
        if tabela != "order_origem":
            row["id"] = row.get("id") or self.seq
        self.t[tabela].append(row)
        return copy.deepcopy(row) if devolver else None

    def upsert(self, tabela, linha, chave):
        cols = chave.split(",")
        for r in self.t[tabela]:
            if all(r.get(c) == linha.get(c) for c in cols):
                r.update(linha)
                return copy.deepcopy(r)
        base = dict(linha, historico=[], pessoal=False, nome=None, a_espera_de=None, silenciado_ate=None)
        return self.inserir(tabela, base)

    def atualizar(self, tabela, filtros, campos):
        conds, _, _ = self._partir(filtros)
        feitos = []
        for r in self.t[tabela]:
            if self._casa(r, conds):
                r.update(copy.deepcopy(campos))
                feitos.append(copy.deepcopy(r))
        return feitos

    # --- servidor falso (as contas aqui sao feitas POR OUTRO CAMINHO que o robo)
    def rpc(self, nome, args):
        self.rpcs.append((nome, copy.deepcopy(args)))
        f = getattr(self, "rpc_" + nome.lstrip("_"), None)
        if not f:
            raise db.ErroDB("rpc desconhecida no FakeDB: " + nome)
        return f(args)

    def rpc_modo_demo_loja(self, a):
        s = next((x["value"] for x in self.t["platform_settings"] if x["key"] == "modo_demo_loja"), None)
        if not s:
            return False
        agora = A.agora()
        dentro = _dt(s["inicio"]) <= agora < _dt(s["fim"])
        return bool(s["restaurant_id"] == a["p_rid"] and dentro and (not a.get("p_uid") or s["cliente_user_id"] == a["p_uid"]))

    def rpc_is_partner_open(self, a):
        return {"is_open": self.loja_aberta, "opens_at": None if self.loja_aberta else "19:00", "closes_in_minutes": 120}

    def _grupo_item(self, product_id, grupo, item):
        for g in self.t["product_option_groups"]:
            if g["product_id"] == product_id and g["name"] == grupo:
                for i in self.t["product_option_items"]:
                    if i["group_id"] == g["id"] and i["name"] == item:
                        return d(i["price_add"])
        raise db.ErroDB(f"opcao inexistente {grupo}/{item}")

    def rpc_order_line_options_extras(self, a):
        tot = Decimal(0)
        for o in a["p_selected_options"]:
            for it in o["items"]:
                tot += self._grupo_item(a["p_product_id"], o["group"], it)
        return [{"extras_total": float(tot)}]

    def rpc_pricing_calculate_loja(self, a):
        L = self.t["restaurants"][0]
        sub, km = d(a["p_subtotal"]), d(a["p_distance_km"])
        gratis = L.get("free_delivery_min_cents")
        entrega = Decimal(0) if gratis and sub * 100 >= gratis else d("2.50") + max(Decimal(0), km - 4) * d("0.5")
        servico = (sub * d("0.05")).quantize(D2, ROUND_HALF_UP)
        saco = d("0.30") if a["p_bag_count"] > 0 else Decimal(0)
        return [{"delivery_fee": float(entrega), "service_fee": float(servico), "bag_fee": float(saco),
                 "customer_total": float((sub + entrega + servico + saco).quantize(D2))}]

    def rpc_small_order_fee_calc(self, a):
        return 0

    def rpc_create_order(self, a):
        p = a["p_input"]
        self.criados.append(copy.deepcopy(p))
        if not p.get("user_id"):
            raise db.ErroDB("AUTH_REQUIRED")
        buscar = p["service_type"] == "takeaway"
        L = self.t["restaurants"][0]
        if buscar and not L.get("takeaway_enabled"):
            raise db.ErroDB("TAKEAWAY_NOT_ENABLED")
        prods = {x["id"]: x for x in self.t["products"]}
        sub = Decimal(0)
        for ln, it in zip(p["product_lines"], p["items"]):
            extra = sum((self._grupo_item(ln["product_id"], o["group"], i) for o in it.get("selected_options", []) for i in o["items"]), Decimal(0))
            sub += (d(prods[ln["product_id"]]["price"]) + extra) * ln["quantity"]
        if buscar:
            total = sub
        else:
            pr = self.rpc_pricing_calculate_loja({"p_subtotal": float(sub), "p_distance_km": p["distance_km"], "p_bag_count": p["bag_count"]})[0]
            total = d(pr["customer_total"])
        if p["payment_method"] == "cash" and not buscar and int(total * 100) > 4000:
            raise db.ErroDB("CASH_LIMIT_EXCEEDED")
        oid = "abc123" + str(len(self.criados)) + "-0000"
        self.t["orders"].append({"id": oid, "user_id": p["user_id"], "restaurant_id": L["id"], "status": "created",
                                 "service_type": p["service_type"], "customer_total": float(total), "price": float(total),
                                 "created_at": self._novo_ts(), "takeaway_pickup_code": "K9X2QZ" if buscar else None,
                                 "client_phone": p.get("client_phone")})
        if self.create_depois_de_criar:
            raise self.create_depois_de_criar
        return {"order_id": oid, "customer_total": float(total), "charge_total": float(total),
                "takeaway_pickup_code": "K9X2QZ" if buscar else None}

    def total_servidor(self, i=-1):
        """O total do ultimo (ou i-esimo) pedido criado, como o servidor falso o calculou."""
        return d(self.t["orders"][i]["customer_total"])


class Guiao:
    """Modelo falso: devolve as mensagens do guiao por ordem. Sem ferramentas pedidas = classificador."""

    def __init__(self):
        self.passos, self.chamadas = [], 0

    def __call__(self, cadeia, mensagens, ferramentas=None, pode_pago=True):
        meta = {"motor": "falso:guiao", "custo_eur": 0.0, "tokens_in": 1, "tokens_out": 1}
        if ferramentas is None:
            return {"content": '{"tipo":"negocio"}'}, meta
        self.chamadas += 1
        if not self.passos:
            return {"content": "ok"}, meta
        p = self.passos.pop(0)
        if isinstance(p, str):
            return {"content": p}, meta
        return {"content": "", "tool_calls": [{"id": f"c{i}", "function": {"name": n, "arguments": json.dumps(a)}}
                                              for i, (n, a) in enumerate(p)]}, meta


def preparar():
    f = FakeDB()
    f.t["restaurants"].append({
        "id": "boom-burger-guarda", "name": "Boom! Burger", "is_partner": True, "coming_soon": False, "takeaway_enabled": True,
        "free_delivery_min_cents": 3000, "pausa_ate": None, "phone_prep_minutes": 20, "lat": 40.5414484, "lng": -7.261693,
        "address": "R. Jardim dos Castelos Velhos, 6300-397 Guarda", "business_hours": {}})
    for pid, nome, preco, cat in (("boom-classico", "Boom! Clássico", 12.72, "Hambúrgueres"), ("boom-coca-cola", "Coca-Cola", 2.68, "Bebidas"),
                                  ("boom-duplo-smash", "Boom! Duplo Smash", 18.55, "Hambúrgueres"),
                                  ("boom-kamikaze", "Boom! Kamikaze", 20.88, "Hambúrgueres"),
                                  ("boom-bombastico", "Boom! Bombástico", 15.05, "Hambúrgueres"),
                                  ("boom-duplo-bacon", "Boom! Duplo Bacon", 17.90, "Hambúrgueres")):
        f.t["products"].append({"id": pid, "name": nome, "price": preco, "category": cat, "description": "", "allergens": [],
                                "is_available": True, "esgotado_ate": None, "sort_order": 1, "restaurant_id": "boom-burger-guarda"})
    f.t["product_option_groups"] += [
        {"id": "g-pao", "product_id": "boom-classico", "name": "Trocar o pão", "is_required": False, "min_choices": 0, "max_choices": 1, "sort_order": 1},
        {"id": "g-extras", "product_id": "boom-classico", "name": "Extras", "is_required": False, "min_choices": 0, "max_choices": 2, "sort_order": 2},
        {"id": "g-ponto", "product_id": "boom-bombastico", "name": "Ponto da carne", "is_required": True, "min_choices": 1, "max_choices": 1, "sort_order": 1}]
    f.t["product_option_items"] += [
        {"id": 1, "group_id": "g-pao", "name": "Pão brioche", "price_add": 1.00, "is_available": True, "sort_order": 1},
        {"id": 2, "group_id": "g-extras", "name": "Bacon", "price_add": 1.20, "is_available": True, "sort_order": 1},
        {"id": 3, "group_id": "g-extras", "name": "Ovo", "price_add": 0.90, "is_available": True, "sort_order": 2},
        {"id": 4, "group_id": "g-extras", "name": "Queijo extra", "price_add": 0.80, "is_available": True, "sort_order": 3},
        {"id": 5, "group_id": "g-ponto", "name": "Mal passada", "price_add": 0, "is_available": True, "sort_order": 1},
        {"id": 6, "group_id": "g-ponto", "name": "Bem passada", "price_add": 0, "is_available": True, "sort_order": 2}]
    f.t["platform_settings"] += [{"key": "max_cash_amount_cents", "value": 4000}, {"key": "delivery_max_distance_km", "value": 15}]
    f.t["assistant_tenants"].append({
        "id": "t-boom", "slug": "boom-burger", "nome": "Boom! Burger", "tipo": "restaurante", "restaurant_id": "boom-burger-guarda",
        "provider_id": None, "sessao": SESSAO, "mode": "teste", "allowlist": [DANILO, "351900000001"], "blocklist": [],
        "owner_number": "351900000009", "dono_destino": DANILO, "motor": "falso:guiao", "motores_reserva": [],
        "orcamento_mensal_eur": 0, "tom": "PT-PT, curto.",
        "knowledge": {"ficha": {"dono": "a loja", "link_app": "https://www.boraguarda.com/baixar?de=whatsapp-boom", "notas": []},
                      "contas_clientes": {DANILO: CLIENTE_DEMO}, "perguntas_aprendidas": []}})
    return f


def janela_demo(fake, ativa=True):
    agora = A.agora()
    ini, fim = (agora - dt.timedelta(hours=1), agora + dt.timedelta(hours=1)) if ativa else (agora - dt.timedelta(hours=5), agora - dt.timedelta(hours=3))
    fake.t["platform_settings"] = [x for x in fake.t["platform_settings"] if x["key"] != "modo_demo_loja"]
    fake.t["platform_settings"].append({"key": "modo_demo_loja", "value": {
        "restaurant_id": "boom-burger-guarda", "inicio": ini.isoformat(), "fim": fim.isoformat(), "cliente_user_id": CLIENTE_DEMO}})


class Base(unittest.TestCase):
    def setUp(self):
        self.f = preparar()
        self.guiao = Guiao()
        self._orig = {n: getattr(db, n) for n in ("ler", "inserir", "upsert", "atualizar", "rpc")}
        for n in self._orig:
            setattr(db, n, getattr(self.f, n))
        self._orig_motores = motores.conversar
        motores.conversar = self.guiao
        self._orig_geo = (M.geocodificar, M._rota_google, A.time.sleep)
        self.km = 2.4
        M.geocodificar = lambda texto, pedir=None: (
            None if "inexistente" in texto else
            {"lat": 40.5373, "lng": -7.2676, "morada": "Praça Luís de Camões 1, 6300-725 Guarda, Portugal", "rua": "Praça Luís de Camões 1",
             "codigo_postal": "6300-725", "cidade": "Guarda"})
        M._rota_google = lambda *a: self.km
        A.time.sleep = lambda s: None
        self.t = self.f.t["assistant_tenants"][0]

    def tearDown(self):
        # nenhuma mensagem de saida nem prompt pode falar do dono da barbearia
        for m in self.f.t["assistant_messages"]:
            self.assertNotIn("ernando", (m.get("texto") or "").lower())
        self.assertNotIn("ernando", R.prompt_restaurante(self.t, {"numero": DANILO}).lower())
        for n, fn in self._orig.items():
            setattr(db, n, fn)
        motores.conversar = self._orig_motores
        M.geocodificar, M._rota_google, A.time.sleep = self._orig_geo

    def turno(self, texto="olá"):
        _DORMIR(0.03)  # o resumo tem de ser de um turno ANTERIOR (relogio do Windows: ~15 ms)
        return R.TurnoRestaurante(self.t, DANILO, {"nome": None}, False, texto)

    def encher(self, linhas, modo="entrega", morada="Praça Luís de Camões 1"):
        t = self.turno()
        for prod, q, ops in linhas:
            r = t.executar("adicionar_ao_pedido", {"produto": prod, "quantidade": q, "opcoes": ops})
            self.assertTrue(r.get("ok"), r)
        r = t.executar("escolher_entrega", {"modo": modo, **({"morada": morada} if modo == "entrega" else {})})
        self.assertTrue(r.get("ok"), r)
        return t

    def orcar(self):
        o = self.turno().executar("orcamento", {})
        return o

    @staticmethod
    def valor(texto_euros):
        return d(texto_euros.replace(" €", "").replace(",", "."))

    def confirmar(self, texto="sim"):
        return self.turno(texto).executar("confirmar_pedido", {})


class TestContas(Base):
    def test_entrega_abaixo_de_30_total_do_robo_igual_ao_servidor(self):
        self.encher([("Clássico", 1, []), ("Coca-Cola", 1, [])])
        o = self.orcar()
        self.assertTrue(o["ok"], o)
        self.assertIn("Entrega: 2,50 €", o["resumo_texto"])
        total_robo = self.valor(o["total"])
        self.assertEqual(total_robo, d("18.97"))  # = quote_order_pricing real medido em producao (15,40 + 2,50 + 0,77 + 0,30)
        r = self.confirmar()
        self.assertTrue(r["ok"], r)
        self.assertEqual(total_robo, self.f.total_servidor())
        self.assertEqual(len(self.f.criados), 1)
        p = self.f.criados[0]
        self.assertEqual((p["service_type"], p["payment_method"], p["user_id"], p["is_partner_store"]), ("restaurant", "cash", CLIENTE_DEMO, True))
        self.assertEqual((p["distance_km"], p["bag_count"], p["client_phone"]), (2.4, 1, "+" + DANILO))
        self.assertEqual(p["items"][0]["productId"], "boom-classico")

    def test_ir_buscar_sem_entrega_nem_taxa(self):
        self.encher([("Clássico", 1, []), ("Coca-Cola", 1, [])], modo="buscar")
        o = self.orcar()
        self.assertTrue(o["ok"], o)
        self.assertNotIn("Entrega", o["resumo_texto"])
        self.assertNotIn("Taxa de serviço", o["resumo_texto"])
        self.assertIn("Paga na loja", o["resumo_texto"])
        self.assertEqual(self.valor(o["total"]), d("15.40"))  # so os produtos
        r = self.confirmar()
        self.assertTrue(r["ok"], r)
        p = self.f.criados[0]
        self.assertEqual((p["service_type"], p["order_type"], p["bag_count"], p["distance_km"]), ("takeaway", "takeaway", 0, 0))
        self.assertEqual(self.valor(r["total"]), self.f.total_servidor())
        self.assertEqual(self.f.t["orders"][0]["takeaway_pickup_code"], "K9X2QZ")

    def test_ir_buscar_desligado_na_loja(self):
        self.f.t["restaurants"][0]["takeaway_enabled"] = False
        r = self.turno().executar("escolher_entrega", {"modo": "buscar"})
        self.assertFalse(r["ok"])
        self.assertEqual(r["erro"], "loja_sem_ir_buscar")

    def test_entrega_gratis_a_partir_de_30(self):
        self.encher([("Duplo Smash", 2, [])])  # 37,10
        o = self.orcar()
        self.assertTrue(o["ok"], o)
        self.assertIn("Entrega: grátis", o["resumo_texto"])
        self.assertEqual(self.valor(o["total"]), d("39.26"))  # 37,10 + 1,86 + 0,30
        r = self.confirmar()
        self.assertTrue(r["ok"], r)
        self.assertEqual(self.valor(o["total"]), self.f.total_servidor())

    def test_entrega_a_beira_dos_30(self):
        self.encher([("Duplo Smash", 1, []), ("Coca-Cola", 1, [])])  # 21,23: paga entrega
        self.assertIn("Entrega: 2,50 €", self.orcar()["resumo_texto"])
        k = self.turno().executar("adicionar_ao_pedido", {"produto": "Bombástico", "quantidade": 1, "opcoes": [{"grupo": "Ponto da carne", "itens": ["Mal passada"]}]})
        self.assertTrue(k["ok"], k)  # 36,28: ja nao paga
        self.assertIn("Entrega: grátis", self.orcar()["resumo_texto"])

    def test_recusa_acima_do_maximo_em_dinheiro(self):
        self.encher([("Kamikaze", 2, [])])  # 41,76 + extras > 40
        o = self.orcar()
        self.assertFalse(o["ok"])
        self.assertEqual(o["erro"], "acima_do_maximo_em_dinheiro")
        self.assertEqual(o["maximo"], "40,00 €")
        self.assertNotIn("resumo_texto", o)
        r = self.confirmar()
        self.assertFalse(r["ok"])
        self.assertEqual(self.f.criados, [])

    def test_ir_buscar_acima_do_maximo_nao_tem_tecto(self):
        self.encher([("Kamikaze", 3, [])], modo="buscar")  # 62,64 a pagar na loja
        o = self.orcar()
        self.assertTrue(o["ok"], o)
        self.assertEqual(self.valor(o["total"]), d("62.64"))

    def test_opcoes_entram_no_total_e_no_pedido(self):
        r = self.turno().executar("adicionar_ao_pedido", {"produto": "Clássico", "quantidade": 1, "opcoes": [
            {"grupo": "Trocar o pão", "itens": ["Pão brioche"]}, {"grupo": "Extras", "itens": ["Bacon", "Ovo"]}]})
        self.assertTrue(r["ok"], r)
        self.turno().executar("escolher_entrega", {"modo": "buscar"})
        o = self.orcar()
        self.assertEqual(self.valor(o["total"]), d("15.82"))  # 12,72 + 1,00 + 1,20 + 0,90
        r = self.confirmar()
        self.assertTrue(r["ok"], r)
        self.assertEqual(self.valor(o["total"]), self.f.total_servidor())
        self.assertEqual(self.f.criados[0]["items"][0]["selected_options"],
                         [{"group": "Trocar o pão", "items": ["Pão brioche"]}, {"group": "Extras", "items": ["Bacon", "Ovo"]}])
        self.assertEqual(self.f.criados[0]["items"][0]["price"], 15.82)
        self.assertEqual(self.f.criados[0]["items"][0]["basePrice"], 12.72)

    def test_opcoes_invalidas(self):
        t = self.turno()
        self.assertEqual(t.executar("adicionar_ao_pedido", {"produto": "Clássico", "opcoes": [{"grupo": "Extras", "itens": ["Foie gras"]}]})["erro"], "opcao_nao_existe")
        self.assertEqual(t.executar("adicionar_ao_pedido", {"produto": "Clássico", "opcoes": [{"grupo": "Extras", "itens": ["Bacon", "Ovo", "Queijo extra"]}]})["erro"], "demasiadas_opcoes")
        r = t.executar("adicionar_ao_pedido", {"produto": "Bombástico"})  # grupo obrigatorio
        self.assertEqual((r["erro"], r["grupo"]), ("falta_escolher", "Ponto da carne"))
        self.assertEqual(t.executar("ver_pedido", {})["pedido"], [])

    def test_produto_que_nao_existe_ou_ambiguo(self):
        t = self.turno()
        self.assertEqual(t.executar("adicionar_ao_pedido", {"produto": "pizza quatro queijos"})["erro"], "nao_ha_no_menu")
        self.assertEqual(t.executar("adicionar_ao_pedido", {"produto": "duplo"})["erro"], "qual_destes")


class TestMotorQueRepete(Base):
    """29/10: um motor de reserva (mais fraco) voltou a juntar o que o carrinho ja tinha (2+2 virou 4+4, 64,98 EUR)."""

    def qtds(self):
        k = R.carrinho(self.t, DANILO)
        return {l["nome"]: l["quantidade"] for l in (k["payload"]["itens"] if k else [])}

    def test_mesma_chamada_repetida_no_mesmo_turno_nao_duplica(self):
        t = self.turno("Queria 2 Boom! Clássico e 2 Coca-Cola")
        for _ in range(2):
            t.executar("adicionar_ao_pedido", {"produto": "Clássico", "quantidade": 2})
            t.executar("adicionar_ao_pedido", {"produto": "Coca-Cola", "quantidade": 2})
        self.assertEqual(self.qtds(), {"Boom! Clássico": 2, "Coca-Cola": 2})

    def test_motor_fraco_nao_volta_a_juntar_quando_o_cliente_so_da_a_morada(self):
        self.turno("Queria 2 Boom! Clássico e 2 Coca-Cola").executar("adicionar_ao_pedido", {"produto": "Clássico", "quantidade": 2})
        self.turno("Queria 2 Boom! Clássico e 2 Coca-Cola").executar("adicionar_ao_pedido", {"produto": "Coca-Cola", "quantidade": 2})
        t = self.turno("Avenida Monsenhor Mendes do Carmo, Guarda")
        r1 = t.executar("adicionar_ao_pedido", {"produto": "Clássico", "quantidade": 2})
        r2 = t.executar("adicionar_ao_pedido", {"produto": "Coca-Cola", "quantidade": 2})
        self.assertTrue(r1["ok"] and r1["ja_estava"] and r2["ja_estava"], (r1, r2))
        self.assertEqual(self.qtds(), {"Boom! Clássico": 2, "Coca-Cola": 2})

    def test_cliente_pede_mais_um_e_soma(self):
        self.turno("um clássico").executar("adicionar_ao_pedido", {"produto": "Clássico", "quantidade": 1})
        r = self.turno("mais um, por favor").executar("adicionar_ao_pedido", {"produto": "Clássico", "quantidade": 1})
        self.assertNotIn("ja_estava", r)
        self.assertEqual(self.qtds(), {"Boom! Clássico": 2})

    def test_cliente_nomeia_o_produto_outra_vez_e_soma(self):
        self.turno("um clássico").executar("adicionar_ao_pedido", {"produto": "Clássico", "quantidade": 1})
        self.turno("quero um clássico").executar("adicionar_ao_pedido", {"produto": "Clássico", "quantidade": 1})
        self.assertEqual(self.qtds(), {"Boom! Clássico": 2})

    def test_um_e_outro_no_mesmo_turno_somam(self):
        t = self.turno("um clássico e outro clássico")
        t.executar("adicionar_ao_pedido", {"produto": "Clássico", "quantidade": 1})
        t.executar("adicionar_ao_pedido", {"produto": "Clássico", "quantidade": 1})
        self.assertEqual(self.qtds(), {"Boom! Clássico": 2})

    def test_linha_nova_com_opcoes_nao_e_repeticao(self):
        self.turno("um clássico").executar("adicionar_ao_pedido", {"produto": "Clássico", "quantidade": 1})
        r = self.turno("outro clássico, com bacon").executar("adicionar_ao_pedido", {"produto": "Clássico", "quantidade": 1,
                                                                                    "opcoes": [{"grupo": "Extras", "itens": ["Bacon"]}]})
        self.assertNotIn("ja_estava", r)
        self.assertEqual(len(R.carrinho(self.t, DANILO)["payload"]["itens"]), 2)


class TestSoCriaDepoisDoSim(Base):
    def test_sem_resumo_nao_cria(self):
        self.encher([("Clássico", 1, [])])
        r = self.confirmar()
        self.assertEqual((r["ok"], r["erro"]), (False, "falta_resumo"))
        self.assertEqual(self.f.criados, [])

    def test_resumo_e_sim_no_mesmo_turno_nao_cria(self):
        self.encher([("Clássico", 1, [])])
        t = self.turno("sim")
        self.assertTrue(t.executar("orcamento", {})["ok"])
        r = t.executar("confirmar_pedido", {})
        self.assertEqual(r["erro"], "resumo_ainda_nao_visto")
        self.assertEqual(self.f.criados, [])

    def test_resposta_que_nao_e_sim_nao_cria(self):
        self.encher([("Clássico", 1, [])])
        self.orcar()
        for texto in ("talvez", "e quanto demora?", "não, tira a coca-cola", "espera", "afinal quero mais um"):
            r = self.confirmar(texto)
            self.assertEqual(r["erro"], "sem_sim_explicito", texto)
        self.assertEqual(self.f.criados, [])

    def test_carrinho_mudou_depois_do_resumo_pede_novo_resumo(self):
        self.encher([("Clássico", 1, [])])
        self.orcar()
        self.turno().executar("adicionar_ao_pedido", {"produto": "Coca-Cola"})
        self.assertEqual(self.confirmar()["erro"], "falta_resumo")
        self.assertEqual(self.f.criados, [])

    def test_morada_mudou_depois_do_resumo_pede_novo_resumo(self):
        self.encher([("Clássico", 1, [])])
        self.orcar()
        self.turno().executar("escolher_entrega", {"modo": "buscar"})
        self.assertEqual(self.confirmar()["erro"], "falta_resumo")

    def test_preco_mudou_entre_resumo_e_sim(self):
        self.encher([("Clássico", 1, [])])
        self.orcar()
        self.f.t["products"][0]["price"] = 13.50
        r = self.confirmar()
        self.assertEqual(r["erro"], "preco_mudou")
        self.assertEqual(self.f.criados, [])

    def test_produto_ficou_indisponivel(self):
        self.encher([("Clássico", 1, [])])
        self.orcar()
        self.f.t["products"][0]["is_available"] = False
        r = self.confirmar()
        self.assertFalse(r["ok"])
        self.assertEqual(r["erro"], "produto_indisponivel")
        self.assertEqual(self.f.criados, [])

    def test_sim_cria_uma_vez_so(self):
        self.encher([("Clássico", 1, [])])
        self.orcar()
        r1 = self.confirmar("Sim, pode ser")
        self.assertTrue(r1["ok"], r1)
        r2 = self.confirmar("sim")
        self.assertTrue(r2["ok"])
        self.assertTrue(r2.get("ja_estava_feito"))
        self.assertEqual(len(self.f.criados), 1)
        self.assertEqual(len(self.f.t["orders"]), 1)

    def test_rede_caiu_depois_de_criar_nao_duplica(self):
        self.encher([("Clássico", 1, [])])
        self.orcar()
        self.f.create_depois_de_criar = TimeoutError("timed out")
        r = self.confirmar()
        self.assertEqual((r["ok"], r["erro"]), (False, "interno"))  # o cliente nao ouve "feito"
        self.f.create_depois_de_criar = None
        r = self.confirmar()
        self.assertTrue(r["ok"], r)
        self.assertEqual(len(self.f.criados), 1, "o segundo sim criou OUTRO pedido")
        self.assertEqual(len(self.f.t["orders"]), 1)

    def test_numero_sem_conta_nao_encomenda(self):
        self.t["knowledge"]["contas_clientes"] = {}
        self.encher([("Clássico", 1, [])])
        self.orcar()
        r = self.confirmar()
        self.assertEqual(r["erro"], "sem_conta")
        self.assertIn("boraguarda.com/baixar", r["link_app"])
        self.assertEqual(self.f.criados, [])

    def test_loja_em_breve_fora_da_janela_nao_cria(self):
        self.encher([("Clássico", 1, [])])
        self.orcar()
        self.f.t["restaurants"][0]["coming_soon"] = True
        r = self.confirmar()
        self.assertEqual(r["erro"], "loja_em_breve")
        self.assertEqual(self.f.criados, [])

    def test_loja_em_breve_dentro_da_janela_demo_cria(self):
        self.f.t["restaurants"][0]["coming_soon"] = True
        janela_demo(self.f, ativa=True)
        self.encher([("Clássico", 1, [])])
        self.orcar()
        self.assertTrue(self.confirmar()["ok"])

    def test_servidor_recusou_diz_o_motivo_e_nao_diz_feito(self):
        self.encher([("Clássico", 1, [])])
        self.orcar()
        self.f.rpc_create_order = lambda a: (_ for _ in ()).throw(db.ErroDB("create_order -> 400 STORE_PAUSED: loja em pausa"))
        r = self.confirmar()
        self.assertEqual((r["ok"], r["erro"], r["detalhe"]), (False, "servidor_recusou", "a loja está em pausa"))
        self.assertEqual(self.f.t["order_origem"], [])


class TestOrigem(Base):
    def test_escreve_order_origem(self):
        self.encher([("Clássico", 1, [])])
        self.orcar()
        r = self.confirmar()
        self.assertTrue(r["ok"], r)
        oid = self.f.t["orders"][0]["id"]
        self.assertEqual(self.f.t["order_origem"], [{"order_id": oid, "origem": "whatsapp", "client_phone": "+" + DANILO,
                                                      "tenant_slug": "boom-burger", "created_at": self.f.t["order_origem"][0]["created_at"]}])
        self.assertIn("#" + oid[:6].upper(), r["mensagem"])

    def test_origem_a_falhar_nao_estraga_o_pedido(self):
        self.encher([("Clássico", 1, [])])
        self.orcar()
        self.f.inserir_original = self.f.inserir

        def inserir(tabela, linha, devolver=True):
            if tabela == "order_origem":
                raise db.ErroDB("tabela sem permissao")
            return self.f.inserir_original(tabela, linha, devolver)
        db.inserir = inserir
        r = self.confirmar()
        self.assertTrue(r["ok"], r)
        self.assertIn("origem_erro", self.f.t["assistant_tasks"][0]["payload"])


class TestAtender(Base):
    def ev(self, numero, texto):
        return {"sessao": SESSAO, "numero": numero, "texto": texto, "msg_id": "m" + str(time.time())}

    def test_numero_fora_da_allowlist_e_ignorado(self):
        r = A.atender(self.ev(ESTRANHO, "Quero um hambúrguer"))
        self.assertFalse(r["tratado"])
        self.assertEqual(r["acao"], "nao-e-do-assistente")
        self.assertEqual(self.f.t["assistant_messages"], [])
        self.assertEqual(self.guiao.chamadas, 0)

    def test_fora_da_allowlist_nunca_recebe_nada(self):
        self.assertIsNone(A.enfileirar(self.t, ESTRANHO, "olá", "teste"))
        m = self.f.t["assistant_messages"][0]
        self.assertEqual(m["entrega_estado"], "bloqueado")

    def test_grupo_ignorado(self):
        r = A.atender(dict(self.ev(DANILO, "Quero um hambúrguer"), grupo=True))
        self.assertFalse(r["tratado"])

    def test_fora_da_janela_diz_que_abre_em_breve_sem_gastar_motor(self):
        self.f.t["restaurants"][0]["coming_soon"] = True
        janela_demo(self.f, ativa=False)
        r = A.atender(self.ev(DANILO, "Boa tarde, queria fazer uma encomenda"))
        self.assertTrue(r["tratado"])
        self.assertEqual(r["acao"], "loja-abre-em-breve")
        self.assertIn("abre em breve", r["respostas"][0])
        self.assertEqual(self.guiao.chamadas, 0)
        self.assertEqual(self.f.t["assistant_messages"][-1]["entrega_estado"], "pendente")

    def test_dentro_da_janela_demo_o_robo_atende(self):
        self.f.t["restaurants"][0]["coming_soon"] = True
        janela_demo(self.f, ativa=True)
        self.guiao.passos = ["Olá! Diga-me o que quer."]
        r = A.atender(self.ev(DANILO, "Boa tarde"))
        self.assertEqual(r["acao"], "respondeu")
        self.assertEqual(self.guiao.chamadas, 1)

    def test_modelo_com_pressa_nao_consegue_criar_pedido_sem_resumo(self):
        """Mesmo que o modelo chame confirmar_pedido logo no primeiro 'sim', o codigo recusa e nao ha pedido."""
        self.guiao.passos = [[("adicionar_ao_pedido", {"produto": "Clássico"}), ("escolher_entrega", {"modo": "buscar"})],
                             "Junto o Clássico. Vem buscar. Confirma?"]
        A.atender(self.ev(DANILO, "Quero um clássico, venho buscar"))
        self.guiao.passos = [[("confirmar_pedido", {})], "Ainda não tenho o resumo; já lho mostro."]
        r = A.atender(self.ev(DANILO, "sim"))
        self.assertEqual(r["ferramentas"], ["confirmar_pedido"])
        self.assertEqual(self.f.criados, [])
        self.assertEqual(self.f.t["order_origem"], [])

    def test_conversa_inteira_pelo_atender(self):
        self.guiao.passos = [[("adicionar_ao_pedido", {"produto": "Clássico"}), ("adicionar_ao_pedido", {"produto": "Coca-Cola"}),
                              ("escolher_entrega", {"modo": "entrega", "morada": "Praça Luís de Camões 1"})], "Encontrei: Praça Luís de Camões. É esta?"]
        A.atender(self.ev(DANILO, "Um clássico e uma coca-cola, entrega na Praça Luís de Camões 1"))
        self.guiao.passos = [[("orcamento", {})], "RESUMO"]
        _DORMIR(0.03)  # relogio do Windows ~15 ms: o resumo tem de ser de um turno ANTERIOR (na vida real passam segundos)
        r = A.atender(self.ev(DANILO, "é essa"))
        self.assertIn("orcamento", r["ferramentas"])
        self.assertEqual(self.f.criados, [])
        self.guiao.passos = [[("confirmar_pedido", {})], "Pedido feito!"]
        _DORMIR(0.03)
        r = A.atender(self.ev(DANILO, "Sim"))
        self.assertEqual(len(self.f.criados), 1)
        self.assertEqual(len(self.f.t["order_origem"]), 1)
        self.assertEqual(self.valor(R.euros(self.f.total_servidor())), d("18.97"))
        self.assertIn("pedido FEITO", self.f.t["assistant_contacts"][0]["historico"][-1]["feito"])


class TestTextoDoServidor(Base):
    """O que o cliente le (resumo e pedido feito) e do servidor, mesmo que um motor de reserva o reescreva."""

    def ev(self, numero, texto):
        return {"sessao": SESSAO, "numero": numero, "texto": texto, "msg_id": "m" + str(time.time())}

    def saida(self):
        return [m["texto"] for m in self.f.t["assistant_messages"] if m.get("direcao") == "saida"][-1]

    def preparar_resumo(self):
        self.guiao.passos = [[("adicionar_ao_pedido", {"produto": "Clássico"}), ("adicionar_ao_pedido", {"produto": "Coca-Cola"}),
                              ("escolher_entrega", {"modo": "buscar"})], "Junto. Vem buscar."]
        A.atender(self.ev(DANILO, "Um clássico e uma coca-cola, venho buscar"))

    def test_resumo_reescrito_por_um_motor_e_substituido_pelo_do_servidor(self):
        self.preparar_resumo()
        self.guiao.passos = [[("orcamento", {})], "Fica tudo por 10 euros. Confirma?"]
        _DORMIR(0.03)
        A.atender(self.ev(DANILO, "é essa"))
        txt = self.saida()
        self.assertIn("Total: 15,40 €", txt)
        self.assertNotIn("10 euros", txt)

    def test_resumo_certo_com_uma_frase_antes_fica_como_esta(self):
        self.preparar_resumo()
        _DORMIR(0.03)
        # o modelo repete o resumo tal e qual, com uma frase antes: nao se mexe
        r = self.turno().executar("orcamento", {})
        self.guiao.passos = [[("orcamento", {})], "Com certeza.\n\n" + r["resumo_texto"]]
        A.atender(self.ev(DANILO, "ok"))
        self.assertTrue(self.saida().startswith("Com certeza."))

    def test_pedido_feito_nao_pode_dizer_que_ja_esta_a_caminho(self):
        self.preparar_resumo()
        self.guiao.passos = [[("orcamento", {})], "RESUMO"]
        _DORMIR(0.03)
        A.atender(self.ev(DANILO, "é essa"))
        self.guiao.passos = [[("confirmar_pedido", {})], "Encomenda confirmada! Já está a caminho, bom apetite!"]
        _DORMIR(0.03)
        A.atender(self.ev(DANILO, "Sim"))
        txt = self.saida()
        self.assertEqual(len(self.f.criados), 1)
        self.assertIn("feito!", txt)
        self.assertIn("15,40 €", txt)
        self.assertNotIn("a caminho", txt)

    def mostrar_resumo(self):
        self.preparar_resumo()
        self.guiao.passos = [[("orcamento", {})], "RESUMO"]
        _DORMIR(0.03)
        A.atender(self.ev(DANILO, "é essa"))
        self.assertIn("Confirma a encomenda?", self.saida())
        self.assertEqual(self.f.criados, [])

    def test_sim_puro_ao_resumo_confirma_em_codigo_sem_motor(self):
        self.mostrar_resumo()
        chamadas = self.guiao.chamadas
        _DORMIR(0.03)
        r = A.atender(self.ev(DANILO, "Sim, confirmo."))
        self.assertEqual(self.guiao.chamadas, chamadas)  # nenhum motor foi chamado
        self.assertEqual(r["acao"].split(" ")[0], "pedido-confirmado-em-codigo")
        self.assertEqual(len(self.f.criados), 1)
        self.assertEqual(len(self.f.t["order_origem"]), 1)
        self.assertIn("feito!", self.saida())
        self.assertIn("15,40 €", self.saida())
        self.assertIn("pedido FEITO", self.f.t["assistant_contacts"][0]["historico"][-1]["feito"])
        _DORMIR(0.03)
        A.atender(self.ev(DANILO, "ok"))  # um 2.o "ok" nao cria outro pedido
        self.assertEqual(len(self.f.criados), 1)

    def test_sim_com_pedido_extra_nao_confirma_sozinho(self):
        self.mostrar_resumo()
        _DORMIR(0.03)
        A.atender(self.ev(DANILO, "Sim, e acrescenta um bacon"))
        self.assertEqual(self.f.criados, [])
        self.assertFalse(R.e_sim_puro("Sim, e com bacon"))
        self.assertFalse(R.e_sim_puro("sim mas muda a morada"))
        self.assertTrue(all(R.e_sim_puro(x) for x in ("Sim", "sim, confirmo", "Pode ser!", "ok", "Está bem, obrigado", "confirmo o pedido")))

    def test_sim_a_outra_pergunta_nao_confirma(self):
        self.mostrar_resumo()
        self.f.t["assistant_contacts"][0]["historico"][-1]["t"] = "Quer mais alguma coisa?"
        _DORMIR(0.03)
        A.atender(self.ev(DANILO, "sim"))
        self.assertEqual(self.f.criados, [])

    def test_sim_puro_com_resumo_velho_ou_carrinho_mudado_nao_cria(self):
        self.mostrar_resumo()
        self.turno("mais uma coca-cola").executar("adicionar_ao_pedido", {"produto": "Coca-Cola", "quantidade": 1})  # carrinho mexeu
        _DORMIR(0.03)
        A.atender(self.ev(DANILO, "sim"))
        self.assertEqual(self.f.criados, [])

    def test_carrinho_mexido_depois_do_resumo_nao_forca_o_resumo_velho(self):
        self.preparar_resumo()
        self.guiao.passos = [[("orcamento", {}), ("adicionar_ao_pedido", {"produto": "Coca-Cola", "quantidade": 1}), ], "Juntei mais uma Coca-Cola."]
        _DORMIR(0.03)
        A.atender(self.ev(DANILO, "mais uma coca-cola"))
        self.assertEqual(self.saida(), "Juntei mais uma Coca-Cola.")


class TestAvisos(Base):
    def criar(self, modo="entrega"):
        self.encher([("Clássico", 1, [])], modo=modo)
        self.orcar()
        r = self.confirmar()
        self.assertTrue(r["ok"], r)
        return self.f.t["orders"][-1]

    def avisos(self):
        n = R.avisos_pedidos(self.t)
        return n, [m["texto"] for m in self.f.t["assistant_messages"] if m["direcao"] == "saida" and str(m.get("motivo", "")).startswith(("pedido:", "link_app"))]

    def test_aceite_saiu_entregue_e_link_uma_vez(self):
        o = self.criar()
        self.assertEqual(self.avisos()[0], 0)  # 'recebido' ja foi dito na confirmacao
        o.update(status="preparing", accepted_at=A.iso(A.agora()), prep_time_minutes=20)
        n, textos = self.avisos()
        self.assertEqual(n, 1)
        self.assertIn("aceitou o seu pedido", textos[0])
        self.assertIn("20 min", textos[0])
        self.assertEqual(self.avisos()[0], 0)  # idempotente
        o.update(status="pickedUp", cash_total_due=o["customer_total"])
        n, textos = self.avisos()
        self.assertEqual(n, 1)
        self.assertIn("já saiu para entrega", textos[-1])
        self.assertIn("em dinheiro", textos[-1])
        o.update(status="delivered")
        n, textos = self.avisos()
        self.assertEqual(n, 2)  # entregue + link
        self.assertIn("Pedido entregue", textos[-2])
        self.assertIn("https://www.boraguarda.com/baixar?de=whatsapp-boom", textos[-1])
        self.assertEqual(self.f.t["assistant_tasks"][0]["estado"], "cumprida")
        self.assertEqual(self.avisos()[0], 0)

    def test_demo_termina_em_cancelado_sem_custo_e_diz_entregue(self):
        o = self.criar()
        o.update(status="cancelled", cancel_reason="Demonstracao concluida: entrega simulada, sem custo")
        n, textos = self.avisos()
        self.assertTrue(any("Pedido entregue" in x for x in textos), textos)
        self.assertFalse(any("cancelado" in x.lower() for x in textos), textos)

    def test_ir_buscar_pronto(self):
        o = self.criar(modo="buscar")
        o.update(status="preparing", accepted_at=A.iso(A.agora()), takeaway_prep_minutes=15, service_type="takeaway")
        n, textos = self.avisos()
        self.assertIn("quando puder vir buscar", textos[-1])
        o.update(takeaway_ready_at=A.iso(A.agora()), status="readyForPickup")
        n, textos = self.avisos()
        self.assertIn("está pronto, pode vir buscar", textos[-1])
        self.assertIn("K9X2QZ", textos[-1])
        o.update(status="delivered")
        n, textos = self.avisos()
        self.assertIn("Pedido levantado", textos[-2])

    def test_produto_em_falta_avisa_o_novo_total(self):
        o = self.criar()
        self.f.t["order_edits"].append({"id": "e1", "order_id": o["id"], "tipo": "remove", "estado": "aplicado", "nome": "Coca-Cola",
                                        "quantidade": 1, "total_depois": 15.10})
        n, textos = self.avisos()
        self.assertEqual(n, 1)
        self.assertIn("não tinha 1x Coca-Cola", textos[0])
        self.assertIn("15,10 €", textos[0])
        self.assertEqual(self.avisos()[0], 0)

    def test_so_a_mudanca_mais_recente_vale(self):
        out = R.mensagens_novas(self.t, {"avisados": ["recebido"]}, {"id": "abcdef123", "status": "pickedUp", "service_type": "restaurant",
                                                                    "accepted_at": "2026-10-29T10:00:00+00:00", "customer_total": 18.97}, [])
        self.assertEqual([c for c, _ in out], ["saiu"])

    def test_cancelado_pela_loja(self):
        o = self.criar()
        o.update(status="rejected")
        n, textos = self.avisos()
        self.assertIn("cancelado pela loja", textos[0])
        self.assertIn("Não tem nada a pagar", textos[0])
        self.assertEqual(self.f.t["assistant_tasks"][0]["estado"], "cancelada")


class TestMorada(Base):
    def test_fora_da_zona(self):
        self.km = 22.0
        self.turno().executar("adicionar_ao_pedido", {"produto": "Clássico"})
        r = self.turno().executar("escolher_entrega", {"modo": "entrega", "morada": "Rua do Fim do Mundo 5, Vilar Formoso"})
        self.assertFalse(r["ok"])
        self.assertEqual(r["erro"], "fora_da_zona")
        self.assertIn("fora da zona", r["instrucao"])

    def test_morada_nao_encontrada(self):
        r = self.turno().executar("escolher_entrega", {"modo": "entrega", "morada": "rua inexistente 99"})
        self.assertEqual(r["erro"], "morada_nao_encontrada")

    def test_km_de_estrada_e_nunca_abaixo_da_linha_reta(self):
        reta = M.haversine_km(40.5414484, -7.261693, 40.5373, -7.2676)
        self.assertEqual(M.km_estrada(40.5414484, -7.261693, 40.5373, -7.2676, rota=lambda *a: 0.1), (round(reta, 2), "estrada"))
        self.assertEqual(M.km_estrada(40.5414484, -7.261693, 40.5373, -7.2676, rota=lambda *a: 3.7), (3.7, "estrada"))

    def test_sem_google_cai_para_a_linha_reta(self):
        def rebenta(*a):
            raise RuntimeError("sem chave")
        km, como = M.km_estrada(40.5414484, -7.261693, 40.5373, -7.2676, rota=rebenta)
        self.assertEqual(como, "linha-reta")
        self.assertGreater(km, 0)

    def test_distancia_de_estrada_entra_no_preco(self):
        self.km = 6.0  # 2,50 + (6 - 4) * 0,50 = 3,50 de entrega
        self.encher([("Clássico", 1, [])])
        o = self.orcar()
        self.assertIn("Entrega: 3,50 €", o["resumo_texto"])
        self.assertEqual(self.confirmar()["ok"], True)
        self.assertEqual(self.f.criados[0]["distance_km"], 6.0)


class TestOutros(Base):
    def test_sim_e_nao(self):
        for t in ("sim", "Sim!", "pode ser", "pode fazer", "ok", "Confirmo", "está bem", "bora"):
            self.assertTrue(R.e_sim(t), t)
        for t in ("não", "talvez", "sim mas tira o bacon", "espera um pouco", "quanto custa?", "", "afinal troca o pão"):
            self.assertFalse(R.e_sim(t), t)

    def test_link_da_app_por_defeito_e_de_boom(self):
        self.assertEqual(R.link_app({"slug": "boom-burger"}), "https://www.boraguarda.com/baixar?de=whatsapp-boom")
        self.assertEqual(R.link_app(self.t), "https://www.boraguarda.com/baixar?de=whatsapp-boom")

    def test_menu_vem_da_base_ao_vivo(self):
        self.f.t["products"][1]["is_available"] = False
        self.f.t["products"][3]["price"] = 21.10
        p = R.prompt_restaurante(self.t, {"numero": DANILO})
        self.assertNotIn("Coca-Cola", p)
        self.assertIn("Boom! Kamikaze 21,10 €", p)
        self.assertIn("Pagamento: só dinheiro", p)

    def test_alergenios_sem_dados_nao_inventa(self):
        r = self.turno().executar("alergenios", {"produto": "Clássico"})
        self.assertTrue(r["sem_dados"])
        self.assertIn("Nunca digas que não tem alergénios", r["instrucao"])

    def test_passar_ao_dono_nao_fala_do_dono_da_bora(self):
        r = self.turno().executar("passar_ao_dono", {"motivo": "quer reembolso"})
        self.assertIn("a loja", r["instrucao"])
        msg = [m for m in self.f.t["assistant_messages"] if m["motivo"] == "passar_dono"][0]
        self.assertIn("quer reembolso", msg["texto"])

    def test_ferramenta_partida_nao_rebenta_a_conversa(self):
        t = self.turno()
        db.ler = lambda *a, **k: (_ for _ in ()).throw(RuntimeError("base em baixo"))
        try:
            r = t.executar("ver_pedido", {})
        finally:
            db.ler = self.f.ler
        self.assertEqual((r["ok"], r["erro"]), (False, "interno"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
