"""A quota diaria do Gemini pertence ao modelo; a do OpenRouter e partilhada."""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from motor_bora import Roteador  # noqa: E402


class QuotaModeloTest(unittest.TestCase):
    def test_gemini_esgotado_nao_bloqueia_outro_modelo(self):
        roteador = Roteador({}, estado_path=None)
        for _ in range(20):
            roteador.contar("gemini", 10, 1, True, "gemini-3.1-flash-lite")

        self.assertFalse(roteador.quota_ok("gemini", 10, "gemini-3.1-flash-lite")[0])
        self.assertTrue(roteador.quota_ok("gemini", 10, "gemini-3.5-flash-lite")[0])

    def test_openrouter_continua_com_quota_do_fornecedor(self):
        roteador = Roteador({}, estado_path=None)
        for _ in range(200):
            roteador.contar("openrouter", 10, 1, True, "modelo-a:free")

        self.assertFalse(roteador.quota_ok("openrouter", 10, "modelo-b:free")[0])

    def test_repor_assinatura_gemini_no_turno_seguinte(self):
        roteador = Roteador({"GEMINI_API_KEY": "chave-teste"}, estado_path=None)
        roteador.ordem["raciocinio"] = [("gemini", "gemini-3.5-flash-lite")]
        pedidos = []

        def responder(fornecedor, chave, caminho, corpo, timeout):
            pedidos.append(corpo)
            if len(pedidos) == 1:
                return 200, {"choices": [{"message": {"content": None, "tool_calls": [{
                    "id": "call_1", "type": "function", "function": {"name": "ler", "arguments": "{}"},
                    "extra_content": {"google": {"thought_signature": "assinatura-teste"}},
                }]}}]}, {}
            return 200, {"choices": [{"message": {"content": "ok"}}]}, {}

        roteador._http = responder
        primeira = roteador.chamar(
            "perfil:raciocinio", [{"role": "user", "content": "teste"}],
            tools=[{"type": "function", "function": {"name": "ler"}}],
        )
        self.assertEqual(primeira["model"], "gemini:gemini-3.5-flash-lite")
        historico = [{"role": "user", "content": "teste"}, {"role": "assistant", "content": None,
                     "tool_calls": [{"id": "call_1", "type": "function", "function": {"name": "ler", "arguments": "{}"}}]},
                    {"role": "tool", "tool_call_id": "call_1", "content": "feito"}]
        segunda = roteador.chamar("perfil:raciocinio", historico, tools=[{"type": "function", "function": {"name": "ler"}}])
        self.assertEqual(segunda["choices"][0]["message"]["content"], "ok")
        self.assertEqual(pedidos[1]["messages"][1]["tool_calls"][0]["extra_content"]["google"]["thought_signature"], "assinatura-teste")
        self.assertNotIn("extra_content", historico[1]["tool_calls"][0])

    def test_assinatura_desconhecida_nao_e_enviada_ao_gemini(self):
        roteador = Roteador({"GEMINI_API_KEY": "chave-teste"}, estado_path=None)
        roteador.ordem["raciocinio"] = [("gemini", "gemini-3.5-flash-lite")]
        roteador._http = lambda *_args: self.fail("Gemini chamado sem assinatura")
        resposta = roteador.chamar("perfil:raciocinio", [{"role": "assistant", "tool_calls": [{"id": "desconhecida"}]}],
                                  tools=[{"type": "function", "function": {"name": "ler"}}])
        self.assertIn("thought_signature indisponivel", resposta["tentativas"][0]["saltado"])


if __name__ == "__main__":
    unittest.main()
