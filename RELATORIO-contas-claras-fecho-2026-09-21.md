# Relatório — contas claras, fecho de 21/09/2026

> Missão `contas-claras-20260921` · Claude Code, Opus (a sessão continuou na mesma janela; não há
> como abrir uma janela nova a partir daqui — o motor FABLE não foi verificável) · 08h40–12h20 UTC.
> Regra do Danilo aplicada em tudo: **digo o que mexi e porquê; o que encontrei fora do scope está
> reportado, não corrigido.** Provas em `.claude/.ai/provas/contas-claras-20260921/` e linhas
> `e2e_log` 2117–2130 (run `contas-claras-20260921`).

## Em duas frases

O painel do Danilo passou a mostrar o acerto de cada estafeta com as corridas TVDE e os talões, deixa
reabrir um acerto só com motivo escrito (semanas antigas travadas) e mostra os avisos novos do fecho;
o extrato da app do estafeta mostra agora **as mesmas parcelas do recibo por email, com os mesmos
nomes e pela mesma ordem**, vindas de uma função só — provado com o Valdemir ao cêntimo (17,00 = 17,00).
O repo ficou igual ao servidor (26 funções comparadas corpo a corpo) e a publicação passou pelo CI
com o autoteste dos 3 perfis verde: **versionCode 612** no Play (alpha) e web. Com o "vai" do Danilo, a
**taxa de pedido pequeno passou a ser cobrada** (C7): o pedido nasce com o mesmo número que o carrinho mostra — provado
com um pedido de parceiro (13,87 = 13,87) e um de mercado (9,21 = 9,21); a parte da função que cria o pedido está
proposta e à espera da Claude.ai.

## Bloco a bloco — o que ficou feito, a prova, o que falhou

| Bloco | O que mexi | Prova | Falhou / ficou |
|---|---|---|---|
| **C0** ler o servidor | Nada (só leitura). `docs/ESTADO-SERVIDOR-2026-09-21.md` + `docs/_estado_servidor_defs_2026-09-21.sql` (definições vivas) | As 7 migrations da Claude.ai existem com as versões exactas; etiqueta PT-PT literal em `weekly_closeout_compile`; `v_small_order_fee_cents` declarada (l.20), lida (l.121), somada (l.225), no audit (l.346) e no JSON (l.389); gatilho `orders_zz_alerta_no_vermelho` e colunas `total_reimbursements`, `cash_in_hand_cents`, `fare_deduced` existem | Nada discorda do prompt |
| **C1** repo = servidor | 7 ficheiros `supabase/migrations/<version>_<nome>.sql` com o statement exacto (as duas de substituição de texto ficaram como definição completa com o corpo vivo); PROPOSTA_b8 removida; 10 corpos de 20/09 sincronizados (só comentários) | `c1-diff-repo-vs-servidor.txt`: **26/26 IGUAL** (sem `supabase db diff` local — comparação corpo a corpo por `pg_get_functiondef`) | — |
| **C2** painel admin | Migration `20260921090657_contas_claras_c2_admin_acertos_reabrir_avisos_2026_09_21`: `admin_weekly_closeout_list` devolve o acerto vivo (corridas TVDE, ganhos das corridas, dinheiro em mão nas corridas, compras adiantadas) e `reabrir_permitido`; **nova** `admin_reabrir_acerto` (motivo ≥ 5 letras → `notes` + `admin_audit_log`; semana antiga → `semana_travada`; recibo da pessoa volta a pendente); **nova** `admin_avisos_fecho`. Painel: colunas novas na linha, "Desfazer" → "Reabrir" com diálogo, recálculo pedido ao servidor, cartão "Avisos do fecho", rota `/admin/orders/{id}`, etiqueta "Pedido no vermelho" na caixa de avisos | `c2-painel-admin-prova.sql`: Danilo 16 corridas 62,00 / em mão 25,00 / talões 14,73; reabrir em rollback nos dois sentidos (paid→pending com nota e auditoria; "ok" recusado; 31/08 recusado); avisos plantados em rollback lidos com nome, valores e link; **Reenviar recibos**: `admin_resend_weekly_digest('2026-08-23')` → HTTP 200, `emails_sent 1`, `force true` (semana cuja única linha é a do Danilo, para não mandar email a mais ninguém) | O recálculo do estafeta é pedido pela app ao servidor a seguir ao reabrir (a Trava recusa DDL que nomeie a função de acerto; não se contorna) |
| **C3** extrato = recibo | Migration `20260921092110_contas_claras_c3_parcelas_do_acerto_2026_09_21`: **nova** `driver_settlement_parcelas(...)` (expressão copiada letra a letra de dentro de `weekly_closeout_compile`); o recibo passa a chamá-la; `extrato_prestador` devolve `parcelas` nos acertos e na previsão. App: `lib/widgets/extrato_prestador_section.dart` lê as parcelas do servidor (nomes e ordem do recibo), sem somar nem nomear nada | `c3-extrato-igual-recibo.sql`: recibo recompilado = breakdown gravado (3/3, rollback); **Valdemir** (JWT dele): parcelas app = parcelas recibo, 1700 = 1700 = soma 1700 (5,00 + 52,00 − 40,00); Danilo 5 parcelas pela ordem, 4352 = 4352 | — |
| **C4** taxa de pedido pequeno | Nada na app (já estava visível). Teste de fonte novo | Quote (JWT do cliente demo): Wells 4,23+2,50+0,99+0,10+**1,39** = 9,21; Goola 13,87. Linha "Taxa de pedido pequeno" no carrinho, no pagamento (valor do `quote_order_pricing`) e no detalhe. Estafeta a dinheiro cobra `cash_total_due` (servidor) | **Fora do scope** (abaixo): a taxa é mostrada mas não entra no total do pedido |
| **C5** investigar | Nada alterado. `c5-investigacao.sql` | Contas: c9fccf85 = nilofulfarotuga@gmail.com = admin + cliente (287 acções de admin, `paid_by`, compras, passageiro TVDE); 4f61dd31 = boraappbora@gmail.com = estafeta/motorista (48 corridas, 14 entregas, 5 acertos). Parceiros: fórmula proposta com SELECT nos 4 pedidos (nenhum vermelho; margens 1,02–3,76) | Plano de fusão: **não fundir** (ver abaixo) |
| **C6** publicar | `flutter analyze` 0 erros/0 warnings (252 infos antigas); `flutter test` **608/608** na 2.ª corrida (1.ª e 3.ª: golden tests a gravar PNG falharam com erro 1224 do Windows — ficheiro mapeado por outro processo; sozinhos 27/27 verdes); anti-trapaça limpo (+20 casos); rebase sobre os 2 espelhos do Córtex; push `0fb40500..6525bc6f` | CI run 35585546832: **Autoteste 3 perfis VERDE** (09:51→10:21 UTC) e **Build AAB & upload VERDE**; commit `ci: bump versionCode to 612` (560c65b0) no ramo, `pubspec` 1.0.1+612 (era 611). Não há emulador neste PC: o autoteste verde é o do CI, que é o portão antes do build | — |
| **C7** taxa de pedido pequeno cobrada (**"vai" do Danilo**, 21/09) | `fn_small_order_fee` (gatilho `orders_aa_small_order_fee`, BEFORE INSERT em `orders`) — migration `20260921112552_..._c7_gatilho_taxa_pedido_pequeno_sem_suposicao`: deixa de assumir que a taxa global já vem em `price`; quem insere declara em `small_order_fee` o que já pôs, e o gatilho soma só o que falta a `price`/`final_total`/`payment_buffer_total`. Valor (139) e mínimo (1500) intocados; 5 pedidos antigos intocados. A função que cria o pedido (zona vermelha; a Trava recusa DDL que a nomeie) fica como **PROPOSTA completa** — `20260921112223_PROPOSTA_..._c7_pedido_nasce_com_taxa_pedido_pequeno.sql` + `platform_settings.staged_contas_claras_20260921_c7` — para a Claude.ai aplicar. Push `1aa46f0a` → CI run 35594439475 **autoteste verde + build verde → versionCode 613** | `c7-taxa-pedido-pequeno-cobrada.sql`: antes (rollback, 5 INSERTs com o gatilho novo) 12,48→13,87 parceiro, 7,82→9,21 não-parceiro, acima do mínimo nada muda, taxa declarada → delta 0, pago com intent → global; fotografia real antes (JWT demo): Goola quote 13,87 vs linha 12,48; **depois**, pela própria função que cria o pedido: **Goola (parceiro) price 13,87 = quote ao cêntimo**, Wells 9,21 = quote, acima do mínimo 24,74 = quote com taxa 0; nada persistiu | Enquanto a proposta não entra: tecto da carteira e `charge_total`/estado de pagamento sem a taxa (só afecta quem paga tudo com a carteira), JSON devolvido à app com o price antigo até ao refresh, tampão MB Way/cartão dos não-parceiros 0,21 abaixo do quote (10,38 vs 10,59) |

## Números que ficam (todos lidos por SELECT)

- Semana 14–20/09 (`driver_weekly_settlements`, todas `pending`): Danilo 43,52 (16 corridas 62,00; entregas 9,63; talões 14,73; tokens 0,48; em mão −43,32) · Valdemir 17,00 (5,00 + 52,00 − 40,00) · Erika 4,00.
- Recibo enviado (`weekly_digest_log`) = acerto vivo em todos (4352=4352, 1700=1700, 400=400).
- Reenvio de recibos provado: `email_sent_at` 2026-09-21 09:10:11 na semana 24–30/08 (só Danilo).

## O que encontrei fora do scope (reportado, NÃO corrigido)

1. **Taxa de pedido pequeno mostrada e não cobrada — CORRIGIDA no gatilho em C7 (com o "vai"); a função que cria o pedido fica em PROPOSTA.** Diagnóstico original: `create_order` e `pricing_calculate` não somam a taxa ao total; só `quote_order_pricing` a soma. O gatilho `fn_small_order_fee` grava `small_order_fee` mas só ajusta o preço pela diferença loja−global (assume que a global já vem no preço — não vem). Nos 5 pedidos reais entregues com taxa (27/08→19/09) a taxa não está em `total/price/customer_total` nem entrou em `final_total`: **6,95 € mostrados e não cobrados**. Desde 21/09 07:12 o fecho da compra (B10 da Claude.ai) soma-a nos não-parceiros; nos **parceiros** (Goola e1078830 e ae711470: cliente viu 17,55, pagou 16,16) não há fecho, logo continua sem ser cobrada. O cliente paga menos do que viu; perde a Bora. **Proposta (zona vermelha, precisa do "vai"):** `create_order` somar `small_order_fee_calc(...)` a `price/customer_total/payment_buffer_total` como o quote faz, e o gatilho deixar de assumir que a global já lá está.
2. **Recibos do Valdemir e da Erika (semana 14–20/09) saíram às 01:20 com o HTML antigo** — Valdemir "Entregas ×1 57,00", sem a linha Corridas. Só o do Danilo foi reenviado (06:47). O `weekly_closeout_compile` não refresca linhas já `sent`, e "Reenviar recibos" manda a todos (Goola incluída, duplicado). **Decisão do Danilo:** reenvio os da semana 14–20/09 com um "vai" (um clique no painel também serve: "Reenviar recibos" com a semana 13/09 escolhida).
3. `admin_unmark_settlement` (o antigo "Desfazer", que o painel já não usa para estafetas) grava a auditoria via `log_admin_action(text,text,text,jsonb)` → tabela `admin_logs`, não `admin_audit_log`.
4. O cabeçalho do ecrã de acertos diz "Semana 13/09 a 20/09": `week_start_at::date` é calculado em UTC (23:00Z de domingo). A semana é 14–20/09. Só apresentação.
5. `close_previous_week_settlements` vai buscar o nome a `public.users`; se a pessoa lá não estiver, o aviso sai com o uuid.
6. **Conta admin com candidatura de estafeta acidental**: a 20/09 15:31:45 UTC nasceram, no mesmo instante, `drivers(user_id c9fccf85, pending, offline, email '')` e `user_roles driver` para a conta do painel — alguém entrou na app de estafeta com a conta do dono. Nunca trabalhou. Está a mais; sai pela função de admin da fila de aprovação, com o "vai".
7. `public.users.email` da conta admin (c9fccf85) é NULL (é isto que faz o "sem email" do prompt); o auth tem `nilofulfarotuga@gmail.com`.
8. Ficheiro `supabase/migrations/20260908180000_add_gallery_urls_to_restaurants.sql` está por versionar na pasta (não é desta missão; não confirmei se está no ar).

## C5.1 — as duas contas: o plano (só com o "vai")

Não fundir. `user_id` manda em ~60 colunas (corridas, pedidos, acertos, saldos, ledger, tokens, carteira): fundir é UPDATE em massa em tabelas com trava e histórico; colidem os únicos (`drivers.user_id`, `user_roles`, `client_wallets`, `driver_balances`, acertos por semana); `is_admin()` lê o `app_metadata`/email da c9fccf85; push e sessões são por uid; Stripe idem. Plano: (a) manter as duas — c9fccf85 = dono (admin + cliente), 4f61dd31 = estafeta/motorista; (b) rejeitar a candidatura acidental de 20/09 pela função de admin; (c) preencher `public.users.email` da c9fccf85; (d) o painel mostrar "(conta do painel)" ao lado do nome quando o uid é o admin.

## C5.2 — vigia do vermelho para parceiros: a fórmula (só proposta)

`sobrou = COALESCE(final_total, total) − COALESCE(order_financials.restaurant_amount, subtotal − partner_commission_visible − partner_markup_hidden) − driver_earnings`; VERMELHO se ≤ 0. A parte do parceiro vem de `order_financials.restaurant_amount` porque é o que o acerto semanal paga (10,90 = 12,72/1,05×0,90); a conta por colunas dá 10,81 (os dois ramos do `partner_store_share`). Nos 4 pedidos de parceiro entregues: 1,04 · 1,04 · 1,02 · 3,76 — nenhum vermelho. Aplicar = trocar o `RETURN` dos parceiros em `_trg_alerta_pedido_no_vermelho_fn` por este ramo.

## PARA O DANILO (decisões que só ele dá)

- **"vai" 1:** reenviar os recibos da semana 14–20/09 (Valdemir e Erika têm o recibo velho).
- ~~"vai" 2~~ **dado e executado (C7):** o gatilho já cobra; falta a Claude.ai aplicar a PROPOSTA da função que cria o pedido (`staged_contas_claras_20260921_c7`) — fecha carteira, estado de pagamento, JSON e tampão.
- **"vai" 3:** limpar a candidatura de estafeta da conta do painel e o email em falta.
- **"vai" 4:** ligar o vigia do vermelho aos parceiros com a fórmula acima.

## Ficheiros

- Migrations: `20260921084507_contas_claras_c1_helper_leitura_repo.sql` (temporária, já removida), `20260921090657_..._c2_...`, `20260921092110_..._c3_...`, `20260921094845_..._c6_remove_helper_...` + as 7 da Claude.ai (`20260920235112` … `20260921071507`).
- C7: `20260921112552_..._c7_gatilho_taxa_pedido_pequeno_sem_suposicao_2026_09_21.sql` (aplicada), `20260921112223_PROPOSTA_..._c7_pedido_nasce_com_taxa_pedido_pequeno.sql` (por aplicar, Claude.ai), `20260921112122`/`20260921112821` (função de leitura temporária, criada e removida).
- Flutter: `lib/screens/admin/admin_acertos_semana_screen.dart`, `lib/screens/admin/admin_notifications_inbox_screen.dart`, `lib/main.dart` (rota), `lib/widgets/extrato_prestador_section.dart`.
- Testes novos: `test/contas_claras_c2_painel_acertos_test.dart` (8), `test/contas_claras_c3_extrato_parcelas_test.dart` (4), `test/contas_claras_c4_taxa_pedido_pequeno_visivel_test.dart` (3).
- Docs: `docs/ESTADO-SERVIDOR-2026-09-21.md`, `docs/_estado_servidor_defs_2026-09-21.sql`.
- Commits (após rebase): af7b5690 · f791fc75 · 4e31a07e · 0f5af5f6 · 209d1c7a · 289412c0 · 6525bc6f.
