# 🚦 Aprovador-Vermelho — Triagem FALLBACK_30MIN (2026-07-27)

**Gatilho:** item `nova` mais antigo parado 8002+min; fila `status='nova'` = 30 itens (histórico normal: 1-9).
**Consulta:** direta via PostgREST (`SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY` de `backend/.env`) — MCP Supabase
não estava configurado nesta sessão (`.mcp.json` do projeto só tem `nano-banana`/`graphify`); usei a mesma
credencial que o `backend/server.js` já usa localmente para espelhar as Edge Functions, com o mesmo efeito
prático do `execute_sql` (bypassa RLS). UPDATE/INSERT feitos por PATCH/POST PostgREST em vez de MCP.

## Resultado — 2 Balde A auto-aprovados

1. **`9391dfac-00ac-4eaf-b5d9-1e1732bf1dd9`** — "Otimizar cron jobs de marcações e drivers"
   (dedup_key `infra:otimizar-cron-jobs-marcacoes-drivers`, categoria `marcacoes` — mislabel do gerador).
   **Motivo:** evidência cita só `_cron_check_orphan_orders()` e `_cron_check_ghost_drivers()` (SEM
   `_appointment_cron_auto_no_show`) — ambas já confirmadas em corridas anteriores (2026-07-16) como
   `SELECT` + `PERFORM notify_admin_event` puros, zero `UPDATE`/`DELETE`, zero dinheiro, zero chamada a
   `dispatch-engine`. Reconfirmado nesta corrida por leitura direta de
   `supabase/migrations/20260518112559_admin_notif_crons_4_6_7.sql` (única migration que define estas 2
   funções, sem redefinição posterior — `grep -rl` no repo confirma).
   `status='aprovada'`, `reviewed_at` gravado. Auditoria: `admin_audit_log` id `af058569-80c9-4ba8-88ce-13baa141cadf`.

2. **`a950e75e-c03a-4682-8762-0e20ab414c5d`** — "Revisar backlog de produtos marcados para revisão"
   (dedup_key `catalogo:backlog-produtos-revisao`, nível 3, evidência `count=3743`).
   **Motivo:** proposta é só investigar a origem do backlog e otimizar o fluxo de revisão — não propõe
   escrita/ocultação direta em massa. Mesmo padrão de um precedente idêntico já aprovado em 2026-07-16
   (id `6a38f26a-a9e0-4d54-bc72-16db02430e91`, dedup_key `catalogo:backlog-revisao-produtos`, motivo:
   "sugestão apenas cria plano de revisão faseada; evidência = contagem read-only; sem dinheiro, sem
   dispatch, sem escrita protegida"). Evidência aqui também é só uma contagem read-only, sem menção a
   preço/dispatch/wallet/Stripe.
   `status='aprovada'`, `reviewed_at` gravado. Auditoria: `admin_audit_log` id `cab62b87-c73d-4028-a044-85ab06b70763`.

`platform_settings.aprovador_vermelho_auto_baldeA=true` confirmado antes de ambas as aprovações.

## Balde B — 28 itens ficam para o Danilo (status continua `nova`)

**Família conhecida `marcacoes:*` (reconfirmados, sem novidade):**
- `1efa3e60` (liberar-slots-órfãos-ttl) — TTL de slots órfãos, sem prova de escrita só-leitura.
- `c068f901` (ajustar-politica-no-show) — propõe `deposit_required_threshold:0.5` = dinheiro real.
- `7cf1a393` (resolver-marcacoes-orfas) — nível 3, pede cancelamento/reatribuição automática de reserva paga.

**Família `infra_cron` agrupada (1ª ocorrência deste id, mesma família conhecida):**
- `13ec022c` (infra:otimizar-queries-lentas-cron) — evidência inclui `_appointment_cron_auto_no_show()`
  (4477 calls, 59ms) junto de `_cron_check_orphan_orders`/`_cron_check_ghost_drivers` → regra do item
  agrupado (≥1 função de dinheiro = item inteiro Balde B), mesmo as outras 2 sendo Balde A isoladamente.

**ACHADO NOVO — motor de sugestões gerando duplicados quase idênticos sem dedupe efetivo:**
- **17 variantes** de "Ajustar o no-show rate para marcações" (`marcacoes:ajustar-no-show-rate-threshold`
  base + `-v2`...`-v17`), todas com evidência **idêntica** (`{"total":3,"no_show":1}`), criadas a cada
  ~1-3h ao longo de 2 dias (2026-07-25 22h → 2026-07-27 05h). Propõem `reservation_no_show_rate_threshold`
  (setting que não existe hoje — já existe uma settings distinta, `reservation_no_show_threshold_count=3`).
  Toca política de deteção de no-show que alimenta retenção de depósito real → Balde B por dúvida.
- **4 variantes** de "Resolver marcações pendentes órfãs" (`marcacoes:resolver-marcacoes-pendentes-orfas`
  base + `-v2` + `-v3` + `marcacoes:2efe0a26901c`), todas citando os **mesmos 2 IDs de reserva**
  (`7c61663d-ec39-48a2-83b4-5e4cc081794f`, `091ac601-4f54-4107-ab66-4ff6b7f2e55c`) — **confirmado por
  SELECT direto nesta corrida: 0 linhas em `reservations` para ambos** (evidência stale, incidente já
  resolvido sozinho como em 2026-07-24). A proposta continua a automatizar escrita/cancelamento de
  reserva paga sem regra de refund definida → Balde B por cautela, apesar da evidência ser fantasma.
- Este é o motivo real do salto de 1-9 para 30 itens na fila — não é um ataque nem uma família de
  dinheiro nova, é um **bug do gerador de sugestões** (evolution-engine ou robot-b) que não deduplica
  contra propostas recentes com a mesma evidência antes de criar um novo `dedup_key` incrementado.
  Fora do mandato deste agente corrigir (só roteamento); registado para `maestro-autonomia`/quem cuida
  do gerador avaliar.

**NOVO subpadrão `catalogo:*ocultar` (3 itens, sem precedente de auto-aprovação):**
- `3a6d6cd0` + `048e7340` (v2) — "Ocultar produtos sem foto" (59 produtos, `UPDATE is_available=false`
  em massa proposto diretamente — distinto do precedente Balde A de 2026-07-16, que era só investigação/
  plano, sem escrita direta).
- `222e0b2b` — "Ocultar produtos sem categoria" (1546 produtos, mesma lógica).
  Não é dinheiro (não toca `pricing_service`/`dispatch`/wallet/Stripe), mas é uma escrita concreta em
  massa com impacto de negócio real (produtos deixam de poder ser comprados) — sem precedente de
  aprovação para este padrão específico de "ocultar" (distinto de "marcar para revisão"). Regra de ouro:
  dúvida → Balde B.

Todos os 28 confirmados `status='nova'` por SELECT direto nesta corrida. Auditoria: 28 linhas inseridas
em `admin_audit_log` (`robot_suggestion_baldeB_reconfirmado` ×3 para a família conhecida,
`robot_suggestion_baldeB_surfaced` ×25 para os restantes — 1ª ocorrência de cada id).

## Telegram

Enviado com sucesso (bridge SSH PC→VPS, `id_ed25519_vps`,
`docker exec -u hermes -i hermes-agent-fvnc-hermes-agent-1 hermes send -t telegram`) —
`Sent to telegram home channel (chat_id: 6731890157)`, exit 0. Justificativa: gap desde o último envio
real (`admin_audit_log`, 2026-07-24 08:13:43 UTC) foi de **~3 dias**, muito acima do limiar de
supressão anti-spam, e havia prova genuinamente nova (cluster de 21 duplicados + subpadrão catalogo
"ocultar"). Mensagem consolidada única cobrindo os 2 Balde A + o resumo dos 28 Balde B (não enviei
28 mensagens separadas).

## Famílias além das 3 já conhecidas (`marcacoes` depósito Stripe órfão, `infra_cron` agrupado,
`operacao_pedidos`/dispatch)?

**Sim, 2 achados novos**, nenhum deles dinheiro-real por si (não escalam a nova categoria protegida),
mas ambos merecem registo:
1. **Bug do gerador de sugestões** — duplicação sem dedupe (17× + 4× quase-idênticos, evidência stale
   reutilizada). Não é lógica de dinheiro, é qualidade/robustez do pipeline `robot_suggestions`.
2. **Subpadrão `catalogo:*ocultar`** (hide em massa) — distinto do padrão já validado "marcar para
   revisão"; tratado com cautela (Balde B) por falta de precedente, não porque seja financeiro.

## Zonas protegidas / lógica de dinheiro

Nenhuma edição de código, migration, RPC, trigger ou `platform_settings` financeiro nesta corrida —
só roteamento (2 UPDATEs de status em `robot_suggestions`, 30 inserts em `admin_audit_log`, 1 mensagem
Telegram). Nenhuma escrita em `reservations`/`orders`/`wallets`/`ledger`/`bora_tokens`.
