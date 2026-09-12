# AUDITORIA GERAL PRÉ-LAUNCH — 2026-06-12

**Modo:** 100% leitura (zero alterações em código/DB/config). Orquestrador Fable 5 + 8 sub-agentes paralelos (Sonnet).
**Âmbito:** Matemática financeira (DB real via MCP) · Qualidade de código · Gaps vs Glovo/Uber Eats/iFood · Performance/robustez.
**Fora de âmbito:** Segurança (auditoria já feita em 2026-06-12 via MCP).
**Fontes:** `business_rules.md`, `00_BORA_DNA.md` (2026-06-10), produção Supabase `ojykpzwqrtusfeakzrna`, repo `bora_app` @ `cfe80d0`.

---

## 1. RESUMO EXECUTIVO (PT-BR, para o Danilo)

A boa notícia: **o coração financeiro está certo**. Recalculei na mão pedidos reais e os totais batem ao centavo — markup 15%/5%, taxas de entrega, sacolas, buffer Stripe, fechamento semanal do entregador (até o saldo negativo de −€3,38 está exato), tokens (ROUND×3, +40/+50, validade 60d, FIFO). Os 8 parâmetros de `platform_settings` estão na especificação.

A má notícia: achei **6 bloqueadores** para corrigir antes do lançamento: (1) não existe limite de distância — já existe um pedido real com 9.125 km e taxa de entrega de €4.563; (2) o desconto máximo de 50% em tokens **não está implementado** — dá para pagar 100% do pedido com tokens/wallet; (3) o stacking de parceiro paga só €3 no 2º pedido (o documento diz base+km+€3 — precisa da sua decisão); (4) a tela do entregador calcula preço com 15% fixo no código, fora do PricingService; (5) o app do cliente carrega os 45 mil produtos na memória ao abrir (45 requests — lento no 4G); (6) não há informação de alergênios (obrigação legal na UE).

Nada disso é estrutural — são correções cirúrgicas. Os prompts prontos estão na secção 7.

---

## 2. 🔴 BLOQUEADORES DE LAUNCH (corrigir antes de lançar)

| # | Bloqueador | Evidência | Esforço |
|---|---|---|---|
| **B1** | **Sem cap de distância no `create_order`** — GPS corrompido gera pedido válido com taxa astronómica | Pedido real `7efdca55-2e97…`: `distance_km=9125`, `delivery_fee=€4.563,00`, buffer Stripe seria €5.254 (foi cancelado, mas nada impede repetição) | **S** (~1h): validação `distance_km ≤ 15` na RPC + erro amigável no Flutter |
| **B2** | **Stacking parceiro: código paga SÓ €3,00 flat no 2º pedido; docs dizem `€3,80+€0,20×km+€3`** | `pricing_calculate` com `p_is_stacked_partner=true` retorna apenas o bónus (comentário no código: "2026-05-16 FIX: stacked = bonus ONLY"); `recalc_driver_earnings_on_stack` idem. business_rules.md §2.2.1 e DNA §3 dizem o contrário | **Decisão Danilo** (qual versão vence?) + **S**: ou 1 migration (corrigir fórmula) ou 15 min (corrigir docs) |
| **B3** | **Cap de 50% de desconto em tokens AUSENTE** — cliente pode pagar 100% do pedido em tokens+wallet | Nenhum enforcement em `create_order`, `consume_tokens` nem `wallet_debit_for_order` (este só limita ao total = 100%). Regra imutável §4.3 | **S-M** (~2h): cap server-side + mensagem no checkout |
| **B4** | **Pricing fora do PricingService no ecrã do estafeta** — `_markupPctDisplay = 0.15` hardcoded recalcula o total localmente | `driver_map_screen.dart:2567,2594,2803` — se o setting mudar, estafeta vê valor errado; viola "fonte autoritativa única" §2.6 | **S** (~30min): usar valores gravados no pedido em vez de recalcular |
| **B5** | **Arranque do cliente carrega os ~45.000 produtos para memória** — 45 requests sequenciais de 1.000 rows no `initState` da home | `restaurant_store.dart:218-249` (loop `while(true)` com range) chamado por `client_home_screen.dart:62`; em 4G fraco = primeira impressão péssima + RAM + dados móveis | **M** (1 sessão): arranque carrega só lojas/categorias; produtos on-demand por `restaurant_id` (paginação já existe) |
| **B6** | **Alergénios ausentes** (Reg. UE 1169/2011 — venda à distância de alimentos exige info de alergénios) | Zero hits `alerg|allergen` em `product_detail_screen`/`restaurant_menu_screen`; Uber Eats/Glovo têm | **S** mínimo legal (~2h): nota por restaurante "Alergénios: contacte o restaurante" + campo opcional; **M** completo (campo por produto) pós-launch |

---

## 3. 🟡 IMPORTANTES (primeiras 2 semanas pós-launch)

**Financeiro / dados**
1. **No-show de reserva sem registo contabilístico** — `auto_close_no_show_reservations` marca o status mas não cria ledger entry do €3 retido; o €1 da Bora na comparência também não tem registo explícito (`partner_reservation_payouts` está vazia). Receita real fica invisível nos relatórios.
2. **Crédito `restaurant_menu_credits` de €2 ao cliente na comparência** existe no código (`partner_mark_arrival`) mas **não está documentado** no DNA/business_rules — documentar ou remover (decisão).
3. **Dois mecanismos de split de refund coexistem** — `compute_refund_split` (proporcional ao método de pagamento, §8.4.2) e `wallet_credit_refund_split` (80/20 wallet/tokens, DNA). Ambos têm base documental, mas **mapear que fluxo chama qual** (`admin_cancel_order`, `request_order_cancel`) e validar com 1 refund de teste.
4. **`customer_total` desatualizado quando sacos sobem pós-compra** — pedidos `97720bfb` (−€0,10) e `8c0649bb` (−€0,20): `final_total` correto (cliente pagou certo), mas `customer_total` ficou com o snapshot da criação → relatórios de reconciliação enganadores.
5. **Pedidos de teste com earnings inconsistentes** (2026-05-27): `898fa066`/`e360def1` (€3,00 p/ 4,77 km, driver_id NULL) e `839c6b48` (€5,30 vs €4,04 esperado) — entraram no settlement da semana 25–31/05. Limpar/marcar `is_test_order` antes do launch para não sujar histórico.
6. **Itens JSONB de pedidos pré-B1** gravados com preço base sem markup (`auc-788275`: 4,99 vs 5,74) — totais corretos (server-side), só o histórico visual ao cliente fica errado. Sem ação obrigatória; saber que existe.

**Performance / robustez (DB)**
7. **`cleanup_payment_drafts` falhou 10+ vezes em 7 dias** ("job startup timeout") — colide com 3 outros jobs às :00/:15/:30/:45. Reescalonar para minutos desfasados (ex.: `7,22,37,52`).
8. **`robot-b-hourly` e `robot-b-weekly-digest` estão ATIVOS** — a decisão T7 era OFF até launch; a EF `robot-b` corre 7,8–24s a cada hora (custo + carga constante).
9. **RLS `auth_rls_initplan` em 118 policies** (orders, drivers, products, ledger_entries, bora_tokens, appointments) — trocar `auth.uid()` por `(SELECT auth.uid())`; é a causa nº 1 de lentidão futura com volume.
10. **`drivers` com 4,6M seq scans (100%)** — `bora_dispatch_maintenance()` varre a tabela toda a cada ciclo; criar índice composto p/ o predicado real (ex.: `(is_online, last_heartbeat)`). `restaurants` 99% seq scan idem.
11. **FKs sem índice** em tabelas quentes: `restaurants.user_id`, `support_tickets.order_id`, `promo_code_uses`, `appointments.service_id` (30 no total fora backups).

**Performance (Flutter)**
12. **`Image.network` sem cache nas listas de produtos** — `store_products_screen.dart:796,1228,1363,1597,1627`, `restaurant_menu_screen.dart:468`, `driver_map_screen.dart:2391,2741`; `cached_network_image ^3.4.1` JÁ está no pubspec, é só usar (+ `memCacheWidth`).
13. **`context.watch<RestaurantStore>()` dentro da grelha de produtos** (`store_products_screen.dart:711,184-185`) — qualquer `notifyListeners` reconstrói o ecrã inteiro; granularizar com `select`/`Selector`.
14. **Queries unbounded**: admin orders sem `.limit()` (`order_store.dart:184-185`), `product_variants` inteiro no arranque (`restaurant_store.dart:328`), histórico cliente sem limit.
15. **Timer fallback do OrderStore** (30s, `order_store.dart:164-166`) dispara rebuild cego em todos os consumers — avaliar remoção pós-estabilização do realtime.

**Produto (paridade Glovo/Uber — confirmados nos 2)**
16. **Self-service "faltou item / problema com pedido"** no detalhe do pedido (hoje: só chat/suporte manual) — com volume real, vira gargalo de suporte.
17. **Repetir pedido (reorder 1 toque)** + **filtros na lista de lojas** (rating/ETA) — retenção básica.
18. **Social login** — skeleton existe (`register_client_screen.dart:319,332`) mas providers não configurados; **garantir flag OFF no launch** (se os botões aparecem sem provider → crash de auth) e ativar nas 2 semanas.
19. **Parceiro: "busy mode"/pausar loja + ajustar tempo de preparação** — Glovo e Uber têm; evita má experiência em pico.
20. **Navegação externa (abrir Google Maps/Waze)** no fluxo do estafeta.

**Código / housekeeping**
21. **`order_eta_service.dart:108-109` lê campos `@Deprecated`** (`order.driverLat/Lng`) — risco de ETA errado; migrar para `DriverStore.currentDriver.location`.
22. **`register_partner_screen.dart:31` `_formKey` unused** — formulário de registo de parceiro pode estar sem validação ativa + 4 imports mortos no mesmo ficheiro.
23. **PT-BR em ecrã de cliente**: `support_screen.dart:24` "Na tela inicial…" (regra: apps PT-PT). 5 min.
24. **Órfãos**: `client_favorites_screen.dart` (zero callers — ligar ou remover), `login_screen.dart` legado (rota `/login` nunca invocada).
25. **Deps críticas desatualizadas** — `flutter_stripe` 10.2→13.0 (3 majors), `flutter_local_notifications` 17→22, `geolocator` 10→14, `flutter_foreground_task` 8→9, `firebase_*` 1 major. ⚠️ **NÃO fazer upgrade às cegas antes do launch** (Stripe major = risco); planear janela de upgrade + teste E2E nas 2 semanas.

---

## 4. 🟢 MELHORIAS (backlog)

- **35 tabelas `_backup_*` (26 MB) em produção** — arquivar/exportar e dropar pós-launch; poluem planner e advisors.
- **104 índices nunca usados** — rever e dropar (custo de escrita).
- **313 combinações de policies permissivas sobrepostas** — consolidar (performance, não segurança).
- **~50 scripts `.ai_*` + screenshots na raiz do repo** — mover para pasta ignorada/arquivo.
- **`flutter analyze`: 0 errors / 11 warnings / 139 infos** — limpar warnings (lista no achado A5); subir `flutter_lints` 3→6; corrigir `Radio`/`TextFormField` deprecated nos ecrãs admin.
- **`product_detail_screen.dart:162`** aplica ×1,15 sobre (base+extras) — confirmar paridade exata com o T1 do `create_order` quando houver pedidos reais com options.
- **`refund_choice_dialog.dart:65`** fallback `_tokenValueCentsX100=50` hardcoded e campo unused — limpar.
- **BoraTileCard() legacy** na categoria Serviços sem PNG (`client_home_screen.dart:537`) — criar `cat_servicos.png`.
- Paridade adicional (não bloqueante): agendamento de entrega, recibo PDF ao cliente, avaliações com foto, histórico com filtros, dark mode, heatmap estafeta, promos criadas pelo parceiro, subscrição tipo Prime.
- **Vantagens Bora a usar no marketing** (nenhum concorrente tem na Guarda): reservas de mesa integradas · marcações de serviços (barbearia) · enviar encomendas · levar compras · compras assistidas em mercados não-parceiros · MB Way nativo · tokens 3% + referral · chat em tempo real cliente↔estafeta · preços de mercado = site oficial (sem inflação de plataforma) · suporte humano local.

---

## 5. TABELA COMPLETA — MATEMÁTICA FINANCEIRA (Área 1)

Recalculado à mão sobre produção (pedidos desde 2026-06-05 + funções SQL via `pg_get_functiondef`).

| REGRA | ESPERADO | REAL (evidência) | DIVERGÊNCIA | SEV |
|---|---|---|---|---|
| `platform_settings` (8 chaves pricing) | 0.15/0.05/250/0.10/0.05/30/10/150 | Todos exatos | — | OK |
| Não-parceiro: preço cobrado = base×1,15 | ex.: 4,25→4,89; 2,99→3,44; 4,99→5,74 | `subtotal` server-side correto nos 4 pedidos verificados; `create_order` aplica ×1,15 sobre `products.price` | — | OK |
| Display = cobrado (fix B1) | item.price com markup + basePrice | Pós-B1 ✅ (`32b97c20`); pedidos PRÉ-B1 têm `items[].price` sem markup no JSONB (histórico visual) | Só histórico | 3→info |
| Taxa serviço não-parceiro €2,50 fixa | 2,50 | 2,50 em todos os storeShopping | — | OK |
| Taxa serviço parceiro 5%×subtotal | 3,00→0,15 | `898fa066`: 0,15 ✅ | — | OK |
| Entrega €2,50 até 4km; +€0,50/km | 2,28km→2,50; 6,88km→3,94; 4,77km→2,88 | Exato ao cêntimo nos 5 casos | — | OK |
| **Cap de distância** | implícito (não existe regra) | `7efdca55`: 9.125 km → €4.563,00 | **Sem validação** | **4** |
| Saco restaurante não-parceiro €0,30 / mercado €0,10×sacos (cap 5) | 0,10/0,20/0,30 | Corretos (GREATEST(1,bags)) | — | OK |
| `customer_total` = soma das parcelas | `32b97c20`: 4,89+2,50+3,94+0,10=11,43 | 11,43 ✅; mas `97720bfb`/`8c0649bb` com snapshot de 1 saco (final_total certo) | −€0,10/−€0,20 no campo | 2 |
| Parceiro 10+5+5 (colunas dedicadas) | 10%=0,30; 5%=0,15; 5%=0,15 s/ subtotal 3,00 | `898fa066` exato; item.price = preço parceiro (markup já embutido) | — | OK |
| Buffer Stripe +15% só não-parceiro | 11,43→13,14; parceiro 1× | `payment_buffer_total` 13,14 / 6,33 ✅ | — | OK |
| Estafeta não-parceiro storeShopping: 3,80+0,80+0,20km+30%×boraNet | 5,29 / 5,30 | `8c0649bb`=5,29 ✅; `97720bfb`=5,30 ✅ (boraNet = subtotal×0,15+fees−fixed confirmado na função) | — | OK |
| Estafeta parceiro: 3,80+0,20×km | 4,75 (4,77km) / 4,04 (1,2km) | `898fa066`/`e360def1`=3,00 (driver_id NULL, teste?); `839c6b48`=5,30 | Dados de teste de 27/05 | 3 |
| **Stacking parceiro: base+km+€3 (docs)** | 2º pedido = 3,80+0,20km+3,00 | `pricing_calculate`: **€3,00 flat** (comentário "stacked = bonus ONLY" 2026-05-16) | **Docs ≠ código — decisão** | **4** |
| Logística €4,00+€0,50/km+€0,80 | — | Sem pedidos reais; fórmula presente na função | Não testável | — |
| Apartamento €1,50 (€1 estafeta) | — | Sem pedidos reais; setting=150 e fórmula corretos | Não testável | — |
| Gorjetas 80/20 | — | Sem gorjetas reais (tip=0 em todos) | Não testável | — |
| Fecho semanal estafeta (semana 08–14/06) | 5,29+5,30=10,59 earnings; cash 8,74+10,94=19,68; net=10,59−19,68+5,71=−3,38 | `driver_weekly_settlements` `51048ed0`: **−3,38 exato** ✅ | — | OK |
| Crons fecho/payout | fecho 00:05 seg → payout 03:00 seg, mín €10 | `close-weekly-settlements` `5 0 * * 1`; `bora_weekly_auto_payout` `0 3 * * 1`; threshold €10 na função | — | OK |
| Tokens cliente ROUND(total×3) mín 1 | 5 grants verificados | `GREATEST(1, ROUND(price*3))` + dados ✅; expiry 60d ✅; FIFO `ORDER BY expires_at` ✅ | — | OK |
| Tokens estafeta +40/+50 | CASE is_partner_store | Todos os grants corretos | — | OK |
| **Desconto tokens máx 50%** | cap no checkout | **Nenhum cap em nenhuma função** (wallet_debit limita a 100%) | **Regra não implementada** | **4** |
| Reserva mesa: cancel 2h (DNA) | 2h | `reservation_cancel_window_hours=2` ✅ (business_rules.md antigo diz 4h → **atualizar docs**) | Docs desatualizadas | 1 |
| Reserva mesa comparece: €2 parceiro/€1 Bora | payout €2 + €1 residual | `partner_mark_arrival` paga €2 (+€2 crédito menu ao cliente, não documentado); €1 Bora sem ledger; payouts nunca executados em prod | Registo contabilístico incompleto | 3 |
| Reserva mesa no-show: €3 Bora | ledger do €3 | Status muda, **zero registo contabilístico** (retenção implícita no Stripe) | Sem ledger | 3 |
| Serviços: sinal €3; fee Bora €0,50; <24h/no-show €0,50+€2,50 | settings/schema | `appointment_deposit_cents=300` ✅; `appointment_payouts` com schema certo mas **vazia** (nunca exercitado); 1 no-show de teste com deposit=0 | Fluxo nunca corrido em prod | 2 |
| Wallet refund 80/20 | 80% saldo+20% tokens | `wallet_split_free_pct=0.80` + função correta; **zero refunds reais** para validar | Não testável | — |
| Dívida wallet em cash delivery | trigger | `apply_client_debt_settlement_on_cash_delivery` + `wallet_max_negative_balance_cents=-1000` ✅ | — | OK |
| Extras/toppings (T1) | price_add somado antes do ×1,15 | Implementado em `create_order` ✅; **zero pedidos com options em prod** → impacto histórico **€0,00** | — | OK |

**Veredicto Área 1:** fórmulas core e fecho semanal CORRETOS ao cêntimo. Os problemas reais são de **regra ausente** (cap distância B1, cap 50% B3), **divergência docs↔código** (stacking B2, janela 2h/4h), e **registo contabilístico** (reservas/no-show §3.1).

---

## 6. METODOLOGIA E LIMITES

- 8 sub-agentes paralelos com scope fechado: A1 matemática cliente · A2 estafeta+fecho · A3 tokens/marcações/wallet/extras · A4 órfãos/duplicação · A5 analyze/deps/idioma · A6 gaps concorrentes · A7 perf DB/EF/crons · A8 perf Flutter. Achados cruzados e deduplicados pelo orquestrador; severidades recalibradas.
- **Volume de produção ainda é pré-launch** (5 pedidos delivered, 1 reserva, 7 marcações) — fórmulas de logística, apartamento, gorjetas, refunds e payouts de reservas/serviços foram verificadas **no código SQL** mas nunca exercitadas com dinheiro real. Recomenda-se 1 pedido de teste de cada tipo no dia do launch.
- A classificação do A6 (reorder/self-service como "bloqueador") foi **recalibrada para 🟡** pelo orquestrador: com volume inicial baixo, suporte manual cobre; alergénios mantém-se 🔴 por ser obrigação legal, com mitigação mínima barata.
- Edge Functions: 44 ativas, zero erros HTTP nas últimas 24h; `robot-b` é a única consistentemente lenta (7,8–24s).

---

## 7. PROMPTS SUGERIDOS (1 por bloqueador — colar um de cada vez)

**P-B1 — Cap de distância**
> ⚠️ MODO PROTECÇÃO TOTAL ⚠️ Invoca o CEO-AI. Bloqueador B1 da auditoria 2026-06-12: a RPC `create_order` aceita qualquer `distance_km` (pedido real `7efdca55` com 9.125 km → delivery_fee €4.563). Adiciona validação server-side `distance_km > 0 AND <= 15` (RAISE EXCEPTION com mensagem clara) + tratamento amigável no Flutter no checkout ("Morada fora da zona de entrega"). Migration única, backup antes, prova com SELECT da função e teste negativo. Commit + push só disto.

**P-B2 — Stacking parceiro (DECISÃO + fix)**
> ⚠️ MODO PROTECÇÃO TOTAL ⚠️ Invoca o CEO-AI. Bloqueador B2: `pricing_calculate` paga só €3,00 flat no 2º pedido stacked de parceiro ("2026-05-16 FIX: stacked = bonus ONLY"), mas business_rules §2.2.1 e DNA dizem `€3,80+€0,20×km+€3`. PRIMEIRO mostra-me as duas interpretações com exemplo numérico (pedido de 3 km) e o histórico do fix de 2026-05-16, e PÁRA para eu decidir. Depois da minha decisão: ou corriges `pricing_calculate`+`recalc_driver_earnings_on_stack` (migration), ou corriges business_rules.md+DNA. Nada de tocar noutros caminhos.

**P-B3 — Cap 50% tokens**
> ⚠️ MODO PROTECÇÃO TOTAL ⚠️ Invoca o CEO-AI. Bloqueador B3: a regra "desconto tokens máx 50% do pedido" (§4.3) não está implementada — cliente pode pagar 100% com tokens+wallet. Implementa cap server-side no ponto único onde o desconto é aplicado (`create_order`/`wallet_debit_for_order` — confirma primeiro qual), com teste: pedido de €10 + tentativa de €6 em tokens → aceita €5. UI do checkout deve mostrar o limite. Migration única + prova SQL. Não tocar na fórmula de atribuição de tokens.

**P-B4 — Markup hardcoded no driver_map**
> ⚠️ MODO PROTECÇÃO TOTAL ⚠️ Invoca o CEO-AI. Bloqueador B4: `driver_map_screen.dart` (~linhas 2567/2594/2803) tem `_markupPctDisplay = 0.15` e recalcula o valor do pedido localmente. Substitui por valores JÁ gravados no pedido (`order.total`/itens com preço cobrado) — zero cálculo de markup no ecrã. Cirúrgico: só este ficheiro, sem mexer em PricingService nem RPCs. flutter analyze 0 errors + prova visual.

**P-B5 — Arranque sem 45k produtos**
> ⚠️ MODO PROTECÇÃO TOTAL ⚠️ Invoca o CEO-AI. Bloqueador B5: `RestaurantStore.loadProductsFromSupabase` (restaurant_store.dart:218-249) carrega ~45k produtos no arranque (45 requests) via client_home_screen:62. Refactor mínimo: no arranque carregar APENAS restaurants/lojas+categorias; produtos passam a carregar on-demand por `restaurant_id` ao abrir a loja (com paginação existente) + cache em memória por loja. NÃO mexer em pricing, realtime de orders, nem nos ecrãs de parceiro. Prova: tempo de arranque antes/depois + ecrã de loja funcional no A36.

**P-B6 — Alergénios (mínimo legal)**
> ⚠️ MODO PROTECÇÃO TOTAL ⚠️ Invoca o CEO-AI. Bloqueador B6 (compliance UE 1169/2011): não há informação de alergénios nos menus. Implementa o mínimo legal: (1) coluna opcional `allergens_info TEXT` em products (migration aditiva), (2) no `product_detail_screen` e `restaurant_menu_screen` mostrar a info quando existir, senão linha fixa "Alergénios: contacte o restaurante — [telefone do parceiro]", (3) campo no painel do parceiro para editar. Sem redesign, PT-PT, regra 1-laranja respeitada.

**P-EXTRA — Crons (rápido, 5 min, fazer já)**
> ⚠️ MODO PROTECÇÃO TOTAL ⚠️ Via MCP: (1) desativa `robot-b-hourly` e `robot-b-weekly-digest` (decisão T7: OFF até launch); (2) reescalona `cleanup_payment_drafts` de `*/15` para `7,22,37,52 * * * *` (10+ falhas/7d por startup timeout em colisão às :00). Mostra-me o SQL antes de aplicar e regista em decisions/.

---

*Relatório gerado por auditoria autónoma read-only. Nenhum ficheiro de código, função, tabela ou configuração foi alterado. Próximo passo: Danilo escolhe a ordem dos bloqueadores (sugestão: P-EXTRA → B1 → B3 → B4 → B2 → B6 → B5).*
