---
tema: aprovador-vermelho-corrida · escopo: agente:aprovador-vermelho · data: 2026-07-19
gatilho: FALLBACK_30MIN (item mais antigo parado 642+ min)
---

# 🚦 APROVADOR-VERMELHO — TRIAGE DA FILA 🔴 (2026-07-19, corrida ~20h00 UTC)

## Achado principal: ANOMALIA CORRIGIDA (não é triagem normal)

Ao chegar, a fila `robot_suggestions status='nova'` estava **vazia (0 itens)** — não por decisão
válida, mas porque uma execução **concorrente** do próprio mecanismo `robot_emerson_decide`
(run_id `9421a789-64ce-4f9c-b94e-c90c2017019d`, 2026-07-19 19:54:41 UTC) tinha acabado de:
- Aprovar `77c31fff-0330-4981-813a-f2268c6f7bbe` ("Investigar e otimizar queries lentas de cron")
  como `aprovada-emerson` (Balde A) — **ERRADO**.
- Rejeitar `29ea4b41-1e28-420e-a7d3-2995c335d7e5` como duplicado do primeiro.

**Por que está errado:** `77c31fff` tem `nivel=3` (nível dinheiro, marcado pelo próprio gerador)
e tinha sido reconfirmado **Balde B 11 vezes seguidas** em corridas anteriores no mesmo dia —
porque agrupa `_appointment_cron_auto_no_show`, que faz `UPDATE appointments SET status='no_show',
deposit_status = CASE WHEN deposit_status='paid' THEN 'retained' ELSE deposit_status END` (decide
reter ou devolver depósito real de cliente). A regra "item agrupado cai inteiro em Balde B, sem
aprovação parcial" já estava consolidada em `permanente/procedural/aprovador-vermelho-triagem.md`.

**Causa raiz (gap na RPC, confirmado por `pg_get_functiondef`):** `robot_emerson_decide` só varre
`titulo + categoria + proposta` contra a regex de palavras vermelhas, e só bloqueia por
`categoria = ANY(['operacao_pedidos','pagamentos','financeiro','dispatch'])`. Nunca lê o campo
`evidencia` (onde `_appointment_cron_auto_no_show` está citado) nem o campo `nivel` (que já vinha
`=3`). A execução concorrente justificou a aprovação exatamente citando essa lacuna ("appointments
não consta na lista [de zonas-protegidas.md]"), ignorando o julgamento de negócio já estabelecido.

**Impacto real avaliado:** baixo/zero — `payload_execucao=null` (proposta é só investigação, sem
escrita automática) e `autonomy_backlog_items` não tinha nenhuma entrada nova nos 6 minutos entre a
aprovação errada e esta correção. Nenhum código/DB foi tocado por causa do erro.

**Ação tomada (dentro do mandato de roteamento, sem tocar lógica de dinheiro):**
1. `UPDATE robot_suggestions SET status='nova', reviewed_at=NULL WHERE id='77c31fff...'` — reverte
   a aprovação errada, sem apagar o registo histórico da decisão errada em `robot_audit_log`.
2. Novo `robot_audit_log` (`operation='emerson_correction:revert_baldeB_wrongly_approved'`)
   documentando a reversão e o gap identificado.
3. Novo `admin_audit_log` (`action='robot_suggestion_baldeB_correcao_reversao'`, id
   `d6d08a01-ccfa-4e7d-87e1-469e98e8efb5`) + reconfirmação normal nº12 (`action=
   'robot_suggestion_baldeB_reconfirmado'`, id `b68c2829-bc08-41de-a059-e6967a5d94fb`).
4. Telegram enviado com sucesso (bridge SSH PC→VPS, `Sent to telegram home channel`,
   chat_id `6731890157`) avisando o Danilo da anomalia + correção + recomendação de fix na RPC.
5. **Não toquei em `29ea4b41` (fica `rejeitada`)** — é duplicado genuíno da mesma evidência
   (mesmas 3 queries lentas), padrão de dedupe já usado antes; manter só um item canónico na fila
   não constitui aprovação de dinheiro.
6. **Não editei a RPC `robot_emerson_decide`** — corrigir o gap (somar `nivel` e `evidencia` ao
   filtro) é mudança de código numa função `SECURITY DEFINER` que decide aprovação de itens
   financeiros → **Lista Vermelha, só proposta.**

## Estado final da fila (`status='nova'`)

| Balde | Item | Motivo |
|---|---|---|
| **B** (dinheiro real — precisa de ti) | `77c31fff-0330-4981-813a-f2268c6f7bbe` — "Investigar e otimizar queries lentas de cron" | nível 3; agrupa `_appointment_cron_auto_no_show` (decide reter/devolver depósito de cliente). Reconfirmado Balde B pela 12ª vez (contando a correção desta corrida). Parado 654,8 min. |

**Balde A nesta corrida:** 0 itens (fila estava vazia dos 2 originais; a única ação foi a
correção acima, que devolveu 1 item a Balde B — não criou nem promoveu nenhum Balde A novo).

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico (tanto o item
`77c31fff` em si, como a proposta de correção da RPC `robot_emerson_decide` para verificar `nivel`
+ `evidencia` antes de aprovar Balde A, prevenindo recorrência).

Auto-Balde-A: **ligado** (`platform_settings.aprovador_vermelho_auto_baldeA = true`) — mas o gap
descoberto mostra que "ligado" ainda pode aprovar Balde B por engano quando a evidência de dinheiro
está fora de `titulo/categoria/proposta`. Recomendo tratar isto como prioridade antes da próxima
corrida com Balde A candidato.

## Fila do carteiro (`estado: zona_vermelha`)
Não verificada nesta corrida — vive na VPS (`orquestracao/`), fora do alcance do filesystem local
desta sessão; o escopo explícito desta tarefa foi a tabela `robot_suggestions`. Sinalizar se precisar
de cobertura também dessa fila numa próxima corrida com acesso à VPS.

## Handoff
`bibliotecario-cerebro` — escopo `agente:aprovador-vermelho` — atualizar
`permanente/procedural/aprovador-vermelho-triagem.md` com: (a) esta anomalia + correção como novo
"Histórico de corridas"; (b) o gap concreto da RPC `robot_emerson_decide` (não checa `nivel`, não
varre `evidencia`) como novo item de conhecimento, para não redescobrir do zero.
