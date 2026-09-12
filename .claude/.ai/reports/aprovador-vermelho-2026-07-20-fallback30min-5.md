# APROVADOR-VERMELHO — FALLBACK 30MIN (6ª corrida, ~11:25 UTC, 2026-07-20)

## Gatilho
Fallback 30MIN: item `nova` mais antigo parado ≥30 min (na prática já ~197 min desde a criação
do item na fila; a ordem subjacente está parada 5h41m). Gatilho pedia triagem completa de TODA a
fila `status='nova'`, não só o item mais recente.

## Fila consultada (SELECT direto, `robot_suggestions.status='nova'`)
1 item — o mesmo desde a 1ª surfaçagem desta manhã (08:13 UTC):

- **`8ccc09bb-e5b7-458e-89f9-f179df67f942`** — "Pedido preso sem atribuição"
  categoria `operacao_pedidos`, dedup_key `operacao_pedidos:pedido-preso-sem-atribuicao`,
  nivel=3, severidade=5, criado 2026-07-20T08:07:14 UTC (197 min parado nesta corrida).

## Triagem (leitura completa do item — proposta + evidência, não só título/categoria)
Proposta completa lida: "investigar causa raiz do pedido preso e reatribuí-lo manualmente OU
implementar mecanismo de reatribuição automática com TTL". Evidência: `orders.id=7aa2e5f7-75d1-
4ef4-b854-e69b2e6fa62b`, reconfirmada por SELECT direto nesta corrida — `status='created'`,
`payment_status='pending'`, `assigned_driver_id=NULL`, criada 2026-07-20 05:43:39 UTC (5h41m
parada agora). Nenhuma mudança de estado desde a 5ª corrida (~11:19 UTC).

**Balde B (sem prova positiva de "só leitura")** — qualquer caminho de execução desta proposta
(reatribuição manual ou mecanismo automático com TTL) toca `dispatch_engine`/atribuição de pedido,
zona protegida vermelha. Não há prova positiva de que a resolução seja apenas leitura/diagnóstico
— regra "qualquer dúvida → Balde B" aplicada, consistente com as 5 reconfirmações anteriores hoje.

0 itens em Balde A nesta corrida (fila só continha este 1 item).

## Ação tomada
- Registo em `admin_audit_log`: `action='robot_suggestion_baldeB_reconfirmado'`,
  `entity_id_text='8ccc09bb-e5b7-458e-89f9-f179df67f942'`, `id=5f23095a-98cb-420d-bfb6-636a0291fa37`,
  `created_at=2026-07-20 11:25:01.608263 UTC`, `details.reconfirmacao_numero=6`,
  `details.surfaced_anterior_id=5fa0e20f-c6da-4642-940b-a24275152e19` — confirmado por `RETURNING`
  real do INSERT.
- **Telegram suprimido** (protocolo anti-spam): último envio real foi na reconfirmação nº2
  (10:57:51 UTC), ~27 min antes desta corrida; evidência idêntica às reconfirmações 3/4/5 (mesma
  order, mesmo status, sem driver) — zero prova nova, reenviar seria spam.
- Nenhuma alteração de lógica de dinheiro/dispatch/pricing/RLS. Nenhuma escrita fora de
  `admin_audit_log` (roteamento/triagem apenas).

## ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO — aguarda "vai" do Danilo
Item `8ccc09bb-e5b7-458e-89f9-f179df67f942` (Balde B) continua a aguardar decisão humana via
Central (`AdminRobotSuggestionsScreen`) ou "vai" no Telegram. Nada foi aplicado.

## Resumo
```
🚦 APROVADOR-VERMELHO — TRIAGE DA FILA 🔴 (2026-07-20, 6ª corrida ~11:25 UTC)
   Fila nova = 1 item
   Balde A (leitura/falso-positivo) — recomendo aprovar:
     (nenhum nesta corrida)
   Balde B (dinheiro real — precisa de ti):
     • 8ccc09bb-e5b7-458e-89f9-f179df67f942 — faz: investigar/reatribuir pedido preso (manual ou
       TTL automático) | risco: toca dispatch_engine (zona protegida)
       ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.
   Auto-Balde-A: ligado (platform_settings.aprovador_vermelho_auto_baldeA=true) — sem efeito
   prático (0 itens Balde A na fila)
```

Sem aprendizado novo de triagem — reforço do padrão já documentado em
`permanente/procedural/aprovador-vermelho-historico-corridas.md` (entrada 2026-07-20).
