# farmacias-2026-11-11 — como publicar (para a Claude.ai)

A trava do PC recusa estrutura em produção ("migration só em local; publica a Claude.ai"), por isso o servidor
fica para ti. Tudo foi provado num Postgres local (PGlite): 65 verificações, 0 falhas
(`prova-sql/provar.mjs` + `prova-sql/resultado.txt`).

## Ordem (cada ficheiro numa transação; parar se algum falhar)
1. `supabase/migrations/20261111180000_farmacias_01_visibilidade.sql` — `restaurants.so_lista_permissao`,
   tabela `loja_lista_permissao`, `lojas_escondidas_para_mim()`, políticas RESTRICTIVE de leitura em
   `restaurants` e `products`, e o filtro nas funções SECURITY DEFINER que servem clientes (corpos copiados da
   produção a 11/11 com `pg_get_functiondef` + uma condição): cliente_pesquisar, home_mais_pedidos,
   home_pede_outra_vez, search_businesses, agent_search_products, agent_get_store_info, store_active_promotions,
   social_lojas_permitidas (exclui sempre) e a vista assistant_lojas (o Amigo nunca mostra lojas escondidas).
   ATENÇÃO: se alguma destas funções mudou em produção depois de 11/11 18:00, refazer o remendo a partir do corpo novo.
2. `..._02_colunas_definicoes_demo.sql` — colunas (`products.is_medicine`, `products.preco_provisorio`,
   `restaurants.pharmacy_prescription_mode`, `partner_extra_commission_pct/_starts_at`, `aberta_ao_publico_em`),
   gatilho que impede o parceiro de mudar esses campos, 8 definições `pharmacy_*` (categoria `farmacias`),
   modo demonstração (`_modo_demo_loja` e `_e_pedido_demo_loja` com o caso "loja escondida") e a guarda
   `a_trg_pedido_demo_zz_loja_escondida` (na loja escondida só entram pedidos de teste em dinheiro; cartão/MB Way
   são recusados antes de haver cobrança; o despacho só oferece ao estafeta demo).
3. `..._03_prescricao.sql` — tabela `pedidos_prescricao` (+ realtime), bucket privado `prescricoes` + políticas,
   RPCs do cliente (`farmacia_botoes_visiveis`, `farmacia_consentimento`, `prescricao_criar`, `prescricao_confirmar`,
   `prescricao_cancelar`), da farmácia (`prescricao_responder`), vigia (`prescricao_vigiar`) e admin
   (`admin_prescricoes_listar`, `admin_prescricao_forcar`, `admin_farmacias_listar`, `admin_farmacia_definir`,
   `admin_loja_lista_permissao_listar/_definir`, `admin_farmacia_abrir`). Avisos pelo caminho de sempre
   (vault + net.http_post → notify-partner / notify-client), tipos `prescricao_*` e `farmacia_lembrete_mensal`.
4. `..._04_lembretes_cron.sql` — `farmacia_lembretes` + RPCs, e 3 pg_cron: `farmacias-prescricao-vigiar` (cada minuto),
   `farmacias-lembretes-mensais` (09:00 UTC), `farmacias-prescricoes-limpeza` (03:40 UTC → Edge).
5. `docs/propostas/farmacias-2026-11-11/20261111180400_farmacias_05_comissao_extra.sql` — ⚠️ DINHEIRO
   (autorizado pelo Danilo 11/11 para estas 2 lojas): `compute_partner_weekly_settlement` desconta
   `partner_extra_commission_pct` da parte da loja nos pedidos criados a partir de `partner_extra_commission_starts_at`.
   Zero efeito noutras lojas (campos a null). Ficou em propostas porque toca no fecho/ledger; aplicar e mover
   para supabase/migrations. Não é preciso para a demonstração de sexta (as lojas escondidas não entram em fechos).
6. `..._06_lojas_so_lista.sql` — dados: as duas farmácias passam a aprovadas, escondidas (so_lista_permissao),
   receita `so_lista`, comissão extra 0,10 com data vazia, e a lista de permissão com as 2 contas do Danilo.
   Usa `bora.forcar_ativacao` só nesta transação (lojas escondidas); a conformidade volta a ser exigida ao abrir.

## Edge Function nova
- `supabase/functions/prescricoes-limpeza` (verify_jwt pode ficar true: só aceita `Bearer <service_role>`).

## Verificar depois de aplicar (só leitura)
```sql
select id, approval_status, is_active_admin, coming_soon, so_lista_permissao, pharmacy_prescription_mode,
       partner_extra_commission_pct, partner_extra_commission_starts_at from restaurants where id like 'farmacia-%-guarda';
select restaurant_id, user_id from loja_lista_permissao order by 1, 2;          -- 4 linhas
select jobname, schedule from cron.job where jobname like 'farmacias-%';        -- 3 linhas
select key, value from platform_settings where category = 'farmacias' order by 1; -- 8 linhas
select id, public from storage.buckets where id = 'prescricoes';                 -- public = false
```
E pela API como cliente que não está na lista: `restaurants?id=like.farmacia-*` devolve [] e
`rpc/cliente_pesquisar {"p_q":"farmacia"}` não traz as duas lojas.

## Desfazer
`update restaurants set so_lista_permissao=true, approval_status='rejected', is_active_admin=false where id like 'farmacia-%-guarda';`
esconde tudo outra vez sem apagar nada. As políticas RESTRICTIVE só afetam lojas com `so_lista_permissao=true`.

## O que o PC faz depois de aplicado
Carregar o catálogo (INSERT em products, dados), provar no servidor pelas contas (transações desfeitas) e
publicar a app pelo pedido de revisão.
