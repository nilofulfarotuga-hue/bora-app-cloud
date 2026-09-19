# Sessão 2026-06-10 — BORA_DNA + ROBOT B v4 "Motor de Perfeição Contínua"

> Missão: gravar o BORA_DNA.md (cérebro da Bora) + evoluir robot-b v3 (crosstalk)
> para v4 com o loop OBSERVAR → DIAGNOSTICAR → CLASSIFICAR → AGIR/SUGERIR →
> REPORTAR → APRENDER, inbox no admin, níveis 1/2/3, kill switches, benchmarks
> e digest semanal. Modelo: Fable 5. ⚠️ MODO PROTECÇÃO TOTAL respeitado.

---

## 1. O QUE FOI ENTREGUE

### 1.1 BORA_DNA.md (Parte A)
Gravado em 3 sítios, conteúdo exato do prompt:
- `bora_app/.claude/.ai/knowledge/00_BORA_DNA.md` (repo, committado)
- `.claude/.ai/knowledge/00_BORA_DNA.md` (root projetosflutter — CEO-AI lê daqui)
- `C:\Users\danil\Desktop\Bora\00_BORA_DNA.md` (Obsidian)

### 1.2 Base de dados (migrations remotas + cópias no repo)
| Migration | Conteúdo |
|---|---|
| `20260610150604_robot_b_v4_motor_perfeicao_continua` | Tabelas `robot_runs`, `robot_suggestions` (campos da spec + severidade/dedup_key), `robot_audit_log`; RLS fechado (sem policies — acesso só por RPC); kill switches em `platform_settings` (`robot_b_enabled`, `robot_b_auto_level1_enabled`, ambos `true`); `_robot_op_guard` (whitelist FECHADA nível 1); RPCs robô (service_role): `robot_start_run/finish_run/create_suggestion/auto_execute/notify_digest`; RPCs admin (authenticated + `_admin_op_guard`): `admin_list_robot_suggestions/audit/metrics`, `robot_apply_suggestion/reject_suggestion/mark_suggestion_done`; REVOKE FROM PUBLIC + GRANTs explícitos em TODAS (armadilha M3.5) |
| `20260610150808/150934/151040_robot_b_v4_observe*` | `robot_observe()` — 20 fontes num jsonb (cron failures, net._http_response, pedidos presos, marcações órfãs, catálogo, tokens push, crosstalk, cancelamentos, no-show, RLS/search_path local-advisors, pg_stat_statements). 2 fixes: `driver_push_tokens.user_id` + cast enum `cancellation_reason_code::text`. **No repo só a versão final consolidada (151040)** |
| `20260610152500_robot_b_v4_weekly_digest_cron` | Cron `robot-b-weekly-digest` (Mon 08:18 UTC ≈ 09:18 Lisboa) — criado **DESATIVADO** (padrão launch mode). ⚠️ `UPDATE cron.job` direto = permission denied; usar `cron.alter_job` |

**Limites duros NO CÓDIGO (o robô nunca os altera):** máx 10 auto-exec/ciclo
(contagem em `robot_audit_log` por run), máx 15 sugestões abertas (substitui a de
menor severidade; nova menos severa não nasce), benchmark obrigatório (sugestão
sem benchmark = EXCEPTION), dedup por `dedup_key`, não-repetição de rejeitadas 60d.

**Whitelist nível 1 (fechada em `_robot_op_guard`):** `flag_products_review`,
`disable_unpriced_market_products`, `clean_test_notifications`, `expire_stale_suggestions`.
**Whitelist payloads nível 2 (em `robot_apply_suggestion`):** `update_setting`
(só `robot_b_*`/`dispatch_*`/`reservation_*` operacional — espelha M5),
`hide_store`, `disable_products`, `flag_products_review`.

### 1.3 Edge Function `robot-b` v4 (local = deployed, via supabase CLI)
- `mode:'cycle'` — observa (RPC), executa nível 1 **determinístico** (sem LLM),
  Gemini 2.5-flash diagnostica e gera sugestões 2/3 → `robot_create_suggestion`.
- `mode:'digest'` — resumo semanal → sino admin.
- `mode:'crosstalk'` — comportamento v3 INTACTO (perguntas Robot A).
- default (cron hourly) — crosstalk + cycle.
- `dry_run:true` — gera tudo, escreve NADA.
- Kill switch verificado em todos os modos (OFF desliga cycle+digest+crosstalk;
  perguntas do Robot A acumulam pending sem dano).
- Fix Gemini: `thinkingConfig.thinkingBudget=0` + `responseMimeType:'application/json'`
  (o 2.5-flash gastava o output budget em thinking e truncava o JSON).

### 1.4 Flutter admin (PT-BR)
- **NOVO** `lib/screens/admin/admin_robot_suggestions_screen.dart` — 2 tabs
  (Sugestões + Auto-execuções), card de métricas (abertas/7d/auto-fixes/taxa
  aprovação + estado kill switches), filtros status/nível, detalhe em bottom
  sheet (proposta, 📊 benchmark, evidência JSON, payload), botões: **Aprovar e
  aplicar** (nível 1/2 c/ payload), **Marcar como feita** (nível 3), **Rejeitar**
  (motivo obrigatório — ensina o robô).
- `admin_dashboard_screen.dart` — card "🤖 Sugestões do Robot" (antes do Comunicação A↔B).
- `admin_platform_settings_screen.dart` — `robot_b_*` na whitelist editável (toggles).

### 1.5 Benchmarks (`knowledge/benchmarks/` + Obsidian)
`delivery.md` (Glovo/Uber/iFood) · `reservas.md` (OpenTable/TheFork/Resy) ·
`servicos.md` (Fresha/Booksy). Versão condensada vive no prompt da EF; os .md
são a fonte de verdade (mudou → atualizar ambos).

### 1.6 restore_launch_mode.sql
Linha nova: ativa `robot-b-weekly-digest` no launch (junto ao robot-b-hourly jobid 35).

---

## 2. VALIDAÇÃO (tudo executado e provado em produção)

| Teste | Resultado |
|---|---|
| **DRY-RUN** (run `c60fa762`, 200 OK) | Observou tudo; planeou 2 auto-fixes; Gemini gerou sugestões válidas; ZERO escrita |
| **Kill switch OFF** | EF devolveu `{"skipped":"kill_switch"}` + run `skipped_kill_switch`; `robot_auto_execute` direto lançou `robot_b_disabled` (guard SQL) |
| **Ciclo REAL #1** (18:52) | 2 auto-fixes executados + 3 sugestões criadas + 5 sinos no inbox admin |
| **Aprovar nível 2** (JWT admin simulado) | Payload `update_setting` executou (`rows_affected:1`), status `aplicada`, audit em `robot_audit_log` (by email) + `admin_audit_log` |
| **Rejeitar com motivo** | Status `rejeitada`, motivo gravado, `reviewed_by` set |
| **Aprendizagem** | Recriar sugestão com dedup_key rejeitado → `NULL` (não nasce) ✅ |
| **Digest** | 200 OK + sino "🤖 Digest semanal Robot B — 5 ciclos: …" |
| **flutter analyze** | **0 erros**. 148 issues = infos/warnings PRÉ-EXISTENTES em ficheiros não tocados; os 3 ficheiros da sessão estão limpos |
| **TestSprite** | NÃO executável — fontes .py desapareceram (armadilha conhecida M3.5 #5: "regenerar antes de confiar"). Pendência pré-existente, não desta sessão |

Registos de teste `[TESTE T]` (2 sugestões + sinos + audit FK) apagados no fim;
`admin_audit_log` mantém o registo oficial das ações (tudo registado).

---

## 3. 🎁 O 1º PRESENTE — o que o robô JÁ encontrou e fez (ciclo real #1)

**Auto-fixes nível 1 (executados, reversíveis, no sino):**
1. `merc-79007` (mercado, sem preço) → `is_available=false` — regra canónica.
2. 34 produtos com preço suspeito (>€500 ou <€0,05; merc-*/cnt-*/wor-*) → `needs_review=true`.

**Sugestões abertas no inbox (3):**
1. 🟡 N2 sev3 — "Liberar slots de agendamento órfãos pendentes" (4 marcações
   `pending_payment` >2h — a pendência conhecida de M11!). Benchmark Fresha/Booksy.
   ⚠️ payload cita chave que não existe → aplicar falha limpo (`unknown_setting`);
   tratar como proposta: criar cron de expiração de marcações órfãs (nível 3 de facto).
2. 🔴 N3 sev4 — "Otimizar função bora_dispatch_maintenance" (106,7ms médios,
   420 calls/24h — a query mais pesada do sistema, via pg_stat_statements).
3. 🔴 N3 sev3 — "Adicionar fotos a 60 produtos sem imagem" (benchmark catálogo 100%).

**Outros números observados:** 1351 produtos sem categoria · backlog needs_review
2853 · 0 falhas cron 24h · 0 RLS desligado · 0 search_path mutável (hardening
M3.5 confirmado limpo pelo próprio robô).

---

## 4. CHECKLIST T PARA O DANILO

- **T1** Admin → dashboard → card "🤖 Sugestões do Robot" abre o inbox; vês 3 sugestões reais + métricas.
- **T2** Abrir a sugestão N2 dos slots órfãos → "Aprovar e aplicar" → deve falhar com `unknown_setting` (prova do guard) → **Rejeitar** com motivo "chave inexistente — tratar como proposta de cron".
- **T3** Abrir uma N3 → ler proposta + benchmark → "Marcar como feita" só depois de implementada (ou Rejeitar com motivo).
- **T4** Sino admin: deves ter ~6 notificações `robot_b_*` (2 auto-fix, 3 sugestões, 1 digest).
- **T5** Configurações da Plataforma → `robot_b_enabled` e `robot_b_auto_level1_enabled` agora EDITÁVEIS (toggles) — desligar/ligar e confirmar no card de métricas do inbox.
- **T6** Tab "Auto-execuções": 2 entradas ROBÔ + 1 do teste de aprovação (email).
- **T7** Decidir QUANDO ligar os crons: `robot-b-hourly` (jobid 35) + `robot-b-weekly-digest` estão DESLIGADOS (padrão launch mode; `restore_launch_mode.sql` liga ambos no lançamento). Para ligar JÁ: `SELECT cron.alter_job(35, active => true);` + o equivalente do digest. Enquanto desligados, o robô só corre por invocação manual.
- **T8** Produto `merc-79007` desativado — confirmar que é lixo de scraping (estava sem preço) ou repor preço+`is_available=true`.

## 5. LEMBRETE ADMIN (espelho)
- O inbox, métricas, auto-execuções e kill switches TÊM espelho admin ✅.
- SEM espelho ainda: histórico de `robot_runs` (ciclos/dry-runs) — só via SQL; e
  edição da whitelist nível 1 (intencional: é hard-coded, o robô nunca a altera —
  mudanças via migration). Avaliar pós-launch se merecem ecrã.

## 6. PENDÊNCIAS / DÍVIDAS DESTA SESSÃO
1. Crons do robô desligados até decisão T7 (launch mode).
2. TestSprite irrecuperável sem regenerar os .py (pré-existente).
3. Migrations remotas 150808/150934 não têm ficheiro local (superseded pela 151040 consolidada — anotado no header).
4. `payment_method_screen.dart` modificado não-commitado no working tree (PRÉ-EXISTENTE, M11 #7 — não tocado nem commitado).
5. Sugestão N2 "slots órfãos" → implementar cron real de expiração de marcações pending_payment (era pendência M11, agora com evidência do robô).

## 7. ARMADILHAS NOVAS (para sessões futuras)
1. **gemini-2.5-flash + JSON**: sem `thinkingConfig:{thinkingBudget:0}` o modelo gasta o `maxOutputTokens` em thinking e trunca o output. Sempre `responseMimeType:'application/json'` para JSON estrito.
2. **`UPDATE cron.job` = permission denied** no MCP/migrations — usar `cron.alter_job(jobid, active => …)`.
3. **pg_net default timeout = 5s** — invocar EFs lentas com `timeout_milliseconds := 150000`; a EF continua a correr server-side mesmo com timeout do cliente.
4. **Simular admin em SQL**: `_admin_op_guard` exige claim `app_metadata.role='admin'` no `request.jwt.claims` (não basta o email na tabela).
5. **supabase CLI deploy funciona sem Docker** (warning inócuo) — `supabase functions deploy <fn> --project-ref … --no-verify-jwt` lê do disco e mantém local=deployed.
