---
name: acordar-agente
description: >
  Usar para mandar trabalho a um agente (ligado, desligado ou arquivado) pelo despacho e acompanhar ate a
  prova. Diz quem trata de que, o que acontece a um agente desligado e o que nunca se faz.
version: 1.0.0
author: missao hermes-diretor-2026-11-20
license: MIT
platforms: [linux]
category: operacao
---

# Mandar trabalho a um agente

1. Escolhe o agente em `/opt/data/ROTAS.md` (assunto -> agente e substituto).
2. Manda pelo despacho, com a tarefa completa (o agente nao ve a tua conversa):
   `python3 /opt/data/bin/porta.py despacho_inserir '{"para":"<agente>","titulo":"...","tarefa":"o que fazer, onde, e que prova quero"}'`
   Tarefa so de leitura: escreve "SO LEITURA" no texto (nao passa pelo fiscal).
3. Estados: no RELOGIO corre a hora dele; A PEDIDO ou DESLIGADO, o despachante ACORDA-O so para essa tarefa;
   ARQUIVADO, faz o substituto (ou eu); BLOQUEADO (trader), nunca: so o Danilo o liga.
4. Acompanha: `porta.py despacho_ler '{"id":<numero>}'`. `feita` com "fiscal: OK" na prova = conferida.
   `aberta` com "[FISCAL n/2]" = o fiscal devolveu, o agente vai repetir. `a-espera-do-danilo` = o agente
   escreveu `PRECISA DO AUTORIZO` (dinheiro ou apagar): segue a skill `pedir-autorizacao`.
5. Um trabalho pesado de cada vez na VPS (1 processador). Nao lances varios agentes ao mesmo tempo.

Nao crio agentes novos por habito: so quando uma area inteira fica sem dono, e digo ao Danilo.
