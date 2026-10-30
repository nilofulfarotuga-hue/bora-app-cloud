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
import re
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
        self.passos, self.chamadas, self.sistema = [], 0, None

    def __call__(self, cadeia, mensagens, ferramentas=None, pode_pago=True):
        meta = {"motor": "falso:guiao", "custo_eur": 0.0, "tokens_in": 1, "tokens_out": 1}
        if ferramentas is None:
            return {"content": '{"tipo":"negocio"}'}, meta
        self.chamadas += 1
        self.sistema = mensagens[0]["content"]  # o prompt que o motor viu (para os testes do carrinho antigo)
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
        # robo ligado para toda a gente: quem nao testa ouve "abre em breve" e nao ha pedido
        self.t["mode"] = "ligado"
        self.encher([("Clássico", 1, [])])
        self.orcar()
        self.f.t["restaurants"][0]["coming_soon"] = True
        r = self.confirmar()
        self.assertEqual(r["erro"], "loja_em_breve")
        self.assertEqual(self.f.criados, [])

    def test_loja_em_breve_numero_de_teste_cria(self):
        # ordem do Danilo 30/10 20:23: em modo teste, a allowlist e atendida como se a loja estivesse aberta
        self.assertEqual(self.t["mode"], "teste")
        self.encher([("Clássico", 1, [])])
        self.orcar()
        self.f.t["restaurants"][0]["coming_soon"] = True
        janela_demo(self.f, ativa=False)
        self.assertTrue(self.confirmar()["ok"])
        self.assertEqual(len(self.f.criados), 1)

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
        # robo ligado para toda a gente: um cliente qualquer ouve "abre em breve"
        self.t["mode"] = "ligado"
        self.f.t["restaurants"][0]["coming_soon"] = True
        janela_demo(self.f, ativa=False)
        r = A.atender(self.ev(ESTRANHO, "Boa tarde, queria fazer uma encomenda"))
        self.assertTrue(r["tratado"])
        self.assertEqual(r["acao"], "loja-abre-em-breve")
        self.assertIn("abre em breve", r["respostas"][0])
        self.assertEqual(self.guiao.chamadas, 0)
        self.assertEqual(self.f.t["assistant_messages"][-1]["entrega_estado"], "pendente")

    def test_numero_de_teste_e_atendido_com_a_loja_em_breve(self):
        # 30/10 20:08 o Danilo escreveu "Quero vinho" e so ouviu "abre em breve": em modo teste isso ja nao acontece
        self.assertEqual(self.t["mode"], "teste")
        self.f.t["restaurants"][0]["coming_soon"] = True
        janela_demo(self.f, ativa=False)
        self.guiao.passos = ["Olá! Diga-me o que quer."]
        r = A.atender(self.ev(DANILO, "Boa tarde"))
        self.assertEqual(r["acao"], "respondeu")
        self.assertNotIn("abre em breve", " ".join(r["respostas"]))
        self.assertEqual(self.guiao.chamadas, 1)

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


# ============================================================================= 30/10/2026: mensagens 333 a 338
def com_bebidas(f):
    """Vinhos, cervejas, sidras, sobremesas, entradas e agua como os da Boom (nomes e sort_order reais; metidos na base
    fora de ordem de proposito, para provar que a lista sai pela ordem do sort_order)."""
    linhas = [  # (id, nome, preco, categoria, sort_order)
        ("v-incantum-meia", "Incantum Tinto Douro Meia Garrafa 375ml", 6.88, "Vinhos", 60),
        ("v-caiado-t", "Caiado Tinto", 11.20, "Vinhos", 61),
        ("v-mayor-res-t", "Adega Mayor Reserva Tinto", 19.25, "Vinhos", 63),
        ("v-caiado-b", "Caiado Branco", 11.20, "Vinhos", 69),
        ("v-mayor-arinto", "Adega Mayor Arinto Branco", 21.00, "Vinhos", 72),
        ("v-caiado-r", "Caiado Rosé", 11.20, "Vinhos", 75),
        ("v-mayor-tn-r", "Adega Mayor Touriga Nacional Rosé", 21.00, "Vinhos", 76),
        ("c-bandida", "Bandida Pomar Maçã Sidra", 3.03, "Cervejas e sidras", 31),
        ("c-super", "Super Bock 0,33 L", 2.22, "Cervejas e sidras", 42),
        ("c-letra-a", "Cerveja Letra A 33cl", 3.85, "Cervejas e sidras", 46),
        ("s-cheesecake", "Cheesecake de frutos vermelhos", 7.12, "Sobremesas", 24),
        ("e-asas", "Asas de frango com molho BBQ", 9.10, "Entradas", 14),
        ("b-agua", "Água 0,33 L", 1.40, "Bebidas", 44),
    ]
    for pid, nome, preco, cat, ordem in reversed(linhas):
        f.t["products"].append({"id": pid, "name": nome, "price": preco, "category": cat, "description": "", "allergens": [],
                                "is_available": True, "esgotado_ate": None, "sort_order": ordem, "restaurant_id": "boom-burger-guarda"})


def ev_de(numero, texto):
    return {"sessao": SESSAO, "numero": numero, "texto": texto, "msg_id": "m" + str(time.time())}


class TestListasPorCategoria(Base):
    """(a) 'Quero vinho' saiu com 3 vinhos do motor. Agora: lista completa da base, sem motor."""

    def setUp(self):
        super().setUp()
        com_bebidas(self.f)

    def da_base(self, categoria):
        ps = [p for p in self.f.t["products"] if p["category"] == categoria]
        return sorted(ps, key=lambda p: p["sort_order"])

    def test_quero_vinho_lista_completa_agrupada_por_cor(self):
        txt = R.resposta_rapida(self.t, {}, "Quero vinho")
        vinhos = self.da_base("Vinhos")
        for p in vinhos:
            self.assertIn(f"• {p['name']} — {R.euros(p['price'])}", txt)
        self.assertEqual(txt.count("• "), len(vinhos))
        pos = [txt.index(x) for x in ("*Tintos*", "Incantum Tinto Douro Meia", "Caiado Tinto", "Adega Mayor Reserva Tinto",
                                      "*Brancos*", "Caiado Branco", "Adega Mayor Arinto Branco", "*Rosés*", "Caiado Rosé")]
        self.assertEqual(pos, sorted(pos))  # grupos Tintos > Brancos > Roses e, dentro, a ordem do sort_order
        self.assertTrue(txt.endswith("Qual quer e quantos? (só para maiores de 18)"), txt)
        self.assertNotIn("**", txt)
        print("\n--- Quero vinho ---\n" + txt)

    def test_pelo_atender_sem_motor(self):
        r = A.atender(ev_de(DANILO, "Quero vinho"))
        self.assertEqual(r["acao"], "resposta-rapida")
        self.assertEqual(self.guiao.chamadas, 0)
        saida = [m for m in self.f.t["assistant_messages"] if m["direcao"] == "saida"][-1]["texto"]
        self.assertEqual(saida.count("• "), 7)

    def test_cervejas_sobremesas_bebidas_plural_sem_acento(self):
        cerv = R.resposta_rapida(self.t, {}, "que cervejas têm")
        for p in self.da_base("Cervejas e sidras"):
            self.assertIn(f"• {p['name']} — {R.euros(p['price'])}", cerv)
        self.assertIn("(só para maiores de 18)", cerv)
        self.assertNotIn("Caiado", cerv)
        self.assertLess(cerv.index("Bandida"), cerv.index("Super Bock"))
        doce = R.resposta_rapida(self.t, {}, "Têm sobremesas?")
        self.assertIn("• Cheesecake de frutos vermelhos — 7,12 €", doce)
        self.assertNotIn("maiores de 18", doce)
        agua = R.resposta_rapida(self.t, {}, "queria uma agua")
        self.assertIn("• Água 0,33 L — 1,40 €", agua)
        self.assertIn("• Coca-Cola — 2,68 €", agua)  # a agua esta na categoria Bebidas: vai a categoria toda
        self.assertIn("• Asas de frango com molho BBQ — 9,10 €", R.resposta_rapida(self.t, {}, "Quais são as entradas?"))
        self.assertIn("Bandida", R.resposta_rapida(self.t, {}, "Têm sidra?"))
        print("\n--- que cervejas têm ---\n" + cerv)

    def test_vinho_tinto_so_os_tintos(self):
        txt = R.resposta_rapida(self.t, {}, "Queria um vinho tinto")
        self.assertIn("Caiado Tinto", txt)
        self.assertNotIn("Caiado Branco", txt)
        self.assertNotIn("Rosé", txt)

    def test_produto_concreto_ou_outra_coisa_vai_para_o_motor(self):
        for x in ("Quero um Caiado Tinto", "quero uma super bock", "Onde é a entrada?", "Quero um Boom! Clássico e uma bebida",
                  "Posso reservar mesa?", "Boa noite"):
            self.assertIsNone(R.lista_categoria(self.t, x), x)

    def test_prompt_diz_que_o_limite_de_6_nao_vale_para_listas_pedidas(self):
        p = R.prompt_restaurante(self.t, {"numero": DANILO})
        self.assertIn("o limite de 6 não vale para listas pedidas", p)
        self.assertIn("nunca ** nem #", p)


MOTOR_COM_MARKDOWN = ("Temos várias opções de vinho. Prefere tinto, branco ou rosé?\n\nAqui estão algumas das nossas opções:\n"
                      "*   **Caiado** (Tinto, Branco ou Rosé) — 11,20 €\n*   **Adega Mayor Reserva** (Tinto ou Branco) — 19,25 €\n"
                      "  - Incantum — 12,60 €\n## Vinhos da casa\n***Boa escolha!*** Diga-me qual prefere.")


class TestFormato(Base):
    """(b) Mensagem 338: '*   **Caiado**' (markdown que o WhatsApp nao mostra). Limpa-se no ponto de saida (enfileirar)."""

    def test_limpar_formato(self):
        s = A.limpar_formato(MOTOR_COM_MARKDOWN)
        self.assertNotIn("**", s)
        self.assertNotIn("#", s)
        self.assertNotRegex(s, r"(?m)^\s*[*-]\s")
        self.assertIn("• *Caiado* (Tinto, Branco ou Rosé) — 11,20 €", s)
        self.assertIn("• *Adega Mayor Reserva* (Tinto ou Branco) — 19,25 €", s)
        self.assertIn("• Incantum — 12,60 €", s)
        self.assertIn("\nVinhos da casa\n", s)
        self.assertIn("*Boa escolha!* Diga-me qual prefere.", s)

        def so_letras(x):
            return re.sub(r"[*#•\s-]", "", x)
        self.assertEqual(so_letras(s), so_letras(MOTOR_COM_MARKDOWN))  # nada cortado
        print("\n--- texto do motor ---\n" + MOTOR_COM_MARKDOWN + "\n--- sai assim ---\n" + s)

    def test_texto_sem_markdown_fica_igual(self):
        for x in ("Resumo do pedido:\n• 1x Boom! Clássico — 11,55 €\nTotal: 11,55 €\nConfirma a encomenda?",
                  "*Tintos*\n• Caiado Tinto — 11,20 €", "Pedido #ABC123 feito! A Boom! Burger já o recebeu.", "2 - 1 = 1", ""):
            self.assertEqual(A.limpar_formato(x), x)

    def test_enfileirar_grava_o_texto_limpo(self):
        A.enfileirar(self.t, DANILO, MOTOR_COM_MARKDOWN, "resposta", simulado=True)
        m = self.f.t["assistant_messages"][-1]
        self.assertNotIn("**", m["texto"])
        self.assertIn("• *Caiado*", m["texto"])
        self.assertEqual(m["entrega_estado"], "simulado")

    def test_resposta_do_motor_sai_limpa_pelo_atender(self):
        self.guiao.passos = [MOTOR_COM_MARKDOWN]
        A.atender(ev_de(DANILO, "Boa noite, que me aconselha?"))
        saida = [m for m in self.f.t["assistant_messages"] if m["direcao"] == "saida"][-1]["texto"]
        self.assertNotIn("**", saida)
        self.assertNotRegex(saida, r"(?m)^\s*[*-]\s")


class TestReservas(Base):
    """(c) Mensagens 333-335: reserva foi para passar_ao_dono ('isso e com a loja'). Agora: pedir_reserva."""

    def setUp(self):
        super().setUp()
        self.dia = A.agora().date() + dt.timedelta(days=3)

    def diz(self, texto):
        _DORMIR(0.02)
        return A.atender(ev_de(DANILO, texto))

    def tarefas_reserva(self):
        return [k for k in self.f.t["assistant_tasks"] if (k.get("payload") or {}).get("reserva")]

    def a_loja(self):
        return [m for m in self.f.t["assistant_messages"] if m["direcao"] == "saida" and m["numero"] == DANILO
                and str(m.get("motivo") or "").startswith(("pergunta_dono:", "dono_ack", "reserva_dono", "pergunta_dono_lembrete"))]

    def pedir_tudo(self, pessoas=2, hora="20h", nome="Rui"):
        r = self.diz(f"Queria reservar mesa para {pessoas} pessoas no dia {self.dia:%d/%m} às {hora} em nome de {nome}")
        self.assertEqual(r["acao"], "reserva-em-codigo")
        self.assertIn(R.MSG_RESERVA_PEDIDA, r["respostas"][0])
        return self.tarefas_reserva()[-1]

    def test_conversa_inteira_uma_pergunta_de_cada_vez_e_confirmacao_da_loja(self):
        passos = [("Posso reservar mesa por aqui?", "Claro! Para quantas pessoas é a mesa?"),
                  ("Somos 4", "Para que dia?"),
                  (f"{self.dia:%d/%m}", "A que horas?"),
                  ("às 20h", "Em que nome fica a reserva?")]
        for cliente, robo in passos:
            r = self.diz(cliente)
            self.assertEqual((r["acao"], r["respostas"][0]), ("reserva-em-codigo", robo))
            print(f"cliente> {cliente}\nrobo   < {r['respostas'][0]}")
        r = self.diz("Ana")
        print(f"cliente> Ana\nrobo   < {r['respostas'][0]}")
        quando = R.dia_cliente(self.dia)
        self.assertEqual(r["respostas"][0], f"Pedido de reserva: 4 pessoas, {quando} às 20:00, em nome de Ana. {R.MSG_RESERVA_PEDIDA}")
        self.assertEqual(self.guiao.chamadas, 0)  # nada disto precisou de motor
        self.assertEqual([m for m in self.f.t["assistant_messages"] if m.get("motivo") == "passar_dono"], [])
        tk = self.tarefas_reserva()[-1]
        self.assertEqual(tk["tipo"], "pergunta_dono")
        self.assertRegex(tk["codigo"], r"^R\d{3}$")
        self.assertEqual(tk["payload"]["reserva"], {"pessoas": 4, "dia": self.dia.isoformat(), "hora": "20:00", "nome": "Ana",
                                                    "estado": "pedida"})
        prazo = (A.hora_local(tk["prazo"]) - A.agora()).total_seconds() / 60
        self.assertTrue(14 < prazo <= 15, prazo)
        loja = [m for m in self.a_loja() if m["motivo"] == f"pergunta_dono:{tk['id']}"]
        self.assertEqual(len(loja), 1)
        self.assertIn(tk["codigo"], loja[0]["texto"])
        self.assertIn("4 pessoas", loja[0]["texto"])
        print("loja   < " + loja[0]["texto"].replace("\n", "\n         "))
        # a loja responde "R123 sim" (em teste o dono_destino e o numero de teste)
        r = self.diz(f"{tk['codigo']} sim")
        print(f"loja  > {tk['codigo']} sim\nrobo   < {r['respostas'][0]}")
        self.assertEqual(r["acao"], "reserva-confirmada")
        self.assertEqual(r["respostas"][0], f"A sua mesa para 4 pessoas, {quando} às 20:00, está confirmada. Em nome de Ana.")
        self.assertEqual(self.tarefas_reserva()[-1]["estado"], "cumprida")
        self.assertEqual(self.t["knowledge"]["perguntas_aprendidas"], [])
        self.assertEqual(self.f.t["assistant_tenants"][0]["knowledge"]["perguntas_aprendidas"], [])
        self.assertIsNone(self.f.t["assistant_contacts"][0]["a_espera_de"])

    def test_loja_propoe_outra_hora_e_o_cliente_aceita(self):
        tk = self.pedir_tudo()
        r = self.diz(f"{tk['codigo']} só às 21:30")
        self.assertEqual(r["acao"], "reserva-outra-hora-proposta")
        self.assertIn("não tem mesa às 20:00, mas tem às 21:30", r["respostas"][0])
        self.assertTrue(r["respostas"][0].endswith("Pode ser às 21:30?"))
        r = self.diz("Sim, pode ser")
        self.assertEqual(r["respostas"][0], f"A sua mesa para 2 pessoas, {R.dia_cliente(self.dia)} às 21:30, está confirmada. Em nome de Rui.")
        self.assertIn(f"{tk['codigo']}: o cliente aceitou as 21:30", self.a_loja()[-1]["texto"])
        self.assertIsNone(self.f.t["assistant_contacts"][0]["a_espera_de"])

    def test_loja_diz_que_nao_ha_mesa_e_o_cliente_tenta_outra_hora(self):
        tk = self.pedir_tudo()
        r = self.diz(f"{tk['codigo']} não, estamos cheios")
        self.assertEqual(r["acao"], "reserva-sem-mesa")
        self.assertIn("não tem mesa para", r["respostas"][0])
        self.assertIn("«não, estamos cheios»", r["respostas"][0])
        r = self.diz("Então às 22h")
        novo = self.tarefas_reserva()[-1]
        self.assertNotEqual(novo["id"], tk["id"])
        self.assertEqual(novo["payload"]["reserva"]["hora"], "22:00")
        self.assertEqual(novo["payload"]["reserva"]["pessoas"], 2)
        self.assertIn(R.MSG_RESERVA_PEDIDA, r["respostas"][0])

    def test_reservas_abertas_na_app_da_o_link(self):
        self.f.t["restaurants"][0].update(reservations_enabled=True, coming_soon=False)
        r = self.diz("Posso reservar mesa por aqui?")
        self.assertIn("«Reservar mesa»", r["respostas"][0])
        self.assertIn("https://www.boraguarda.com/baixar?de=whatsapp-boom", r["respostas"][0])
        self.assertEqual(self.tarefas_reserva(), [])

    def test_app_em_breve_fora_da_janela_ainda_trata_da_reserva(self):
        self.f.t["restaurants"][0]["coming_soon"] = True
        janela_demo(self.f, ativa=False)
        r = self.diz("Posso reservar mesa por aqui?")
        self.assertEqual(r["acao"], "reserva-em-codigo")
        r = self.diz("4")
        self.assertEqual(r["respostas"][0], "Para que dia?")
        # a meio da reserva, outra conversa nao leva o "abre em breve" (vai ao motor, que tem a ferramenta da reserva)
        self.assertNotEqual(self.diz("Boa tarde, queria fazer uma encomenda")["acao"], "loja-abre-em-breve")

    def test_motor_que_chama_passar_ao_dono_e_desviado_para_a_reserva(self):
        self.guiao.passos = [[("passar_ao_dono", {"motivo": "pedido de reserva de mesa"})], "Isso é com a loja, já passei o seu pedido."]
        r = self.diz("Dá para marcar um jantar de grupo?")
        self.assertEqual(r["respostas"][0], "Claro! Para quantas pessoas é a mesa?")
        self.assertEqual([m for m in self.f.t["assistant_messages"] if m.get("motivo") == "passar_dono"], [])
        self.assertEqual(R.reserva_de(self.f.t["assistant_contacts"][0])["estado"], "a_recolher")

    def test_motor_que_chama_perguntar_ao_dono_com_a_reserva_toda(self):
        pergunta = f"Reserva de mesa: 4 pessoas, {A.DIAS[self.dia.weekday()]} {self.dia:%d/%m} às 20:00, em nome de Ana"
        r = self.turno("então é isso").executar("perguntar_ao_dono", {"pergunta": pergunta})
        self.assertRegex(r["codigo"], r"^R\d{3}$")
        self.assertEqual(self.tarefas_reserva()[-1]["payload"]["reserva"],
                         {"pessoas": 4, "dia": self.dia.isoformat(), "hora": "20:00", "nome": "Ana", "estado": "pedida"})
        self.assertFalse(any((k.get("codigo") or "").startswith("P") for k in self.f.t["assistant_tasks"]))

    def test_lembrete_a_loja_aos_15_min(self):
        import rotinas
        tk = self.pedir_tudo()
        rotinas.vigia_perguntas(self.t, A.agora() + dt.timedelta(minutes=10))
        self.assertFalse(any(str(m.get("motivo")).startswith("pergunta_dono_lembrete") for m in self.f.t["assistant_messages"]))
        rotinas.vigia_perguntas(self.t, A.agora() + dt.timedelta(minutes=16))
        lembrete = [m for m in self.f.t["assistant_messages"] if m.get("motivo") == f"pergunta_dono_lembrete:{tk['id']}"]
        self.assertEqual(len(lembrete), 1)
        self.assertIn(f"reserva {tk['codigo']}", lembrete[0]["texto"])

    def test_desistir_a_meio(self):
        self.diz("Posso reservar uma mesa?")
        r = self.diz("Afinal esquece")
        self.assertIn("fica sem reserva", r["respostas"][0])
        self.assertIsNone(self.f.t["assistant_contacts"][0]["a_espera_de"])

    def test_pergunta_normal_continua_a_aprender_e_reserva_nao(self):
        r = self.turno("têm estacionamento?").executar("perguntar_ao_dono", {"pergunta": "Têm estacionamento?"})
        self.assertRegex(r["codigo"], r"^P\d{3}$")
        self.diz(f"{r['codigo']} Sim, à porta")
        self.assertEqual(len(self.f.t["assistant_tenants"][0]["knowledge"]["perguntas_aprendidas"]), 1)
        tk = self.pedir_tudo()
        self.diz(f"{tk['codigo']} ok")
        self.assertEqual(len(self.f.t["assistant_tenants"][0]["knowledge"]["perguntas_aprendidas"]), 1)

    def test_ler_o_que_o_cliente_escreve(self):
        sexta = dt.date(2026, 10, 30)
        for txt, d in (("sábado", "2026-10-31"), ("amanhã", "2026-10-31"), ("dia 2", "2026-11-02"), ("01/11", "2026-11-01"),
                       ("2026-11-05", "2026-11-05"), ("domingo", "2026-11-01"), ("sexta", "2026-10-30"), ("próxima sexta", "2026-11-06")):
            self.assertEqual(R.ler_dia(txt, sexta).isoformat(), d, txt)
        for txt, h in (("20h", "20:00"), ("às 8 da noite", "20:00"), ("20:30", "20:30"), ("20h30", "20:30"), ("às 9", "21:00"),
                       ("às 10 da manhã", "10:00"), ("meio-dia", "12:00")):
            self.assertEqual(R.ler_hora(txt), h, txt)
        self.assertEqual(R.ler_hora("20", solto=True), "20:00")
        self.assertIsNone(R.ler_hora("4 pessoas", solto=True))
        for txt, n in (("Somos 4", 4), ("para quatro pessoas", 4), ("2 adultos e 2 crianças", 4)):
            self.assertEqual(R.ler_pessoas(txt), n, txt)
        self.assertIsNone(R.ler_pessoas("Queria reservar para uma mesa"))
        self.assertEqual(R.ler_pessoas("4", solto=True), 4)
        self.assertIsNone(R.ler_pessoas("sábado às 20h", solto=True))
        self.assertEqual(R.ler_nome("Ana", solto=True), "Ana")
        self.assertEqual(R.ler_nome("em nome de Ana Silva"), "Ana Silva")
        self.assertEqual(R.ler_nome("o meu nome é rui"), "Rui")
        for txt in ("sábado", "sim", "Somos 4", "Pode ser", "ok obrigado"):
            self.assertIsNone(R.ler_nome(txt, solto=True), txt)


class TestCarrinhoVelho(Base):
    """(d) Mensagem 335: as 22:35 o robo retomou o carrinho das 19:31 (pediu a morada para o Kamikaze)."""

    def carrinho_antigo(self, horas=3):
        self.turno("quero um kamikaze").executar("adicionar_ao_pedido", {"produto": "Kamikaze"})
        k = self.f.t["assistant_tasks"][-1]
        antes = (A.agora() - dt.timedelta(hours=horas)).isoformat()
        k["created_at"] = antes
        k["payload"]["mexido_em"] = antes
        A.contacto(self.t, DANILO)
        self.f.t["assistant_contacts"][0]["historico"] = [{"r": "user", "t": "Só isso", "ts": antes},
                                                          {"r": "assistant", "t": "Qual é a morada de entrega?", "ts": antes}]
        return k

    def diz(self, texto):
        _DORMIR(0.02)
        return A.atender(ev_de(DANILO, texto))

    def test_reserva_depois_de_3_h_nao_retoma_o_carrinho(self):
        k = self.carrinho_antigo()
        r = self.diz("Posso reserva mesa por aqui?")
        self.assertEqual(r["respostas"][0], "Claro! Para quantas pessoas é a mesa?")
        self.assertTrue(k["payload"].get("suspenso"))
        self.assertIsNone(R.carrinho(self.t, DANILO))

    def test_motor_nao_ve_o_carrinho_e_o_cliente_e_perguntado(self):
        self.carrinho_antigo()
        self.guiao.passos = ["Boa noite! Em que posso ajudar?"]
        r = self.diz("Boa noite")
        self.assertIn("Pedido em curso: nenhum.", self.guiao.sistema)
        self.assertEqual(r["respostas"][0], "Boa noite! Em que posso ajudar?\n\nAinda quer o Boom! Kamikaze de há pouco?")
        r = self.diz("Sim")
        self.assertEqual(r["acao"], "carrinho-antigo")
        self.assertEqual(r["respostas"][0], "Está bem, o Boom! Kamikaze continua no seu pedido. Mais alguma coisa?")
        k = R.carrinho(self.t, DANILO)
        self.assertEqual([l["nome"] for l in k["payload"]["itens"]], ["Boom! Kamikaze"])

    def test_cliente_ja_nao_quer(self):
        k = self.carrinho_antigo()
        self.guiao.passos = ["Boa noite!"]
        self.diz("Boa noite")
        r = self.diz("Não, obrigado")
        self.assertIn("fica sem efeito", r["respostas"][0])
        self.assertEqual(k["estado"], "cancelada")
        self.assertIsNone(R.carrinho(self.t, DANILO))

    def test_pergunta_espera_pelo_fim_da_reserva_e_vai_na_resposta_seguinte(self):
        self.carrinho_antigo()
        r = self.diz("Posso reservar mesa?")
        self.assertNotIn("de há pouco", r["respostas"][0])
        com_bebidas(self.f)
        r = self.diz("Quero vinho")  # a meio da reserva, mas nao responde a pergunta: lista dos vinhos + a pergunta do carrinho
        self.assertEqual(r["acao"].split(" ")[0], "resposta-rapida")
        self.assertIn("• Caiado Tinto — 11,20 €", r["respostas"][0])
        self.assertTrue(r["respostas"][0].endswith("Ainda quer o Boom! Kamikaze de há pouco?"))

    def test_carrinho_recente_continua_como_estava(self):
        k = self.carrinho_antigo(horas=1)
        self.guiao.passos = ["Boa noite!"]
        r = self.diz("Boa noite")
        self.assertNotIn("de há pouco", r["respostas"][0])
        self.assertIn("Pedido em curso: 1. 1x Boom! Kamikaze", self.guiao.sistema)
        self.assertFalse(k["payload"].get("suspenso"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
