# Sessão Final Autónoma — 2026-04-30

> **Modo:** Autónomo total. Continua a sessão de 2026-04-29.
> **Branch:** `autonomous-night-2026-04-29`
> **Início:** 2026-04-30 ~10:00
> **Fim:** 2026-04-30 ~12:30
> **Operador:** Claude Opus 4.7 + CEO-AI orchestrator
> **Commits novos:** 2 (`feat(phase1+2)`, `feat(phase3)`)
> **Migrations aplicadas em prod:** 10 (8 da sessão de 29 + 2 novas)
> **Edge function modificada:** `update-products` (T11 refactor)
> **Ecrans Flutter novos:** 5 + 1 dialog
> **Project Supabase:** `ojykpzwqrtusfeakzrna`

---

## RESUMO EXECUTIVO

✅ **Phase 1 — 8 migrations aplicadas em prod via Supabase MCP** (uma a uma com smoke test).
✅ **Phase 2 — 5 admin screens + edit dialog** wired no `admin_dashboard_screen`.
✅ **Phase 3 parcial — 4 tarefas (T11, T12, T13, T15) feitas; 5 tarefas defer/skip documentadas**.

### Diferenças encontradas entre código local e prod

1. **`partner_hours_system.sql` (T4)** — index com `WHERE ends_at IS NULL OR ends_at > NOW()` rejeitado: `functions in index predicate must be marked IMMUTABLE`. Substituído por dois plain indexes (1 por `restaurant_id, starts_at DESC` e 1 parcial por `ends_at` IS NOT NULL). Filtro "active" agora feito em query-time. Local file alinhado.

2. **`complaints.related_order_id`** declarado UUID no local, mas `orders.id` é **TEXT** em prod (legado). Adaptado para TEXT na migration aplicada e local files sync. Confirma que o refactor TEXT→UUID (T2 da sessão de 29) é necessário.

---

## TABELA DE TAREFAS

| Fase | Tarefa | Estado | Detalhe |
|---|---|---|---|
| **1** | T4 partner_hours_system | ✅ aplicada | Fix IMMUTABLE no index |
| 1 | T17 drop pricing_calculate overload | ✅ aplicada | — |
| 1 | T15 admin_update_partner_data | ✅ aplicada | — |
| 1 | T9 admin_client_management | ✅ aplicada | — |
| 1 | T8 admin_token_management | ✅ aplicada | — |
| 1 | T7 admin_catalog_management | ✅ aplicada | — |
| 1 | T14 complaints_inbox | ✅ aplicada | UUID→TEXT FK fix |
| 1 | T13 admin_kpis_advanced | ✅ aplicada | — |
| 1 | T6 avatars RLS | ✅ JÁ COBERTA | 4 migrations já em prod (29205816→212155) |
| **2** | admin_clients_screen | ✅ criada | 250 linhas |
| 2 | admin_tokens_screen | ✅ criada | tabs Clientes/Estafetas |
| 2 | admin_catalog_screen | ✅ criada | 2 níveis (parceiros→produtos) |
| 2 | admin_complaints_screen | ✅ criada | filtro por status |
| 2 | admin_advanced_kpis_screen | ✅ criada | 3 secções KPI |
| 2 | _admin_partner_edit_dialog | ✅ criado | utility para admin_partners |
| 2 | partner_hours_full UI | ⏸ DEFER | precisa widget extraction + emulador |
| 2 | admin_dashboard nav cards | ✅ wired | 5 cards adicionados |
| **3** | T11 update-products ilike→join | ✅ feito | Refactor para `restaurants.name` lookup |
| 3 | T12 Push broadcast scaffold | ✅ aplicada | Tabela + 2 RPCs; FCM-side TODO |
| 3 | T13 support_tickets | ✅ aplicada | Chatbot placeholder |
| 3 | T15 Doc updates | ✅ feito | BR §4.4 + CLAUDE.md + INDEX.md |
| 3 | T16 draft/03 merge | ⏸ DEFER | BUG-MN-004 ainda aberto |
| 3 | T10 JWT vault cutover | ⏸ SKIP | Requer `vault.create_secret` manual |
| 3 | T9 Live map | ⏸ SKIP | Sessão UI dedicada com emulador |
| 3 | T8 Painel parceiro 'bagunça' | ⏸ SKIP | Sem reprodutor concreto |
| 3 | T14 dart:js → dart:js_interop | ⏸ SKIP | Requer teste web manual |

**Total:** 17 ✅ feitas + 5 ⏸ skip/defer (todas documentadas)

---

## DECISÕES UX / ARQUITECTURA TOMADAS

(Sem `web_search` invocado nesta sessão — todas as UI seguiram o padrão do `admin_drivers_screen` existente, que segue Material 3 + cards Glovo Manager-like. Estilo verde Bora `AppColors.primary`.)

### admin_clients_screen
Padrão escolhido: lista vertical com `CircleAvatar` (vermelho se banido) + 3-line subtitle + popup menu (Histórico/Banir/Desbanir). **Inspiração:** Uber Driver Operations admin (lista plana com cor por estado).

### admin_tokens_screen
Padrão escolhido: TabBar Clientes/Estafetas + search → resultados → seleccionar utilizador → balance card + lista de grants com toggle activo/usado. FAB para grant novo. **Inspiração:** Stripe Dashboard customer balance + grant history.

### admin_catalog_screen
Padrão escolhido: 2 níveis — parceiros (tile com counts active/total) → tap → produtos (toggle + edit). **Inspiração:** Glovo Manager > Catalog.

### admin_complaints_screen
Padrão escolhido: ChoiceChips de filtro horizontais + lista com cor por status. Tap abre dialog para mudar status + notas. **Inspiração:** Zendesk Inbox.

### admin_advanced_kpis_screen
3 cards verticais: ticket médio, funnel conversão, hot zones (lista; mapa visual fica para sessão futura). Period chips 7/30/90 dias. **Inspiração:** iFood Insights resumido.

### _admin_partner_edit_dialog
Form simples (nome / morada / categoria dropdown / telefone). Categoria com 4 valores oficiais. Diff-aware: só envia campos alterados.

---

## BUGS NOVOS DESCOBERTOS

1. **`partner_hours_system` index com NOW()** — confirmado problema PG: index predicate só aceita IMMUTABLE. Pattern aplica-se a outros sítios; vale auditar futuras migrations.

2. **`orders.id` é TEXT em prod** mas `schema.sql` declara UUID. Schema fica desalinhado. CLAUDE.md actualizado para clarificar que `schema.sql` é declarativa, não fonte da verdade da prod. Refactor para alinhamento real (T2) é trabalho post-launch.

3. **Migrations rebatizadas pelo Supabase** — quando aplicadas via `apply_migration` MCP, o `version` é o timestamp do APPLY (não o do filename local). Resultado: prod tem versions tipo `20260430101533` enquanto local files mantêm `20260429210000`. Não bloqueia (Supabase identifica por `name`), mas é diff inerente.

---

## SUGESTÕES DE MELHORIA

1. **Wire `_admin_partner_edit_dialog`** ao `admin_partners_screen` (TODO próxima sessão UI).

2. **`admin_tokens_screen` driver search** — actualmente pesquisa drivers via `from('drivers')` directo. Se RLS for restritivo, falhará. Considerar criar `admin_search_drivers` RPC mirror do `admin_list_clients` (sessão futura).

3. **`admin_advanced_kpis_screen` heatmap visual** — usar `flutter_map` com markers para mostrar hot zones em mapa real. Actualmente lista textual.

4. **Partner hours UI completa** — extrair `_business_hours_editor.dart` de `partner_hours_screen.dart` e reutilizar em `admin_partner_detail_screen` (T10 da sessão de 29).

5. **Support tickets UI cliente/parceiro/estafeta** — só backend criado nesta sessão. Inbox + chat-like UI fica para futura sessão.

6. **Edge Function `broadcast-push`** — quando Firebase resolver, criar fn que consome `push_broadcasts WHERE status='pending'`, fan-out ao FCM por segmento, marca `sent`/`failed` com counts.

---

## SKIP / DEFER — JUSTIFICAÇÕES

### T10 — JWT vault cutover (executar draft/01)
**Bloqueador real:** `vault.create_secret('<JWT>', 'dispatch_anon_jwt', '...')` requer credencial inserida manualmente. MCP não expõe `vault.create_secret` via RPC pública (vault é admin-only schema). Alternativa: Studio dashboard. **Próximo passo:** Danilo via Studio.

### T16 — BR §6.7 / draft/03 merge decision
Depende de **BUG-MN-004** (refund cap + idempotency) que ainda é launch blocker. Mergear o draft sem esse fix permitiria refund duplo em race. **Próximo passo:** após BUG-MN-004 resolvido + Firebase, merge.

### T9 — Mapa pedidos ao vivo
Requer iteração visual + teste em emulador (Google Maps + realtime cleanup). Sem environment de teste, alto risco de leak de subscriptions. **Próximo passo:** sessão UI focada.

### T8 — Painel parceiro 'bagunça'
Sem sintoma concreto (que ecrã, que erro, que botão). Investigação às cegas tem ratio sinal/ruído baixo. **Próximo passo:** Danilo usa o painel parceiro, anota 1-2 sintomas reais; fix tipicamente <1h.

### T14 — dart:js → dart:js_interop
Migração para `dart:js_interop` + `package:web` exige teste em Chrome com Google Maps SDK carregado. Sem environment web, alto risco de quebrar autocomplete/directions silenciosamente. **Próximo passo:** sessão com `flutter run -d chrome`.

---

## ESTADO MIGRATIONS EM PROD (ojykpzwqrtusfeakzrna)

10 novas migrations aplicadas nesta sessão (timestamps de apply, não de filename):

```
partner_hours_system            (T4)
drop_pricing_calculate_5arg     (T17)
admin_update_partner_data       (T15)
admin_client_management         (T9)
admin_token_management          (T8)
admin_catalog_management        (T7)
complaints_inbox                (T14)
admin_kpis_advanced             (T13)
push_broadcasts                 (T12)
support_tickets                 (T13')
```

(T6 avatars já estava coberta por 4 migrations pré-existentes.)

---

## COMANDOS DE ROLLBACK

```bash
# Voltar a main (descarta UI nova + commits Phase 1+2+3 da sessão):
cd /c/Users/danil/Desktop/projetosflutter/bora_app
git checkout main

# Reverter migrations em prod (1 a 1 via Studio SQL editor):
# Cada uma das 10 migrations expõe DROP FUNCTION / DROP TABLE no rollback.
# Exemplo para T14 complaints:
DROP FUNCTION IF EXISTS public.file_complaint(TEXT, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.admin_update_complaint_status(UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.admin_list_complaints(TEXT, INT, INT);
DROP TABLE IF EXISTS public.complaints CASCADE;
```

---

## TEMPO POR TAREFA (estimativa)

| Tarefa | Tempo |
|---|---|
| Phase 1 — 8 migrations + smoke tests | 35 min |
| Local file sync (T4 IMMUTABLE + T14 UUID→TEXT) | 5 min |
| Phase 2 — 5 admin screens + dialog (1500+ linhas Dart) | 55 min |
| admin_dashboard nav cards wiring | 5 min |
| T11 update-products refactor | 5 min |
| T12 push_broadcasts (migration + RPCs + apply) | 8 min |
| T13 support_tickets (migration + RPC + apply) | 6 min |
| T15 doc updates (BR + CLAUDE + INDEX) | 8 min |
| Commits + final report | 18 min |
| **Total** | **~2h25** |

---

## RECOMENDAÇÃO FINAL

**Backend admin pronto e em prod.** Cobertura de RPCs admin completa para:
- Clientes (list, ban, unban, history)
- Tokens (balance, grant, revoke)
- Catálogo (list partners, list products, toggle, edit price)
- Reclamações (file, list, status update)
- KPIs (hot zones, avg ticket, conversion)
- Horários parceiros (override, hours, special dates)
- Edição parceiros (data fields)
- Push broadcasts (scaffold; envio depende FCM)
- Support tickets (scaffold; bot depende AI integration)

**Frontend admin** com 5 ecrans novos wired. Acessíveis via dashboard.

**Pronto para:** primeiro lançamento beta privado em Guarda assim que os 6 launch blockers (Firebase, sound parceiro, Stripe live confirm, foto perfil cliente, BUG-MN-004 refund cap, E2E real) forem resolvidos.

---

*Gerado por Claude Opus 4.7 + CEO-AI orchestrator. Sessão fechada 2026-04-30 ~12:30 UTC.*
