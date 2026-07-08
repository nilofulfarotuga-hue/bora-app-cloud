# Sessão 2026-06-10 — BORA_DNA + Robot B v4 "Motor de Perfeição Contínua"

> Relatório completo: `bora_app/relatorios/SESSAO_ROBOT_B_V4_2026-06-10.md`

## Resumo
- **00_BORA_DNA.md** gravado (knowledge repo + root + Obsidian) — filosofia/decisão;
  business_rules.md vence nos números, DNA vence na filosofia. Só Danilo o altera.
- **Robot B v3 → v4**: EF `robot-b` agora tem `mode cycle` (loop observar→agir→
  sugerir→aprender), `mode digest` (semanal), crosstalk v3 intacto. Local=deployed.
- DB: `robot_runs` + `robot_suggestions` + `robot_audit_log` + `robot_observe()`
  (20 fontes) + `_robot_op_guard` + RPCs (migrations `20260610150604`→`152500`).
  Limites duros NO SQL: 10 auto-exec/ciclo, 15 abertas, benchmark obrigatório,
  dedup, não-repetição de rejeitadas 60d.
- Kill switches `robot_b_enabled` + `robot_b_auto_level1_enabled` em
  platform_settings (editáveis no ecrã admin M5).
- Flutter: `AdminRobotSuggestionsScreen` (inbox 2 tabs + métricas + aprovar/
  rejeitar/marcar feita) + card no dashboard + whitelist settings.
- `knowledge/benchmarks/{delivery,reservas,servicos}.md` (+ cópia condensada no
  prompt da EF — manter em sincronia).
- Crons: `robot-b-hourly` (35) continua OFF + novo `robot-b-weekly-digest` OFF —
  `restore_launch_mode.sql` liga ambos no launch (decisão T7 do Danilo).

## Validação executada (tudo provado)
dry-run ✅ · kill switch (EF skipped + guard SQL exception) ✅ · ciclo real
(2 auto-fixes + 3 sugestões + sinos) ✅ · aprovar nível 2 c/ payload (JWT admin
simulado) ✅ · rejeitar c/ motivo ✅ · aprendizagem dedup ✅ · digest ✅ ·
flutter analyze 0 erros ✅ · TestSprite N/A (fontes .py perdidas — pré-existente).

## 1º ciclo real encontrou
merc-79007 sem preço (desativado) · 34 preços suspeitos (needs_review) · 4
marcações órfãs pending_payment (sugestão N2 — era a pendência M11!) ·
bora_dispatch_maintenance 106ms/420 calls (sugestão N3 performance) · 60 produtos
sem foto (N3) · 1351 sem categoria · hardening M3.5 limpo (0 RLS off/0 search_path).

## Armadilhas novas
1. gemini-2.5-flash trunca JSON sem `thinkingConfig:{thinkingBudget:0}` +
   `responseMimeType:'application/json'`.
2. `UPDATE cron.job` = permission denied → `cron.alter_job()`.
3. pg_net timeout default 5s → `timeout_milliseconds := 150000` p/ EFs lentas.
4. Simular admin em SQL: claims precisam `app_metadata.role='admin'`.
5. `supabase functions deploy` CLI funciona sem Docker e lê do disco (melhor que
   MCP deploy para manter local=deployed).
