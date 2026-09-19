# Relatório — Assinatura TVDE Segunda a Sexta + Admin "Coberta pelo plano"

**Data:** 2026-07-07
**Escopo:** só display (app cliente + admin). Backend confirmado já feito via MCP — nada foi tocado em RPCs/migrations/settings.

---

## PARTE 1 — Ecrã de planos (cliente)

**Ficheiro:** `lib/screens/client/tvde/tvde_plans_screen.dart`

Antes, os 3 cards de plano tinham tudo **hardcoded**: preços `€56/€105/€180` e `14/30/60` corridas — valores antigos, já não batiam com o backend.

Mudanças:
- **Preço puxado do backend em runtime** via nova função `TvdeStore.planPriceCents(plan)` → RPC `tvde_plan_price_cents`. Confirmei ao vivo na base (MCP `execute_sql`) que hoje devolve: semanal **4000¢ (€40)**, quinzenal **7000¢ (€70)**, mensal **13200¢ (€132)**. Enquanto carrega, o card mostra "A carregar…" e o botão "Quero aderir" fica desativado (evita comprar com preço errado se a RPC demorar).
- **Total de corridas corrigido para 10 / 20 / 44** (era 14/30/60). Confirmei ao vivo que `admin_grant_subscription` e `tvde_activate_paid_subscription` (as duas vias de ativação — admin manual e pagamento Stripe/MBWay) já geram `rides_total = 10/20/44` com o comentário explícito "Planos SEGUNDA A SEXTA: 2 corridas/dia útil".
- Cada card agora mostra: **"X corridas · Segunda a Sexta · 2 por dia útil"**.
- Adicionei um aviso fixo acima dos planos: *"Válido Segunda a Sexta. Aos fins de semana (sábado e domingo) as corridas não são cobertas pelo plano — paga-se a tarifa normal."*
- No card da **assinatura ativa** (quem já tem plano), acrescentei a legenda "Segunda a Sexta · fim de semana não incluído" por baixo do nome do plano.
- O preço passado ao picker de pagamento (`ReservationPaymentMethodSheet`) agora é o mesmo valor da RPC (`_priceCents[plan] / 100`) — deixou de ser um número solto no código. A cobrança real continua 100% server-side (Edge Function `tvde-plan-payment` + `tvde_activate_paid_subscription`), isto só corrige o valor mostrado no ecrã de confirmação.

### Achado extra (fora do pedido, mas relevante) — `tvde_preview_coverage`
A RPC que alimenta o preview "Incluída no plano" no ecrã de pedir corrida (`tvde_request_ride_screen.dart`) **não checa o dia da semana** — só a RPC de consumo real (`tvde_consume_subscription_ride`, chamada no fim da corrida) é que bloqueia fim de semana. Ou seja: sem alteração, um cliente com plano ativo veria "Grátis · incluída no plano" ao pedir uma corrida ao sábado, mas ao terminar a corrida o backend cobraria a tarifa normal em dinheiro (o `tvde_consume_subscription_ride` recusa com `weekend_not_covered`) — promessa quebrada na hora de pagar.
Como isto é só **display** (a RPC de consumo já está certa — dinheiro não é afetado, só a expectativa mostrada antes de pedir), corrigi no cliente: se hoje é sábado/domingo, a app já não mostra "Incluída no plano" (replica a mesma regra Segunda-Sexta do lado da UI, sem tocar a RPC). Fica registado aqui para o caso de quereres alinhar `tvde_preview_coverage` no backend também (não é urgente porque não mexe em dinheiro real).

---

## PARTE 2 — Admin: tag "Coberta pelo plano"

**Ficheiro:** `lib/screens/admin/admin_tvde_rides_screen.dart` (aba Corridas — Ao Vivo/Histórico)

- Confirmei ao vivo que a RPC `admin_tvde_rides_list` **já devolve** `used_subscription_ride`. Acrescentei, ao lado da tarifa (topo do card), uma tag verde **"Coberta pelo plano"** quando `used_subscription_ride = true` — para não confundir leitura de receita quando a tarifa aparece €0,00 (o €0 está correto: a receita entrou na compra do plano, não nesta corrida).

⚠️ **`admin_tvde_cancellations`** (ecrã `admin_tvde_cancellations_screen.dart`, relatório de cancelamentos) **NÃO devolve `used_subscription_ride`** — confirmei a definição da função ao vivo via MCP. Como instruído, **não mexi na RPC**. Não dá para mostrar a tag lá até adicionares essa coluna ao `SELECT`/`jsonb_build_object` dessa função (é aditivo, sem risco — só falta o campo). Aviso para adicionares via MCP quando quiseres.

---

## Verificação

- `flutter analyze` nos 4 ficheiros alterados: **0 erros**. Os 9 avisos "info" que aparecem já existiam antes (linhas não tocadas por mim — confirmado comparando antes/depois); nenhum aviso novo introduzido pelas minhas alterações.
- **Não consegui testar no Redmi.** Tentei `flutter run -d 23028RN4DG`: o Gradle crashou por falta de memória (ambiente tem ~4GB RAM total, ~45MB livres no momento do build — mesmo limite já documentado no projeto para `flutter analyze` em paralelo). Não insisti para não gastar mais tempo numa maratona de crashes.
  Em vez disso, confirmei a correção **lendo os valores reais ao vivo na base** (MCP `execute_sql`): os preços e totais de corridas que a app vai buscar por RPC batem exatamente com o que o ecrã agora mostra (€40/€70/€132 e 10/20/44). Recomendo um teste visual rápido manual quando tiveres oportunidade — não há garantia substituta a 100% de ver o ecrã renderizado.

---

## Commit

`git push origin autonomous-night-2026-04-29` — ver commit `fix(tvde): assinatura Segunda-Sexta dinâmica (preço+corridas do backend) + admin tag "coberta pelo plano"`.

**Não toquei em:** `dispatch_engine`, `pricing_service.dart`, `finalizePurchase`, `bora_tokens`, Stripe webhook, RLS de `orders`/`wallets`/`ledger`, nenhuma RPC/migration/setting. `versionCode` não foi alterado.
