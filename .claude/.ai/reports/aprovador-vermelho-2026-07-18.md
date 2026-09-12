# 🚦 APROVADOR-VERMELHO — TRIAGE DA FILA 🔴 (2026-07-18)

Fila `robot_suggestions` status='nova': **2 itens** (ambos criados 2026-07-18T20:07:15, ciclo `a9162906-9fa6-40b6-80da-ad95ad2c6509`).

## Balde A (leitura/falso-positivo/não-financeiro) — aprovado

- **`ef6350ee-d1b4-4a27-bd98-9bebf1c67ad2`** — "Remover RLS desabilitado em tabelas sensíveis"
  (categoria `seguranca`, nível 3, severidade 4). Tabelas afetadas: `notification_failures`,
  `_backup_categorias_2026_07_18`. **Motivo:** nenhuma das duas é tabela financeira
  (não é `orders`/`wallets`/`ledger_entries`/`bora_tokens`/`wallet_transactions`/`*_balances`/
  `appointment_payouts` — lista de `zonas-protegidas.md`); não altera pricing/dispatch/Stripe/tokens.
  A trava de servidor da própria RPC `robot_emerson_decide` (regex de palavras vermelhas +
  categoria protegida) também não bloqueou — confirmação independente.
  **Ação:** `robot_emerson_decide('aprovada-emerson', motivo)` executado com sucesso
  (flag `platform_settings.aprovador_vermelho_auto_baldeA` = **true**, confirmado por SELECT antes
  de agir). Status agora `aprovada-emerson`. Isto só aprova a *sugestão* — a aplicação real do
  `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` é trabalho de implementação separado (agente
  `seguranca`), sujeito à Trava/Juiz como qualquer mudança de código.

## Balde B (ambiguidade / adjacente a dinheiro) — aguarda o Danilo

- **`9db0124a-964e-4b67-b098-c81a57c576a4`** — "Otimizar queries lentas de cron jobs"
  (categoria `performance`, nível 3, severidade 3). Faz: propõe refatorar/indexar 3 crons —
  `_cron_check_orphan_orders()`, `_appointment_cron_auto_no_show()`, `_cron_check_ghost_drivers()`.
  **Risco:** o filtro mecânico da RPC (regex de palavras vermelhas) NÃO capturou isto — nenhuma
  das palavras `dispatch|pricing|payment|wallet|ledger|payout|...` aparece literalmente. Mas
  `_appointment_cron_auto_no_show` decide quando um agendamento perde o pré-pagamento de €3
  (Reservas Pro) e `_cron_check_orphan_orders` mexe em pedidos órfãos ligados ao ciclo de vida do
  `dispatch_engine`. Qualquer refactor/índice nestas funções pode mudar timing/comportamento de
  lógica financeira-adjacente. **Não alterado** — status continua `nova`.
  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO (adjacente). Está tudo pronto — confirma que eu aplico.
  **Notificação:** push in-system tentado (`PushNotification`) → não entregue (Remote Control
  inativo nesta sessão). Fica registado aqui como o encaminhamento formal — decisão humana
  pendente sobre `9db0124a-964e-4b67-b098-c81a57c576a4`.

Auto-Balde-A: **ligado** (`platform_settings.aprovador_vermelho_auto_baldeA` = true, confirmado
por SELECT ao vivo antes da decisão).

## Handoff
`bibliotecario-cerebro` — escopo: `agente:aprovador-vermelho`. Registo: 1 aprovação Balde A via
`robot_emerson_decide` (audit trail em `robot_audit_log`), 1 item Balde B encaminhado ao Danilo
via push in-system.

## Addendum — reconfirmação (corrida independente, mesma data)
Segunda corrida no mesmo dia (gatilho separado) reconsultou a fila via SELECT direto e confirmou,
de forma independente, os dois vereditos acima:
- `ef6350ee-d1b4-4a27-bd98-9bebf1c67ad2` — já `status='aprovada-emerson'` (fora de `nova`), fora do
  escopo desta reconfirmação; não foi tocado de novo.
- `9db0124a-964e-4b67-b098-c81a57c576a4` — ainda `status='nova'`, reconfirmado **Balde B**: além do
  risco geral de zona financeira-adjacente já descrito acima, a lição
  `permanente/procedural/aprovador-vermelho-triagem.md` estabelece precedente explícito de que
  `_appointment_cron_auto_no_show()` é **Balde B sempre, independente do verbo da proposta**
  (escreve `deposit_status`/retenção de depósito) — como esta sugestão cita essa função junto com
  duas outras confirmadas Balde A (`_cron_check_orphan_orders`, `_cron_check_ghost_drivers`), o
  item agrupado inteiro cai em Balde B (não há aprovação parcial 2/3 numa única linha da fila).
  Continua **não alterado**, `status='nova'`, à espera do Danilo. Registado também em
  `admin_audit_log` (ação `robot_suggestion_baldeB_encaminhado`, entity_id `9db0124a-...`,
  `admin_email='aprovador-vermelho-agent'`) como reconfirmação adicional.
- Flag `platform_settings.aprovador_vermelho_auto_baldeA` reconfirmada `true` por SELECT ao vivo.
- Telegram: sem acesso direto a canal Telegram nesta sessão de reconfirmação (mesma limitação da
  corrida anterior, que também não conseguiu push in-system por falta de Remote Control) — o
  resumo de 2 linhas de `9db0124a` fica pronto acima para entrega na próxima passagem do
  `hermes-aprovador-vermelho.sh`/carteiro, ou leitura direta pelo Danilo neste relatório/na Central.

## Addendum 2 — Telegram entregue (3ª corrida, mesma data)

3ª corrida (gatilho: item novo, newest=2026-07-18T20:07:15.729305, count=2) reconsultou a fila
do zero e reconfirma, independentemente, os mesmos dois vereditos:

- `ef6350ee-d1b4-4a27-bd98-9bebf1c67ad2` — confirmado `status='aprovada-emerson'` (já decidido
  pela 1ª corrida via RPC `robot_emerson_decide`); não retriado, fora do escopo desta passagem.
- `9db0124a-964e-4b67-b098-c81a57c576a4` — reconfirmado **Balde B** pela 3ª vez consecutiva
  (mesmo motivo: agrupa `_appointment_cron_auto_no_show`, Balde B sempre por precedente, junto
  com 2 funções Balde A na mesma linha da fila → item inteiro desce). Continua `status='nova'`,
  **não alterado**.

**Diferença desta corrida:** as 2 corridas anteriores não conseguiram entregar o aviso (push
in-system sem Remote Control ativo; sem acesso a canal Telegram na sessão). Nesta 3ª corrida a
ponte SSH PC→VPS (`ssh -i /c/Users/danil/.ssh/id_ed25519_vps root@srv1786862.hstgr.cloud`)
respondeu `PONG`, e o envio via `docker exec -u hermes hermes-agent-fvnc-hermes-agent-1 hermes
send -t telegram "<resumo>"` foi confirmado entregue: `Sent to telegram home channel (chat_id:
6731890157)`, exit code 0. Registado também em `admin_audit_log` (ação
`robot_suggestion_baldeB_surfaced`, id `7db4bb7a-c1df-4f81-821a-7f205ad351e2`, `entity_id
9db0124a-...`, `details.telegram_enviado=true`) — 2ª entrada de auditoria para este item (a 2ª
corrida já tinha gravado `robot_suggestion_baldeB_encaminhado`).

Flag `platform_settings.aprovador_vermelho_auto_baldeA` reconfirmada `true` por SELECT ao vivo
(inalterada — sem impacto aqui pois não há item Balde A por decidir nesta passagem).
