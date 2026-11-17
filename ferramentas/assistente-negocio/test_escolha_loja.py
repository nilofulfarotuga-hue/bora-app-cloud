"""Testes da escolha de loja quando o mesmo numero esta em teste em duas lojas (missao a3-guarda-16-11, parte 2).
Sem rede: tenants e contactos falsos em memoria.

Correr (PC ou VPS):   python -m unittest -v test_escolha_loja     (dentro de ferramentas/assistente-negocio)
"""
import datetime as dt
import os
import sys
import unittest

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
os.environ.setdefault("SUPABASE_URL", "http://fake.invalid")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "fake")

import assistente as A  # noqa: E402

NUM = "351900000009"  # numero inventado
BOOM = {"id": "t-boom", "slug": "boom-burger", "nome": "Boom! Burger", "mode": "teste", "allowlist": [NUM],
        "created_at": "2026-10-29T14:30:20+00:00"}
A3 = {"id": "t-a3", "slug": "a3-guarda", "nome": "A3 Guarda", "mode": "teste", "allowlist": [NUM],
      "created_at": "2026-11-17T08:00:00+00:00"}
OUTRO = {"id": "t-x", "slug": "x", "nome": "Barbearia X", "mode": "teste", "allowlist": ["351900000001"],
         "created_at": "2026-10-01T00:00:00+00:00"}


class EscolhaDeLoja(unittest.TestCase):
    def setUp(self):
        self.tenants = [A3, BOOM, OUTRO]  # de proposito fora de ordem
        self.contactos = []
        self._orig = (A.tenants_da_sessao, A.db.ler)
        A.tenants_da_sessao = lambda sessao: list(self.tenants)

        def ler(tabela, filtro):
            assert tabela == "assistant_contacts"
            ids = filtro.split("tenant_id=in.(")[1].split(")")[0].split(",")
            linhas = [c for c in self.contactos if c["tenant_id"] in ids and c["numero"] == NUM]
            return sorted(linhas, key=lambda c: c["ultima_msg_em"], reverse=True)[:1]
        A.db.ler = ler

    def tearDown(self):
        A.tenants_da_sessao, A.db.ler = self._orig

    def _msg(self, tenant, horas_atras):
        self.contactos.append({"tenant_id": tenant["id"], "numero": NUM,
                               "ultima_msg_em": (A.agora() - dt.timedelta(hours=horas_atras)).isoformat()})

    def test_um_so_candidato_igual_a_antes(self):
        t, porque = A.tenant_para("s", "351900000001", "olá")
        self.assertEqual(t["slug"], "x")
        self.assertEqual(porque, "allowlist")

    def test_fora_da_lista(self):
        self.assertEqual(A.tenant_para("s", "351911111111", "olá"), (None, "fora"))

    def test_sem_escolha_fica_a_mais_antiga_boom(self):
        t, _ = A.tenant_para("s", NUM, "quero um hambúrguer")
        self.assertEqual(t["slug"], "boom-burger")

    def test_ola_a3_escolhe_a3(self):
        for txt in ("Olá A3", "olá a3!", "Boa tarde, A3", "Ola A3 tem agendas?"):
            t, porque = A.tenant_para("s", NUM, txt)
            self.assertEqual(t["slug"], "a3-guarda", txt)
            self.assertTrue(porque.endswith(":escolhida"))

    def test_ola_boom_escolhe_boom(self):
        self._msg(A3, 1)
        t, _ = A.tenant_para("s", NUM, "Olá Boom")
        self.assertEqual(t["slug"], "boom-burger")

    def test_a3_fica_enquanto_ha_conversa(self):
        self._msg(BOOM, 5)
        self._msg(A3, 2)
        t, porque = A.tenant_para("s", NUM, "e canetas?")
        self.assertEqual(t["slug"], "a3-guarda")
        self.assertTrue(porque.endswith(":recente"))
        t, _ = A.tenant_para("s", NUM, "")  # audio: sem texto, segue a conversa
        self.assertEqual(t["slug"], "a3-guarda")

    def test_24h_sem_mensagens_volta_a_boom(self):
        self._msg(A3, 25)
        t, _ = A.tenant_para("s", NUM, "olá")
        self.assertEqual(t["slug"], "boom-burger")

    def test_ola_sem_nome_nao_escolhe(self):
        self.assertFalse(A.abre_loja(A3, "olá"))
        self.assertFalse(A.abre_loja(A3, "a3 tem agendas"))  # sem saudação: não muda de loja
        self.assertFalse(A.abre_loja(BOOM, "Olá Boomerang"))

    def test_blocklist_so_vale_para_a_sua_loja(self):
        self.tenants = [dict(BOOM, blocklist=[NUM]), A3]
        t, porque = A.tenant_para("s", NUM, "quero canetas")
        self.assertEqual(t["slug"], "a3-guarda")
        self.assertEqual(porque, "allowlist")

    def test_blocklist_em_todas_cala(self):
        self.tenants = [dict(BOOM, blocklist=[NUM]), dict(A3, blocklist=[NUM])]
        t, porque = A.tenant_para("s", NUM, "Olá A3")
        self.assertEqual(porque, "blocklist")

    def test_texto_mudar_de_loja(self):
        cands, _ = A.candidatos("s", NUM)
        txt = A.texto_mudar_de_loja(cands)
        self.assertIn("Boom! Burger — escreva: Olá Boom", txt)
        self.assertIn("A3 Guarda — escreva: Olá A3", txt)


if __name__ == "__main__":
    unittest.main()
