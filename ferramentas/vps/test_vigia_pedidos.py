"""Testes da vigia dos pedidos presos (missao fechar-app-15-11, 14/11/2026). Sem rede.

Caso real: a vigia punha a data no endereco como '2026-11-13T23:05:06.615216+00:00'; o '+' le-se como
espaco, a API respondia 400 (142 vezes em 24 h, de 10 em 10 minutos) e a vigia ficava calada, como se
nao houvesse pedidos presos.

Correr:   python -m unittest -v test_vigia_pedidos     (dentro de ferramentas/vps)
"""
import datetime as dt
import os
import re
import sys
import unittest
import urllib.parse

AQUI = os.path.dirname(os.path.abspath(__file__))
if AQUI not in sys.path:
    sys.path.insert(0, AQUI)
import vigia_pedidos  # noqa: E402


class InstanteParaUrl(unittest.TestCase):
    def test_formato_sem_caracteres_que_o_endereco_estraga(self):
        t = dt.datetime(2026, 11, 13, 23, 5, 6, 615216, tzinfo=dt.timezone.utc)
        s = vigia_pedidos.instante_para_url(t)
        self.assertEqual(s, "2026-11-13T23:05:06Z")
        self.assertNotIn("+", s)
        self.assertNotIn(" ", s)
        # O que chega ao servidor depois de o endereco ser lido e exatamente o que se escreveu.
        self.assertEqual(urllib.parse.parse_qs("created_at=lt." + s)["created_at"], ["lt." + s])

    def test_o_formato_antigo_chegava_estragado(self):
        antigo = dt.datetime(2026, 11, 13, 23, 5, 6, 615216, tzinfo=dt.timezone.utc).isoformat()
        chegou = urllib.parse.parse_qs("created_at=lt." + antigo)["created_at"][0]
        self.assertIn(" ", chegou)  # o '+' virou espaco: a API recusava com 400
        self.assertNotEqual(chegou, "lt." + antigo)

    def test_outro_fuso_vai_em_utc(self):
        lisboa_verao = dt.timezone(dt.timedelta(hours=1))
        t = dt.datetime(2026, 7, 1, 13, 0, 0, tzinfo=lisboa_verao)
        self.assertEqual(vigia_pedidos.instante_para_url(t), "2026-07-01T12:00:00Z")

    def test_pela_fonte_as_duas_consultas_usam_o_formato_novo_e_a_vigia_cega_avisa(self):
        with open(os.path.join(AQUI, "vigia_pedidos.py"), encoding="utf-8") as fh:
            fonte = fh.read()
        corpo = fonte.split("def main():", 1)[1]
        self.assertEqual(len(re.findall(r"instante_para_url\(agora - dt\.timedelta", corpo)), 2)
        self.assertNotIn(".isoformat()\n        st2", corpo)
        self.assertNotRegex(corpo, r"timedelta\([^)]*\)\)\.isoformat\(\)")
        self.assertIn("vigia cega", corpo)


class PedidosAgendadosEChave(unittest.TestCase):
    """Revisao de 15/11/2026: agora que a vigia voltou a ver, nao pode gritar de 10 em 10 minutos nem
    chamar preso a um pedido agendado que esta a espera da hora."""

    def test_filtro_deixa_de_fora_o_agendado_que_ainda_espera(self):
        f = vigia_pedidos.filtro_pedidos_presos("2026-11-15T19:35:00Z")
        lido = urllib.parse.parse_qs(f)
        self.assertEqual(lido["or"], ["(scheduled_for.is.null,scheduled_for.lt.2026-11-15T19:35:00Z)"])
        self.assertEqual(lido["created_at"], ["lt.2026-11-15T19:35:00Z"])
        self.assertEqual(lido["status"], ["in.(created,preparing,callingDriver)"])
        self.assertEqual(lido["is_test_order"], ["eq.false"])

    def test_o_relogio_do_agendado_comeca_na_hora_marcada(self):
        agora = dt.datetime(2026, 11, 15, 20, 30, tzinfo=dt.timezone.utc)
        agendado = {"id": "abc", "status": "preparing", "created_at": "2026-11-15T18:12:00+00:00",
                    "scheduled_for": "2026-11-15T20:00:00+00:00"}
        normal = {"id": "def", "status": "preparing", "created_at": "2026-11-15T19:50:00+00:00",
                  "scheduled_for": None}
        self.assertEqual(int((agora - vigia_pedidos.desde_quando_conta(agendado)).total_seconds() // 60), 30)
        self.assertEqual(int((agora - vigia_pedidos.desde_quando_conta(normal)).total_seconds() // 60), 40)

    def test_a_chave_nao_muda_com_os_minutos_mas_muda_com_o_estado(self):
        p = {"id": "0f3a9c1e-1111-2222-3333-444455556666", "status": "preparing",
             "created_at": "2026-11-15T19:00:00+00:00", "scheduled_for": None}
        self.assertEqual(vigia_pedidos.chave_do_pedido_preso(p), vigia_pedidos.chave_do_pedido_preso(dict(p)))
        self.assertNotIn("min", vigia_pedidos.chave_do_pedido_preso(p))
        outro_estado = dict(p, status="callingDriver")
        self.assertNotEqual(vigia_pedidos.chave_do_pedido_preso(p),
                            vigia_pedidos.chave_do_pedido_preso(outro_estado))

    def test_pela_fonte_o_mudou_olha_para_as_chaves_e_nao_para_o_texto(self):
        with open(os.path.join(AQUI, "vigia_pedidos.py"), encoding="utf-8") as fh:
            corpo = fh.read().split("def main():", 1)[1]
        self.assertIn('"|".join(sorted(chaves))', corpo)
        self.assertNotIn('"|".join(sorted(problemas))', corpo)
        self.assertIn("chave_do_pedido_preso(p)", corpo)
        self.assertIn("filtro_pedidos_presos(limite)", corpo)


if __name__ == "__main__":
    unittest.main()
