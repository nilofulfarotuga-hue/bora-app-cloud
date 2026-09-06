# Bugs / Observações em Zonas Protegidas

> Itens detectados em zonas que exigem Validation Gate (RLS, pricing, dispatch,
> Stripe, triggers financeiros). **NÃO foram alterados autonomamente** — requerem
> aprovação do Danilo / validação Claude.ai antes de qualquer mudança.

---

## OBS-RLS-001 — Policies duplicadas/redundantes em `public.products` (2026-05-28, Ciclo 2)

**Zona:** RLS (security) — Validation Gate obrigatório.

**Observação:** a tabela `products` tem **dois conjuntos** de policies de escrita que
parecem fazer a mesma coisa mas referenciam colunas de `restaurants` com nomes
diferentes:

| Policy | Cmd | Coluna referenciada |
|---|---|---|
| `products_update_owner` | UPDATE | `restaurants.user_id` |
| `products_update_own_restaurant` | UPDATE | `restaurants.user_` (underscore final) |
| `products_insert_owner` | INSERT | `restaurants.user_id` |
| `products_write_own_restaurant` | INSERT | `restaurants.user_` |
| `products_delete_owner` | DELETE | `restaurants.user_id` |
| `products_delete_admin` | DELETE | `is_admin()` |
| `products_public_read` | SELECT | `true` (público — intencional) |

**Risco:** confirmado via `information_schema` que `restaurants` tem **AMBAS** as
colunas `user_` E `user_id`. Há portanto duas fontes de verdade para o dono do
restaurante. Policies PERMISSIVE fazem OR — basta uma passar. Se `user_` e `user_id`
divergirem para algum restaurante, a escrita pode ser autorizada por uma e não pela
outra. Dívida técnica real, mas sem falha de segurança imediata.

**Veredicto de segurança:** **NÃO é vulnerabilidade.** Escrita/edição/eliminação de
produtos continua travada ao dono do restaurante (pelo menos uma policy correcta
cobre). SELECT público é **intencional** — clientes têm de navegar o catálogo.
Isto valida o "BUG-2" do TEST_4_BUGS.md como **comportamento correcto, não bug**.

**Acção recomendada (requer Validation Gate):** consolidar para um único conjunto
de policies usando o nome de coluna canónico de `restaurants`, removendo as
redundantes. Confirmar primeiro qual é a coluna real (`user_id` vs `user_`).

**Estado:** documentado, não alterado.
