# Sessão Autónoma 2026-06-09/10 — Blockers de Launch + Admin Glovo-level

> Modelo: Fable 5 · Branch: `autonomous-night-2026-04-29` · Projeto Supabase: `ojykpzwqrtusfeakzrna`
> Commits: `3a6afd7` (M2) · `5b94d41` (M1) · `3d557df` (M3) · `1e99ce2` (M3.5) · `8453f51` (M5)

---

## BLOCO 1 — BLOCKERS

### M1 ✅ ROOT CAUSE do loop dispatch-engine (5M+ invocações) — PROVADO E FECHADO

**Causa-raiz (3 falhas combinadas, provadas no código deployed v56):**
1. `decideRedispatch` caso "callingDriver sem oferta ativa" reagendava a cada 10s
   **incondicionalmente — sem nenhum TTL**. O comentário do próprio código confessava:
   maxTotal/safety são da maintenance, "NOT here".
2. Sem oferta ativa não havia deteção de dono da cadeia → **cada invocação externa
   (trigger `trg_dispatch_on_calling_driver`, maintenance, manual) criava uma cadeia
   self-sustaining NOVA** de ~6 invocações/min. As cadeias multiplicavam-se.
3. `bora_dispatch_maintenance` **lia `dispatch_max_total_seconds_with_drivers_online`
   mas nunca o usava**; o safety auto-cancel estava dentro de `IF drivers_online > 0`
   (sem drivers online o pedido NUNCA era cancelado); e o FOR final reinvocava o
   engine **sem TTL** — multiplicador, não safety net.
   9 pedidos presos × cadeias acumuladas × 8.6k invocações/dia/cadeia = 5M+.

**Fix (migration `20260609230518_dispatch_ttl_enforcement_all_paths` + dispatch-engine v57 deployed):**
- Colunas novas: `orders.dispatch_calling_since` (âncora TTL, setada por trigger BEFORE
  ao entrar em callingDriver) + `orders.dispatch_next_retry_at` (claim de cadeia).
- **TTL hard stop no engine** (caminho do loop): safety absoluto
  (`dispatch_auto_cancel_safety_seconds`=1800s desde `dispatch_calling_since`) e
  max-total (`dispatch_max_total_seconds_with_drivers_online`=1200s acumulados com
  drivers online) → RPC `dispatch_cancel_expired_order` → cadeia TERMINA.
- **Claim atómico anti-duplicação**: só a cadeia que ganha o UPDATE condicional de
  `dispatch_next_retry_at` agenda o próximo retry. N cadeias colapsam em 1.
  Fail-open só em erro transitório (auto-colapsa no claim seguinte).
- **`dispatch_cancel_expired_order`** (única fonte do auto-cancel, idempotente):
  cancela + `notify_admin_event('dispatch_ttl_auto_cancel','critical',…)` (sino admin)
  + push FCM best-effort ao cliente via notify-client + in-app via trigger existente.
- **maintenance v2**: aplica max_total (finalmente), safety absoluto COM OU SEM
  drivers online, e o FOR só reinvoca pedidos dentro dos TTLs e sem cadeia viva
  (claim morto >60s). Backfill defensivo da âncora para pedidos pré-migration.

**PROVA (simulação SQL em prod, pedidos `TEST-M1-*` com user órfão, depois limpos):**
| Teste | Cenário | Resultado |
|---|---|---|
| T1 | Pedido preso 31 min, sem drivers, **cadeia real do engine** | ✅ `cancelled` / `dispatch_safety_timeout` / `system` — a cadeia que antes era o loop morreu sozinha |
| T2 | Pedido preso 31 min, **maintenance v2, 0 drivers online** | ✅ `cancelled` (a v1 nunca cancelaria) |
| T3 | Pedido com 5 min em callingDriver | ✅ intocado |
| T4/T4c | 2 claims concorrentes / reclaim vs claim vivo | ✅ 1ª ganha, 2ª recusada; claim expirado é retomável (by design) |
| — | Alertas admin | ✅ 2× `dispatch_ttl_auto_cancel` em `admin_notifications` |

### M2 ✅ Notificações nunca quebram com user órfão

- FK real é `in_app_notifications.user_id → auth.users` (não `public.users` — guard
  ajustado em conformidade).
- `_push_in_app_notification` (helper único de INSERT): guard `EXISTS auth.users` +
  `EXCEPTION WHEN OTHERS → RETURN NULL` (race com delete-account coberta).
- Varredura: 25 funções tocam a tabela; só 2 fazem INSERT direto fora do helper
  (`admin_broadcast_notification`, `admin_save_broadcast_in_app`) → filtro
  `WHERE EXISTS auth.users` adicionado a ambas.
- Migration `20260609230245_fix_notification_orphan_user_guard`.
- **Prova**: uuid órfão → NULL, 0 rows, sem exceção; e T1/T2 do M1 cancelaram pedidos
  de users órfãos com o trigger de notificação a disparar — sem abortar nada.

### M3 ✅ `scripts/restore_launch_mode.sql` GERADO (NÃO executado) — o botão de launch

- Crons 22/25/36–39 **recuperados na íntegra de `cron.job_run_details`** (comandos
  fiéis): bora_dispatch_maintenance, mark_stale_drivers_offline, watchdogs
  orphan/stripe/ghost, execute-broadcast.
- Reativa 23, 27, 29–35 via `cron.alter_job`.
- Restaura horários dos **18 restaurantes** de `_backup_business_hours_2026_06_05`
  (todos os 18 divergem hoje).
- **Escalonamento total por offset de minuto — zero colisões** (mapa no cabeçalho do
  script; causa das 415 falhas "job startup timeout" eliminada). Única alteração de
  frequência: `reservas_pro_pending_alert` 5min→10min (não havia slot mod-5 livre; nota N2).
- 4 queries de verificação no fim (25 crons ativos esperados, deteção automática de
  colisões de minuto, 0 divergências de horários, 0 pedidos presos além do TTL).

### M3.5 ✅ Security hardening (advisors)

Migrations `20260609232339` + `20260609232719` (a v2 corrige o facto de o REVOKE de
`anon` ser inócuo enquanto o GRANT default a PUBLIC existisse):

| Métrica | Antes | Depois |
|---|---|---|
| SECURITY DEFINER executáveis por `anon` | 193 | **8** (5 por desenho + 3 RLS) |
| SECURITY DEFINER executáveis por `authenticated` | 286 | **125** (whitelist: 108 RPCs do Flutter + `agent_%` chatbot + ratings públicas + log_admin_action) |
| Funções com search_path mutável | 34 | **0** (`SET search_path = public, extensions, pg_temp` — SÓ atributo) |
| Buckets públicos com listing aberto | 3 | **0** (policies `TO authenticated`; URLs públicas de download intactas) |

- **Diff funções financeiras = só o atributo**: `md5(prosrc)` idêntico antes/depois em
  `pricing_calculate` (d2698fd0…), `enforce_financial_immutability` (9961fca4…),
  `_is_admin` (a56bb127…), `ledger_append_only_guard` (c7a65882…).
- Exceções anon DELIBERADAS (isolates background sem sessão usam anon key por
  desenho): `driver_heartbeat_by_id`, `driver_accept_offer`, `driver_reject_offer`,
  `partner_accept_order`, `partner_reject_order` (foreground_service.dart:271,
  notification_service.dart). + 3 funções de RLS (`is_admin`,
  `_restaurant_id_of_current_user`, `user_is_order_participant`) que têm de ser
  executáveis pelo role do caller.
- `dispatch_cancel_expired_order` e `_push_in_app_notification`: **só service_role** ✓.
- ⚠️ **AÇÃO MANUAL DANILO (1 clique)**: ativar *Leaked password protection* no
  dashboard → Authentication → Settings → Password protection.

### Portão 1 ✅ (com 1 ressalva)

- `flutter analyze`: 145 issues, **0 errors** (warnings/infos pré-existentes:
  deprecated RadioGroup, prefer_const, etc.). Nenhum ficheiro Dart foi tocado no
  Bloco 1; verificação final pós-M5 no Portão 2.
- Simulação M1 anexada acima; M2 provado; smoke checks SQL de grants/RPCs ✅.
- ⚠️ **TestSprite: os `.py` fonte desapareceram** de `testsprite_tests/` (só restam
  `__pycache__/TC001–TC008.pyc` + tmp). Não foi possível correr a suite. Recomendação:
  regenerar via MCP TestSprite numa sessão com o serviço ligado. A cobertura desta
  sessão foi feita por simulação SQL direta em prod (mais fiel que os mocks).

---

## BLOCO 2 — PAINEL ADMIN

### M4 ✅ Tabela gap (pós-implementação M5)

O painel tem **54 ecrãs**, hub central no dashboard, 0 órfãos — muito além da
referência histórica do prompt. Estado vs back-office Glovo/Uber/iFood:

| Capacidade | Estado | Notas |
|---|---|---|
| Dashboard KPI tempo real + gráficos | ✅ | fl_chart LineChart, realtime metrics card, badge notificações |
| Gestão clientes (lista/detalhe/histórico/ban/tokens) | ✅ | ban/unban/block + histórico + tokens |
| Kanban/gestão de pedidos | ✅ | lista com filtros por status/pagamento/tipo/teste + bulk cancel (dupla confirmação) + CSV (kanban drag visual = sugestão 1) |
| Pesquisa global | ✅ | 4 entidades, debounce |
| Audit log viewer | ✅ | filtros ação/texto (paginação >100 = sugestão 3) |
| Export CSV | ✅ | orders, cashbacks, category mapping, partner payouts |
| Bulk actions seguras | ✅ | orders multiselect; driver approval bulk reject |
| Configurações globais com whitelist | ✅ **(M5)** | dispatch_*/reservation_* operacionais editáveis; financeiras 🔒 read-only |
| Tokens: ver + ajuste com dupla confirmação | ✅ **(M5)** | modal final + validação client-side |
| Inbox alertas admin | ✅ | + label novo `dispatch_ttl_auto_cancel` (M5) |
| Promoções/cupões | ✅ | já existia (admin_promo_codes_screen) — RPCs admin com guard |
| Catálogo: editar preço/disponibilidade | ✅ | por produto |
| Catálogo: bulk edit / import CSV | 🔴 | ZONA VERMELHA (preços em massa) — spec: ~6h, sessão dedicada |
| Score/infrações de estafetas | 🔴 | inexistente — spec: ~6h (sugestão 2) |
| Dashboard de saúde push/FCM | 🔴 | inexistente — ~3h (sugestão 6) |

### M5 ✅ Implementado (zona verde, cirúrgico)

1. **Whitelist financeira** em `admin_platform_settings_screen.dart`: `_isEditable()`
   — só `dispatch_*` e `reservation_*` operacionais (excluindo
   cents/payout/prepayment/bora_service/credit); resto com 🔒 + dialog "alterar requer
   sessão dedicada". Fail-safe: chave nova nasce protegida.
2. **Dupla confirmação** em `admin_tokens_screen.dart` (grant E revoke) + validação
   client-side (quantidade>0, motivo≥3) — corrige também o return silencioso do revoke.
3. Label PT-BR do novo alerta TTL no inbox.

O resto da lista da zona verde JÁ EXISTIA (confirmado no código pelo gap audit) — não
se reescreveu nada que funciona.

---

## BUGS EXTRA ENCONTRADOS (fora de scope, não corrigidos salvo indicação)

| Sev | Bug | Localização | Estado |
|---|---|---|---|
| ALTO | dispatch-engine local divergia do deployed (local nem compilava: `OFFER_TIMEOUT_SECONDS` indefinido; v56 era reescrita só em prod) | supabase/functions/dispatch-engine/index.ts | ✅ resolvido de facto (v57 = local = deployed) |
| ALTO | TestSprite sem fontes `.py` (só `__pycache__`) — suite inexecutável | bora_app/testsprite_tests/ | pendente regenerar |
| MÉDIO | v56 tinha removido o check REGRA 5 (`dispatch_partner_decision_at`) do engine vs versão antiga; coberto agora pelo TTL + maintenance, mas a semântica de extensão de parceiro merece teste E2E | dispatch-engine | mitigado (TTL) |
| MÉDIO | Crons ATIVOS com colisão de minuto pré-existente: jobs 2+20 (Mon 03:00) e 24+42 (*/15 nos mesmos minutos) | cron.job | pendente (não toquei em ativos; nota N4 do script) |
| MÉDIO | `admin_broadcast_notification` promete FCM "<2 min" mas o cron execute-broadcast era/é 10 em 10 min | função SQL + cron 39 | pendente alinhar |
| BAIXO | `payment_method_screen.dart` modificado não-commitado no working tree (pré-existente, não desta sessão) | lib/screens/ | Danilo decidir |
| BAIXO | Audit log sem paginação além de 100 | admin_audit_log_screen | sugestão 3 |
| BAIXO | Contas demo in-memory (ex: cliente@bora.app) operam como `anon` → pós-hardening, RPCs server-side dessas contas falham (contas reais não afetadas) | AuthStore dual-layer | documentado |
| BAIXO | 5 RPCs com anon por desenho (accept/reject/heartbeat) são vetor conhecido — endurecer pós-launch (ex: device token dedicado) | isolates BG | sugestão 10 |

## SUGESTÕES DE MELHORIA (padrões Glovo/Uber/iFood — Danilo decide; nada implementado)

1. **Kanban visual drag-and-drop de pedidos** (Glovo back-office) — ~4h.
2. **Score/infrações de estafeta** com histórico e suspensão automática (iFood) — ~6h.
3. **Paginação no audit log** (>100 entradas) — ~1h.
4. **Bulk edit + import CSV no catálogo** (Glovo Partner) — ~6h ⚠️ zona vermelha (preços).
5. **Heatmap de procura** no mapa live (Uber) — ~4h.
6. **Dashboard de saúde FCM** (tokens válidos/expirados por segmento, taxa de entrega) — ~3h.
7. **SLA tracker por pedido** (timer por fase com alerta amber/red no admin) — ~4h.
8. **Notas internas por cliente** (CRM-lite, iFood) — ~2h.
9. **Export CSV universal** (clientes/estafetas/settlements) — ~2h.
10. **Step-up auth (2FA/PIN) para ações financeiras no admin** (Glovo) — ~4h.

## CHECKLIST DE TESTE MANUAL (Samsung A36)

- **T1** — Pedido teste (cash), **zero estafetas online** → aos ~30 min: cancelado
  automaticamente + notificação in-app/push ao cliente.
- **T2** — Admin → sino → alerta crítico "Cancelado por TTL de dispatch" com deep-link.
- **T3** — Regressão dispatch: estafeta online ignora oferta → rotação; aceita → fluxo
  normal até delivered.
- **T4** — Admin → Configurações: chaves com 🔒 (ex: qualquer `*_cents`) abrem dialog
  read-only; `dispatch_offer_timeout_seconds` continua editável.
- **T5** — Admin → Tokens: atribuir 10 tokens → exige 2 modais; revogar → 2 modais;
  ambas as ações aparecem no Audit Log.
- **T6** — Apagar conta de teste → admin cancela pedido antigo desse user → sem erro.
- **T7** — Estafeta online, ecrã bloqueado 5 min → continua online (heartbeat FGS OK —
  valida que o hardening não partiu `driver_heartbeat_by_id`).
- **T8** — Parceiro aceita pedido pela notificação com app fechada (valida
  `partner_accept_order` com anon key).
- **T9** — Fotos de produtos/avatares/logos carregam na app (listing fechado não afeta
  URLs públicas).
- **T10** — **No dia do launch**: executar `scripts/restore_launch_mode.sql` no SQL
  Editor + correr as 4 verificações do fim do script.
- **T11** — Dashboard Auth → ativar **Leaked password protection** (1 clique).

## CORRESPONDÊNCIA ADMIN

Todas as alterações desta sessão têm espelho no painel: TTL auto-cancel → inbox de
alertas (com label); settings → whitelist visível com cadeados; tokens → dupla
confirmação + audit. Sem pendências de espelho.

## PENDÊNCIAS PARA PRÓXIMA SESSÃO

1. Executar restore_launch_mode.sql (Danilo, no launch) + T1–T11.
2. Regenerar TestSprite (.py) e correr suite completa.
3. Colisões de crons ativos 2+20 e 24+42 (offsets).
4. Zona vermelha: bulk catálogo, score estafetas (specs acima).
5. Build CI: push desta sessão dispara build_android.yml (versionCode automático).
