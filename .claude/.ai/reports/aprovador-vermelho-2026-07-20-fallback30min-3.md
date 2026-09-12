---
tema: aprovador-vermelho-corrida · escopo: agente:aprovador-vermelho · data: 2026-07-20
---

# Aprovador-Vermelho — corrida FALLBACK 30MIN #3 (2026-07-20, ~11:13 UTC)

## Gatilho
FALLBACK 30MIN — item `nova` mais antigo da fila `robot_suggestions` parado ≥30 min (citado no
prompt como "92+ minutos", `count=1`). Mesmo item já coberto pelas duas corridas anteriores de hoje
(`aprovador-vermelho-2026-07-20-fallback30min.md` ~08:13 UTC, `...-fallback30min-2.md` ~11:06 UTC)
— este é o refire seguinte do backoff (fix de backoff exponencial ainda não deployado na VPS), não
um item novo.

## Fila lida (SELECT direto, `status='nova'`)
1 item, sem duplicados, sem sinal de teto 30/deadlock (fila saudável, longe do teto de 30).

## Triagem

### Balde B — dinheiro/lógica sensível (precisa do Danilo)
- **`8ccc09bb-e5b7-458e-89f9-f179df67f942`** — "Pedido preso sem atribuição"
  (categoria `operacao_pedidos`, dedup_key `operacao_pedidos:pedido-preso-sem-atribuicao`,
  nível 3, severidade 5, criado 2026-07-20T08:07:14 UTC).
  - **Faz:** propõe investigar causa raiz de um pedido preso sem `assigned_driver_id` e reatribuir
    manualmente ou implementar "mecanismo de reatribuição automática com TTL".
  - **Risco:** reatribuição automática/TTL toca `dispatch_engine` (zona protegida vermelha) —
    família `operacao_pedidos:*` já reconhecida em
    `permanente/procedural/aprovador-vermelho-triagem.md`. Cai em Balde B sempre.
  - **Evidência revalidada nesta corrida** (SELECT fresco em `orders`, não reaproveitada): order
    `7aa2e5f7-75d1-4ef4-b854-e69b2e6fa62b` ainda `status='created'`, `payment_status='pending'`,
    `assigned_driver_id=NULL`, criada 2026-07-20 05:43:39 UTC — agora **5h29m parada** (era 5h22m
    na corrida anterior). Zero mudança de estado, só o tempo avançou.
  - **Ação:** reconfirmado Balde B (não promovido, não aplicado nada). `admin_audit_log`
    `action='robot_suggestion_baldeB_reconfirmado'`, id `dd34fbb8-37c8-49b5-bf8d-49d8df100e84`,
    `created_at=2026-07-20 11:13:24.40 UTC`, `details.reconfirmacao_numero=4`.
  - **Telegram: suprimido nesta corrida.** Último envio real foi ~15min antes (10:57:51 UTC,
    reconfirmacao_numero=2, `telegram_enviado=true`); a corrida imediatamente anterior (11:06:02,
    reconfirmacao_numero=3) já suprimiu por identidade de evidência. Mesma order, mesmo status,
    zero evidência nova — reenviar agora seria spam.
  - ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO (dispatch/reatribuição). Já avisado no Telegram em corrida
    anterior — está tudo pronto; aguarda o Danilo decidir via Central/RPC `robot_approve_plan`.

### Balde A — nenhum item nesta corrida (fila só tinha o item acima).

## Estado da flag
`platform_settings.aprovador_vermelho_auto_baldeA = true` (confirmado por SELECT direto). Sem
efeito nesta corrida — 0 itens Balde A na fila.

## Fora do normal
Nenhum item novo, nenhum duplicado, nenhum sinal de teto 30/deadlock. O `count=1` citado no
gatilho ("92+ minutos parado") é o mesmo item já triado 3x hoje — staleness esperada de item
Balde B (ver lição em `aprovador-vermelho-triagem.md`), não é bug. Backoff exponencial do fallback
(commitado no repo, ver "Anomalia conhecida" na mesma lição) ainda não deployado na cópia LIVE da
VPS — explica o refire a curto intervalo (~7min desta vez) em vez de já espaçar para 60min+.
Comportamento do agente permanece correto (não reenviar spam) mesmo com o script a disparar cedo.

## Resumo objetivo
- Itens na fila: **1**.
- Balde A promovidos: **0**.
- Balde B (aguarda Danilo): **1** — `8ccc09bb-e5b7-458e-89f9-f179df67f942` (já avisado por
  Telegram em corrida anterior; nesta corrida só reconfirmado em auditoria, sem reenvio).
- Lista Vermelha tocada: **sim, mas sem promoção/aplicação** — item cita `dispatch_engine`
  (reatribuição/TTL de pedido), 100% PROPOSE-ONLY, nada aplicado.

## Auto-Balde-A
`ligado` (`platform_settings.aprovador_vermelho_auto_baldeA=true`) — sem efeito prático nesta
corrida (0 itens Balde A).
