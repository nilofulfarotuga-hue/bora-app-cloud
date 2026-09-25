# 🚦 APROVADOR-VERMELHO — TRIAGE DA FILA 🔴 (2026-07-19, corrida ~11:32 UTC)

## Contexto do gatilho
Gatilho reportou: newest=2026-07-19T11:07:12.677728+00:00, count=4 itens `status='nova'`.
Ao chegar a esta corrida (query real às 11:32:53 UTC), **os 4 itens do snapshot já tinham sido
decididos por uma execução concorrente** (padrão conhecido — ver `project_commit_concorrente_colateral_2026-07-14.md`
e `aprovador-vermelho-triagem.md`, corridas múltiplas no mesmo dia). Esta corrida fez só
**verificação read-only** do resultado; não houve escrita nova (evitar Telegram duplicado / RPC
redundante).

## Balde A (leitura/catálogo, não mexe em dinheiro) — já auto-aprovados
- `88bebaed-7e1f-4c0c-916a-b8756f078106` — "Marcar produtos sem foto para revisão manual"
  (`products_no_photo_count=60`). Só marca flag de revisão, não altera visibilidade/preço.
  Status final: `aprovada-emerson`, `reviewed_at=2026-07-19 11:20:14.30 UTC`, `reviewed_by=NULL`
  (mecanismo `robot_emerson_decide`, confirmado por SELECT).
- `86dc8990-a964-421a-85cc-329fb45a0591` — "Marcar produtos sem categoria para revisão manual"
  (`products_no_category_count=30`). Mesma natureza (flag de revisão, zero $).
  Status final: `aprovada-emerson`, `reviewed_at=2026-07-19 11:20:16.45 UTC`.

## Balde B (dinheiro/zona protegida — humano) — reconfirmados, já encaminhados
- `77c31fff-0330-4981-813a-f2268c6f7bbe` (dedup `infra:otimizar-queries-cron-lentas`) e
  `29ea4b41-1e28-420e-a7d3-2995c335d7e5` (`-v2`) — item agrupado: `_cron_check_orphan_orders` (A)
  + `_cron_check_ghost_drivers` (A) + `_appointment_cron_auto_no_show` (B sempre — decide
  reter/devolver depósito de cliente no-show). Regra de item agrupado (confirmada 2026-07-18,
  reconfirmada 6x em 2026-07-19): item inteiro cai em Balde B, sem aprovação parcial.
  Reconfirmados pela 7ª (`77c31fff`) e 5ª (`29ea4b41`) vez às 11:20:34 UTC, `telegram_enviado=true`
  em ambos (`admin_audit_log` ids `89a9222f-6de5-43ba-af2c-6b089590b6a7` e
  `5d0b4954-d785-475e-b06d-1dd6251a7a01`). **Não reenviei Telegram nesta corrida** — só 12 min
  desde o último envio bem-sucedido, sem prova nova (mesmo `evidencia.slow_queries_top3`),
  protocolo anti-spam já estabelecido nas corridas anteriores.
- `01a67895-05fc-4a07-8b98-0bdef3f1c1a2` (`-v3`, mesmo padrão agrupado, mesmo Balde B por regra)
  — **este NÃO foi decidido pelo agente**: `status='aprovada'`, `reviewed_by=c9fccf85-03ee-4efc-83bf-613f211a78ff`
  (confirmado = Danilo, `nilofulfarotuga@gmail.com`, `app_metadata.role=admin`), `reviewed_at=2026-07-19
  11:09:00.75 UTC`, ação `robot_approve_plan`. Interpretação: depois de 6-7 avisos Telegram
  repetidos sobre este padrão recorrente, o próprio Danilo reviu e aprovou via RPC humana
  (JWT admin real) no Central. **Isto é o comportamento correto do sistema** (Balde B só o
  humano decide) — não é uma falha de roteamento do agente, só registo aqui para o rasto.

## Estado final da fila `nova`
2 itens (`77c31fff`, `29ea4b41`) — ambos Balde B já triados/encaminhados, aguardando decisão
humana (padrão recorrente, não uma falha nova). 0 itens pendentes de ação do agente.

## Ações concretas tomadas nesta corrida
Nenhuma escrita nova na base de dados — tudo já estava decidido por execução concorrente antes
desta corrida chegar à fila. Só SELECTs de verificação (`robot_suggestions`, `admin_audit_log`,
`auth.users` para confirmar identidade de `reviewed_by`).

Auto-Balde-A: **ligado** (`platform_settings.aprovador_vermelho_auto_baldeA=true`, confirmado
por SELECT nesta corrida).
