# Sessão 2026-06-09/10 — Blockers launch (dispatch TTL + órfãos + hardening) + Admin M5

> Relatório completo: `bora_app/relatorios/SESSAO_AUTONOMA_2026-06-09_BLOCKERS_LAUNCH_ADMIN.md`
> Commits: 3a6afd7 (M2) · 5b94d41 (M1) · 3d557df (M3) · 1e99ce2 (M3.5) · 8453f51 (M5)

## O que mudou (resumo técnico)

- **M1 root cause loop 5M+**: decideRedispatch sem TTL + cadeias sem dono (multiplicação)
  + maintenance que não usava max_total, não cancelava sem drivers online e reinvocava sem TTL.
  Fix: `orders.dispatch_calling_since` (trigger BEFORE âncora TTL) +
  `orders.dispatch_next_retry_at` (claim atómico de cadeia) +
  `dispatch_cancel_expired_order()` (cancel central: admin alert `dispatch_ttl_auto_cancel`
  + push best-effort) + `bora_dispatch_maintenance` v2 + **dispatch-engine v57 deployed**
  (local = deployed agora; o local antigo nem compilava). Migration `20260609230518`.
  Simulação SQL provou: engine auto-cancela aos 30 min, maintenance cancela sem drivers,
  claim exclui duplicados.
- **M2**: `_push_in_app_notification` com guard `EXISTS auth.users` (FK real é auth.users!)
  + EXCEPTION safety net; 2 broadcasts com filtro de órfãos. Migration `20260609230245`.
- **M3**: `bora_app/scripts/restore_launch_mode.sql` (NÃO executado — botão de launch).
  Crons 22/25/36-39 recuperados de `cron.job_run_details`; 23/27/29-35 reativados;
  18 horários de `_backup_business_hours_2026_06_05`; schedules escalonados (zero colisões).
- **M3.5**: anon em SECURITY DEFINER 193→8 (5 isolates by-design: driver_heartbeat_by_id,
  driver/partner accept/reject — chamados com ANON KEY pelos isolates FGS/notification!
  + 3 fns RLS); authenticated 286→125 (whitelist 108 RPCs Flutter + agent_% + ratings +
  log_admin_action); search_path fixo em 34 fns (`public, extensions, pg_temp` — extensions
  tem unaccent/pg_trgm/pg_net); listing fechado em avatars/product-images/restaurant-assets.
  ⚠️ REVOKE de role só funciona com REVOKE FROM PUBLIC primeiro (grant default!).
  Migrations `20260609232339` + `20260609232719`. md5 corpos financeiros inalterados.
- **M4/M5**: painel admin tem 54 ecrãs, hub no dashboard, 0 órfãos — auditoria revelou
  que quase tudo da lista Glovo já existia. Implementado só o que faltava (zona verde):
  whitelist financeira em platform_settings (🔒 read-only fora de dispatch_*/reservation_*
  operacionais), dupla confirmação grant/revoke tokens, label inbox do alerta TTL.

## Armadilhas para sessões futuras

1. **Grants Postgres**: funções têm EXECUTE p/ PUBLIC por default — REVOKE de anon
   é inócuo sem REVOKE FROM PUBLIC. has_function_privilege é o teste da verdade.
2. **5 RPCs precisam de anon** (isolates sem sessão): nunca revogar
   driver_heartbeat_by_id/driver_accept_offer/driver_reject_offer/partner_accept_order/
   partner_reject_order — senão heartbeat FGS morre e estafetas caem offline.
3. **Funções em policies RLS** (is_admin, _restaurant_id_of_current_user,
   user_is_order_participant) têm de ser executáveis pelo role do caller.
4. **Edge deployed ≠ local**: confirmar via get_edge_function antes de editar.
5. **TestSprite**: .py fontes desapareceram (só __pycache__) — regenerar antes de confiar.
6. Crons ativos 2+20 (Mon 03:00) e 24+42 (*/15) colidem — pendente offset.
7. payment_method_screen.dart modificado não-commitado no working tree (pré-existente).

## Pendente Danilo

- Executar restore_launch_mode.sql no launch + checklist T1-T11 do relatório.
- Ativar Leaked password protection (dashboard Auth, 1 clique).
