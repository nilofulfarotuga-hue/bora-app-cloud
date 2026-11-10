# -*- coding: utf-8 -*-
"""Testes sem rede do ia_visao.py (e do juiz de visão por cima dele).

    python -m unittest .claude/juiz/test_ia_visao.py -v      (ou)  python .claude/juiz/test_ia_visao.py

O urlopen é trocado por um falso que regista os pedidos. Valores de brincar feitos em tempo de execução.
"""
from __future__ import annotations

import io
import json
import os
import sys
import tempfile
import unittest
import urllib.error

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import ia_visao  # noqa: E402
import vision_judge  # noqa: E402

PNG = bytes.fromhex("89504e470d0a1a0a0000000d4948445200000001000000010806000000")  # cabeçalho chega
URL_CLAUDE = ia_visao.URL_CLAUDE


class _Resp:
    def __init__(self, status: int, corpo: dict):
        self.status = status
        self._b = json.dumps(corpo).encode()

    def read(self):
        return self._b

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


def _falso(respostas: dict):
    """respostas: {chave: (status, corpo) | Exception}; chave = 'claude' | 'perfil:<p>'."""
    pedidos = []

    def urlopen(req, timeout=None):
        corpo = json.loads(req.data.decode())
        chave = "claude" if req.full_url == URL_CLAUDE else corpo.get("model")
        pedidos.append({"url": req.full_url, "corpo": corpo, "cab": {k.lower(): v for k, v in req.header_items()}})
        r = respostas.get(chave, (500, {"error": "falso"}))
        if isinstance(r, Exception):
            raise r
        status, j = r
        if status >= 400:
            raise urllib.error.HTTPError(req.full_url, status, "erro", {}, io.BytesIO(json.dumps(j).encode()))
        return _Resp(status, j)

    return urlopen, pedidos


def _claude_ok(texto):
    return (200, {"content": [{"type": "text", "text": texto}], "stop_reason": "end_turn",
                  "usage": {"input_tokens": 1200, "output_tokens": 30}})


def _openai_ok(texto, modelo="gemini:gemini-3.1-flash-lite"):
    return (200, {"model": modelo, "choices": [{"message": {"role": "assistant", "content": texto}}]})


class TesteIaVisao(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.senha = os.path.join(self.tmp.name, "senha-de-brincar")
        with open(self.senha, "w", encoding="utf-8") as f:
            f.write("-".join(["valor", "de", "brincar"]))
        self.chave = "-".join(["valor", "claude", "brincar"])

    def tearDown(self):
        self.tmp.cleanup()

    def env(self, claude=True, porteiro=True):
        e = {"PORTEIRO_URL": "http://porteiro.falso:1"}
        if claude:
            e[ia_visao.NOME_VAR_CLAUDE] = self.chave
        e["PORTEIRO_SENHA_FICHEIRO"] = self.senha if porteiro else os.path.join(self.tmp.name, "nao-existe")
        return e

    def test_claude_direto_responde_com_a_imagem(self):
        urlopen, pedidos = _falso({"claude": _claude_ok('{"severity":"verde","finding":"ok"}')})
        linhas = []
        r = ia_visao.pedir("S", "olha", [("image/png", PNG)], urlopen=urlopen, env=self.env(), livro=linhas.append)
        self.assertTrue(r["ok"])
        self.assertEqual(r["motor"], "claude-direto")
        corpo = pedidos[0]["corpo"]
        self.assertEqual(corpo["model"], "claude-haiku-5-5")
        self.assertEqual(corpo["thinking"], {"type": "disabled"})
        self.assertNotIn("temperature", corpo)
        bloco = corpo["messages"][0]["content"][0]
        self.assertEqual(bloco["type"], "image")
        self.assertEqual(bloco["source"]["media_type"], "image/png")
        self.assertEqual(len(pedidos), 1)
        self.assertEqual(linhas[0]["robo"], "juiz-visao")
        self.assertGreater(linhas[0]["custo_usd"], 0)
        self.assertTrue(linhas[0]["ok"])

    def test_claude_falha_402_429_500_cai_na_rotacao_gratis(self):
        for status in (402, 429, 500):
            with self.subTest(status=status):
                urlopen, pedidos = _falso({
                    "claude": (status, {"type": "error"}),
                    "perfil:claude-so-volume": (503, {"error": "sem credito"}),
                    "perfil:visao": _openai_ok('{"severity":"amarelo","finding":"x"}'),
                })
                r = ia_visao.pedir("S", "olha", [("image/png", PNG)], urlopen=urlopen, env=self.env())
                self.assertTrue(r["ok"], r)
                self.assertEqual(r["motor"], "porteiro-gratis")
                self.assertEqual(r["tentativas"][0]["http"], status)
                ultimo = pedidos[-1]
                self.assertEqual(ultimo["cab"]["x-motor-origem"], "juiz-visao")
                partes = ultimo["corpo"]["messages"][1]["content"]
                self.assertTrue(partes[1]["image_url"]["url"].startswith("data:image/png;base64,"))

    def test_sem_chave_claude_vai_pelo_porteiro_so_claude(self):
        urlopen, pedidos = _falso({"perfil:claude-so-volume": _openai_ok('{"severity":"verde"}', "claude:claude-haiku-5-5")})
        r = ia_visao.pedir("S", "olha", [("image/png", PNG)], urlopen=urlopen, env=self.env(claude=False))
        self.assertTrue(r["ok"])
        self.assertEqual(r["motor"], "porteiro-claude")
        self.assertEqual([p["url"] for p in pedidos], ["http://porteiro.falso:1/v1/chat/completions"])

    def test_tudo_a_falhar_da_erro_claro(self):
        urlopen, _ = _falso({"claude": (500, {}), "perfil:claude-so-volume": (503, {}), "perfil:visao": (503, {})})
        r = ia_visao.pedir("S", "olha", [("image/png", PNG)], urlopen=urlopen, env=self.env())
        self.assertFalse(r["ok"])
        self.assertTrue(r["erro"].startswith("nenhum motor respondeu"), r["erro"])
        for m in ("claude-direto", "porteiro-claude", "porteiro-gratis", "http 500", "http 503"):
            self.assertIn(m, r["erro"])

    def test_porteiro_em_baixo_nao_tenta_o_segundo_perfil(self):
        urlopen, pedidos = _falso({"claude": (529, {}), "perfil:claude-so-volume": urllib.error.URLError("sem rota")})
        r = ia_visao.pedir("S", "olha", [("image/png", PNG)], urlopen=urlopen, env=self.env())
        self.assertFalse(r["ok"])
        self.assertIn("o porteiro não responde", r["erro"])
        self.assertEqual(len(pedidos), 2)

    def test_sem_nada_configurado(self):
        urlopen, pedidos = _falso({})
        r = ia_visao.pedir("S", "olha", [("image/png", PNG)], urlopen=urlopen, env=self.env(claude=False, porteiro=False))
        self.assertFalse(r["ok"])
        self.assertIn(ia_visao.NOME_VAR_CLAUDE, r["erro"])
        self.assertIn("senha do porteiro", r["erro"])
        self.assertEqual(pedidos, [])
        self.assertEqual(ia_visao.motores_configurados(self.env(claude=False, porteiro=False)), [])

    def test_nunca_le_a_anthropic_api_key(self):
        e = self.env(claude=False, porteiro=False)
        e["ANTHROPIC_API_KEY"] = "-".join(["nao", "usar"])
        self.assertEqual(ia_visao.motores_configurados(e), [])


class TesteJuizDeVisao(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.png = os.path.join(self.tmp.name, "ecra.png")
        with open(self.png, "wb") as f:
            f.write(PNG)
        self.original = ia_visao.pedir

    def tearDown(self):
        ia_visao.pedir = self.original
        self.tmp.cleanup()

    def test_veredito_e_motor(self):
        ia_visao.pedir = lambda *a, **k: {"ok": True, "texto": '```json\n{"severity":"vermelho","finding":"botão cortado"}\n```',
                                          "motor": "porteiro-claude", "modelo": "claude:claude-haiku-5-5", "tentativas": []}
        v = vision_judge.julga_foto(self.png)
        self.assertEqual(v["severity"], "vermelho")
        self.assertEqual(v["motor"], "porteiro-claude:claude:claude-haiku-5-5")

    def test_sem_motor_fica_amarelo_com_o_erro(self):
        ia_visao.pedir = lambda *a, **k: {"ok": False, "erro": "nenhum motor respondeu — claude-direto: http 402", "tentativas": []}
        v = vision_judge.julga_foto(self.png)
        self.assertEqual(v["severity"], "amarelo")
        self.assertIn("juiz sem olhos", v["finding"])
        self.assertIn("http 402", v["finding"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
