# VERIFICAÇÃO T1 (toppings) + T2 (Minhas Marcações) — 2026-06-12

**Resultado: ZERO código alterado.** Os dois itens **já foram implementados na sessão de 2026-06-11** (commits pushed nessa data). O diagnóstico do prompt ("create_order NÃO soma extras" / "NÃO há ecrã de listagem") descreve o estado ANTERIOR a esse fix. Em vez de reimplementar, esta sessão **verificou e provou em produção** cada ponto da missão — e encontrou 1 divergência de regra que precisa da decisão do Danilo (secção 3).

---

## 1. T1 — Toppings/extras: JÁ COBRADOS ✅ (provas vivas de hoje)

| Ponto do prompt | Estado | Evidência (hoje, em produção) |
|---|---|---|
| create_order soma price_add | ✅ desde 2026-06-11 | Bloco T1 no `create_order`: `order_line_options_extras(productId, selected_options)` → `subtotal += extras × qty` ANTES do ×1,15 não-parceiro (parceiro: entra no subtotal do 10+5+5). O código está transcrito nas migrations de hoje `20260612213000`/`20260612214500` (B1/B3a re-publicaram a função completa com o bloco T1 intacto) |
| **Prova açaí + Mel(+€1) + Banana(+€1) → +€2** | ✅ | `SELECT order_line_options_extras('45d25e51…' /* Copo Pequeno 250ml */, '[{"group":"Deseja Extras?","items":["Mel","Banana"]}]')` → **`extras_total = 2.00`** + options_priced detalhado |
| Prova 2 (grupos múltiplos) | ✅ | KFC Sundae Caramelo: Topping Caramelo (0,83) + Kream Caramelo (2,89) → **3,72** exato |
| Exibido = cobrado no carrinho | ✅ | `product_detail_screen.dart:162` soma (base+extras) e aplica ×1,15 não-parceiro ao `CartItem.price` (auditoria A4 de hoje) |
| Histórico com nome+preço das opções | ✅ cliente/estafeta/parceiro | Servidor grava `selected_options_priced` em `orders.items`; `CartItem.displayOptions` parseia (`cart_item.dart:115,134`); exibido em [order_details_screen.dart:1001](lib/screens/order_details_screen.dart) (cliente), [driver_map_screen.dart:2789](lib/screens/driver_map_screen.dart) (estafeta) e [partner_dashboard_screen.dart:1345](lib/screens/partner_dashboard_screen.dart) (parceiro) |
| Antes/depois | ✅ registado 2026-06-11 | Prova da época: pedido 3,50 → **5,50** com 2 extras (relatório SESSAO_2026-06-11; auditoria A3 de hoje confirmou "T1 CONFORME em código") |

**Nota de catálogo (não é bug):** o açaí tem 2 grupos homónimos em conteúdo — "Escolha os Acompanhamentos:" (price_add=0, incluídos no copo) e "Deseja Extras?" (price_add=1). O helper cobra 0 nos acompanhamentos grátis e €1 nos extras — modelo Glovo correto. O helper usa `MIN + FILTER(is_available)` → **nunca cobra a mais**.

**Diferença vs prompt:** o prompt sugeria `WHERE id = ANY(selected_option_ids)`; a implementação real casa por **nome por grupo** (formato que o `CartItem.toJson` envia). Funcionalmente equivalente e provado ao cêntimo.

## 2. T2 — "Minhas marcações": JÁ EXISTE ✅

| Ponto do prompt | Estado | Evidência |
|---|---|---|
| Leitura das marcações | ✅ SELECT direto com RLS own-read (`ap_select`) — sem RPC nova (como o prompt preferia) | `my_appointments_screen.dart` |
| Ecrã na área Serviços + atalho Perfil | ✅ | [services_category_screen.dart:56](lib/screens/client/services/services_category_screen.dart) · [profile_screen.dart:593](lib/screens/profile_screen.dart) · pós-marcação: booking_success_screen:79 |
| Próximas vs Histórico | ✅ **3 tabs**: Próximas / Passadas / Canceladas | my_appointments_screen.dart:11,145 |
| Card + detalhe | ✅ serviço, barbearia, data/hora, preço, **estado do sinal em PT-PT** (deposit_status), status | my_appointments_screen.dart:464+ |
| Cancelamento com regra clara ANTES | ✅ modal mostra a regra e o destino do sinal; usa `client_cancel_appointment(uuid,text)` existente — zero lógica financeira nova | my_appointments_screen.dart:79-86 |
| Lembretes 24h/2h | ✅ ativos, sem duplicar | crons `appt-reminders-24h` (`0 10 * * *`) e `appt-reminders-2h` (`*/30`) ativos + flags `appointment_reminder_24h/2h_enabled=true`; `appt-auto-noshow` e `appt-weekly-payout` também OK |
| Espelho admin | ✅ | `admin_appointments_screen.dart` + busca de cliente no admin (sessão 2026-06-11) |
| Visual | ✅ BoraScreenAppBar/design system/PT-PT (sessão 2026-06-11) | — |

## 3. ⚠️ ÚNICA PENDÊNCIA — divergência de regra (decisão Danilo, não toquei)

O prompt pede cancelamento de **marcações** com janela **2h** ("<2h sinal retido, Bora 100% €3"). Mas:

- **Implementado (DB+ecrã+função):** janela **24h** via `platform_settings.appointment_cancel_window_hours=24`; retenção <24h reparte **Bora €0,50 + parceiro €2,50** (`appointment_deposit_bora_cut_cents=50`, `partner_cut_cents=250`).
- **DNA (2026-06-10, fonte mais recente):** "Serviços: sinal €3; **>24h refund; <24h/no-show: Bora €0,50+parceiro €2,50**" → o implementado está **alinhado com o DNA**.
- A regra de **2h** é a das **reservas de MESA** (`reservation_cancel_window_hours=2`), e "Bora fica €3" é o split do **no-show de mesa** — o prompt misturou as duas verticais.

**Se o Danilo quiser MESMO 2h nas marcações:** é 1 `UPDATE platform_settings SET value='2' WHERE key='appointment_cancel_window_hours'` + ajustar os textos do modal (my_appointments_screen.dart:79-86 dizem "24 horas" hardcoded) e o split da retenção (se "Bora 100%" for intencional, muda os cuts — **regra de dinheiro: só com aprovação explícita**). Prompt pronto:
> ⚠️ MODO PROTECÇÃO TOTAL ⚠️ Decisão: janela de cancelamento de MARCAÇÕES passa de 24h para 2h e retenção passa a 100% Bora (€3). Atualizar appointment_cancel_window_hours=2 (+cuts se aplicável) via update-platform-setting, textos do modal em my_appointments_screen.dart:79-86, DNA §3 e business_rules.md. Provar com marcação de teste.

## 4. Validação da sessão

- ✅ flutter analyze: 0 errors (sessão de hoje, inalterado — zero edits agora)
- ✅ T1 provado ao cêntimo em produção (2,00 / 3,72) sem criar pedidos (função STABLE read-only)
- ✅ T2 verificado ponto a ponto (ficheiro:linha)
- ✅ Crons confirmados ativos (24h/2h/no-show/payout)
- 🚫 Cancelamento real >2h/refund não exercitado (criaria marcação+refund reais; fluxo já provado na sessão 2026-06-11)

**Lição (anti-regressão):** prompts gerados a partir de diagnósticos antigos podem re-pedir trabalho já feito — verificar memória/relatórios ANTES de editar evitou hoje uma reimplementação cega de duas features em produção.
