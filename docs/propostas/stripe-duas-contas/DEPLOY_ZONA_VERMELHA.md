# Duas contas Stripe — o que falta publicar (zona vermelha) — 02/11/2026

> Retoma da missão `stripe-empresa-2026-11-01` (Claude Code, Opus, sessão
> session_01HPEpVCiQJz5VkNWpbqKu2X). Autorização literal do Danilo: «Autorizo», 01/11/2026 22:03.
> Este ficheiro é para a **Claude.ai** (MCP Supabase) ou para uma sessão com o Danilo.
> A sessão do Claude Code NÃO pode: a bora-tranca nega escrever em `supabase/functions/<fn>/`
> destas 8 funções e nega publicá-las (lista PROTSLUG + zonas-vermelhas.json).

## Estado no ar às 06:55 de 02/11/2026 (provado)

- 24 funções publicadas com o código das duas contas (lista e versões no e2e_log, fluxo
  `stripe-empresa-2026-11-01`, passos R2-deploy-*), todas com verify_jwt igual ao de antes.
- `admin-payments` v12: ações novas `prova_conta` (PaymentIntent de 0,50 € sem meio de pagamento,
  criado e cancelado logo — sem cobrança) e `webhooks` (lista os destinos de webhook, só leitura).
  Aceita administrador ou o próprio servidor (pg_net com a chave do cofre).
- `stripe-webhook-empresa` v1 publicado (verify_jwt=false). Provado: evento
  `evt_3UXEwPGWwQxC9wR21WIODkPa` chegou com 200, gravado com `stripe_account='empresa'`.
- Destino da empresa na Stripe (`we_1UXDJtGWwQxC9wR2CbwB2BH7`) com os MESMOS 3 eventos da pessoal:
  `payment_intent.succeeded`, `payment_intent.payment_failed`, `charge.refunded`.
- Interruptor `platform_settings.stripe_conta_nao_tvde` = `"pessoal"` (não mudado).

## As 8 funções por publicar

Código: ramo git `stripe-empresa-retoma-2026-11-02` (sobre `stripe-empresa-2026-11-01`), pasta
`supabase/functions/_propostas/stripe-duas-contas/<fn>/index.ts`. Os imports `../_shared/x.ts` são
os de `supabase/functions/_shared/` (vão como ficheiros `../_shared/x.ts` ao lado do `index.ts`).
Base = versão no ar (nenhuma mudou desde 01/11 21:04; comparação feita a 02/11 06:50).

Ordem recomendada (as que só mexem em dinheiro já recebido primeiro; as que CRIAM pagamentos no
fim — só elas fazem a empresa começar a receber, e só com a app nova + interruptor):

| # | Função | verify_jwt | Diferença vs ar (linhas sem comentários) |
|---|---|---|---|
| 1 | refund | true | index −11/+18 |
| 2 | reprocess-refund | true | index −10/+7 |
| 3 | client-cancel-order | true | index −11/+23; cobranca_stripe −2/+4; gorjeta_devolver −3/+8 |
| 4 | charge-extra | true | index −24/+66 (usa a conta gravada no pedido) |
| 5 | finalize-order-from-intent | true | index −7/+17 |
| 6 | stripe-webhook (pessoal) | **false** | index de 739 linhas passa a 15 (chama `_shared/stripe_webhook_core.ts`, 1038 linhas — a MESMA lógica do ar, só com a conta como parâmetro e `stripe_account` gravado; diff revisto: 44 linhas, todas da conta) |
| 7 | create-mbway-payment-intent | **false** | index −15/+27 |
| 8 | create-payment-intent | **false** | index −56/+40 |

Ficheiros de cada uma (md5 dos 10 primeiros caracteres, para conferir que se enviou o certo):

```
create-payment-intent        index 250 l. c03d284c94 | _shared: cors 638630b92d, keys 453a392d21, chaves ff397660ef, stripe_contas 6b33be6644
create-mbway-payment-intent  index 240 l. 2fb7f88fc4 | _shared: cors, keys, chaves, stripe_contas (iguais acima)
finalize-order-from-intent   index 172 l. 8b68a89871 | _shared: cors, chaves, keys, stripe_contas
stripe-webhook               index  15 l. 3dfbb0d991 | _shared: stripe_webhook_core a3d6364436, keys, chaves, stripe_contas
refund                       index 112 l. 3fd468c241 | _shared: cors, chaves, keys, stripe_contas
reprocess-refund             index  95 l. 88987e7e54 | _shared: cors, keys, chaves, stripe_contas
charge-extra                 index 131 l. dbe84b470c | _shared: cors, keys, chaves, stripe_contas
client-cancel-order          index 334 l. caa2e5dce8 | _shared: platform_settings e08724c19f, cors, cobranca_stripe 93be2d2bc2,
                                                       stripe_contas, keys, chaves, chamadas c7991f8a28, gorjeta_devolver a8dc91f071
```

Depois de cada uma: `list_edge_functions` (versão subiu, verify_jwt como na tabela) e um pedido
OPTIONS (200 "ok"; os webhooks respondem 400 "Missing stripe-signature", é normal).
Enquanto o interruptor estiver em `"pessoal"`, tudo continua a funcionar como hoje.

## Depois das 8

1. **Proposta 04** (`docs/propostas/stripe-duas-contas/04_order_store_duas_linhas.md`): 2 linhas em
   `lib/stores/order_store.dart` (zona vermelha — sessão com o Danilo).
2. **Interruptor**: pelo caminho oficial, com sessão de administrador:
   `select public.admin_update_money_setting('stripe_conta_nao_tvde', '"empresa"'::jsonb, 'duas contas Stripe — autorizo 01/11 22:03');`
   ou no painel novo "Stripe — duas contas". Voltar a `"pessoal"` desfaz (sem build novo).
   Só faz efeito para a app nova (que manda `stripe_contas_v2: true`); as apps das lojas ficam na pessoal.
3. **Publicar a app nas 3** (só com ordem do Danilo): juntar este ramo ao
   `autonomous-night-2026-04-29` (conflitos esperados só em `lib/main.dart` e
   `lib/screens/admin/admin_menu_registry.dart`, por causa do commit 358cd9fe das chaves).
   A chave pública da empresa no `DART_DEFINES_FILE_B64` do GitHub é opcional (o servidor manda-a
   em cada pagamento; a compilada é só recurso).

## Migrações aplicadas que faltam em `supabase/migrations/`

A tranca recusa escrevê-las na sessão. SQL exato, com o nome final, em
`docs/propostas/stripe-duas-contas/aplicadas/` (20261102020808, 20261102055123, 20261102062513,
20261102062623; 20261102051537 é a reaplicação idempotente da 020808).
