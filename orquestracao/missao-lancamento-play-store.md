--- missao ---
id: missao-lancamento-play-store
tipo: missao
cor: ⚫ Mission (arquiva ao concluir — loops.md)
estado: aguarda_aprovacao_do_plano
autor: claude-code (missão "Do Prompt ao Loop" F3, 2026-07-10)
criada: 2026-07-10
dono: maestro-autonomia
--- fim ---

# 🚀 Missão: Lançar o Bora na Play Store

## Objetivo
App Bora publicada e estável no teste fechado, cumprindo os critérios da Play Store, pronta
para promover a produção.

## Critério de conclusão (quando isto tudo for verdade, a missão arquiva-se)
1. Teste fechado com **12 testadores × 14 dias** completo (requisito Google).
2. Fluxos E2E críticos **verdes 2 ciclos seguidos** (checkout, dispatch, entrega, TVDE).
3. **0 crashes recorrentes** na última semana de teste (hoje: 44/7d — inaceitável).
4. Blockers financeiros verificados: Stripe live (BACKEND_BASE_URL prod) + BUG-MN-004
   (refund cap/idempotency) — com o "vai" do Danilo no que for 🔴.
5. Ficha da Play Console completa (Conteúdo da app + países).

## Decomposição em ordens (EM SEQUÊNCIA — uma de cada vez, a próxima só nasce quando a anterior fechar)

| # | Ordem | Score decision-brain | Estado |
|---|---|---|---|
| 1 | Fechar trabalho TVDE tokens + autocomplete (analyze+test+commit+push) | 13/16 (lançamento 2, risco 2, tempo 2) | ✅ FEITA (ordem-20260710101114-ef7d aprovada; commits 42a57dc+aa4fd18+36bceb9) |
| 2 | Loop E2E single-device montado e smoke verde (runner --single-device, loop-noturno, run-tudo.cmd) | 12/16 (lançamento 2, qualidade, reuso 2) | 🔄 EM CURSO (esta sessão, Fase 7) |
| 3 | Triagem dos 44 crashes/7d (Play Console/logs → top 3 causas → correções zona verde) | 14/16 (lançamento 2, UX 2, receita 1) | ⏳ pendente — 1.ª ordem nova após aprovação do plano |
| 4 | Operação 12×14d: monitor diário dos testadores (monitor_teste_fechado.py) + mensagem de reforço (draft → confirmação) | 12/16 (lançamento 2) | ⏳ pendente |
| 5 | 🔴 Verificar Stripe live mode (BACKEND_BASE_URL prod) — PREPARAR verificação; aplicar = Danilo | 11/16 (risco 0 por ser 🔴) | ⏳ pendente (proposta) |
| 6 | 🔴 BUG-MN-004: refund sem cap + sem idempotency key — verificar e PROPOR fix | 10/16 | ⏳ pendente (proposta) |
| 7 | BUG #15 (P0 conhecido): PIN validado client-side + admin_approve_driver duplicada | 10/16 (risco 🟡) | ⏳ pendente |
| 8 | Ficha Play Console: Conteúdo da app + países (PENDENTE-HUMANO — só UI, conta boraappbora@gmail.com) | 9/16 | ⏳ pendente (Danilo) |

## Estado
- **aguarda_aprovacao_do_plano** — plano enviado ao Danilo no Telegram (encerramento da
  missão 2026-07-10). A ordem #3 só nasce quando o Danilo aprovar E a fila estiver livre.
- Regra (maestro + Concierge rota 7): decompor com decision-brain, UMA ordem de cada vez,
  atualizar esta página a cada fecho de ordem.
