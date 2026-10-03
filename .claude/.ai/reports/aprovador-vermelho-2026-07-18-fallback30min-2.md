---
tema: aprovador-vermelho-corrida · escopo: agente:aprovador-vermelho · estado: atual · atualizado: 2026-07-18
---

# Aprovador-Vermelho — corrida FALLBACK 30MIN (2026-07-18, 20:42 UTC)

Gatilho: `FALLBACK 30MIN` — item `nova` mais antigo parado ≥30min (count=1 reportado).

## Fila (SELECT direto, `ojykpzwqrtusfeakzrna`)
- `status='nova'`: **1 item** (confirmado por COUNT + SELECT).
- Outros status: aplicada=12, aprovada=32, aprovada-emerson=1, expirada=96, rejeitada=41.

## Triagem
- **`9db0124a-964e-4b67-b098-c81a57c576a4`** — "Otimizar queries lentas de cron jobs"
  (categoria performance, nível 3, `dedup_key performance:otimizar-cron-queries-lentas`,
  criado 2026-07-18 20:07:15 UTC, idade ~35 min no momento da triagem).
  Evidência: agrupa `_cron_check_orphan_orders()` + `_appointment_cron_auto_no_show()` +
  `_cron_check_ghost_drivers()` (as 3 queries mais lentas do cron).
  **Veredito: Balde B (item inteiro).** Prova: `_appointment_cron_auto_no_show()` faz
  `UPDATE appointments SET status='no_show', deposit_status=...RETAINED...` — escreve
  dinheiro real (retenção de depósito). Pela regra de item agrupado (confirmada 3x
  independentes em 2026-07-18, ver `permanente/procedural/aprovador-vermelho-triagem.md`),
  quando uma linha da fila agrupa função Balde B com funções Balde A, **o item inteiro** cai
  em Balde B — não há aprovação parcial. Esta é a **4ª reconfirmação no mesmo dia**, mesmo
  veredito.
  - Auto-Balde-A: não aplicável (item não é puro Balde A).
  - Ação: NÃO promovido. `admin_audit_log` id `c71e5629-cae6-4045-8736-6ad16acdf022`
    (action `robot_suggestion_baldeB_reconfirmado`, `reconfirmacao_numero=4`).
  - Telegram enviado com sucesso (`Sent to telegram home channel (chat_id: 6731890157)`),
    via ponte SSH PC→VPS (`docker exec ... hermes send -t telegram`).

## Balde A
Nenhum item Balde A nesta corrida (fila `nova` = só o item acima).

## Flag
`platform_settings.aprovador_vermelho_auto_baldeA` = **true** (confirmado por SELECT).

## Nota
Nenhuma lógica de dinheiro tocada — só roteamento (leitura + `admin_audit_log` + Telegram).
Não editei `_appointment_cron_auto_no_show`, `pricing_service`, `dispatch_engine`, migrations,
nem `platform_settings` financeiros.
