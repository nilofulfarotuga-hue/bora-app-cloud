# Busca leve — como aplicar em produção (para a Claude.ai)

Missão `servidor-busca-leve-2026-11-17`. Preparado pelo Claude Code no ramo `ai/2026-11-17-busca-leve`.
A trava do modo automático não deixa o executor aplicar migrações em produção (`apply_migration`,
`CREATE`, `DROP`), por isso fica tudo pronto aqui. Registo de cada passo: `e2e_log`, fluxo
`servidor-busca-leve-2026-11-17`.

## O que muda e o que NÃO muda

- Os resultados da lupa NÃO mudam (mesmos produtos, mesma ordem). Provado antes de aplicar, com a
  função de hoje ao lado da nova, em produção, só com leituras e tabelas temporárias:
  - 444 pesquisas (299 tiradas dos nomes dos produtos + lista fixa, todas as lojas e Continente):
    444 iguais, produto a produto e pela ordem;
  - 170 delas com 1/3 das linhas guardadas estragadas de propósito: 170 iguais (o caminho de reserva
    calcula na hora quando a linha guardada não é do nome de agora);
  - versão final: 24 + 14 pesquisas, iguais com o plano próprio e com o plano genérico.
- Tempo (medido como a app chama, uma pesquisa por instrução, versão final, plano genérico):
  leite (todas as lojas) 101 → 43 ms; leite no Continente 65 → 27 ms; car 321 → 147 ms;
  car no Continente 181 → 80 ms; frango 407 → 223 ms; cães 539 → 223 ms; papel higenico 276 → 174 ms;
  porta chaves no Continente 304 → 22 ms; auchan no Continente 605 → 89 ms. Soma de 14: 4887 → 2105 ms.
  As palavras com milhares de candidatos (car, frango, cães) continuam acima de 60 ms: o resto do
  tempo é pontuar milhares de produtos, e isso não se mexeu para não mudar resultados.
- Secções (2 letras ou mais): deixam de fazer DISTINCT nos ~51 mil produtos (~33 ms) e passam a ler
  `seccoes_disponiveis` (390 linhas).

## Ordem

0. **Primeiro, a mais urgente e independente** — `20261117100300_cliente_pesquisar_produtos_3_letras.sql`.
   A lupa da PÁGINA INICIAL chama `cliente_pesquisar`, que ainda corre a pesquisa de produtos com 2
   letras (~3,7 s de CPU por "pa"/"co"): o conserto de hoje às 06:51 só tapou a lupa das lojas.
   Com esta, as lojas continuam a aparecer com 2 letras e os produtos a partir de 3. Prova rápida:
   `select jsonb_array_length(cliente_pesquisar('pa')->'produtos')` = 0 e
   `select jsonb_array_length(cliente_pesquisar('pao')->'produtos') > 0`.
1. **Migração 1** — `supabase/migrations/20261117100000_busca_leve_tabelas.sql` (apply_migration).
   Cria `bora_ns`, `bora_nr`, `produtos_busca_ns`, `seccoes_disponiveis`, os gatilhos em `products`,
   as regras de leitura (iguais às de `products`), enche as secções e agenda o lote
   `lote-5min-busca` (4-59/5). Não muda resultado nenhum.
2. **Encher os nomes normalizados** (~63 mil linhas, ~3-4 s de CPU no total, em lotes):
   `select public.produtos_busca_ns_preencher(2000, 40, 0.3);`
   Pára sozinha se o último registo do vigia passar 50%. Repetir até devolver 0.
3. **Provas da parte 1** — `supabase/tests/busca_leve_igualdade.sql`, PARTE 0 (cópia
   `pesquisa_produtos_antiga`) e PARTE 1 (1a a 1e). Esperado: 0 diferenças, `true`, 0 em falta.
4. **Migração 2** — `supabase/migrations/20261117100100_busca_leve_pesquisa.sql`.
5. **Provas da parte 2** — PARTE 2 do mesmo ficheiro: `diferentes_postgres = 0`, `diferentes_anon = 0`,
   secções 0/0, e a tabela de tempos DEPOIS (lista fixa, mediana de 3).
6. **Índice duplicado** (1.5) — à parte, fora de transação, pelo execute_sql:
   `drop index concurrently if exists public.idx_products_search_trgm;`
   (ou a migração `20261117100200_busca_leve_indice_duplicado.sql`, com lock_timeout de 3 s).
7. **PARTE 3** (apagar `pesquisa_produtos_antiga`) só 24 h depois, se ninguém se queixar: é o
   caminho de volta.
8. Registo: a migração `20261117065156_busca_minimo_3_letras_produtos.sql` já está aplicada (foi a de
   hoje às 06:51); o ficheiro só passa a existir no repo.

## Vigia em português de gente (B4, independente das outras)

- `20261117100400_vigia_servidor_portugues.sql`: funções `vigia_quem` / `vigia_o_que`, colunas
  `quem` e `o_que` em `vigia_servidor_registos`, tabela `vigia_servidor_avisos` (um aviso por causa +
  quem + o quê de 30 em 30 min; o seguinte diz quantas vezes se repetiu) e `_cron_vigia_servidor`
  com o aviso novo. Antes: depois de um aviso, QUALQUER outro ficava calado 30 min.
- Prova: `select public.vigia_quem('anon'), public.vigia_o_que(query) from extensions.pg_stat_statements where query like '%search_products%' limit 1;`
  → "pessoas sem login (…)" e "a lupa dentro das lojas (search_products)". Testado só com leituras
  a 17/11 que a extração acerta nas consultas reais (search_products, orders, meu_ganho_ao_vivo…).
- O ecrã "Vigia do servidor" do painel já mostra "Quem" e "O quê" (PR #33); nas medições antigas
  traduz a partir do papel e do SQL.

## Voltar atrás

- Pesquisa: recriar `pesquisa_produtos` a partir da cópia (antes da PARTE 3):
  `do $$ declare d text; begin perform extensions.similarity('a','b'); d := replace(pg_get_functiondef('public.pesquisa_produtos_antiga(text,text,integer,vector)'::regprocedure), 'FUNCTION public.pesquisa_produtos_antiga(', 'FUNCTION public.pesquisa_produtos('); execute d; end $$;`
- Secções: voltar a aplicar `20261117065156_busca_minimo_3_letras_produtos.sql` (o `search_products` de hoje).
- As tabelas, os gatilhos e o lote podem ficar (não mexem em resultados). Se for preciso tirá-los:
  `select cron.unschedule('lote-5min-busca');` e `drop trigger trg_products_busca_ns_ins/upd`,
  `trg_products_seccoes_ins/upd/del on public.products`.

## Riscos que vi e como ficaram

- Gatilhos em `products` (tabela no tempo real): só escrevem nas tabelas novas, nunca em `products`;
  disparam só quando muda nome/categoria/loja (nomes) ou disponível/secção/loja (secções). Mudança de
  preço não chama nada. São SECURITY DEFINER porque quem edita produtos (parceiro, admin) não tem
  escrita nas tabelas novas.
- Linha guardada atrasada (gatilho desligado, réplica, etc.): a pesquisa compara o nome guardado com
  o de agora e calcula na hora se não forem iguais. Fica mais lenta, nunca errada. O lote de 5 em 5 min
  volta a acertar até 2000 linhas por vez.
- `pesquisa_produtos` passa a `plpgsql` (o plano fica guardado na ligação). Mesmos argumentos, mesmo
  tipo de saída, mesmos privilégios.
- Regras de leitura das tabelas novas = as de `products` (lojas escondidas `lojas_escondidas_para_mim()`
  e prémios do check-in). Se as de `products` mudarem, mudar também aqui.
