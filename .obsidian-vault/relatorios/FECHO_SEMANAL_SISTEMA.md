# FECHO SEMANAL DO SISTEMA + 2 tarefas do teste do Valdemir — RELATÓRIO

> 2026-08-17 · Motor: Opus 4.8 (PC) · Branch de trabalho: `autonomous-night/fase2-cortex-tasks`
> Verdade = produção via MCP. NÃO toquei em: FK settlements→drivers(user_id), driver_earnings_summary v3,
> settings tvde_cancel_* (só proposta em F2). Cada fase: MARCO + commit + push + analyze 0 erros.

## Resumo executivo
Quatro frentes. **F1 e F3 feitos, provados e commitados** (branch de trabalho). **F2 (dinheiro) pronto e
provado, aguarda "vai"**. Duas pendências humanas não-bloqueantes (RESEND_API_KEY; F2 "vai"). O sistema
de fecho semanal está montado ponta-a-ponta e provado com o acerto real do Valdemir (−€0,80).

## F1 — ECRÃ DE GANHOS (feito · commit d7f7d26)
A tela `DriverEarningsScreen` já existia e já consumia a RPC `driver_earnings_summary`, mas só mostrava
**HOJE** e **ESTA SEMANA**. Acrescentei **SEMANA PASSADA** e **ÚLTIMO ACERTO** (da mesma RPC v3, zero contas
no Dart). O motorista **TVDE** (Valdemir) não achava os ganhos: o home dele apontava para uma tela só de
histórico de corridas — re-apontei o `_openEarnings` para a **tela unificada** (que inclui as corridas TVDE
+ settlement). `analyze` 0 erros.

## F2 — TAXA TVDE estilo Uber (💰 PRONTO + PROVADO · aguarda "vai")
`tvde_cancel_ride`, 3 mudanças: (1) `v_had_driver` = SÓ `driver_id IS NOT NULL` (oferta pendente não é
motorista); (2) fee pós-aceite = taxa **FIXA** `tvde_cancel_fee_cents` (250), não o valor da corrida;
(3) no-show = caminho próprio `tvde_noshow_driver_fee_cents` (350). Migration completo em
`F2_TVDE_CANCEL_PROPOSTA.md`. **PROVA** (simulação SQL da lógica com settings reais): sem aceite→**0**;
pós-aceite pós-graça→**250**; no-show→**350**.

⚠️ **ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.** Com o "vai": aplico a
função + `UPDATE platform_settings SET value='true' WHERE key='tvde_cancel_full_after_grace'` (religar).
Nota: cancelar corrida-de-PLANO pós-aceite passa de 350→250 (se quiseres 350 para plano, digo e ajusto).

## F3 — SISTEMA DE FECHO SEMANAL (feito · commit aa04ca6)
Camada de **comunicação** que corre 2.ª feira **09:00** (cron novo), DEPOIS de todos os crons de settlement.
Não muda cobranças — lê o que os settlements já fecharam e comunica.
- **Compilador** `weekly_closeout_compile` (RPC): junta os 4 settlements (estafetas, TVDE incluído; limpeza;
  serviços; parceiros), normaliza o net (positivo=Bora paga / negativo=deve ao Bora), breakdown por item,
  grava em `weekly_digest_log` (RLS admin). **Provado**: semana 09–16/08 → `to_receive: Valdemir €0,80`.
- **EF** `weekly-closeout-digest`: (a) emails individuais (recibo HTML verde PT-PT) com **GATE do Resend** —
  envia de verdade só ao email do Danilo até o domínio estar verificado; os restantes ficam `aguarda_dominio`
  (prontos, gravados). O setting `weekly_digest_emails_enabled` liga o envio externo. (b) Resumo ao Danilo:
  **push persistente** (via notify-admin-urgent) + Telegram + email. **Provado**: `admin_push=true`, Valdemir
  → `aguarda_dominio`.
- **Painel admin PT-BR** "Acertos da semana": lista quem recebe / quem deve, com MB Way, estado de email e de
  pago; **Marcar pago** (muda só o estado do settlement, com auditoria), **Reenviar**, campo **MB Way do Bora**
  + **toggle** do envio externo. RPCs `admin_*` guardadas por `is_admin`. **Provado** (identidade admin do
  Danilo): lista devolve o Valdemir com breakdown e estado.

## Pendências humanas (não bloqueiam; com guia)
1. **F2 "vai"** — aplicar a função de cancelamento + religar `tvde_cancel_full_after_grace`.
2. **RESEND_API_KEY nas Edge Function secrets do Supabase** — descobri que NÃO está lá (`resend_key_present=false`);
   por isso NENHUM email das EFs sai (nem o antigo da notify-admin-urgent). Sem isto, o push+Telegram funcionam
   e os emails ficam preparados/`aguarda_dominio`. Definir em: Supabase → Edge Functions → Secrets → `RESEND_API_KEY`.
3. **Domínio Resend + toggle** — quando `boraapp.pt` (ou .com) estiver verificado no Resend: ligar
   `weekly_digest_emails_enabled` no painel "Acertos da semana". A partir daí todos recebem o extrato por email.

## Merge para produção
F1 + F3 estão na branch de trabalho, prontos e sem tocar em dinheiro. **Recomendo** trazer F1+F3 (e, com o
"vai", F2) para `autonomous-night-2026-04-29` numa só build. Não fiz o merge sozinho: espero o "vai" do F2
para levar tudo junto (ou faço já F1+F3 se preferires).

## Digest Hermes (8 linhas)
1. Fecho semanal do sistema MONTADO ponta-a-ponta e provado com o Valdemir (−€0,80).
2. F1: tela de ganhos mostra agora HOJE/ESTA SEMANA/SEMANA PASSADA/ÚLTIMO ACERTO; motorista TVDE já a acha do home.
3. F2 (dinheiro): taxa de cancelamento estilo Uber pronta e provada (0/250/350) — aguarda "vai".
4. F3 compilador junta os 4 settlements por pessoa e grava weekly_digest_log com a direção recebe/deve.
5. F3 EF: emails com gate do Resend + resumo ao Danilo (push persistente PROVADO + Telegram).
6. F3 painel admin "Acertos da semana": marcar pago (auditado), reenviar, MB Way do Bora, toggle de envio.
7. Cron novo 2.ª 09:00 depois de todos os settlements.
8. Pendências humanas: F2 "vai"; RESEND_API_KEY nas EF secrets; verificar domínio + ligar envio externo.
