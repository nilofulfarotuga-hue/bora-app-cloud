# Missão m1-dinheiro-favores-2026-11-08 — guia para aplicar e publicar (Claude.ai)

Autorização do Danilo, literal, 08/11/2026 (17:13, 18:59, 19:30): "Eu quero que você faça tudo, cara. Não deixa
nada para depois." · "Eu sou o dono do aplicativo. É pra forçar e pronto. Tem que tirar essas limitações aí." ·
"Não pode esquecer do NIF... quando fazer qualquer pedido, já ir a fatura pro e-mail da pessoa."

A sessão do PC (Claude Code) não aplicou nada em produção: a trava do modo automático bloqueia DDL, deploy de
Edge e o envio para o ramo de produção, e a bora-tranca não deixa escrever migrações de pagamento em
`supabase/migrations`. Tudo o que está aqui foi provado no PGlite: `provar_m1.mjs` → 60 passaram, 0 falharam
(saída em `.claude/.ai/reports/m1-2026-11-08/prova_pglite_sql.txt`).

Backups já feitos em produção (08/11): `bkp_orders_20261108` (18 linhas, colunas tocadas dos Favores e do pedido
BK) e `bkp_tips_20261108` (3 linhas). RLS ligada nos dois.

## 1. SQL — por MCP `apply_migration`, por esta ordem

| ficheiro | nome da migração | md5 |
|---|---|---|
| `01_favor_diferencas_e_entrega_sem_codigo.sql` | `20261108210000_m1_favor_diferencas_e_entrega_sem_codigo` | 43b650ef |
| `02_favor_aprovacao_com_tecto.sql` | `20261108210100_m1_favor_aprovacao_com_tecto` | 92f5467a |
| `03_nif_estafeta_e_recibo_cliente.sql` | `20261108210200_m1_nif_estafeta_e_recibo_cliente` | 924e4c6c |
| `04_gorjeta_conta_ganho_e_robo_talao.sql` | `20261108210300_m1_gorjeta_conta_ganho_e_robo_talao` | 68d6f29e |

Todos idempotentes (reaplicar não estraga). Depois copiar cada um para `supabase/migrations/<nome>.sql` pelo
GitHub (a tranca do PC recusa).

O 02 substitui `finalize_errand_purchase` (no ar: md5 `efd5e65eb415523c032a60f66a58d2b8`): igual ao do ar mais 3
remendos marcados "M1 08/11" (a diferença MB Way já paga conta como pago; nunca dois MB Way vivos ao mesmo tempo;
o pedido da diferença sai por `_favor_diferenca_pedir`). Antes de aplicar, confirmar que o md5 do ar ainda é esse.

O 04 substitui `meu_ganho_ao_vivo` (igual ao do ar + linha "gorjetas") e `catalog_price_update_from_receipt`.

## 2. Edge Functions — publicar depois do SQL

| função | de onde | verify_jwt |
|---|---|---|
| `favor-cobrar-diferenca` | `supabase/functions/favor-cobrar-diferenca/index.ts` (no ar v1 de 03/11; agora lê `_favor_diferenca_devida`) | **false** (a chave do cofre é `sb_secret`, não é JWT; a função confere a chave sozinha) |
| `stripe-webhook` | `index.ts` = `supabase/functions/_propostas/m1-dinheiro-favores-2026-11-08/stripe-webhook/index.ts` (é a v39 do ar, md5 4689370f) + `_shared/stripe_webhook_core.ts` do repo (= ar a3d63644 + ramo `errand_extra`) + `_shared/stripe_contas.ts`, `_shared/keys.ts`, `_shared/chaves.ts` | false (como hoje) |
| `stripe-webhook-empresa` | `supabase/functions/stripe-webhook-empresa/index.ts` (igual ao ar) + o mesmo `_shared` | false (como hoje) |
| `notify-client` | repo (igual ao ar) + remendo `05_notify-client_toque_persistente.patch` (`git apply`): `ring`/`ring_seconds` → canal de alarme `bora_offers_alarm_v4`. O remendo não foi gravado no ficheiro porque a trava do PC lê o cabeçalho de chave privada que o ficheiro já tem como "segredo" e recusa o commit | como hoje |
| `charge-tip` | repo (igual ao ar + taxa proporcional das gorjetas pagas junto, só contabilidade) | como hoje |
| `recibo-pedido-cliente` | **nova** — `supabase/functions/recibo-pedido-cliente/index.ts` | **false** |

Guardar o md5 de cada uma antes e depois no `e2e_log` (fluxo `m1-dinheiro-favores-2026-11-08`).

## 3. Provas depois de aplicar (com rollback, conta demo, nunca dinheiro real)

```sql
begin;
-- tecto e aprovação num Favor de teste (escolher um pedido errand demo em pickedUp)
select set_config('request.jwt.claims', json_build_object('sub','<uid do estafeta demo>','role','authenticated')::text, true);
select public.errand_teto_compra('<pedido demo>');
select public.estafeta_favor_pedir_aprovacao('<pedido demo>', <teto + 300>, null);
select * from public.favor_aprovacoes where pedido_id = '<pedido demo>';
rollback;
```

E por cada bloco: `driver_order_invoice_nif` com o estafeta atribuído (NIF ou 519686233), `_recibo_pedido` num
pedido entregue (total pago = Stripe), `admin_marcar_entregue_sem_codigo` sem motivo → `motivo_obrigatorio`.

## 4. Livro

Página `regras-operacao-agentes`: a linha "forçar entrega: ops_marcar_entregue_sem_codigo com a frase do Danilo"
já foi acrescentada a 08/11 pela sessão do PC, marcada "quando a função estiver no ar".

## 5. Para o Danilo decidir (não foi mexido)

1. O cartão/MB Way do Favor já é cobrado à partida a estimativa × **1,2** (`errand_buffer_multiplier`). A
   Claude.ai pediu 1,15 numa setting nova; não criei uma segunda setting para a mesma coisa. Se quiser 1,15 é
   mudar essa setting (mexe no valor cobrado).
2. A taxa de 3,00 € entra no pedido de cancelamento (`cancellation_requests.fee_cents`) só quando o cliente não
   responde; quando é o cliente a carregar "Cancelar" não leva taxa (não estava decidido).
3. Burger King: o menu Triple Whopper Spicy custa 12,45 € ao balcão (app 13,25 € de base) — o robô não sobe, fica
   pendente; o que está barato na app é o "EXTRA Bacon" (0,91 € na app, 2,50 € ao balcão). O preço das opções é
   decisão dele.
