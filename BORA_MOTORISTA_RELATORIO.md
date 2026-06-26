# BORA MOTORISTA (TVDE) — RELATÓRIO FINAL DA VERTICAL

> Fecho das Fases 1–6. Vertical de transporte de passageiros (estilo Uber, preço
> fixo Guarda), **categoria escondida** só visível ao cliente após aprovação do
> admin. **100% isolada** do delivery. · 2026-06-26 · CEO-AI / Claude Code.

---

## 1. O QUE FICOU PRONTO (6 fases)

| Fase | Entrega | Estado |
|---|---|---|
| **1 — Backend** | 6 tabelas isoladas (`tvde_rides`, `tvde_access_requests`, `tvde_ride_events`, `tvde_subscriptions`, `tvde_ride_counters`, `tvde_driver_balances`) + coluna `users.tvde_access` + `tvde_calculate_fare()` + 17 RPCs + 13 chaves `platform_settings` + RLS. | ✅ em prod |
| **2 — Dispatch passageiros** | Motor próprio (`tvde_offer_to_next`, `tvde_dispatch_sweep`, trigger `fn_tvde_dispatch_on_request`, cron) — escolhe motorista `carro_passageiros` online mais próximo (haversine), oferta com TTL, **recusa → rotação** ao próximo (fix `tried_driver_ids`), sem motorista → `sem_motorista`. | ✅ em prod |
| **3 — App Cliente (PT-PT)** | `TvdeStore` + 6 ecrãs (desbloqueio/estado, pedir corrida c/ Places + preço estimado, tracking mapa, avaliar, histórico, planos). Tile escondido na home só se `tvde_access=true`. | ✅ |
| **4 — App Estafeta (PT-PT)** | `carPassengers` no enum + opção 🚗 no cadastro + 4 ecrãs (home passageiros, oferta c/ timeout, corrida ativa a caminho→cheguei→iniciar→finalizar, avaliar). Reusa heartbeat/GPS/FCM. | ✅ |
| **5 — Painel Admin (PT-BR)** | 4 ecrãs (pedidos de acesso c/ perfil + aprovar/recusar/revogar, corridas ao-vivo+histórico+financeiro+CSV, motoristas, assinaturas) + 4 RPCs `admin_tvde_*_list`. | ✅ em prod |
| **6 — Verificação + ícone + push** | Ícone próprio da categoria, checklist §9 verde, 1 bug apanhado e corrigido, relatório, 1º push. | ✅ (este doc) |

---

## 2. PROVA FINANCEIRA (smoke ao vivo, ROLLBACK)

Tarifa (`tvde_calculate_fare`): base 500c até 6km + 50c/km extra.
Ganho motorista (no `finish`): base 400c + 40c/km extra. `bora_cut = fare − driver_earn`.

| Distância | Cliente paga | Motorista recebe | Bora fica |
|---|---|---|---|
| 3 km | €5,00 | — | — |
| 6 km | €5,00 | — | — |
| **10 km** | **€7,00** (700c) | **€5,60** (560c) | **€1,40** (140c) |

✅ Confirmado no ciclo completo executado contra a base de produção (em transação
com `ROLLBACK`, zero resíduo): `final_fare_cents=700`, `driver_earn_cents=560`,
`bora_cut_cents=140`, e o saldo isolado do motorista subiu **€1,40** em
`tvde_driver_balances`.

---

## 3. CHECKLIST §9 — RESULTADO

- **ACESSO:** pedir acesso → admin aprovar (`tvde_access=true`). ✅
- **CLIENTE:** solicitar corrida (10km, preço estimado €7) → auto-dispatch. ✅
- **ESTAFETA:** ofertar → **recusar → rotação ao próximo** (fix Fase 2) → aceitar
  → cheguei → iniciar → finalizar (tarifa correta). ✅
- **Bidirecional:** cliente avalia motorista + motorista avalia cliente. ✅
- **BACKEND:** liquidação cash isolada (`tvde_driver_balances`); recusa→rotação;
  `sem_motorista` quando não há motorista elegível. ✅
- **Migrations no disco:** `20260626100000`→`100006` presentes e consistentes com prod. ✅
- **`flutter analyze`:** **0 erros** (185 info + 10 warnings, todos pré-existentes;
  **0 em ficheiros TVDE** — só lints cosméticos `prefer_const`). ✅
- **`flutter build apk --debug`:** compila. ✅
- **Supabase advisors (security):** **0 ERROR**. Os 16 WARN TVDE são o padrão
  intencional `SECURITY DEFINER` + `REVOKE public/anon` + `GRANT authenticated`
  (igual a todas as ~300 RPCs do projeto). ✅

### Bug apanhado e corrigido nesta fase
`tvde_request_access()` notificava o admin com `severity='warning'`, mas
`admin_notifications` só aceita `low|medium|high|critical` → o pedido de acesso
**rebentava** com violação de CHECK. Corrigido para `'medium'` no ficheiro-fonte
(`20260626100001`) **e** aplicado a prod via migration aditiva
`20260626100006_tvde_fix_access_request_severity.sql`. Re-verificado: ciclo 100% verde.

---

## 4. ISOLAMENTO CONFIRMADO (0 toques em zonas protegidas)

- Cash da corrida vai **só** para `tvde_driver_balances` (mirror de `driver_balances`).
  **Nunca** `ledger_entries`, `order_financials`, `orders`, nem triggers de orders.
- `tvde_calculate_fare` é função própria — **não** toca `pricing_service` / `pricing_calculate`.
- Dispatch de passageiros é motor próprio — **não** toca `dispatch-engine` nem o
  `DispatchEngine` Flutter.
- Único ponto partilhado é aditivo e retro-compatível: `VehicleType.carPassengers`
  (novo valor) e o tile escondido na home (gated por `tvde_access`).

---

## 5. PENDENTES — DECISÃO / AÇÃO DO DANILO (não do código)

1. **Pagamentos cartão + MB Way** (corridas e compra de assinatura) → **Fase 7**
   (reusar o seam de pagamento do delivery). Hoje: só **cash** + assinatura
   concedida pelo admin.
2. **Valor da taxa de cancelamento** — hoje `tvde_cancel_fee_cents=0`
   (configurável em `platform_settings`). Estados já implementados; falta o valor.
3. **Licença IMT / legislação TVDE** — responsabilidade legal do Danilo (fora do código).
4. **TESTE NO DEVICE FÍSICO** — push da oferta a chegar, mapa a mexer, tocar e
   aceitar. **Só o Danilo** consegue (instalar o build do CI no telemóvel).

---

## 6. PRÓXIMO PASSO

Após o push, aguardar **~10–15 min** o build aparecer no **Play Internal Testing**,
instalar e fazer o teste no device. Depois disso: Fase 7 (pagamentos).
