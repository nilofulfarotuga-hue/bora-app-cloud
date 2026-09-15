---
tema: aprovador-vermelho-corrida · escopo: agente:aprovador-vermelho · data: 2026-07-20
---

# Aprovador-Vermelho — corrida FALLBACK 30MIN (2026-07-20, ~10:57 UTC)

## Gatilho
FALLBACK 30MIN — item `nova` mais antigo da fila `robot_suggestions` parado ≥30 min (na prática,
~2h49m). `count=1`. Gatilho normal por item-novo pode ter falhado (falso silencioso) — mecanismo
de segurança a funcionar como desenhado.

## Fila lida (SELECT direto, `status='nova'`)
1 item, sem duplicados, sem sinal de teto 30 / deadlock (fila saudável, longe do teto de 30).

## Triagem

### Balde B — dinheiro/lógica sensível (precisa do Danilo)
- **`8ccc09bb-e5b7-458e-89f9-f179df67f942`** — "Pedido preso sem atribuição"
  (categoria `operacao_pedidos`, dedup_key `operacao_pedidos:pedido-preso-sem-atribuicao`,
  nível 3, severidade 5, criado 2026-07-20T08:07:14 UTC).
  - **Faz:** propõe investigar causa raiz de um pedido preso sem `assigned_driver_id` e ou
    reatribuir manualmente ou implementar "mecanismo de reatribuição automática com TTL".
  - **Risco:** reatribuição automática/TTL toca `dispatch_engine` (zona protegida vermelha) —
    família já conhecida (1ª ocorrência registada em 2026-07-20, ver
    `permanente/procedural/aprovador-vermelho-triagem.md`). Regra "qualquer dúvida → Balde B"
    aplica mesmo sem prova de escrita — a proposta em si já é sobre lógica de dispatch.
  - **Evidência revalidada nesta corrida:** order `7aa2e5f7-75d1-4ef4-b854-e69b2e6fa62b` ainda
    `status='created'`, `payment_status='pending'`, `assigned_driver_id=NULL`, criada
    2026-07-20 05:43:39 UTC — agora **5h13m parada** (era ~1h56m na 1ª surfaçagem). Nenhuma
    evidência nova além do tempo decorrido.
  - **Ação:** reconfirmado Balde B (não promovido). `admin_audit_log`
    `action='robot_suggestion_baldeB_reconfirmado'`, id `aadf36eb-248a-4a32-a903-12165846fc32`,
    `created_at=2026-07-20 10:57:51.54 UTC`, `details.reconfirmacao_numero=2`.
  - ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO (dispatch/reatribuição). Está tudo pronto — confirma que
    eu aplico (ou decide via Central/RPC `robot_approve_plan`).
  - Telegram enviado com sucesso (bridge SSH PC→VPS): "Sent to telegram home channel
    (chat_id: 6731890157)". Gap desde o aviso anterior (08:13:48 UTC) = ~2h44min — muito acima
    do limiar de supressão anti-spam usado noutras corridas (só suprime com gap <20min e zero
    evidência nova); reenvio justificado.

### Balde A — nenhum item nesta corrida (fila só tinha o item acima).

## Estado da flag
`platform_settings.aprovador_vermelho_auto_baldeA = true` (confirmado por SELECT direto). Não
teve efeito nesta corrida porque não havia nenhum item Balde A na fila.

## Fora do normal
Nenhum item novo, nenhum duplicado, nenhum sinal de teto 30/deadlock. O único item da fila é o
mesmo `8ccc09bb` já triado à 1ª surfaçagem (08:13:48 UTC) — staleness esperada de item Balde B
(ver lição em `aprovador-vermelho-triagem.md`), não é bug. O próprio disparo do FALLBACK 30MIN
confirma que o mecanismo de segurança está a funcionar (acorda o agente mesmo que o gatilho
normal por item-novo não tenha disparado de novo, já que este item não é novo).

## Balde A (recomendo aprovar)
Nenhum.

## Auto-Balde-A
`ligado` (`platform_settings.aprovador_vermelho_auto_baldeA=true`) — sem efeito prático nesta
corrida (0 itens Balde A).
