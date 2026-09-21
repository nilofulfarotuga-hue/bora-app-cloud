# ESTADO DO SERVIDOR — 21/09/2026 (lido antes de escrever uma linha)

> Missão `contas-claras-20260921` · Bloco C0 · lido por MCP/REST em `ojykpzwqrtusfeakzrna` entre as
> 09h e as 09h40 de 21/09. Definições vivas completas em `docs/_estado_servidor_defs_2026-09-21.sql`
> (`pg_get_functiondef`, só leitura). **Tudo o que o prompt diz bate com o servidor** — não houve nada
> para parar e reportar.

## As sete migrações da Claude.ai (noite de 20/09 → manhã de 21/09)

| version | nome | o que faz (lido no corpo vivo) |
|---|---|---|
| 20260920235112 | contas_claras_b8_acerto_le_dinheiro_em_mao_2026_09_21 | `compute_driver_settlement` passa a somar o dinheiro em mão das corridas de `tvde_rides.cash_in_hand_cents` (a regra "tarifa = ganho + corte" de 20/09 fica escrita como ERRADA no próprio corpo); devolve `tvde_sem_dinheiro_em_mao_gravado` |
| 20260921064507 | contas_claras_b9_acerto_guarda_reembolsos_2026_09_21 | a mesma função passa a **gravar** `total_reimbursements` na linha do acerto (INSERT + ON CONFLICT); antes só entrava na conta e não ficava na tabela |
| 20260921064611 | contas_claras_b9_recibo_mostra_corridas_2026_09_21 | `weekly_closeout_compile` ganha a linha "Corridas" (qty = `tvde_rides_count`, valor = `tvde_earnings`) e as parcelas passam a somar o total |
| 20260921064817 | contas_claras_b9_recibo_acentos_ptpt_2026_09_21 | substituição de texto na definição viva: etiqueta `Dinheiro que recebeu em mão (devolve à Bora)` com acentos PT-PT — **confirmado literal no corpo vivo** |
| 20260921064931 | contas_claras_b9_fecho_grita_linha_travada_2026_09_21 | `close_previous_week_settlements` recalcula cada pessoa; se a linha estiver `paid/received` e o valor recalculado for outro, **não a reescreve**, grava `admin_audit_log.action = 'fecho_linha_travada_valor_diferente'` (com nome, valor na linha, valor recalculado, diferença, nota) e manda `notify-admin-urgent` (kind generic, route `/admin/acertos-semana`, ref `fecho_travado_<semana>`); se o aviso falhar grava `fecho_aviso_linha_travada_falhou` |
| 20260921071222 | contas_claras_b10_taxa_pedido_pequeno_nao_desaparece_2026_09_21 | substituição de texto em `finalize_storeshopping_purchase`: `v_small_order_fee_cents` declarada, lida de `v_order.small_order_fee` (l.121), somada a `v_final_total_cents` (l.225), presente no `admin_audit_log` (l.346) e no JSON de resposta (l.389) — **os quatro pontos confirmados** |
| 20260921071507 | contas_claras_b11_vigia_pedido_no_vermelho_2026_09_21 | `_trg_alerta_pedido_no_vermelho_fn` + gatilho `orders_zz_alerta_no_vermelho` (AFTER UPDATE OF status, quando passa a `delivered`): só lojas não-parceiras; `sobrou = cliente − mercadoria (talão) − estafeta`; se ≤ 0 chama `notify_admin_event('pedido_no_vermelho', high/medium, texto, 'order', id, jsonb com cliente_pagou, mercadoria, estafeta, sobrou_para_a_bora, catalog_price_gap_cents, small_order_fee)` |

## Colunas e definições

- `driver_weekly_settlements`: `total_reimbursements numeric default 0` ✓, `tvde_rides_count integer default 0`, `tvde_earnings numeric default 0`, `tvde_cash_received numeric default 0`, `notes text` (existe, para o motivo do reabrir).
- `tvde_rides.cash_in_hand_cents integer` ✓ e `fare_deduced boolean default false` ✓; `tvde_ride_cash_in_hand(uuid)` ✓ (regra única: pacote pago a dinheiro conta na ida, 0 na volta, 0 no plano, tarifa na corrida normal, só extras nas pagas na app; corrida normal a dinheiro sem tarifa → deduz e marca).
- `platform_settings`: `small_order_fee_cents = 139`, `small_order_fee_enabled = true`, `min_order_cents = 1500`.
- Semana 14–20/09 em `driver_weekly_settlements` (todas `pending`, ainda sem `paid_at`): Danilo net 43,52 (16 corridas, ganhos 71,63, em mão 43,32, talões 14,73); Valdemir net 17,00 (13 corridas, 57,00 / 40,00); Erika net 4,00 (1 corrida). `admin_audit_log` sem nenhum `fecho_linha_travada_valor_diferente` ainda (o fecho de 21/09 00:05 correu antes destas migrações? — a verificar em C2 ao ler os avisos).

## O recibo semanal (weekly_closeout_compile) — as parcelas, pela ordem e com os nomes exactos

1. `Entregas` — qty `total_deliveries`, valor `total_earnings − tvde_earnings`
2. `Corridas` — qty `tvde_rides_count`, valor `tvde_earnings`
3. `Compras que adiantou do bolso` — `total_reimbursements`
4. `Tokens convertidos` — `tokens_converted_value`
5. `Dinheiro que recebeu em mão (devolve à Bora)` — `−total_cash_received`

Cada parcela só aparece quando ≠ 0. O total é a soma. **É isto que o ecrã do estafeta tem de mostrar** (C3), pelas mesmas colunas, sem o Flutter somar nada.

## Repo × servidor (C1)

Depois de puxar as sete migrações por REST (statements exactos; as duas de substituição de texto ficaram como `CREATE OR REPLACE` com o corpo vivo completo) e de sincronizar os corpos das funções de 20/09 com o vivo (só diferiam em comentários que eu tinha cortado ao colar no MCP), a comparação corpo a corpo dá **22/22 IGUAL** — `.claude/.ai/provas/contas-claras-20260921/c1-diff-repo-vs-servidor.txt`. Não há `supabase db diff` local (sem Docker/CLI ligada); a prova é este diff função a função contra `pg_get_functiondef`.

## Fora do scope, visto de passagem (não tocado)

- `close_previous_week_settlements` vai buscar o nome à tabela `public.users` (`u.id = v_drv.id`), não a `drivers`; se `users` não tiver a pessoa, o aviso sai com o uuid.
- Ficheiro `supabase/migrations/20260920221500_tvde_oferta_em_voo_admin.sql` existe na pasta e não é desta missão (outra sessão); não foi confirmado se está no ar.
