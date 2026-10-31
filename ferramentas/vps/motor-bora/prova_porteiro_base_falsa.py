# -*- coding: utf-8 -*-
"""Prova do porteiro com base FALSA (nao chama a Anthropic, nao gasta nada, nao escreve no Motor vivo).
Correr na VPS:  cd /opt/motor-bora && python3 /tmp/prova_porteiro_base_falsa.py
"""
import json
import os
import sys
import tempfile

sys.path.insert(0, "/opt/motor-bora")
from motor_bora import porteiro as P  # noqa: E402
from motor_bora import catalogo as C  # noqa: E402

ok_total = []


def verifica(nome, cond, extra=""):
    ok_total.append(bool(cond))
    print(("OK   " if cond else "FALHOU ") + nome + ((" | " + extra) if extra else ""))


class Falsa:
    def __init__(self):
        self.respostas = []
        self.corpos = []

    def __call__(self, corpo, timeout):
        self.corpos.append(corpo)
        return self.respostas.pop(0)


def resp_ok(texto="Ola! Em que posso ajudar?", tool=False):
    content = [{"type": "text", "text": texto}]
    if tool:
        content.append({"type": "tool_use", "id": "toolu_1", "name": "ver_menu", "input": {"loja": "boom"}})
    return 200, {"content": content, "stop_reason": "tool_use" if tool else "end_turn",
                 "usage": {"input_tokens": 120, "output_tokens": 30, "cache_creation_input_tokens": 900, "cache_read_input_tokens": 0}}, {}


pasta = tempfile.mkdtemp(prefix="porteiro-prova-")
falsa = Falsa()
por = P.Porteiro({}, pasta, http=falsa)

# 0. catalogo: perfis claude-* existem e nenhum perfil tem go/zen/ollama
mortos = [(p, f, m) for p, v in C.PERFIS.items() for f, m in v.get("candidatos", []) if f in ("go", "zen", "ollama", "gemini2")]
verifica("catalogo sem go/zen/ollama/gemini2", not mortos, str(mortos[:3]))
verifica("perfis claude-* criados", all(k in C.PERFIS for k in P.PERFIS_CLAUDE), ", ".join(k for k in C.PERFIS if k.startswith("claude-")))
verifica("claude-cliente comeca pela rotacao gratis medida", C.PERFIS["claude-cliente"]["candidatos"][:6] == [tuple(x) for x in [("groq", "openai/gpt-oss-120b"), ("gemini", "gemini-3.1-flash-lite"), ("groq", "qwen/qwen3.8-27b"), ("gemini", "gemini-3.5-flash-lite"), ("groq", "openai/gpt-oss-20b"), ("gemini", "gemini-3-flash-preview")]])

# 1. sem chave -> gratis
r, info = por.tentar("claude-cliente", [{"role": "user", "content": "oi"}])
verifica("sem chave vai para o gratis", r is None and "sem chave" in info["porque"], info["porque"])

# 2. com chave e resposta 200 -> Claude, custo pelo preco oficial, livro escrito
por.env = {P.VAR_CHAVE: "x-falsa"}
falsa.respostas.append(resp_ok())
msgs = [{"role": "system", "content": "Es o assistente do Boom Burger."}, {"role": "user", "content": "oi"}]
r, info = por.tentar("claude-cliente", msgs, origem="prova")
c = falsa.corpos[-1]
verifica("P1 com credito vai ao Claude Sonnet 5.5", r is not None and info["modelo"] == "claude-sonnet-5-5", info["porque"])
verifica("pedido sem temperature, com cache no system e thinking between_tools",
         "temperature" not in c and c["system"][-1].get("cache_control") == {"type": "ephemeral"} and c["thinking"] == {"type": "between_tools"} and c["output_config"] == {"effort": "low"})
custo = P.custo_usd("claude-sonnet-5-5", 120, 30, 900, 0)
verifica("custo = 120x2 + 30x10 + 900x2,5 por milhao", abs(info["custo_usd"] - custo) < 1e-9 and abs(custo - 0.00279) < 1e-9, "%.6f USD" % custo)
linhas = open(os.path.join(pasta, "ia_gastos.jsonl"), encoding="utf-8").read().splitlines()
verifica("livro de gastos com 1 linha", len(linhas) == 1 and json.loads(linhas[0])["perfil"] == "claude-cliente", linhas[0][:160])
verifica("resposta no formato OpenAI", r["choices"][0]["message"]["content"].startswith("Ola") and r["model"] == "claude:claude-sonnet-5-5")

# 3. ferramentas: tool_use -> tool_calls -> e volta (blocos originais repostos, resultados juntos)
falsa.respostas.append(resp_ok("Vou ver o menu.", tool=True))
tools = [{"type": "function", "function": {"name": "ver_menu", "description": "Menu da loja", "parameters": {"type": "object", "properties": {"loja": {"type": "string"}}}}}]
r, info = por.tentar("claude-classificar", [{"role": "user", "content": "menu?"}], tools=tools)
tc = r["choices"][0]["message"]["tool_calls"]
verifica("tool_use -> tool_calls", r["choices"][0]["finish_reason"] == "tool_calls" and tc[0]["function"]["name"] == "ver_menu" and json.loads(tc[0]["function"]["arguments"]) == {"loja": "boom"})
verifica("Haiku 5.5 com thinking disabled e tool_choice auto", falsa.corpos[-1]["model"] == "claude-haiku-5-5" and falsa.corpos[-1]["thinking"] == {"type": "disabled"} and falsa.corpos[-1]["tool_choice"] == {"type": "auto"})
seguinte = [{"role": "user", "content": "menu?"}, r["choices"][0]["message"], {"role": "tool", "tool_call_id": "toolu_1", "content": "Smash 8,50"}]
s, m, f = P.para_anthropic(seguinte, tools, por.blocos)
verifica("historico: assistente com blocos originais e tool_result numa mensagem user",
         m[1]["role"] == "assistant" and m[1]["content"][1]["type"] == "tool_use" and m[2]["content"][0]["type"] == "tool_result" and m[-1]["role"] == "user")

# 4. P3 com parte do dia esgotada -> gratis, enquanto P1 continua no Claude
cont = por.contas()
por.simular["gasto_hoje_extra_usd"] = cont["parte_do_dia_usd"] * 0.6
pode3, motivo3, _, _ = por.decidir("claude-agente")
pode2, motivo2, _, _ = por.decidir("claude-decisao")
pode1, motivo1, _, _ = por.decidir("claude-cliente")
verifica("parte do dia a 60%: P3 vai ao gratis", not pode3, motivo3)
verifica("parte do dia a 60%: P2 continua no Claude", pode2, motivo2)
verifica("parte do dia a 60%: P1 continua no Claude", pode1, motivo1)
por.simular["gasto_hoje_extra_usd"] = cont["parte_do_dia_usd"] * 1.1
verifica("parte do dia passada: P2 vai ao gratis e P1 continua", (not por.decidir("claude-decisao")[0]) and por.decidir("claude-cliente")[0])
por.simular["gasto_hoje_extra_usd"] = 0

# 5. sem saldo (400 credit balance) -> dormido ate ao proximo credito, tudo gratis, sem erro
falsa.respostas.append((400, {"type": "error", "error": {"type": "invalid_request_error", "message": "Your credit balance is too low to access the Anthropic API."}}, {}))
r, info = por.tentar("claude-cliente", [{"role": "user", "content": "oi"}])
verifica("400 sem saldo -> gratis e Claude dormido", r is None and por.dormido_ate and por.dormido_ate.startswith("2026-11-30"), str(por.dormido_ate))
r, info = por.tentar("claude-cliente", [{"role": "user", "content": "oi"}])
verifica("dormido: pedido seguinte nem tenta o Claude", r is None and "dormido" in info["porque"] and len(falsa.respostas) == 0, info["porque"])

# 6. dia do credito novo: teste minimo e volta sozinho
por.dormido_ate = "2026-10-01T00:00:00+00:00"
falsa.respostas.append(resp_ok("o"))
acordou = por.talvez_acordar()
verifica("acordar: chamada minima 200 -> volta ao Claude com o credito mensal", acordou and por.dormido_ate is None and por.cfg["credito_usd"] == 200.0, "proximo %s" % por.cfg["proximo_credito"])
verifica("a chamada de acordar e minima (max_tokens 1, Haiku)", falsa.corpos[-1]["max_tokens"] == 1 and falsa.corpos[-1]["model"] == "claude-haiku-5-5")

# 7. 529 / timeout -> gratis e pausa curta
falsa.respostas.append((529, {"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}}, {}))
r, info = por.tentar("claude-cliente", [{"role": "user", "content": "oi"}])
verifica("529 -> gratis e pausa de 60 s", r is None and por.castigo_ate > 0 and "pausa" in por.decidir("claude-cliente")[1], por.decidir("claude-cliente")[1])

# 8. Opus nunca automatico
por.castigo_ate = 0
por.cfg["robos"]["claude-decisao"]["modelo"] = "claude-opus-5-5"
verifica("Opus pedido no painel -> fica Sonnet", por.decidir("claude-decisao")[2] == "claude-sonnet-5-5")

# 9. Bloco 4a: bloco comum em cache (P1 sem o livro interno; P2/P3 com o livro e as licoes)
por.castigo_ate, por.dormido_ate, por.simular["sem_saldo"] = 0, None, False
por.ctx_paginas = {"regras-do-danilo": "REGRAS INTERNAS X", "erros-aprendidos": "ERROS Y"}
por.ctx_licoes = [{"robo": "whatsapp-bora", "errou": "respondeu 'nao tenho resposta' a um oi", "regra": "cumprimento recebe cumprimento"}]
falsa.respostas.append(resp_ok())
por.tentar("claude-cliente", [{"role": "system", "content": "PESSOA: Ana"}, {"role": "user", "content": "oi"}])
s1 = falsa.corpos[-1]["system"]
verifica("P1: bloco comum primeiro, com cache, licao incluida e SEM o livro interno",
         s1[0].get("cache_control") and "NUNCA" not in "" and "nao tenho resposta" in s1[0]["text"] and "REGRAS INTERNAS" not in s1[0]["text"] and s1[-1]["text"] == "PESSOA: Ana")
por.cfg["robos"]["claude-decisao"]["modelo"] = "claude-sonnet-5-5"
falsa.respostas.append(resp_ok())
por.tentar("claude-decisao", [{"role": "user", "content": "decide"}])
s2 = falsa.corpos[-1]["system"]
verifica("P2: bloco comum com o livro (regras do Danilo e erros aprendidos)", "REGRAS INTERNAS X" in s2[0]["text"] and "ERROS Y" in s2[0]["text"])
verifica("no maximo 4 marcas de cache por pedido", sum(1 for b in s1 if b.get("cache_control")) <= 4)

print("RESULTADO %d/%d" % (sum(ok_total), len(ok_total)))
