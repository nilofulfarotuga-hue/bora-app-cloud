# -*- coding: utf-8 -*-
"""Cerebro do WhatsApp da Bora: o SUPORTE QUE RESPONDE A TUDO (ordens do Danilo 31/10 09:53 e 10:01).
Acrescenta ao prompt fixo (parte estavel = cache) as regras: cumprimento, responder a tudo consultando antes,
conversa humana, falar com uma pessoa, e a lista do que NUNCA se diz (dono, nomes/telefones pessoais, comissoes
internas, margens, ganhos de outros, dados de outros, chaves). Tira o nome do Danilo das frases ditas ao cliente.
Correr na VPS como root:  python3 patch_cerebro_suporte_20261031.py   |   --repor
"""
import os
import py_compile
import shutil
import sys

AG = "/opt/whatsapp-bora/cerebro/agente.py"
SUF = ".bak-suporte-20261031"
MARCA = "SUPORTE QUE RESPONDE A TUDO"

if "--repor" in sys.argv:
    if os.path.exists(AG + SUF):
        shutil.copy2(AG + SUF, AG)
        print("reposto", AG)
    sys.exit(0)

if not os.path.exists(AG + SUF):
    shutil.copy2(AG, AG + SUF)
    print("copia", AG + SUF)

t = open(AG, encoding="utf-8").read()
if MARCA in t:
    print("agente.py: ja aplicado")
    sys.exit(0)

REGRAS = '''
# 31/10/2026 (missao motor-claude, ordens do Danilo 09:53 e 10:01): SUPORTE QUE RESPONDE A TUDO.
# Texto FIXO (entra na parte estavel do prompt, que o Claude guarda em cache). Vale para clientes,
# estafetas e parceiros. Ganha a qualquer frase antiga que diga o nome do Danilo a quem escreve.
REGRAS_SUPORTE = (
    "SUPORTE QUE RESPONDE A TUDO: "
    "1) Cumprimento ('oi', 'ola', 'boa tarde') recebe cumprimento e 'em que posso ajudar?'. NUNCA respondas "
    "'nao tenho resposta para isso' nem 'nao sei'. "
    "2) O que nao sabes, CONSULTAS antes de responder: ler_manual (precos, entregas, pagamentos, premios do check-in, "
    "tokens, limpeza, reservas, como funciona para cliente, estafeta e parceiro), loja (horarios, morada, se esta "
    "aberta), pedidos (estado do pedido DESTA pessoa), quem_e. Sabes tudo do Bora, nao so de uma loja. Se depois de "
    "consultar continuas sem saber: 'vou confirmar e ja lhe digo' + agendar_seguimento + avisar_danilo. Nunca inventas "
    "precos nem prometes o que nao existe. "
    "3) Problema com pedido: ves o pedido (pedidos) e explicas o estado real; se atrasou, pedes desculpa. "
    "4) Quem quer ser parceiro: explicas as condicoes devagar, 1-2 coisas de cada vez. "
    "5) Conversa fiada ou pessoal ('tas bom?', 'hoje esta um frio'): respondes como uma pessoa, curto e simpatico, e "
    "voltas ao que podes ajudar. "
    "6) So passas para uma pessoa quando pedem ('quero falar com alguem', 'com o responsavel'): dizes que passas ja a "
    "mensagem a equipa e que respondem por este mesmo numero do Bora; avisar_danilo. "
    "O QUE NUNCA SE DIZ: quem e o dono do Bora; o nome ou o telefone pessoal de ninguem da equipa (dizes 'a equipa' ou "
    "'vou confirmar com o meu superior'); markups, margens, comissoes internas (a parceiros so explicas a comissao "
    "das condicoes de parceria), ganhos de estafetas ou parceiros que nao sejam a propria pessoa; dados pessoais, "
    "moradas ou pedidos de outros clientes, estafetas ou parceiros; chaves e segredos; o que o manual marca como "
    "interno. 'Quem e o dono?' -> 'O Bora e uma empresa da Guarda; se quiser falar com o responsavel, passo-lhe ja a "
    "mensagem.' Dinheiro, reembolsos, descontos e reclamacoes: explicas a regra e dizes que a equipa vai tratar; nunca "
    "prometes valores. Sempre em portugues de Portugal (ou na lingua da pessoa), curto, humano, sem jargao."
)
'''

anc = "\ndef _sistema(f, tratamento, lingua_, registo_, porta):"
if t.count(anc) != 1:
    raise SystemExit("ancora _sistema nao encontrada")
t = t.replace(anc, REGRAS + anc)

# o bloco entra logo a seguir as regras fixas (antes de FACTOS_OPERACAO) no prompt principal
anc2 = '''        FACTOS_OPERACAO,
        "MANUAL (pede seccoes com ler_manual):\\n" + manual.indice()[:1500],'''
if t.count(anc2) != 1:
    raise SystemExit("ancora FACTOS_OPERACAO/MANUAL nao encontrada (%d)" % t.count(anc2))
t = t.replace(anc2, '''        REGRAS_SUPORTE,
''' + anc2)

# o nome do Danilo deixa de ir para quem escreve
n = 0
for velho, novo in (("(ai: assistente do Bora; o Danilo le tudo)", "(ai: assistente do Bora; a equipa le tudo)"),
                    ("e que o Danilo responde ja.", "e que a equipa responde ja."),
                    ("dizes que o Danilo responde ja,", "dizes que a equipa responde ja,")):
    n += t.count(velho)
    t = t.replace(velho, novo)
print("frases com o nome do Danilo trocadas:", n)

# o caminho rapido (sem ferramentas) tambem leva as regras
anc3 = '''def _sistema_rapido(f, tratamento, lingua_, registo_):'''
i = t.index(anc3)
j = t.index("partes = [", i)
k = t.index("\n", j)
t = t[:k + 1] + "        REGRAS_SUPORTE,\n" + t[k + 1:]

if not t[k + 1:].lstrip().startswith(("REGRAS_SUPORTE", '"', "f\"", "(")) or t[j:k].strip() != "partes = [":
    raise SystemExit("_sistema_rapido: 'partes = [' nao esta sozinho na linha - nada gravado")
with open(AG + ".tmp", "w", encoding="utf-8") as fh:
    fh.write(t)
py_compile.compile(AG + ".tmp", doraise=True)      # so substitui se compilar
os.replace(AG + ".tmp", AG)
print("agente.py: regras do suporte no prompt principal e no rapido; py_compile OK")
