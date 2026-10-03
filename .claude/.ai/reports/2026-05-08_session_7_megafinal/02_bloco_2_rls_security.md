# BLOCO 2 — RLS hardening (Sessão 7-SEC-1 · 2026-05-08)

**Data**: 2026-05-08
**Sessão**: 7-SEC-1
**Modo**: MCP directo via Claude.ai
**Migrations aplicadas**: 4

---

## Objectivo

Endurecer postura de segurança RLS antes do launch:
- Eliminar tabelas backup obsoletas (Abril 2026).
- Activar RLS em 3 tabelas internas com data sensitivo.
- Substituir padrão vulnerável `user_metadata` por função
  `is_admin()`.
- Mover views `SECURITY DEFINER` desnecessárias para `INVOKER`.
- Fechar policies com `WITH CHECK true` (insert sem restrição).

---

## §2a — DROP backups + ENABLE RLS em 3 tabelas

**Migration**: `bloco_2a_drop_backups_enable_rls_3_tables`
(`20260508091407`)

### DROP de 6 tabelas backup (Abril 2026)

Liberta ~28 MB. Tabelas eram snapshots ad-hoc da Sessão 4 e
seguintes — já não referenciadas por código.

### ENABLE RLS em 3 tabelas

Tabelas que estavam sem RLS por engano e contêm dados sensíveis:

- **`token_config`** — config global de tokens (admin only)
- **`driver_token_transactions`** — transacções de tokens dos
  estafetas (admin only)
- **`market_update_schedule`** — agendamento de scrapers de
  mercados (admin only)

### Policies aplicadas

Padrão admin-only via `is_admin()`:

```sql
CREATE POLICY <table>_admin_select ON <table>
  FOR SELECT USING (is_admin());

CREATE POLICY <table>_admin_insert ON <table>
  FOR INSERT WITH CHECK (is_admin());

CREATE POLICY <table>_admin_update ON <table>
  FOR UPDATE USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY <table>_admin_delete ON <table>
  FOR DELETE USING (is_admin());
```

---

## §2b — Fix 6 policies `user_metadata` → `is_admin()`

**Migration**: `bloco_2b_fix_6_rls_user_metadata_to_is_admin`
(`20260508091529`)

### Vulnerabilidade

Padrão `auth.jwt() ->> 'user_metadata' ->> 'role' = 'admin'` é
inseguro: `user_metadata` é editável pelo próprio user, logo
qualquer user pode auto-atribuir-se role `admin`.

### Solução

Função SECURITY DEFINER `is_admin()` (definida em sessão anterior)
lê `auth.users.raw_user_meta_data ->> 'bora_role' = 'admin'`
(verificado via service_role) — não-editável pelo user.

### 6 policies migradas

- `client_wallets`
- `wallet_transactions`
- `cancellation_requests`
- `referral_codes`
- `referral_invites`
- `promo_code_uses`

### Validação MCP (CHECK 4)

```sql
SELECT pol.policyname, qual::text AS check_expr
FROM pg_policies pol
WHERE qual::text LIKE '%user_metadata%'
   OR with_check::text LIKE '%user_metadata%';
-- Resultado: 0 rows ✅
```

---

## §2c — Views SECURITY DEFINER → INVOKER

**Migration**: `bloco_2c_views_security_definer_to_invoker`
(`20260508091707`)

### Razão

Views `SECURITY DEFINER` executam com privilégios do criador
(`postgres`/`service_role`), ignorando RLS do caller. Útil em
casos específicos, mas **default deveria ser INVOKER**.

### 4 views migradas

- `v_cron_dispatch_health` — leitura de jobs cron
- `v_driver_withdrawals` — saques estafetas
- `v_driver_weekly_earnings` — agregados semanais
- `v_ledger_reconciliation` — ledger reconciliation

### Compatibilidade Edge Functions

Edge Functions usam `SUPABASE_SERVICE_ROLE_KEY` que **bypassa
RLS** — sem regressão esperada. Admin panel via Edge Fns continua
a funcionar.

### Cenário de regressão (rollback info)

Se admin panel em Flutter (não Edge Fn) deixar de ler estas views,
investigar se o caller tem permissões SELECT. Em vez de reverter
para DEFINER, criar function SECURITY DEFINER específica que
encapsule a query.

---

## §2d — Fix `WITH CHECK true` em 2 policies

**Migration**: `bloco_2d_fix_messages_restaurants_with_check_true`
(`20260508092014`)

### Vulnerabilidade

`WITH CHECK true` permite INSERT sem restrição alguma
(qualquer user autenticado pode inserir qualquer linha).

### Policy 1 — `messages.allow_insert_messages` → `messages_insert_participant`

**Antes**:
```sql
CREATE POLICY allow_insert_messages ON messages
  FOR INSERT WITH CHECK (true);
```

**Depois**:
```sql
CREATE POLICY messages_insert_participant ON messages
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM orders o
      WHERE o.id = messages.order_id
        AND (
          o.client_id = auth.uid()
          OR o.assigned_driver_id::TEXT = auth.uid()::TEXT
          OR o.partner_id = auth.uid()
        )
    )
  );
```

Apenas participantes do order (cliente, estafeta atribuído,
partner) podem inserir mensagens.

### Policy 2 — `restaurants.allow_insert_restaurants` → `restaurants_insert_admin_only`

**Antes**: `WITH CHECK (true)` (qualquer user podia inserir
restaurantes!).

**Depois**: `WITH CHECK (is_admin())`.

### Cenário de regressão (rollback info)

Se chat de mensagens partir após BLOCO 2d:
- Verificar se Flutter está autenticado (`auth.uid()` não NULL).
- Verificar que o user é cliente OR driver atribuído OR partner
  do order.

Para inserções de restaurantes via admin panel, garantir que
admin tem `bora_role='admin'` em `raw_user_meta_data`.

---

## Resumo BLOCO 2

| Sub-bloco | Migration | Acção |
|---|---|---|
| 2a | `bloco_2a_drop_backups_enable_rls_3_tables` | DROP 6 backups + ENABLE RLS em 3 tabelas |
| 2b | `bloco_2b_fix_6_rls_user_metadata_to_is_admin` | 6 policies `user_metadata` → `is_admin()` |
| 2c | `bloco_2c_views_security_definer_to_invoker` | 4 views DEFINER → INVOKER |
| 2d | `bloco_2d_fix_messages_restaurants_with_check_true` | 2 policies `WITH CHECK true` fechadas |

**Estado final BLOCO 2**: postura RLS endurecida. ZERO policies
remanescentes com padrão vulnerável `user_metadata` ou
`WITH CHECK true`. ✅
