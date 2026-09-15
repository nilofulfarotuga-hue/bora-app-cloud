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

---
---

# ADENDO 2026-06-10 — M6–M11 (screenshots do device + chat Glovo-level)

> Commits: `c037bd7` (M6) · `3713a0a` (M7) · `bfd72ac` (M8) · `0de7260` (M9) ·
> M10 só prod · `d80e0dd` (M11). flutter analyze pós-tudo: **0 errors**.
> Sessão caiu 1× a meio do fecho — recuperação verificada (zero híbridos;
> tudo recommitado; protocolo de commits frequentes adotado).

## M6 ✅ Design: headers + logo

- **`headerGradient` → VERDE SÓLIDO #16A34A** (1 edit em app_theme.dart) — afeta
  TODOS os ecrãs que usam o gradient (cliente/parceiro/admin + BoraScreenAppBar).
  Padrão Glovo: header colorido consistente, sem variações.
- **Logo real na home**: o "quadrado verde com B" era o `_BoraLogo` do `BoraAppBar`
  — *"fallback text (até existir asset dedicado)"* que nunca foi atualizado depois
  de o asset chegar (Fase 3). Agora renderiza `assets/branding/bora_app_icon.png`
  (com fallback defensivo).
- **Varredura**: análise programática de todos os ecrãs cliente — ZERO casos de
  branco-sobre-claro no código atual (todos têm gradient ou BoraScreenAppBar).
  ⚠️ Os screenshots "Restaurantes"/"Serviços" ilegíveis não são reproduzíveis no
  código HEAD → forte suspeita de **APK desatualizado** no A36 (padrão já visto a
  2026-06-09). T12 reconfirma com o build novo.

## M7 ✅ MB Way + cartão em Reservas E Serviços (zero dinheiro)

- Reservas JÁ tinham sheet Cartão|MBWay (sem cash). Serviços só tinham PaymentSheet
  (GPay+cartão) — `create-appointment-payment-intent` era card-only.
- **2 Edge Functions novas (deployed)**: `create-mbway-appointment-payment-intent` v1
  (PI `mb_way` confirm:true server-side → push à app MB Way; marcação já criada pela
  RPC com validação de colisão) e `confirm-mbway-appointment-payment` v1 (endpoint de
  polling que verifica o PI **no Stripe** e confirma via a mesma RPC do cartão).
  O `stripe-webhook` NÃO foi tocado (zona protegida — não trata appointment_deposit;
  nota: o fluxo card confirma client-side via RPC sem verificação Stripe — o caminho
  MB Way novo é mais rigoroso; alinhar o card em sessão dedicada = sugestão).
- Flutter: `ReservationPaymentMethodSheet` reutilizado (param `title` novo),
  `AppointmentMBWayWaitingDialog` (poll 3s/timeout 120s), `ServicesStore.bookMbway`,
  booking_flow com sheet antes de pagar; timeout/cancel → cancela a marcação órfã
  (liberta o slot). **Paridade total; nunca dinheiro nos 2 fluxos.**
- Conta Stripe: `mb_way` ATIVO confirmado (LIVE em orders+reservas desde 2026-04/05).

## M8 ✅ Parceiro-serviços: Barbearia Nobre

- **Login**: o routing JÁ estava correto (f6585e9: partner_entry_screen → hub se
  service_providers existe; sem gate de restaurants). O bloqueio do Danilo era
  **password** → password temporária definida via SQL admin (audit log SEM a senha);
  credencial em `C:\Users\danil\Desktop\BORA-credenciais-barbearia-nobre.txt`
  (FORA do git — apagar após trocar a password no 1º login).
- **Gap audit do hub** (muito mais completo do que se pensava): agenda Hoje/Semana ✅,
  **marcação manual walk-in ✅ (já existia: PartnerAddWalkInScreen + partner_add_walk_in)**,
  bloquear horário ✅, serviços (preço/duração) ✅, staff + horários por profissional ✅,
  financeiro ✅. Faltava e foi implementado:
  - **Push FCM de nova marcação**: Edge `notify-service-provider` v1 (deployed —
    multi-device via partner_push_tokens do owner; notify-partner era restaurant-centric)
    + `_appt_notify_partner` v2 (in-app + FCM best-effort). Migration `20260610064237`.
  - **Cancelar marcação pelo parceiro**: RPC `partner_cancel_appointment` (sinal pago →
    cliente avisado do reembolso + alerta admin `appointment_partner_cancel_refund_due`)
    + botão "Cancelar" na agenda com dialog de motivo.
- **Espelho admin**: ver/cancelar marcações ✅ (já existia) + aprovar/rejeitar/ativar
  providers ✅. 🔴 pendente (specado): gestão de staff no admin (~3h) e block-slot
  admin (~2h) — mecanismo de emergência atual: toggle `is_active_admin`.
- Decisão de desenho documentada: marcações são AUTO-CONFIRMADAS com o sinal pago
  (padrão Fresha/Booksy) — "aceitar/recusar" manual não existe por design; o parceiro
  tem agora cancelamento para imprevistos.

## M9 ✅ Paridade Glovo: McDonald's, BK, KFC

| Loja | Produtos vs fonte | Fotos | Grupos opções | Ordem secções |
|---|---|---|---|---|
| McDonald's | 111 = 138−27 colapsos "(Grande)" ✓ | 100% | 330 (88 produtos) ✓ | **CORRIGIDA** |
| Burger King | 173/173 ✓ | 100% | 488 (127) ✓ | **CORRIGIDA** |
| KFC | 176/176 ✓ | 100% | 705 (145) ✓ | **CORRIGIDA** |

- **Fix principal**: `_groupByCategory` ordenava secções ALFABETICAMENTE — o McD
  abria com "Acompanhamentos" em vez de "Sanduíches e McMenus". Os produtos já vêm
  por `sort_order` (0..N = sequência Glovo, 100% populado) → preservar a ordem de
  inserção resolve a paridade nas 3 lojas (e em qualquer loja Glovo futura). 1 edit.
- Página de produto com extras/menus/stepper: ✅ já existia (4611e67).
- Divergência menor de categorias McD (9 vs 10 do Glovo: sem "Items Individuais"/
  "Saco de Transporte"; "McCafé"+"Menu Almoço" extra com 1 produto cada) — resultado
  dos merges do insert; impacto baixo; correção fina = sessão de dados (~1h).
- Preços: intocados (×0.8261 protegido).

## M10 ✅ Limpeza pré-launch

- 3 lojas de teste escondidas do cliente (`is_active_admin=false` — o feed filtra
  por esta flag; admin continua a vê-las; DADOS INTACTOS) + audit log por loja:
  ifxfixif, pizza danilo, Pizzaria Teste Noite.
- 66 in_app_notifications de teste do user do Danilo (todas pré-2026-06-09, todas
  por ler) apagadas → badge a zero. Verificado: 0 restantes.

## M11 ✅ Chat nível Glovo/Uber

**Parte A — ROOT CAUSE do push que nunca chegava: 5 ELOS QUEBRADOS**
1. O trigger `_notify_chat_message_trigger` enviava só `{message_id}`; a Edge v9
   exige `message_id+order_id+sender_id` → **400 em TODAS as invocações**.
2. A Edge resolvia o estafeta por `orders.driver_id` — coluna quase nunca populada
   (canónica: `assigned_driver_id`).
3. Parceiro resolvido por `restaurants.user_` — divergente de `user_id` em 4 rows
   → `COALESCE(user_id, user_)`.
4. **O cliente NUNCA receberia push**: `client_push_tokens` nem era consultada.
5. `partner_push_tokens` é keyed por `partner_id`; a v9 consultava `user_id`
   (coluna inexistente nessa tabela).
Fix: trigger v2 (payload completo — migration `20260610065143`) + Edge
`notify-chat-message` **v10 deployed** (4 correções + log de diagnóstico).
Foreground/background handlers no device JÁ tratavam `type=chat` (data-only +
notif local com som bora_alert) — com o pipeline corrigido, passam a disparar.

**Parte B — Bolha + badge (padrão Glovo)**
- `ChatBubbleButton` novo: badge VERMELHO de não-lidas em realtime + preview de
  1 linha (tracking). Integrado: CLIENTE tracking (2 acessos: Restaurante E
  Estafeta — padrão Uber Eats), ESTAFETA (entrega ativa), PARCEIRO (2 botões
  compact no detalhe do pedido).
- Não-lidas: coluna `messages.read` (já existia) + RPC `chat_mark_read` (valida
  participante por papel) — marca ao abrir o chat e quando chegam mensagens com o
  ecrã aberto (throttled); badge zera via realtime.
- `ChatTarget.partner` novo: cliente/estafeta escolhem destinatário explícito
  (antes o destino era inferido do status — impossível ter 2 acessos).

**Parte C — Polimento**
- ✓ (enviada) / ✓✓ (lida) nas bolhas próprias; timestamps e auto-scroll já existiam.
- Janela do chat: os entry points vivem nos ecrãs de pedido ATIVO (tracking/driver/
  parceiro) — fecham naturalmente com a entrega (padrão Uber). Histórico: admin.
- Som in-app: o handler de foreground existente posta notif local com som ao
  receber `type=chat` (não suprimido).

**Admin**: `AdminChatViewerScreen` (PT-BR, read-only) via RPC
`admin_list_order_messages` (`_admin_op_guard` + **audit `chat_viewed` a cada
acesso**) + botão "Ver conversa" no detalhe do pedido.

## CHECKLIST DE TESTE MANUAL — NOVOS ITENS (T12+, build novo do CI)

- **T12 (M6)** — Instalar o build novo: headers VERDES #16A34A com seta/título
  brancos em "Restaurantes", "Serviços" e todos os ecrãs interiores; topo da home
  mostra o LOGO real da Bora (não o "B").
- **T13 (M7)** — Serviços → marcar corte → sheet mostra SÓ "Cartão" e "MBWay"
  (sem dinheiro) → escolher MBWay, nº 9 dígitos → push MB Way chega → confirmar →
  dialog fecha em ≤6s → ecrã de sucesso → barbeiro recebe push "Nova marcação".
- **T14 (M7)** — Reservas: mesmo sheet com título "Reserva" (regressão zero).
- **T15 (M8)** — Login barbearia.nobre@bora.app com a password do ficheiro no
  Desktop → entra direto no hub Marcações → trocar a password e apagar o ficheiro.
- **T16 (M8)** — Na agenda: cancelar uma marcação confirmada com motivo → cliente
  recebe notificação (com menção a reembolso se o sinal foi pago) → sino do admin
  mostra alerta "refund_due".
- **T17 (M9)** — Abrir McDonald's: primeira secção = "Sanduíches e McMenus"
  (não "Acompanhamentos"); BK e KFC também na ordem Glovo.
- **T18 (M10)** — Cliente NÃO vê ifxfixif/pizza danilo/Pizzaria Teste Noite;
  admin → Parceiros continua a vê-las; sino do cliente do Danilo a zero.
- **T19 (M11)** — Com a app do estafeta FECHADA: cliente envia mensagem no chat →
  push com som chega ao estafeta; abrir o push → conversa.
- **T20 (M11)** — Tracking do cliente: 2 botões de chat (Restaurante + Estafeta
  após aceitar); enviar msg do parceiro → badge vermelho incrementa no tracking
  sem abrir o chat; abrir o chat → badge zera; remetente vê ✓ → ✓✓.
- **T21 (M11)** — Admin → Pedidos → detalhe → "Ver conversa" → mensagens read-only
  + entrada `chat_viewed` no Audit Log.

## BUGS EXTRA (adendo)

| Sev | Achado | Estado |
|---|---|---|
| ALTO | Edge `notify-chat-message` local estava em **v3** vs deployed v9 (drift grave) | ✅ resolvido — local=v10=deployed |
| MÉDIO | Fluxo CARD de serviços confirma via RPC sem verificar o PI no Stripe (`client_confirm_appointment_payment` confia no client) — o MB Way novo verifica; alinhar card | pendente (~1h, sessão paga.) |
| MÉDIO | `restaurants.user_` vs `user_id` divergentes (4 rows) — fonte de bugs recorrente (RLS 2026-05-20, chat hoje); consolidar numa coluna + dropar a outra | pendente (migração cuidadosa) |
| MÉDIO | `orders.driver_id` quase nunca populada mas existe (confusão com assigned_driver_id) — dropar ou backfill | pendente |
| BAIXO | Marcações `pending_payment` órfãs (MB Way/card abandonado) não têm cron de limpeza (reservas têm cancel_orphan) | pendente (~30min) |
| BAIXO | `_appt_notify_client` não faz FCM (só in-app) — cliente não recebe push de confirmação/cancelamento de marcação no telemóvel | pendente (~30min, padrão vault igual ao M8) |

## SUGESTÕES (adendo — Glovo/Uber fazem)

11. Verificação Stripe server-side no fluxo card de serviços/reservas (paridade com o MB Way novo) — ~1h.
12. Cron de limpeza de marcações pending_payment órfãs — ~30min.
13. FCM no `_appt_notify_client` (cliente recebe push de marcação confirmada/cancelada/lembretes) — ~30min.
