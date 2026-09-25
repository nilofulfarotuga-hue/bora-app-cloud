# -*- coding: utf-8 -*-
"""Testes do Jev preparado no Motor Bora (biblioteca padrao: python3 -m unittest discover -s tests).
Provam a flag desligada por defeito, a chave (env / Vault / nenhuma), o contrato do pedido,
o fecho da resposta e que NADA levanta excepcao para quem chama — o roteador nunca parte."""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from motor_bora import jev  # noqa: E402
from motor_bora import Roteador  # noqa: E402


class _Resultado:
    def __init__(self, data):
        self.data = data


class _Query:
    def __init__(self, data):
        self._data = data

    def execute(self):
        return _Resultado(self._data)


class SupaFalso:
    def __init__(self, valor=None, falha=False):
        self.valor, self.falha, self.chamadas = valor, falha, []

    def rpc(self, nome, params):
        self.chamadas.append(nome)
        if self.falha:
            raise RuntimeError("sem permissao")
        return _Query(self.valor)


def http_ok(k, corpo):
    http_ok.ultimo = (k, corpo)
    return 200, {"model": "jev-2026-09", "usage": {"input_tokens": 120, "output_tokens": 4},
                 "answers": {"d": {"choice": "estafeta_2", "confidence": 0.81,
                                   "probabilities": {"estafeta_1": 0.15, "estafeta_2": 0.8,
                                                     "estafeta_3": 0.05}}}}


class TestFlagEChave(unittest.TestCase):
    def test_desligado_por_defeito(self):
        self.assertFalse(jev.ativo({}))
        self.assertFalse(jev.ativo({"MOTOR_JEV_ATIVO": "0"}))
        self.assertTrue(jev.ativo({"MOTOR_JEV_ATIVO": "1"}))

    def test_sem_flag_nao_chama_rede_mesmo_com_chave(self):
        def http_proibido(k, c):
            raise AssertionError("nao devia chamar a rede")
        r = jev.decidir({"TYPESAFE_API_KEY": "x"}, "noul", "?", {"a": 1}, http=http_proibido)
        self.assertIsNone(r)

    def test_chave_do_env_manda(self):
        s = SupaFalso("do-vault")
        self.assertEqual(jev.chave({"TYPESAFE_API_KEY": "do-env"}, s), "do-env")
        self.assertEqual(s.chamadas, [])

    def test_chave_do_vault_quando_env_vazio(self):
        s = SupaFalso("sk-vault")
        self.assertEqual(jev.chave({}, s), "sk-vault")
        self.assertEqual(s.chamadas, ["decisor_chave_typesafe"])

    def test_vault_vazio_ou_a_falhar_da_none(self):
        self.assertIsNone(jev.chave({}, SupaFalso(None)))
        self.assertIsNone(jev.chave({}, SupaFalso("", falha=True)))
        self.assertIsNone(jev.chave({}, None))

    def test_ligado_sem_chave_devolve_none(self):
        self.assertIsNone(jev.decidir({"MOTOR_JEV_ATIVO": "1"}, "noul", "?", {}, http=http_ok))


class TestContrato(unittest.TestCase):
    ENV = {"MOTOR_JEV_ATIVO": "1", "TYPESAFE_API_KEY": "chave-teste"}

    def test_choice_pedido_e_resposta(self):
        r = jev.decidir(self.ENV, "choice", "Quem leva?", {"trabalho": "pedido"},
                        opcoes=["estafeta_1", "estafeta_2", "estafeta_3"], http=http_ok)
        k, corpo = http_ok.ultimo
        self.assertEqual(k, "chave-teste")
        self.assertEqual(corpo["model"], jev.JEV_MODEL)
        self.assertEqual(corpo["questions"]["d"]["type"], "choice")
        self.assertEqual(corpo["questions"]["d"]["criteria"],
                         {"estafeta_1": None, "estafeta_2": None, "estafeta_3": None})
        self.assertEqual(r["motor"], "jev")
        self.assertEqual(r["resposta"], "estafeta_2")
        self.assertEqual(r["confianca"], 0.81)
        self.assertAlmostEqual(sum(r["probabilidades"].values()), 1.0, places=3)
        self.assertEqual(r["tokens_entrada"], 120)

    def test_score_e_noul(self):
        def http_score(k, c):
            return 200, {"answers": {"d": {"score": 2.4,
                                           "probabilities": {"0": 0.1, "1": 0.2, "2": 0.4, "3": 0.3}}}}
        r = jev.decidir(self.ENV, "score", "Falta?", {}, escala=["nao", "pouco", "medio", "muito"],
                        http=http_score)
        self.assertEqual(r["resposta"], "2.4")

        def http_noul(k, c):
            return 200, {"answers": {"d": {"noul": 0.2}}}
        r = jev.decidir(self.ENV, "noul", "Escalar?", {}, http=http_noul)
        self.assertEqual(r["resposta"], "nao")
        self.assertEqual(r["probabilidades"], {"sim": 0.2, "nao": 0.8})

    def test_falhas_nunca_levantam(self):
        self.assertIsNone(jev.decidir(self.ENV, "choice", "?", {}, opcoes=["a", "b"],
                                      http=lambda k, c: (429, {})))
        self.assertIsNone(jev.decidir(self.ENV, "choice", "?", {}, opcoes=["a", "b"],
                                      http=lambda k, c: (200, {"answers": {}})))

        def rebenta(k, c):
            raise OSError("rede em baixo")
        self.assertIsNone(jev.decidir(self.ENV, "choice", "?", {}, opcoes=["a", "b"], http=rebenta))
        self.assertIsNone(jev.decidir(self.ENV, "tipo-invalido", "?", {}, http=http_ok))


class TestRoteador(unittest.TestCase):
    def test_roteador_desligado_devolve_none_e_nao_toca_na_rede(self):
        r = Roteador({"TYPESAFE_API_KEY": "x"}, maquina="teste", estado_path=None)
        self.assertIsNone(r.decidir_jev("noul", "?", {"a": 1}))
        self.assertFalse(r.jev_disponivel())

    def test_roteador_ligado_com_chave_chama_o_jev(self):
        r = Roteador({"MOTOR_JEV_ATIVO": "1", "TYPESAFE_API_KEY": "x"}, maquina="teste",
                     estado_path=None)
        self.assertTrue(r.jev_disponivel())
        out = r.decidir_jev("choice", "Quem leva?", {"trabalho": "pedido"},
                            opcoes=["estafeta_1", "estafeta_2", "estafeta_3"], http=http_ok)
        self.assertEqual(out["resposta"], "estafeta_2")
        self.assertEqual(out["motor"], "jev")


if __name__ == "__main__":
    unittest.main()
