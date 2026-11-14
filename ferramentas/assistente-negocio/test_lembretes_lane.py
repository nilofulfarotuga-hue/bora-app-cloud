"""Testes da pista dos lembretes do dono (missao fechar-app-15-11, bloco 8 parte F). Sem rede e sem Supabase:
uma base falsa em memoria no lugar do db.py e um .env de brincar numa pasta temporaria.

Caso real: a 12/11/2026 as 04:38 um alerta do robo do suporte para o WhatsApp do dono ficou
'cancelada-anonimato' porque o CLIENTE tinha o mesmo nome do dono. A trava do anonimato e para o que vai
para clientes; esta pista so entrega ao proprio dono.

Correr (PC ou VPS):   python -m unittest -v test_lembretes_lane     (dentro de ferramentas/assistente-negocio)
"""
import datetime
import os
import sys
import tempfile
import types
import unittest

AQUI = os.path.dirname(os.path.abspath(__file__))

# Numeros e nome de brincar (nenhum e de ninguem).
DESTINO = "351900000001"
OUTRO = "351900000002"
NOME_DONO = "Fulano"


class BaseFalsa:
    """Guarda as linhas de whatsapp_saida e responde como o db.py: ler devolve as pendentes, atualizar
    muda o estado (respeitando o filtro 'estado=eq.pendente' da reserva)."""

    def __init__(self, linhas):
        self.linhas = {str(l["id"]): dict(l) for l in linhas}
        self.atualizacoes = []

    def q(self, v):
        return str(v)

    def ler(self, tabela, filtros="", seleciona="*"):
        if tabela != "whatsapp_saida":
            return []
        return [dict(l) for l in self.linhas.values() if l["estado"] == "pendente"]

    def atualizar(self, tabela, filtros, campos):
        if tabela != "whatsapp_saida":
            return True
        rid = filtros.split("id=eq.", 1)[1].split("&", 1)[0]
        linha = self.linhas.get(rid)
        if linha is None:
            return False
        if "estado=eq.pendente" in filtros and linha["estado"] != "pendente":
            return False
        linha.update(campos)
        self.atualizacoes.append((rid, dict(campos)))
        return True

    def inserir(self, *a, **k):
        return True


def _agora(menos_s=0):
    return (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=menos_s)).isoformat()


def _linha(rid, numero, texto, criada=None, motivo="lembrete-danilo:suporte:abc"):
    return {"id": rid, "numero": numero, "texto": texto, "motivo": motivo, "estado": "pendente",
            "created_at": criada or _agora()}


class PistaDosLembretes(unittest.TestCase):
    def _montar(self, linhas, env=None):
        base = BaseFalsa(linhas)
        falso = types.ModuleType("db")
        for nome in ("q", "ler", "atualizar", "inserir"):
            setattr(falso, nome, getattr(base, nome))
        sys.modules["db"] = falso
        sys.modules.pop("lembretes_lane", None)
        if AQUI not in sys.path:
            sys.path.insert(0, AQUI)
        import lembretes_lane as pista
        pasta = tempfile.mkdtemp()
        caminho = os.path.join(pasta, ".env")
        with open(caminho, "w", encoding="utf-8") as fh:
            fh.write(env if env is not None
                     else "LEMBRETES_DESTINO=+%s\nLEMBRETES_NOMES_DONO=%s,Beltrano\n" % (DESTINO, NOME_DONO))
        pista.ENV = caminho
        pista.RE_DONO = pista._re_dono()  # como na VPS: a lista de nomes existe e esta carregada
        return pista, base

    def test_alerta_ao_dono_com_o_nome_dele_no_texto_sai(self):
        # O caso de 12/11: o cliente chama-se como o dono.
        texto = "Suporte: o cliente %s Silva precisa de ti (pedido atrasado)." % NOME_DONO
        pista, base = self._montar([_linha(1, "+" + DESTINO, texto)])
        self.assertIsNotNone(pista.RE_DONO, "a lista de nomes tem de estar carregada para o teste valer")
        self.assertTrue(pista.RE_DONO.search(texto), "o texto tem mesmo o nome do dono")
        saida = pista.pendentes()
        self.assertEqual([s["id"] for s in saida], ["ld-1"])
        self.assertEqual(saida[0]["texto"], texto)
        self.assertEqual(base.linhas["1"]["estado"], "a-enviar")
        self.assertNotIn("cancelada-anonimato", [c.get("estado") for _, c in base.atualizacoes])

    def test_nunca_sai_para_outro_numero_com_ou_sem_nome(self):
        pista, base = self._montar([
            _linha(1, "+" + OUTRO, "Olá, o %s já vai ver isso." % NOME_DONO),
            _linha(2, "+" + OUTRO, "Olá, já vamos ver isso."),
        ])
        self.assertEqual(pista.pendentes(), [])
        self.assertEqual(base.linhas["1"]["estado"], "cancelada-fora-da-allowlist")
        self.assertEqual(base.linhas["2"]["estado"], "cancelada-fora-da-allowlist")

    def test_alerta_velho_expira(self):
        pista, base = self._montar([_linha(1, DESTINO, "Lembrete antigo.", criada=_agora(menos_s=3600))])
        self.assertEqual(pista.pendentes(), [])
        self.assertEqual(base.linhas["1"]["estado"], "cancelada-expirada")

    def test_sem_destino_configurado_nada_sai_e_nada_muda(self):
        pista, base = self._montar([_linha(1, DESTINO, "Lembrete.")], env="LEMBRETES_NOMES_DONO=%s\n" % NOME_DONO)
        self.assertEqual(pista.pendentes(), [])
        self.assertEqual(base.linhas["1"]["estado"], "pendente")
        self.assertEqual(base.atualizacoes, [])

    def test_o_mesmo_alerta_nao_sai_duas_vezes(self):
        pista, base = self._montar([_linha(1, DESTINO, "Lembrete do dia.")])
        self.assertEqual(len(pista.pendentes()), 1)
        self.assertEqual(pista.pendentes(), [])  # ja esta 'a-enviar'

    def test_pela_fonte_a_pista_ja_nao_cancela_por_anonimato(self):
        with open(os.path.join(AQUI, "lembretes_lane.py"), encoding="utf-8") as fh:
            fonte = fh.read()
        corpo = fonte.split("def pendentes():", 1)[1].split("\ndef ", 1)[0]
        self.assertNotIn('{"estado": "cancelada-anonimato"}', corpo)
        self.assertIn('{"estado": "cancelada-fora-da-allowlist"}', corpo)
        # A trava continua onde tem de estar: no que vai para clientes.
        with open(os.path.join(AQUI, "..", "whatsapp-loja", "servidor_cerebro.py"), encoding="utf-8") as fh:
            cerebro = fh.read()
        self.assertIn("if verdades.RE_DONO.search(texto or", cerebro)


if __name__ == "__main__":
    unittest.main()
