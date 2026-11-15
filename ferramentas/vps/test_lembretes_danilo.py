"""Testes dos lembretes do dono (missao fechar-app-15-11, revisao, nota 16; 15/11/2026). Sem rede.

Ordem do dono de 12/11: a trava do anonimato vale so para mensagens a clientes; NUNCA para alertas
ao numero do proprio dono. Esta rotina so escreve para LEMBRETES_DESTINO, que e o numero dele, mas
ate 15/11 deixava de fora os itens que tivessem o nome dele (por exemplo um cliente com o mesmo
nome) e recusava enfileirar um texto com o nome.

O nome usado aqui e inventado ("Zeferino"): o nome verdadeiro vem do .env da VPS.

Correr:   python -m unittest -v test_lembretes_danilo     (dentro de ferramentas/vps)
"""
import contextlib
import io
import os
import sys
import unittest
from unittest import mock

AQUI = os.path.dirname(os.path.abspath(__file__))
if AQUI not in sys.path:
    sys.path.insert(0, AQUI)

# O modulo vai buscar a configuracao a /opt/data/rotinas/comum.py, que so existe na VPS. Aqui entra
# um modulo de faz-de-conta: so interessam o .env falso e o registo de erros (a rede nunca e usada,
# porque `pedir` e trocado em cada teste).
ERROS = []
comum = mock.MagicMock()
comum.E = {"LEMBRETES_NOMES_DONO": "Zeferino", "LEMBRETES_DESTINO": "+351 900 000 001"}
comum.registar_erro = lambda onde, erro: ERROS.append((onde, str(erro)))
sys.modules["comum"] = comum
import lembretes_danilo as ld  # noqa: E402


class Base(unittest.TestCase):
    def setUp(self):
        ERROS.clear()
        self.pedidos = []
        self._originais = (ld.pedir, ld.gravar_voz, ld._ler_json)
        ld._ler_json = lambda caminho: {}
        ld.gravar_voz = lambda texto: None

        def pedir_falso(metodo, caminho, corpo=None, prefer=None):
            self.pedidos.append((metodo, caminho, corpo))
            if metodo == "POST":
                return [{"id": 1, "estado": "pendente", "created_at": "2026-11-15T09:30:00Z"}]
            return []
        ld.pedir = pedir_falso

    def tearDown(self):
        ld.pedir, ld.gravar_voz, ld._ler_json = self._originais


class Filtrar(Base):
    def test_o_vocativo_do_inicio_sai(self):
        r = ld.filtrar([{"id": 1, "texto": "Zeferino, liga a contabilista", "link": None}])
        self.assertEqual([i["texto"] for i in r], ["Liga a contabilista"])

    def test_item_que_fala_de_um_cliente_com_o_nome_do_dono_segue(self):
        itens = [
            {"id": 1, "texto": "Pagar a renda", "link": None},
            {"id": 2, "texto": "O cliente Zeferino Matos pediu fatura do pedido de ontem", "link": None},
            {"id": 3, "texto": "Ver a loja nova", "link": "https://exemplo.invalid/lojas/zeferino"},
        ]
        r = ld.filtrar(itens)
        self.assertEqual([i["id"] for i in r], [1, 2, 3], "nenhum item fica de fora")
        self.assertEqual(r[1]["texto"], "O cliente Zeferino Matos pediu fatura do pedido de ontem")
        self.assertEqual(ERROS, [], "ja nao e um erro: nada vai para o registo de erros")

    def test_os_perdidos_continuam_de_fora(self):
        ld._ler_json = lambda caminho: {"2": {"porque": "ja nao serve"}}
        r = ld.filtrar([{"id": 1, "texto": "a"}, {"id": 2, "texto": "b"}, {"id": 3, "texto": "c"}])
        self.assertEqual([i["id"] for i in r], [1, 3])

    def test_sem_nomes_no_env_nao_mexe_no_texto(self):
        original = (ld.RE_DONO, ld._NOMES)
        ld.RE_DONO, ld._NOMES = None, []
        try:
            self.assertEqual(ld.sem_nome("  Zeferino, liga  "), "Zeferino, liga")
        finally:
            ld.RE_DONO, ld._NOMES = original


class Enfileirar(Base):
    TEXTO = "Urgente:\n• O cliente Zeferino Matos pediu fatura"

    def test_texto_com_o_nome_e_enfileirado_e_so_para_o_numero_do_dono(self):
        with contextlib.redirect_stdout(io.StringIO()):
            codigo = ld.enfileirar(self.TEXTO, "lembrete-danilo:urgente:20261115T0930", ["2"], seco=False)
        self.assertEqual(codigo, 0, "antes devolvia 3 e nao enfileirava")
        escritas = [p for p in self.pedidos if p[0] == "POST"]
        self.assertEqual(len(escritas), 1)
        metodo, caminho, corpo = escritas[0]
        self.assertEqual(caminho, "whatsapp_saida")
        self.assertEqual(corpo["texto"], self.TEXTO)
        self.assertEqual(corpo["numero"], "351900000001", "so o numero de LEMBRETES_DESTINO")
        self.assertTrue(corpo["motivo"].startswith("lembrete-danilo:"), "a pista reconhece-o pelo motivo")
        self.assertEqual(corpo["estado"], "pendente")
        self.assertEqual(ERROS, [])

    def test_em_ensaio_mostra_e_nao_escreve(self):
        saida = io.StringIO()
        with contextlib.redirect_stdout(saida):
            codigo = ld.enfileirar(self.TEXTO, "lembrete-danilo:urgente:x", ["2"], seco=True)
        self.assertEqual(codigo, 0)
        self.assertIn("Zeferino Matos", saida.getvalue())
        self.assertEqual([p for p in self.pedidos if p[0] == "POST"], [])


class PelaFonte(unittest.TestCase):
    def test_o_unico_destino_e_o_numero_do_env(self):
        with open(os.path.join(AQUI, "lembretes_danilo.py"), encoding="utf-8") as fh:
            fonte = fh.read()
        # A razao de ja nao haver trava: nao ha outro numero para onde esta rotina escreva.
        self.assertEqual(fonte.count('"numero":'), 1)
        self.assertIn('"numero": destino()', fonte)
        self.assertNotIn("nao enfileirei", fonte)
        self.assertNotIn("fica de fora, os outros seguem", fonte)


if __name__ == "__main__":
    unittest.main()
