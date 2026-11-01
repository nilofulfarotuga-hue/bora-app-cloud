# -*- coding: utf-8 -*-
"""Prova do porteiro SEM RACAO (01/11/2026, missao infra-claude-tudo) com base FALSA: nao chama a Anthropic,
nao gasta nada, nao escreve no Motor vivo.  Correr na VPS:  python3 prova_porteiro_sem_racao.py
"""
import json
import os
import sys
import tempfile
import time

sys.path.insert(0, os.environ.get("MOTOR_DIR", "/opt/motor-bora"))
from motor_bora import porteiro as P  # noqa: E402
from motor_bora import catalogo as C  # noqa: E402

ok_total = []


def verifica(nome, cond, extra=""):
    ok_total.append(bool(cond))
    print(("OK   " if cond else "FALHOU ") + nome + ((" | " + extra) if extra else ""))


class Falsa:
    def __init__(self):
        self.respostas, self.corpos, self.esperas = [], [], []

    def __call__(self, corpo, timeout):
        self.corpos.append(json.loads(json.dumps(corpo)))
        self.esperas.append(timeout)
        return self.respostas.pop(0)


def resp_ok(texto="ok", thinking=False):
    content = ([{"type": "thinking", "thinking": "", "signature": "sig"}] if thinking else []) + [{"type": "text", "text": texto}]
    return 200, {"content": content, "stop_reason": "end_turn",
                 "usage": {"input_tokens": 100, "output_tokens": 20, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0}}, {}


pasta = tempfile.mkdtemp(prefix="porteiro-semracao-")
falsa = Falsa()
por = P.Porteiro({P.VAR_CHAVE: "x-falsa"}, pasta, http=falsa)
livro = os.path.join(pasta, "ia_gastos.jsonl")

# 1. sem racao por defeito: P3 com o gasto de hoje enorme continua no Claude
verifica("config nova nasce sem racao", por.cfg.get("racao") is False and por.estado()["racao"] is False)
por.simular["gasto_hoje_extra_usd"] = 999.0
for p in ("claude-agente", "claude-volume", "claude-decisao", "claude-cliente", "claude-dipsy"):
    pode, motivo, _, _ = por.decidir(p)
    verifica("sem racao: %s vai ao Claude mesmo com 999 USD gastos hoje" % p, pode and "sem racao" in motivo, motivo)
# 2. a racao antiga continua a existir e liga-se pela config
por.cfg["racao"] = True
verifica("racao ligada: P3 volta a ir ao gratis", not por.decidir("claude-agente")[0], por.decidir("claude-agente")[1])
por.cfg["racao"] = False
por.simular["gasto_hoje_extra_usd"] = 0

# 3. perfis novos
verifica("perfis claude-dipsy e claude-opus no catalogo e no porteiro",
         all(k in C.PERFIS and k in P.PERFIS_CLAUDE for k in ("claude-dipsy", "claude-opus")))
verifica("claude-dipsy tem cauda gratis (nunca fica sem)", len(C.PERFIS["claude-dipsy"]["candidatos"]) >= 6)
falsa.respostas.append(resp_ok("ROTA-CLAUDE-DIPSY-OK"))
r, info = por.tentar("claude-dipsy", [{"role": "system", "content": "Es o Dipsy."}, {"role": "user", "content": "responde"}], origem="dipsy")
c = falsa.corpos[-1]
verifica("claude-dipsy -> Sonnet 5.5, between_tools, esforco medium, 8000 tokens, 150 s",
         r is not None and c["model"] == "claude-sonnet-5-5" and c["thinking"] == {"type": "between_tools"}
         and c["output_config"] == {"effort": "medium"} and c["max_tokens"] == 8000 and falsa.esperas[-1] == 150)
verifica("claude-dipsy sem o bloco comum dos clientes (so o system dele)", len(c["system"]) == 1 and c["system"][0]["text"] == "Es o Dipsy.")
verifica("claude-dipsy com cache automatica da conversa", c.get("cache_control") == {"type": "ephemeral"})
ln = json.loads(open(livro, encoding="utf-8").read().splitlines()[-1])
verifica("livro: robo=dipsy, perfil claude-dipsy, ok", ln["robo"] == "dipsy" and ln["perfil"] == "claude-dipsy" and ln["ok"] is True)

falsa.respostas.append(resp_ok("opus", thinking=True))
r, info = por.tentar("claude-opus", [{"role": "user", "content": "pergunta curta"}], origem="dipsy")
c = falsa.corpos[-1]
verifica("claude-opus -> Opus 5.5 sem campo thinking (nao se desliga) e esforco medium",
         r is not None and c["model"] == "claude-opus-5-5" and "thinking" not in c and c["output_config"] == {"effort": "medium"})
verifica("custo Opus = 100x4 + 20x20 por milhao", abs(info["custo_usd"] - (100 * 4 + 20 * 20) / 1e6) < 1e-9, str(info["custo_usd"]))
por.cfg["robos"]["claude-decisao"]["modelo"] = "claude-opus-5-5"
verifica("Opus continua proibido nos outros perfis", por.decidir("claude-decisao")[2] == "claude-sonnet-5-5")
por.cfg["robos"]["claude-decisao"]["modelo"] = "claude-sonnet-5-5"

# 4. 400 por blocos thinking que ja nao batem: tenta uma vez sem eles
por.blocos["toolu_9"] = [{"type": "thinking", "thinking": "", "signature": "velha"}, {"type": "tool_use", "id": "toolu_9", "name": "ler", "input": {}}]
hist = [{"role": "user", "content": "le"}, {"role": "assistant", "content": "", "tool_calls": [{"id": "toolu_9", "type": "function", "function": {"name": "ler", "arguments": "{}"}}]},
        {"role": "tool", "tool_call_id": "toolu_9", "content": "feito"}]
falsa.respostas.append((400, {"type": "error", "error": {"type": "invalid_request_error", "message": "thinking block signature invalid"}}, {}))
falsa.respostas.append(resp_ok("depois"))
r, info = por.tentar("claude-opus", hist)
verifica("400 thinking -> 2.a tentativa sem os blocos thinking, responde pelo Claude",
         r is not None and not P._tem_thinking(falsa.corpos[-1]["messages"]) and P._tem_thinking(falsa.corpos[-2]["messages"]))

# 5. 429 -> pausa de 2 min (e nao 60 s); falha vai ao livro com custo 0
falsa.respostas.append((429, {"type": "error", "error": {"type": "rate_limit_error", "message": "slow down"}}, {"retry-after": "5"}))
r, info = por.tentar("claude-volume", [{"role": "user", "content": "x"}])
falta = por.castigo_ate - time.time()
verifica("429 -> gratis e pausa ~120 s", r is None and 110 < falta <= 121, "%.0f s" % falta)
ln = json.loads(open(livro, encoding="utf-8").read().splitlines()[-1])
verifica("falha 429 escrita no livro (ok=false, custo 0)", ln["ok"] is False and ln["custo_usd"] == 0 and ln["erro"].startswith("http 429"))
por.castigo_ate = 0

# 6. 401 -> pausa 6 h
falsa.respostas.append((401, {"type": "error", "error": {"type": "authentication_error", "message": "invalid x-api-key"}}, {}))
por.tentar("claude-cliente", [{"role": "user", "content": "x"}])
verifica("401 -> pausa de 6 h", 6 * 3600 - 60 < por.castigo_ate - time.time() <= 6 * 3600 + 1)
por.castigo_ate = 0

# 7. sem saldo (402) -> dormido ate ao credito novo; linha "sem credito" no livro para as Edge Functions
falsa.respostas.append((402, {"type": "error", "error": {"type": "billing_error", "message": "Your credit balance is too low"}}, {}))
r, info = por.tentar("claude-agente", [{"role": "user", "content": "x"}])
ln = json.loads(open(livro, encoding="utf-8").read().splitlines()[-1])
verifica("402 -> gratis e Claude dormido ate 30/11", r is None and (por.dormido_ate or "").startswith("2026-11-30"), str(por.dormido_ate))
verifica("linha 'sem credito' no livro", ln["ok"] is False and "(sem credito)" in ln["erro"])
verifica("dormido: todos os perfis vao ao gratis sem chamar a API",
         all(not por.decidir(p)[0] for p in P.PERFIS_CLAUDE) and len(falsa.respostas) == 0)
# 7b. dormido ate 30/11 mas o Danilo carregou credito antes: a sonda de 6 em 6 h acorda-o sem esperar
por._ult_sonda = 0
falsa.respostas.append(resp_ok("o"))
verifica("sonda de 6 h acorda antes do dia do credito", por.talvez_acordar() is True and por.dormido_ate is None)
por._dormir("teste")
verifica("sonda nao repete antes de 6 h", por.talvez_acordar() is None)
# 8. credito novo: acorda e volta tudo ao Claude
por.dormido_ate = "2026-10-01T00:00:00+00:00"
falsa.respostas.append(resp_ok("o"))
verifica("acordar -> volta ao Claude", por.talvez_acordar() and por.decidir("claude-agente")[0])
# 9. simulacao do porteiro (o mesmo que POST /porteiro/simular)
por.simular["sem_saldo"] = True
verifica("simular sem saldo -> gratis", not por.decidir("claude-dipsy")[0])
por.simular["sem_saldo"] = False
verifica("fim da simulacao -> Claude", por.decidir("claude-dipsy")[0])

print("RESULTADO %d/%d" % (sum(ok_total), len(ok_total)))
