---
tema: bugs-resolvidos · escopo: projeto · estado: atual · atualizado: 2026-07-02
id: bugs-resolvidos
tipo: conceito
origem: [_arquivo/MEMORY_pre_cerebro_2026-07-01.md, migration 20260702091000]
ultima_confirmacao: 2026-07-08
zona: verde
confianca: auto
---

# Bugs Resolvidos — Saga Arquitetural do Bora

> Memória episódica consolidada a partir da auto-memória do Claude Code (MEMORY.md, ~46 KB, arquivada verbatim em `_arquivo/MEMORY_pre_cerebro_2026-07-01.md`). Cada bug: sintoma → causa-raiz → fix → commit → **estado**. Detalhe completo vive nos `project_*.md`/`bugfix_*.md` da pasta de auto-memória do Claude Code.

---

## 1. `vehicle_type` hard-coded 'motorcycle' no signup — TVDE partido
- **Sintoma:** onboarding de motorista TVDE (carro) partido; toda a candidatura entra como mota.
- **Causa-raiz:** `driver_signup` força `vehicle_type = 'motorcycle'` no registo — não há escolha moto×carro na entrada. A elegibilidade moto×carro (Bloco 3) foi feita e validada ao cêntimo via MCP, mas o signup continua a forçar mota.
- **Fix (2026-07-02):** valor canónico definido — `vehicle_type ∈ {motorcycle, car, bicycle, carro_passageiros}` com CHECK `drivers_vehicle_type_canonico`; 4 grafias normalizadas (moto→motorcycle); `AuthStore.registerDriverAsync` grava `.dbValue`; `VehicleTypeDb.fromDb` aceita grafia legada 'carPassengers'; `admin_update_driver` aceita o canónico; migration `20260702091000`.
- **Origem:** `project_auditoria_paridade_360_2026_07_01.md`, sessão TVDE P0 2026-07-02.
- **estado: atual** (resolvido 2026-07-02).

## 2. Telas brancas = card stretch (Serviços/Barbearia)
- **Sintoma:** ecrã Serviços em branco (build 272, Samsung A36); Barbearia não renderizava.
- **Causa-raiz REAL:** `_ProviderCard` usava `Row(crossAxisAlignment: stretch)` dentro de `ListView` (altura ilimitada) → card esticava para a altura do viewport (~1910px), conteúdo fora do ecrã = tela branca. Latente desde a criação da feature; Barbearia foi o 1º prestador aprovado+online a renderizar. Teoria inicial "APK stale" estava ERRADA (markers [SERVICOS] mostravam raw=1 parsed=1 providers=1 sem crash — query/parse OK, era layout).
- **Fix:** stretch→center + Column mainAxisSize.min.
- **Commit:** 688bb6e (relatório FIX_SERVICOS_TELA_BRANCA_FINAL).
- **Lições:** CI `build_android.yml` auto-bumpa versionCode (por-build, não por-commit) → NÃO bumpar pubspec manual; `uiautomator dump` mostra widget na árvore mesmo invisível (bounds 1910px vs ~96px revelou o bug).
- **Origem:** `project_fase1_glovo_opcoes_2026_06_09.md`.
- **estado: atual** (fix pushed; pendente confirmação device build >272).

## 3. Telas brancas / headers branco-no-branco
- **Sintoma:** headers brancos invisíveis; telas brancas em vários ecrãs (build 241).
- **Causa-raiz:** 3 padrões de header não-unificados; `DecoratedBox` não pinta no Flutter 3.41 (33 ecrãs, provado a pixels — Bloco B4). No mapa design 2026-05-31: **0 headers branco-no-branco no código atual** — o que se via no device era APK stale (fixes design são de 2026-05-30).
- **Fix:** migrar tudo para `BoraScreenAppBar`; B4 substituiu DecoratedBox.
- **Commits:** série Fase 4 design system; mapa design e169ab9.
- **Origem:** `project_mapa_design_telas_2026_05_31.md`, `project_sessao_lancamento_b1_b4_2026_06_11.md`, `project_blocos1_4_verificacao_2026_06_29.md`.
- **estado: atual** (resolvido; latência entre fix e device = APK stale).

## 4. `chat_mark_read` 100% quebrado (uuid = text)
- **Sintoma:** marcar chat como lido nunca funcionava.
- **Causa-raiz:** comparação/cast entre `uuid` e `text` na RPC `chat_mark_read`.
- **Fix:** RPC corrigida; sem chat para loja não-parceira; FAB estafeta.
- **Origem:** `project_sessao_chat_papeis_financeiro_2026_06_12.md`.
- **estado: atual** (resolvido, pushed).

## 5. IBAN validation — PT+22 dígitos errado (aprovação de parceiro/estafeta)
- **Sintoma:** aprovação de parceiro falhava no registo.
- **Causa-raiz:** validação de IBAN esperava PT + 22 dígitos (24 chars), mas o correto é PT + 21 dígitos (23 chars).
- **Fix:** Edge Function corrigida + auth logging; também faltava `setRole(partner)` e a msg de erro era genérica.
- **Commits:** f15baad, 7aa8d36, 6148aeb.
- **Origem:** `project_sessao_partner_approval_fix_2026_05_26.md`, `project_sessao_partner_registration_debug_2026_05_26.md`.
- **estado: atual** (resolvido, deployed).

## 6. Navegação race condition — registo de parceiro
- **Sintoma:** navegação instável após registo de parceiro.
- **Causa-raiz:** `setRole` no `RegisterPartnerScreen` interferia com `_RootNavigator`.
- **Fix:** removido `setRole` do `RegisterPartnerScreen`.
- **Origem:** `bugfix_partner_nav_2026_05_27.md`.
- **estado: atual** (resolvido).

## 7. Parceiro só-serviços expulso no login (barbearia)
- **Sintoma:** barbearia (existe em `service_providers`, sem linha em `restaurants`) era expulsa no `partner_login_screen` pelo restaurant-gate.
- **Causa-raiz:** gate assumia sempre `restaurants`; só-serviços não passava.
- **Fix:** 3 ficheiros routeiam para `PartnerServicesHubScreen`; verificado live.
- **Commit:** f6585e9.
- **Origem:** `bugfix_service_only_partner_nav_2026_06_08.md`.
- **estado: atual** (resolvido, pushed).

## 8. Driver online bloqueado (motorista fraco / Android antigo)
- **Sintoma:** motorista com telemóvel fraco/Android antigo não conseguia ficar online.
- **Causa-raiz:** gate `_handleOnlineToggle` exigia 4 permissões (overlay + otimização de bateria bloqueavam). NÃO era background location.
- **Fix:** `ensureMinimumOnlinePermissions` (só notificações, nunca bloqueia) + melhorias opcionais pós-online; delivery/getPositionStream/manifest intactos.
- **Commit:** b61179c.
- **Origem:** `project_driver_online_no_background_2026_06_28.md`.
- **estado: atual** (pushed; pendente device test sem background).

## 9. Loop de dispatch (pedido preso / dispatch em loop)
- **Sintoma:** pedido preso; motor de dispatch em loop.
- **Causa-raiz:** falta de TTL + claim atómico; engine antigo.
- **Fix:** TTL + claim, engine v57, maintenance v2; guard órfão em `auth.users`; `driver_reject_offer` RPC criada + fix URL `invoke_dispatch_engine`.
- **Commits:** série blockers-launch 2026-06-09 (5 commits); a05d260 (reject).
- **Origem:** `project_blockers_launch_2026_06_09.md`, `project_sessao_dispatch_reject_2026_05_22.md`.
- **estado: atual** (RESOLVIDO + PROVADO).

## 10. Apresentação de oferta ao estafeta (FG/BG/locked) — saga longa
- **Sintoma:** oferta de pedido não aparecia consistentemente (foreground OK; background/locked falhava); overlay system_alert bloqueado no Android 14+/16.
- **Causa-raiz múltipla:** overlay `system_alert` em background bloqueado (Android 14+); Realtime cai em BG; Play revoga `USE_FULL_SCREEN_INTENT` (FSI); order de teste corrupta no DB (status=cancelled + assigned_driver_id setado) filtrava fora de `availableOrders`; realtime subscribe perdia UPDATE pré-arranque.
- **Fix (pivot):** abandonado overlay em BG → `DriverFullScreenOfferDialog` (Material widget via navigatorKey global); `OfferPresentationGate` central com 3 estados (FG laranja inline / BG-unlocked fullscreen / locked-ou-dead CallKit); FCM data-only + canal `bora_alert`; rehydrate `pending_offer`; markers [BORA-OFFER]. **REGRA OPERACIONAL:** reset completo da order antes de cada teste (não só a offer).
- **Commits:** 1cc4619, 48a0d8a, 95f4f14, e13165e, d9ec9f3, d14b2e9 (série exec1–exec6).
- **Origem:** `project_sessao_hibrido_uber_exec1_2026_05_24.md` … `project_sessao_offer_gate_exec6_2026_05_25.md`, `project_parte2_fsi_2026_06_11.md`.
- **estado: atual** (TESTE A FG OK; TESTE B BG-unlocked + C locked/dead pendentes).

## 11. FCM heads-up / token — vários bugs de push
- **Sintoma:** notificações heads-up não apareciam em background; tokens FCM perdidos.
- **Causa-raiz:** faltava `default_notification_channel_id` no manifest; `saveTokenForDriver` race; `driver_store` sem `PushTokenService`; `notify-driver` sem log; `saveTokenForPartner` gravava na tabela errada (BUG-PT-006).
- **Fix:** manifest + handler simplificado + body rico; PushTokenService no driver_store; `saveTokenForPartner`→`partner_push_tokens` + RPC migration; fallback `push_tokens` em notify-driver/partner.
- **Commits:** 76d296d, bd8e1f1, 62fae69; BUG-PT-006 na Sessão 2.2.
- **Origem:** série FCM 2026-05-22, `project_sessao_2_2_firebase_push.md`.
- **estado: atual** (resolvido).

## 12. Extras/toppings não cobrados
- **Sintoma:** `price_add` dos extras não era cobrado no total.
- **Causa-raiz:** RPCs de checkout não somavam `price_add` dos option items.
- **Fix:** 2 RPCs corrigidas; provado 3.50→5.50.
- **Origem:** `project_sessao_toppings_dedupe_2026_06_11.md`.
- **estado: atual** (T1 resolvido, pushed).

## 13. `bag_fee` duplicado
- **Sintoma:** taxa de saco cobrada em duplicado.
- **Fix:** removida a duplicação.
- **Commit:** 89a10da.
- **Origem:** `project_sessao_signup_bagfee_2026_05_22.md`.
- **estado: atual** (resolvido).

## 14. Chat — 3 root causes (trigger/tipo/backfill)
- **Sintoma:** mensagens de chat inconsistentes entre papéis.
- **Causa-raiz:** trigger de parceiro; `conversationType` errado em `driver_map_screen`; 16 mensagens sem backfill; labels de chat não-dinâmicos; `senderId`→`senderType`.
- **Fix:** 3 commits (147483d, d891f14, 7025187); customer_name backfill; migration 20260520000002 pendente prod.
- **Origem:** `project_sessao_chat_fix_2026_05_20.md`, `project_sessao_ui_fix_2026_05_20.md`, `project_sessao_ui_fix_pt3_2026_05_20.md`.
- **estado: atual** (resolvido).

## 15. `admin_approve_driver` duplicado + KYC não-bloqueante + PIN entrega client-side
- **Sintoma / achados P0 (Auditoria Paridade 360°):**
  - `admin_approve_driver` existe duplicado (2 overloads/definições).
  - KYC não é bloqueante (candidatura avança sem verificação).
  - PIN de entrega validado client-side = vetor de fraude.
  - 3 buckets de storage públicos (listing exposto).
  - zonas/surge inexistentes.
- **Fix:** ainda NÃO aplicado — reportado read-only, relatório em `audits/` (repo + Obsidian).
- **Origem:** `project_auditoria_paridade_360_2026_07_01.md`.
- **estado: atual** (abertos, P0 pré-launch).

## 16. Cadastro estafeta bloqueava (validators)
- **Sintoma:** cadastro de estafeta bloqueado por validators rígidos (nome/NIF/IBAN/MBWay).
- **Causa-raiz:** validators bloqueantes + overload antigo 11-param de `driver_register_or_update` a causar PGRST203.
- **Fix (modelo Glovo — nunca bloqueia):** migration 20260531000000 DROP overload 11-param; validators→helperText; Step0 avança sempre; uploads em try/catch; gate único = email+password+termos; pós-submit → `DriverPendingScreen`.
- **Commit:** b1fcd14.
- **Origem:** `project_sessao_admin_designsystem_2026_05_30.md` (FIX cadastro estafeta 2026-05-31).
- **estado: atual** (resolvido; RPC 14-param/RLS/dispatch intactos).

## 17. Storage 403 admin (hero/logo parceiro)
- **Sintoma:** upload de hero/logo do parceiro dava 403 no admin.
- **Causa-raiz:** path não-canónico.
- **Fix:** path canónico `{restId}/{kind}.{ext}`.
- **Commit:** 884f3a5.
- **Origem:** `project_sessao_storage_audit_2026_05_21.md`.
- **estado: atual** (resolvido).

## 18. `restaurant_dashboard` em inglês (bloqueante pré-launch)
- **Sintoma:** strings de UI em inglês no dashboard de restaurante.
- **Fix:** commit 0187c0a — 32 substituições PT-PT em 16 chunks; comentários dev + chaves Supabase preservados em inglês.
- **Origem:** `project_sessao_fase4_completa_2026_05_29.md#i18n-fix`.
- **estado: atual** (resolvido, desbloqueado).

## 19. Splash hang no CI (dart_defines não injetados)
- **Sintoma:** app pendurava no splash (builds CI).
- **Causa-raiz:** GitHub Actions não injetava `.dart_defines`.
- **Fix:** secret `DART_DEFINES_FILE_B64` + flag no `build_android.yml`.
- **Commit:** 3209cde.
- **Origem:** `project_sessao_ci_dart_defines_2026_05_30.md`.
- **estado: atual** (resolvido, run SUCCESS).

## 20. Bug scraper de preços (price=0 / preços absurdos)
- **Sintoma:** preços a 0 ou absurdos vindos de crawlers de mercado.
- **Causa-raiz:** bug de parsing (ex.: Termo price=0; lombo @65,40 ×3; contorno olhos €300).
- **Fix:** guard `price>0`; revert do backup; soft-delete de erros com `price_error_unconfirmed`/`removal_reason` (NUNCA hard delete).
- **Origem:** `project_sessao_continente_pvpr_2026_06_14.md`, `project_sessao_intermarche_2026_06_05.md`, `project_sessao_auchan_2026_06_05.md`.
- **estado: atual** (mitigado por guards).

## 21. Crawler Glovo perdia 69% do catálogo
- **Sintoma:** catálogo Glovo Auchan lido como 1953 quando o real era 6245.
- **Causa-raiz:** crawler não seguia `CONTENT_PLACEHOLDER.contentUri` (secções lazy/leaf) — falha silenciosa.
- **Fix:** walk + MAX6000; commit 379022a.
- **Origem:** `project_sessao_marketsync_noturno_2026_06_06.md`.
- **estado: atual** (resolvido).

## 22. Tela branca Favores (SendPackage/CarryGroceries) — Column max no footer
- **Sintoma:** os 2 formulários brancos (corpo invisível); breadcrumbs build 344: `bodyH=0 padBottom=48 insetsBottom=0` — insets NORMAIS.
- **Hipóteses anteriores — AMBAS estado: superado (2026-07-02):** (a) "build 340 stale nos aparelhos" e (b) "insets Android 16 esticam o footer" (fix 2c80205: clamp 40px + sanitizador viewInsets). O clamp/sanitizador ficam como blindagem, mas NÃO eram a causa.
- **Causa-raiz REAL:** o Scaffold dá ao `bottomNavigationBar` constraints soltas com maxHeight = ecrã inteiro; a `Column` dentro do `QuotePriceFooter` não tinha `mainAxisSize: MainAxisSize.min` (default = max) → footer branco de ecrã inteiro → body = max(0, ecrã − appBar − footer) = **0**. Determinístico, Android 13 e 16. Mesma família do bug #2 (card stretch): **layout flex sem mainAxisSize.min em contexto de altura solta**.
- **Fix:** `mainAxisSize: MainAxisSize.min` na Column do footer (1 linha). Breadcrumbs bodyH mantidos para a build de confirmação (esperar bodyH>0).
- **estado: atual** (fix nesta sessão 2026-07-02; pendente confirmação device).

## 23. Central de Autonomia — botão ✅ chamava a RPC errada + mojibake
- **Sintoma:** aprovar item "FEITO" dava `PostgrestException: payload_type_fora_da_whitelist (P0001)`; títulos com âœ…/â€".
- **Causa-raiz:** o ecrã chamava `robot_apply_suggestion` (que EXECUTA payloads whitelisted: update_setting/hide_store/disable_products/flag_products_review) para sugestões de evidência (payload sem 'type' executável) e mostrava o erro cru. Mojibake = SQL com acentos escrito via consola Windows cp1252.
- **Fix:** roteamento no ecrã (executável→apply; evidência→mark_done; plano N3 nova→`robot_approve_plan` RPC nova sem execução); `_friendlyError` PT-BR; regra ENCODING no `maestro-autonomia.md` (escrita via MCP/ficheiro UTF-8, nunca SQL acentuado inline na consola).
- **estado: atual** (resolvido 2026-07-02; a segurança da whitelist funcionou — o encaixe do botão é que estava errado).

## 24. TVDE — cliente não acha motorista / telemóvel mudo (P0)
- **Sintoma:** rides `sem_motorista` com `tried=[]` apesar de motorista online com heartbeat fresco; oferta das 22:47 expirou em ~25s sem o telemóvel tocar.
- **Causa-raiz (3):** (1) `tvde_offer_to_next` exigia `driver_locations.last_updated` fresco — que só atualiza quando o GPS SE MOVE; motorista parado = invisível (drivers.updated_at congelado 22:46 = última chamada de driver_update_location). (2) Aba TVDE sumia: hydrate de sessão lia só o metadata (`firstWhere` por `.name`) → carPassengers caía para car/motorcycle. (3) `notify-tvde-driver` devolve 200 SEMPRE (fire-and-forget) — falha FCM invisível; TTL 25s contava desde a criação da oferta; sem handler foreground para `new_tvde_ride_offer`.
- **Fix:** elegibilidade = `GREATEST(dl.last_updated, d.last_heartbeat_at)` fresco (heartbeat 30s = prova de vida, padrão Uber); hydrate usa `fromDb` + refresh da coluna DB por user_id; resultado FCM auditado em `tvde_ride_events` (`push_enviado`/`push_falhou`); TTL reancorado quando o FCM aceita; notificação local heads-up em foreground (canal `bora_orders_urgent_v3`); admin TVDE mostra heartbeat/GPS/token. EF `notify-tvde-driver` v3 deployed.
- **estado: atual** (resolvido 2026-07-02; pendente teste 2 telemóveis).
