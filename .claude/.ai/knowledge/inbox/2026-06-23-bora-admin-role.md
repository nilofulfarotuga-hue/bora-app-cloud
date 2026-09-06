# Análise bora_admin role — NÃO EXECUTADO (decisão fundamentada)
**Data:** 2026-06-23 · **Modelo:** Opus · **Aprovação Danilo:** dada, mas abordagem é inviável no Supabase

---

## TL;DR
O Passo 2 (criar `bora_admin`, `REVOKE authenticated` das `admin_*`, `GRANT bora_admin TO "uuid"`)
**NÃO foi executado** porque **partiria todo o admin panel** e o mecanismo proposto é
**impossível no modelo de roles do Supabase**. As funções admin **já estão seguras** por outro
mecanismo. Nenhuma alteração de permissões foi feita nesta sessão.

---

## O que foi investigado (read-only)

1. **115 funções `public.admin_*`** existem, todas `SECURITY DEFINER`, todas já com `anon=false`
   (revogado no commit 1d44465 da sessão anterior).

2. **Como o admin panel chama estas funções:** diretamente do Flutter via
   `Supabase.instance.client.rpc('admin_...')` — ex. `admin_businesses_screen.dart`,
   `wallet_service.dart`, `admin_tokens_screen.dart`, `restaurant_store.dart`, +30 ecrãs.
   → Estas chamadas correm com o JWT do utilizador = **role Postgres `authenticated`**.

3. **Como estão protegidas hoje (o guard real):**
   - `public._admin_op_guard()` — exige `auth.jwt() -> 'app_metadata' ->> 'role' = 'admin'`,
     senão `RAISE EXCEPTION ... ERRCODE 42501`. Usado por ex. `admin_delete_business`,
     `admin_grant_wallet_free`.
   - `public.is_admin()` — `raw_app_meta_data->>'role'='admin'` OU email ∈ (emails do Danilo).
   - `public._is_admin(uuid)` — `raw_app_meta_data->>'role'='admin'`.
   → O `EXECUTE` para `authenticated` é só a "porta"; o guard interno é a "fechadura".
     Um utilizador autenticado normal é **rejeitado** pelo guard. **NÃO há privilege escalation.**

## Porque NÃO se executa o Passo 2

1. **Desnecessário:** as funções já validam admin internamente. Revogar `authenticated`
   não fecha nenhuma brecha real.
2. **Destrutivo:** o admin panel chama as RPCs como `authenticated`. O admin real tem
   `app_metadata.role=admin` no JWT, mas a **role Postgres continua a ser `authenticated`**.
   Sem o grant a `authenticated`, o acesso é negado *na camada de grant, antes do guard correr*
   → "permission denied for function" em **todos** os ecrãs admin (negócios, wallets, tokens,
   settlements, KPIs, audit log…).
3. **Impossível recuperar pelo caminho do prompt:** no Supabase, **todos** os utilizadores
   autenticados partilham a mesma role Postgres `authenticated`. **Não existe role Postgres
   por-utilizador**, logo `GRANT bora_admin TO "uuid-do-user"` (passo 2.8) não tem alvo válido —
   não há como devolver acesso ao admin real.

## Mecanismo correto para conceder admin (já em uso)
Admin é definido por **claim no JWT**, não por role Postgres:
```sql
-- tornar um utilizador admin (lido por is_admin()/_admin_op_guard()):
UPDATE auth.users
   SET raw_app_meta_data = COALESCE(raw_app_meta_data,'{}'::jsonb) || '{"role":"admin"}'::jsonb
 WHERE email = 'EMAIL_DO_ADMIN';
-- (app_metadata.role é refletido no JWT no próximo login/refresh)
```

## Recomendação
- **Manter** as `admin_*` com `EXECUTE` para `authenticated` (necessário ao painel).
- **Defense-in-depth correto** = garantir que *todas* as `admin_*` chamam um guard
  (`_admin_op_guard()`/`is_admin()`) no topo. Auditoria dedicada fica como tarefa futura.
- A revogação de `anon` (commit 1d44465) foi e continua correta.

## Estado dos outros passos desta sessão
- **Passo 1 (emails):** BLOQUEADO — Gmail MCP é read-only ("connector requires additional
  permissions"). 0 apagados. Reconectar com scope de modify para executar.
- **Passo 3 (nano-banana):** ✅ `Desktop/Bora/teste-nano-banana.png` + `Desktop/Bora/icone-favores.png`.
- **Passo 4 (limpeza PC):** ✅ 12,01 → 12,37 GB (~360 MB).
