# Auditoria guards admin_* — 2026-06-23 (read-only, nenhuma alteração na DB)

**Contexto:** esta auditoria foi explicitamente deferida como "tarefa futura" na sessão
[2026-06-23-bora-admin-role.md](2026-06-23-bora-admin-role.md) (mesmo dia, sessão anterior),
que já tinha concluído que as `admin_*` **não têm privilege escalation** porque o guard real
é `_admin_op_guard()` / `is_admin()` / `_is_admin(uuid)` lido do JWT, não a role Postgres.
Esta sessão completa essa auditoria função-a-função.

## Método

1. Listadas 134 definições `public.admin_*` (133 nomes distintos — `admin_approve_driver` tem
   2 overloads) via `pg_get_functiondef`.
2. 1ª passagem por regex (`_admin_op_guard()`, `is_admin()`, `app_metadata`, `role=admin`)
   marcou 9 como "sem guard" — **falsos positivos na maioria**: o módulo de reservas usa
   `_reservas_pro_assert_admin()` (nome diferente) e várias usam `_is_admin(v_admin_uid)`
   (com argumento, o regex inicial só apanhava a forma sem argumento).
3. 2ª passagem com regex alargado (`_reservas_pro_assert_admin`, `_is_admin\(`, `assert_admin`,
   `app_metadata`, `role='admin'`) reduziu para 6 candidatas reais.
4. Leitura do corpo completo das 6: 4 tinham guard via padrões adicionais ainda diferentes
   (`auth.jwt()->'user_metadata'->>'bora_role'`, `raw_user_meta_data->>'bora_role'`,
   `raw_app_meta_data->>'role'` + whitelist de emails, `current_setting('request.jwt.claim.role')
   = 'service_role'`). **Só restaram 2 funções genuinamente sem nenhum guard interno.**

## Resultado final

### ✅ Com guard (131 de 133 funções, ~98%)
Todas usam pelo menos um destes mecanismos (lista de padrões encontrados, não exaustiva):
`_admin_op_guard()`, `is_admin()`, `_is_admin(uuid)`, `_reservas_pro_assert_admin()`,
checks inline de `auth.jwt()->'app_metadata'/'user_metadata'->>'role'/'bora_role'`,
`raw_app_meta_data`/`raw_user_meta_data`, whitelist de email do Danilo, ou
`request.jwt.claim.role = 'service_role'`.

### ⚠️ Sem guard interno — análise caso a caso

| Função | Guard interno? | Quem pode executar (GRANT) | Guard externo? | Risco real |
|---|---|---|---|---|
| `admin_run_select(p_query text)` | ❌ Nenhum. Só banlist regex (bloqueia INSERT/UPDATE/DELETE/DROP/etc, exige `^SELECT`) | Só `postgres` + `service_role` (NÃO `authenticated`/`anon`) | ✅ SIM — `supabase/functions/admin-ai-assistant/index.ts:215-220` valida `app_metadata.role === 'admin'` do JWT do utilizador **antes** de chamar a RPC com o client `service_role` | **Baixo.** Inacessível via PostgREST a um utilizador normal; o único caller real já valida admin a montante. |
| `admin_run_write(p_query text, p_admin_id uuid)` | ❌ Nenhum. Banlist regex (bloqueia DROP/TRUNCATE/GRANT/REVOKE/ALTER/CREATE TABLE; exige WHERE em UPDATE/DELETE); regista em `admin_audit_log` (best-effort) | Só `postgres` + `service_role` | ❌ **Não encontrado nenhum call-site** em `lib/`, `supabase/functions/`, ou scripts — busca por `admin_run_write` no repo só aparece nesta função em si | **Médio-dormente.** RPC de escrita arbitrária (INSERT/UPDATE/DELETE em qualquer tabela, incl. `orders`/`wallets`/`bora_tokens` — bypassa RLS por ser `SECURITY DEFINER`) sem nenhuma verificação de identidade admin, interna ou externa. Só protegida pelo facto de a `service_role` key nunca ser exposta ao cliente. Se algum dia for ligada a um novo endpoint/Edge Function sem repetir o check do `admin-ai-assistant`, fica aberta. `p_admin_id` é recebido mas **nunca validado** — só usado para o log. |

**Nota sobre `_admin_op_guard()`:** depende de `auth.uid()`/`auth.jwt()`, que só existem quando a
chamada chega via PostgREST com o JWT de um utilizador autenticado. Chamado com a `service_role`
key directamente (sem JWT de utilizador, como faz `admin-ai-assistant`), `auth.uid()` é `NULL` e
o guard falharia sempre com `admin_required: not authenticated`. **Por isso NÃO se deve colar
`PERFORM public._admin_op_guard();` cegamente nestas duas funções** — partiria o único caller real
de `admin_run_select`. SQL sugerido fica em
[`admin-guard-missing.sql`](../security/admin-guard-missing.sql) com esta ressalva.

## Recomendação (decisão de Danilo — toca em segurança/auth, ver Validation Gate)

1. `admin_run_select` — risco baixo, mas **não está reciprocamente auditado**: não grava em
   `admin_audit_log` (ao contrário de `admin_run_write`). Sugestão de baixo risco: adicionar log.
2. `admin_run_write` — recomenda-se **uma** destas (não ambas, decisão de produto):
   - (a) Adicionar verificação explícita de `p_admin_id` contra
     `auth.users.raw_app_meta_data->>'role' = 'admin'` (não usar `_admin_op_guard()`, ver nota acima);
   - (b) Se confirmado que não tem caller real hoje, considerar `REVOKE EXECUTE` de `service_role`
     até haver um consumidor com guard próprio, reduzindo superfície de ataque a zero;
   - (c) Manter como está, documentando a decisão (arquitetura: confiança total na `service_role`
     key + nenhum endpoint atual a expô-la).
3. Nenhuma alteração foi aplicada — apenas leitura + SQL sugerido (comentado, não executado).

## Zonas protegidas — confirmação

Nenhuma tabela `orders`/`wallets`/`ledger`/`bora_tokens` foi alterada. `admin_run_write` tem a
*capacidade* teórica de as escrever (é genérica), mas isso já era verdade antes desta auditoria —
não é uma alteração introduzida aqui, é um achado sobre código já existente.

## Bloco B — Email Gmail: BLOQUEADO (confirmado, sem nova tentativa)

A sessão anterior do mesmo dia ([2026-06-23-bora-admin-role.md](2026-06-23-bora-admin-role.md))
já confirmou: "Gmail MCP é read-only (\"connector requires additional permissions\")". As
ferramentas Gmail disponíveis nesta sessão (`create_draft`, `create_label`, `delete_label`,
`get_thread`, `label_message`, `label_thread`, `list_drafts`, `list_labels`, `search_threads`,
`unlabel_message`, `unlabel_thread`, `update_label`) não incluem nenhuma de arquivar/apagar
mensagens — só etiquetagem e rascunhos. Por decisão desta sessão, **não foi feita nenhuma
tentativa de escrita real em emails** (mesmo de teste), dado o histórico já confirmado de
bloqueio e o risco de operações em lote irreversíveis sobre a caixa de correio real do Danilo
sem confirmação explícita prévia da lista completa. Triagem em massa continua **suspensa**
até reconexão do Gmail MCP com scope de escrita E aprovação explícita da lista a apagar.
