# Sessão 2.4 — RLS Hardening (restaurants, products, messages)
**Data:** 2026-05-17 | **Branch:** autonomous-night-2026-04-29 | **Tag rollback:** pre-rls-hardening-2026-05-17
**Scope:** 100% SQL/migrations — zero código Flutter

---

## Buracos Fechados

| Tabela | Policy eliminada | Risco era |
|---|---|---|
| `restaurants` | `restaurants_auth_write (ALL, auth.uid() IS NOT NULL)` | Qualquer cliente autenticado podia UPDATE/DELETE qualquer restaurante |
| `products` | `products_auth_write (ALL, auth.uid() IS NOT NULL)` | Qualquer cliente podia alterar preços dos 42.000+ produtos |
| `messages` | `messages_all_authenticated (ALL, auth.uid() IS NOT NULL)` | Qualquer autenticado podia ler/criar/apagar qualquer mensagem |
| `messages` | `allow_select_messages (SELECT, qual=true)` | **Anónimos** podiam ler TODAS as mensagens (GDPR breach) |

---

## Policies Criadas

### restaurants
```sql
-- UPDATE: só o dono (user_ = auth.uid()) OU admin
CREATE POLICY restaurants_update_own ON restaurants
  FOR UPDATE TO authenticated
  USING ((user_ = auth.uid()) OR is_admin())
  WITH CHECK ((user_ = auth.uid()) OR is_admin());

-- DELETE: só admin
CREATE POLICY restaurants_delete_admin ON restaurants
  FOR DELETE TO authenticated
  USING (is_admin());
```

### products
```sql
-- INSERT: parceiro dono do restaurante OU admin
CREATE POLICY products_write_own_restaurant ON products
  FOR INSERT TO authenticated
  WITH CHECK (restaurant_id IN (SELECT id FROM restaurants WHERE user_ = auth.uid()) OR is_admin());

-- UPDATE: parceiro dono OU admin
CREATE POLICY products_update_own_restaurant ON products
  FOR UPDATE TO authenticated
  USING (restaurant_id IN (SELECT id FROM restaurants WHERE user_ = auth.uid()) OR is_admin())
  WITH CHECK (restaurant_id IN (SELECT id FROM restaurants WHERE user_ = auth.uid()) OR is_admin());

-- DELETE: só admin (soft-delete via is_available=false é o padrão)
CREATE POLICY products_delete_admin ON products
  FOR DELETE TO authenticated
  USING (is_admin());
```

### messages
```sql
-- Helper function (SECURITY DEFINER para evitar RLS loop)
CREATE OR REPLACE FUNCTION user_is_order_participant(p_order_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM orders o WHERE o.id = p_order_id::text AND (
      o.user_id = auth.uid()
      OR o.assigned_driver_id = auth.uid()::text
      OR EXISTS (SELECT 1 FROM restaurants r WHERE r.id = o.restaurant_id AND r.user_ = auth.uid())
      OR is_admin()
    )
  );
$$;

-- SELECT: participante da order OU admin
CREATE POLICY messages_select_participant ON messages
  FOR SELECT TO authenticated
  USING ((order_id IS NOT NULL AND user_is_order_participant(order_id)) OR is_admin());

-- UPDATE: só admin (sem sender_id na tabela)
CREATE POLICY messages_update_admin ON messages
  FOR UPDATE TO authenticated
  USING (is_admin()) WITH CHECK (is_admin());

-- DELETE: só admin
CREATE POLICY messages_delete_admin ON messages
  FOR DELETE TO authenticated
  USING (is_admin());
```

**Mantida sem alteração:** `messages_insert_participant` (já tinha lógica correcta)

---

## Smoke Tests T1-T13 + H1-H4 + T-extra-1/2/3

### Helper function (H1-H4)
| Test | Role | Esperado | Resultado |
|---|---|---|---|
| H1 | Cliente dono da order | `true` | ✅ `true` |
| H2 | Utilizador aleatório | `false` | ✅ `false` |
| H3 | Parceiro dono do restaurante | `true` | ✅ `true` |
| H4 | Driver da order | `true` | ✅ `true` |

### Migration 1 — restaurants (T1, T2, T7, T10, T11, T13)
| Test | Acção | Esperado | Resultado |
|---|---|---|---|
| T1 | Cliente UPDATE restaurante alheio | Bloqueado | ✅ `photo_url` original |
| T2 | Cliente DELETE restaurante aprovado | Bloqueado | ✅ `row_still_exists=1` |
| T7 | Parceiro UPDATE SEU restaurante | Passa | ✅ `TEST_OWNER_OK_T7` |
| T10 | service_role UPDATE qualquer | Passa | ✅ |
| T11 | Cliente SELECT restaurantes | 11 visíveis | ✅ |
| T13 | Parceiro UPDATE photo_url (sessão 2.3) | Passa | ✅ URL actualizado |

### Migration 2 — products (T3, T5, T6, T9, T12)
| Test | Acção | Esperado | Resultado |
|---|---|---|---|
| T3 | Cliente UPDATE `price=0.01` | Bloqueado | ✅ `price=13.0` original |
| T5 | Parceiro UPDATE SEU produto | Passa | ✅ `T5_OK` |
| T6 | Parceiro UPDATE produto alheio | Bloqueado | ✅ `price=2.9` original |
| T9 | Driver UPDATE products | Bloqueado | ✅ `price=13.0` original |
| T12 | Cliente SELECT products | 34.586 produtos | ✅ |

### Migration 3 — messages (T4, T8, T-extra-1/2/3)
| Test | Acção | Esperado | Resultado |
|---|---|---|---|
| T4 | Cliente alheio SELECT messages de order alheia | 0 rows | ✅ `0` |
| T8 | Driver SELECT messages da própria order | >0 rows | ✅ `2` |
| T-extra-1 | Cliente SELECT própria order (non-regression) | >0 rows | ✅ `2` |
| T-extra-2 | Parceiro SELECT order do seu restaurante | >0 rows | ✅ `2` |
| **T-extra-3** | **Anon SELECT messages** | **0 rows** | ✅ **`0` — vulnerabilidade fechada** |

**Resultado global: 20/20 testes passaram ✅**

---

## Nota 3 (verificada por Danilo via Claude.ai)
- 40.439 produtos — ZERO órfãos (todos `restaurant_id` válido)
- Migration 2 aplicada sem risco de ruptura

---

## Rollback de cada migration

**restaurants (reverso):**
```sql
DROP POLICY restaurants_update_own ON restaurants;
DROP POLICY restaurants_delete_admin ON restaurants;
CREATE POLICY restaurants_auth_write ON restaurants FOR ALL USING (auth.uid() IS NOT NULL);
```

**products (reverso):**
```sql
DROP POLICY products_write_own_restaurant ON products;
DROP POLICY products_update_own_restaurant ON products;
DROP POLICY products_delete_admin ON products;
CREATE POLICY products_auth_write ON products FOR ALL USING (auth.uid() IS NOT NULL);
```

**messages (reverso):**
```sql
DROP POLICY messages_select_participant ON messages;
DROP POLICY messages_update_admin ON messages;
DROP POLICY messages_delete_admin ON messages;
DROP FUNCTION IF EXISTS user_is_order_participant(uuid);
CREATE POLICY messages_all_authenticated ON messages FOR ALL USING (auth.uid() IS NOT NULL);
CREATE POLICY allow_select_messages ON messages FOR SELECT TO anon, authenticated USING (true);
```

---

## Follow-ups Registados

| # | Prioridade | Item |
|---|---|---|
| 1 | 🟡 | **`messages_insert_participant` duplica lógica do helper** — refactor para usar `user_is_order_participant()` em sessão de housekeeping |
| 2 | 🟡 | **5 users em `public.users` com name/email NULL** — backfill one-off (sessão 2.3) |
| 3 | 🟢 | **Trigger `auth.users → public.users`** — considerar criar para auto-sync |
| 4 | 🟢 | **Partner pode falhar UPDATE restaurants se `_partnerRestaurant` null** — sessão 2.3 follow-up |
| 5 | 🟢 | **is_admin() usa email hardcoded** — migrar para role-based exclusivamente quando houver mais admins |
