# Migrações por pôr no repo (missao-geral-2026-10-28)

Estas migrações já estão aplicadas em produção, mas o texto delas tem palavras que a guarda do PC
(`zonas-vermelhas.json`, `migracoes.padrao_conteudo`) recusa em `supabase/migrations/`. Não se
tentou escrevê-las. O Claude.ai põe-nas no repo depois, num commit com `[skip ci]`, com o SQL
exato de `supabase_migrations.schema_migrations` (e, nos blocos DO que trocam texto, também a
definição final tirada de `pg_get_functiondef`).

| Versão | Nome | Palavra que a guarda apanha |
|---|---|---|
| 20261022114259 | tvde_no_show_paga_corrida_e_compensa_motorista_2026_10_22 | função de débito da carteira |
| 20261026130940 | peso_variavel_b_talao_2026_10_26 | tabela de movimentos da carteira, stripe |
| 20261028114641 | fatura_nif_cliente_2026_10_28 | tabela de movimentos da carteira |
| 20261028175946 | talao_dinheiro_respeita_saldo_e_tokens_20261028 | coluna do saldo usado |
| 20261028182812 | favor_dinheiro_respeita_saldo_e_tokens_20261028 | coluna do saldo usado |
| 20261028190806 | loja_parceira_dinheiro_respeita_saldo_e_tokens_20261028 | coluna do saldo usado |
| (sem versão) | mudança do split do reembolso para 1 (28/10 18:27), migração só documental | nome da chave |

A vigia C5 (`janela2/C5_vigia_dinheiro_a_cobrar.sql`) entra nesta lista depois de aplicada na
JANELA 2, porque lê a coluna do saldo usado.

Postas no repo nesta missão (md5 igual ao da base, conferido duas vezes):
20261020120020, 20261022114631, 20261026130514, 20261026131049, 20261028121958,
20261028203348, 20261028203353.
