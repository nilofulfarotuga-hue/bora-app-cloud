# SQL para a Claude.ai aplicar — missão varrer-pendentes-2026-11-28

Nesta sessão o Supabase não foi usado (ordem da Claude.ai, 28/11). Tudo o que
precisa de servidor está aqui, por ordem. Projeto `ojykpzwqrtusfeakzrna`.

## 1. Conferir o que já está aplicado (só leitura)

```sql
select version, name
from supabase_migrations.schema_migrations
where name ~ '(busca|lupa|pesquisa_dono|vigia_servidor|selos_novo|novidades_farmacia|redes_comunidade|farmacia_peca_aqui|jai_robo|painel_aprovacoes|whatsapp_bora|conteudo_ia_fila|quando_chamar|receita_cartao|licoes|editar_perfil|robos_livro)'
order by version;
```

Se a versão em produção for diferente do nome do ficheiro no repo, diz-me e eu
renomeio o ficheiro para a versão real (regra da casa).

Ficheiros que entram no repo pelo pedido da app (`ai/2026-11-28-pendentes-app`) e
que a missão diz estarem aplicados — confirmar:
- `20261117065156_busca_minimo_3_letras_produtos`, `20261117100000_busca_leve_tabelas`,
  `20261117100100_busca_leve_pesquisa`, `20261117100200_busca_leve_indice_duplicado`,
  `20261117100300_cliente_pesquisar_produtos_3_letras` (#33)
- `20261117151500_novidades_farmacia_robos`, `20261117152000_selos_novo_atalhos` (#37)
- `20261118120000_farmacia_peca_aqui` (#39 — o relatório do #39 dizia "por aplicar"; a missão diz aplicado)
- `20261117193000_redes_comunidade_24h` (#38)
- `20261123071500_jai_robo_portas` (#44)

Por confirmar (não sei o estado):
- `20261123083000_jai_robo_teste_fora_da_quota` (#44; só muda as contagens da quota)
- `20261127220000_whatsapp_bora_atendente` (ramo 26-voz; tenant "Bora" em teste)

## 2. Aplicar — pode ir já (não é dinheiro; a app aguenta sem)

- `supabase/migrations/20261117100400_vigia_servidor_portugues.sql` (#33). O ecrã
  do vigia usa `quem`/`o_que` se existirem; sem eles traduz no telemóvel.

## 3. Aplicar ANTES de publicar o pedido `ai/2026-11-28-pendentes-app-sql`

Sem isto a lupa e os botões do painel falham. Ficheiros no ramo
`ai/2026-11-28-pendentes-app-sql`:
- `supabase/migrations/20261117140000_lupa_sugestoes.sql` (#35)
- `supabase/migrations/20261117140100_pesquisa_dono.sql` (#35; troca `pesquisa_produtos`
  e `cliente_pesquisar` — testes de igualdade em `supabase/tests/pesquisa_dono_igualdade.sql`)
- `supabase/migrations/20261118210000_painel_aprovacoes_excecao_e_pedir_docs.sql` (#41)

Prova depois de aplicar:
```sql
select proname from pg_proc where proname in
 ('lupa_sugestoes','lupa_sugestoes_recalcular','admin_lupa_sugestoes_listar',
  'admin_aprovar_prestador_excecao','admin_pedir_documentos_em_falta');
select count(*) from public.lupa_sugestoes;
```

Quando estiver aplicado, diz-me (ou corre tu)
`node .claude/tools/publicar/publicar-pedido.mjs <n.º do pedido -sql> --repo nilofulfarotuga-hue/bora-app-cloud`.

## 4. Funções (Edge Functions) a publicar depois de juntar o pedido da app

O CI não publica funções. Depois de o pedido `ai/2026-11-28-pendentes-app` entrar:
- `client-assistant` (#39 farmácia primeiro + #43 lições dos robôs)
- `support-chatbot` (#43 lições dos robôs)
- `voz-cerebro` — confirmar se a que está no ar já é a v14 do repo (ramo 26-voz)

## 5. NÃO aplicar sem o "autorizo" do Danilo (dinheiro / dispatch)

- `20261117130000_quando_chamar_estafeta.sql` (#32) — muda `partner_auto_dispatch_ready_orders` (dispatch)
- `20261117120000_receita_cartao_mbway.sql` (#34) — cartão e MB Way da receita
- Edges de pagamento de reservas e marcações (ramo `ai/2026-11-28-reservas-pagamento`)
- `conteudo_ia_fila` (#20) não é dinheiro, mas ficou fora desta missão: o ficheiro
  `20261115110000_conteudo_ia_fila.sql` já está no repo, por aplicar.

## 6. Livro e registo (B0 e B5)

```sql
insert into public.e2e_log (fluxo, passo, estado, detalhe, device)
values ('varrer-pendentes-2026-11-28','B0','ok',
        'Inventário em docs/missoes/varrer-pendentes-2026-11-28-inventario.md (ramo ai/2026-11-28-pendentes-docs).',
        'claude-code-nuvem');
```
O texto do B5 e do digest vai no fim deste ficheiro quando a missão fechar.
