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


if __name__ == "__main__":
    unittest.main()
