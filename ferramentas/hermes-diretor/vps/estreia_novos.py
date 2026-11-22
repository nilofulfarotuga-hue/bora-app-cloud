#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""estreia_novos.py — poe a correr, uma vez, cada agente criado a 22/11/2026 (missao hermes-diretor).
Molde: /opt/data/rotinas/estreia_agentes.py. Uma pergunta real por agente; nao se aceita exit 0,
aceita-se conteudo. Um de cada vez (a VPS tem 1 processador). Corre no host, como root."""
import sys
import time

sys.path.insert(0, "/opt/data/rotinas")
import despachante as D  # noqa: E402

PRE = ("ESTREIA do agente (teste tecnico da missao hermes-diretor; quem pergunta e o Claude Code, nao o "
       "Danilo). Nao mandes nada a ninguem e nao mudes dados. Responde em 3 a 5 linhas. ")
PERGUNTAS = {
    "engenheiro": "O painel admin mostra um ecra em branco ao abrir a lista de pedidos e ha 40 erros iguais nos "
                  "registos da ultima hora. Diz o que verificas primeiro, como mandas consertar, e o que NUNCA "
                  "fazes mesmo com pressa.",
    "zelador": "O disco da VPS esta a 84% e a memoria disponivel a 1,9 GB. Diz o que medes primeiro, o que podes "
               "limpar sozinho e o que nunca apagas.",
    "mercados": "Um cliente diz que o arroz comprado no mercado custou no talao mais 30 centimos do que na app. Diz "
                "o que verificas, o que podes corrigir sozinho e o que precisa do autorizo.",
    "gestor-servicos": "Nos ultimos 30 dias houve 8 corridas TVDE sem motorista em 37. Diz o que vais ver primeiro, "
                       "o que propoes, e o que nunca prometes a um motorista.",
    "loja-online": "Um brinquedo da Loja Online tem um certificado CE generico que cobre 99 modelos e nao mostra "
                   "este produto. Diz se o ligas, o que pedes ao fornecedor, e o que nunca fazes.",
}

falhas = 0
for nome in sorted(PERGUNTAS):
    est = D.estado_agente(nome)
    t0 = time.time()
    ok, saida, rc = D.invocar(nome, PRE + PERGUNTAS[nome], 200)
    ms = int((time.time() - t0) * 1000)
    bom = ok and len(saida) > 120
    D.guardar_corrida(nome, "estreia", PERGUNTAS[nome], bom, ms, saida if bom else "", None if bom else saida[:1000])
    falhas += 0 if bom else 1
    print("=== %s | estado %s | %s | %d ms | %d caracteres" % (nome, est[0], "OK" if bom else "FALHOU", ms, len(saida)))
    print(saida.strip()[:900])
    print()
print("RESULTADO: %d de %d agentes novos responderam com conteudo" % (len(PERGUNTAS) - falhas, len(PERGUNTAS)))
sys.exit(1 if falhas else 0)
