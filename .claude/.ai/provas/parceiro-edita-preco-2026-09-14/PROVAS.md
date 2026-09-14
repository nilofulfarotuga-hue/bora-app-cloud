# Provas — missão parceiro-edita-preco-14-09 (2026-09-14)

Ficheiros ao lado: `prova-parceiro-patch.txt` (as chamadas feitas com a sessão do dono da
Sabores de Casa) e `flutter-test-532.txt` (fim da suite completa).

## 1. `flutter analyze lib`

    0 erros em lib (209 avisos/infos pré-existentes, nenhum nos ficheiros tocados).

## 2. Teste da fórmula nos dois sentidos — `test/partner_price_rules_test.dart`

    00:00 +11: All tests passed!

Cobre: 8,00 € → 9,33 € → 8,00 € (exemplo real); Goola 7,90 → 9,22 → 7,90; varrimento de
0,01 € a 200,00 € (20 000 valores) balcão → app → balcão e app → balcão → app; percentagens
diferentes (12 %/3 %, 0 %/0 %) a mudarem o resultado — logo vêm do mapa de definições e não
do código; loja com `app_markup_pct` (Leonidas +10 %: 14,95 → 16,45 → 14,95; Mr Kebab +15 %).

Suite completa: `00:52 +532: All tests passed!` (exit 0).

## 3. Mesmo varrimento do lado do servidor (SQL, percentagens lidas de platform_settings)

    n=20000 | round_trip_ok=20000 | round_trip_fail=0 | exemplo_8_00=9.33 | volta_9_33=8.00 | goola_7_90=9.22

## 4. Migration `20260914170000_admin_precos_parceiro_balcao_e_app.sql` — aplicada e provada em rollback

DO-block com JWT de admin simulado (`set_config('request.jwt.claims', …)`) e `RAISE EXCEPTION 'RESULT …'`
no fim para reverter tudo:

    RESULT pid=c97d8d66-5237-4305-82e5-9d952a7901f6
    | incoerente=> admin_update_product_prices: par incoerente (balcao 8.00 mas partner_store_share(9.00) = 7.71)
    | coerente=> {"success": true, "new_price": 8.75, "old_price": 9.33, "new_shelf_price": 7.50, "old_shelf_price": 8.00}
    | lido: price=8.75 shelf=7.50 share=7.50 | audit=1

Depois do rollback: produto `9.33 / shelf 8.00`, `audit rows persisted = 0`.
Permissões: anon → `false` nas duas funções; authenticated → `true`; PUBLIC → `false`.

## 5. Prova real pelo lado do parceiro (conta do dono da Sabores de Casa)

Sessão obtida por `admin/generate_link` (magiclink de uma vez, sem email enviado, sem mexer na
palavra-passe) → `verify` 303 com `#access_token` (fluxo implícito) → JWT `sub 033e0fef-…`,
`email kauanmtsaru@gmail.com`, `bora_role partner`. Com essa sessão fez-se exactamente o PATCH
que o `RestaurantStore.updatePartnerProduct` envia (`/rest/v1/products?id=eq.<id>`, mesmos campos):

    platform_settings lidas com a sessão do parceiro: partner_hidden_markup_pct 0.05, partner_visible_commission_pct 0.1
    ANTES: Copo Grande | price 9.33 | partner_shelf_price 8.0
    EDIÇÃO 1 (8,00 -> 8,50): PATCH HTTP 200 | enviado shelf=8.5 price=9.92 | devolvido price 9.92, partner_shelf_price 8.5, updated_at 2026-09-14T19:29:22
    EDIÇÃO 2 (repor 8,00):   PATCH HTTP 200 | enviado shelf=8.0 price=9.33 | devolvido price 9.33, partner_shelf_price 8.0, updated_at 2026-09-14T19:29:23
    EDIÇÃO 3 (8,50 outra vez, para o SELECT ver): HTTP 200

SELECT (MCP) com o produto no estado editado:

    id c97d8d66-… | Copo Grande | Sabores de Casa Açaí | price 9.92 | partner_shelf_price 8.50
    | partner_store_share(price) = 8.50 | partner_store_share(price, restaurant_id) = 8.50 | coerente = true
    | updated_at 2026-09-14 19:29:43

Reposição pela mesma via: `REPOSICAO HTTP 200 price 9.33 shelf 8.0`.
SELECT final: `9.33 / shelf 8.00 / share 8.00`.

Sessão de prova fechada: `logout HTTP 204` (⚠️ foi `scope=global` — ver relatório: pode ter
fechado também a sessão do dono no telemóvel; a partir de agora usa-se `scope=local`).

## 6. Estado do catálogo parceiro na base (antes de mexer)

    Sabores de Casa Açaí: 105 produtos, 104 com balcão, 0 incoerentes com partner_store_share(price)
      (o único sem balcão é o "Saco" a 0,10 €)
    Goola Açaí: 2/2 com balcão, 0 incoerentes
    Leonidas (app_markup_pct 0,10): 93/93 coerentes com partner_store_share(price, restaurant_id)
    Mr Kebab (app_markup_pct 0,15): 47/47 coerentes com partner_store_share(price, restaurant_id)
    Sabores do Brasil: 8 produtos, 0 com balcão (fica gravado na primeira edição)
