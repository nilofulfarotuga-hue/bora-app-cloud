# R7 — remendo da app que a bora-tranca não deixa fazer no PC (11/11/2026)

**Para quem:** Claude.ai (ou sessão com a tranca aberta pelo Danilo). A bora-tranca do PC nega qualquer
Edit em `lib/stores/order_store.dart` ("zona vermelha: order_store.dart (finalizePurchase)"), mesmo com a
janela das travas aberta. O servidor já está pronto e provado (migração `20261111100000_checkin_r7_descontos`,
e2e_log `fechar-tudo-2026-11-11` passo `9-r7-servidor`).

**Ordem do Danilo:** 11/11/2026 07:54 (adendo 1 da missão fechar-tudo-2026-11-11): implementar a R7 e ligar os
6 degraus de desconto só com as provas verdes.

## O que falta (3 sítios, nenhum toca no finalizePurchase)

1. `lib/stores/order_store.dart`, assinatura de `createOrder({...})`, logo a seguir a `bool deixarAPorta = false,`:

```dart
    // 11/11/2026 (R7) — vale de desconto do check-in escolhido no carrinho.
    // Quem decide se desconta é o servidor (_create_order_core valida dono,
    // loja, validade e mínimo de produtos); a app só o passa.
    String? checkinValeId,
```

2. No mesmo ficheiro, no mapa `rpcInput`, logo a seguir a `'deixar_a_porta': true,`:

```dart
      // 11/11/2026 (R7): vale de desconto do check-in (o servidor valida).
      if (checkinValeId != null && checkinValeId.isNotEmpty)
        'checkin_vale_id': checkinValeId,
```

3. `lib/stores/cart_store.dart`, na chamada `orderStore.createOrder(` (perto da linha 1620), acrescentar
   `checkinValeId: checkinValeId,` e mudar `static bool descontoCheckinNoPedido = false;` para `true`
   (o carrinho passa a mostrar o vale da loja e o desconto antes de pagar — `premio_carrinho_banner.dart`).

## Depois do remendo

- Prova na app (conta de teste, DINHEIRO, Continente, compra de 25-40 € em produtos): o carrinho mostra
  "3 € de desconto", o total do pedido é 3 € mais baixo, o vale fica usado; um 2.º pedido não tem desconto.
- Só então ligar os 6 degraus (SQL abaixo) e retirar de `admin_checkin_degrau_editar` o
  `RAISE EXCEPTION 'desconto_fica_desligado_ate_entrar_no_pagamento'` (migração 20261110200400).

```sql
-- cópia antes
create table if not exists public.bkp_platform_settings_r7_20261111 as
  select * from public.platform_settings where key like 'checkin_marco_desconto_%';
update public.platform_settings
   set value = jsonb_set(value, '{ativo}', 'true'::jsonb), updated_at = now()
 where key in ('checkin_marco_desconto_mercadona_3','checkin_marco_desconto_continente_3',
               'checkin_marco_desconto_mercadona_5','checkin_marco_desconto_continente_5',
               'checkin_marco_desconto_continente_7','checkin_marco_desconto_continente_10');
```

## Achado para o Danilo

Os vales de 5, 7 e 10 € do Continente pedem 40, 55 e 70 € de produtos; o pagamento em dinheiro está limitado
a 40 € (create_order recusou um pedido de 49,05 € com `CASH_LIMIT_EXCEEDED`). Esses vales só se usam com
cartão ou MB Way. O de 5 € da Mercadona Beleza (mínimo 30 €) fica no limite.
