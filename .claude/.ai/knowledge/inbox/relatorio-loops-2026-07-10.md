---
id: relatorio-loops-2026-07-10
tipo: relatorio
origem: [missão "Do Prompt ao Loop" 2026-07-10 + retoma da missão noturna (Fases 5–7)]
ultima_confirmacao: 2026-07-10
zona: verde
confianca: auto
---

# 🔁 Relatório — Do Prompt ao Loop (2026-07-10)

> Sessão diurna (retoma pós-crash Bun/AVX + missão nova na mesma sessão). MODO PROTECÇÃO
> TOTAL. Princípio gravado (constituição §10): problema recorrente vira loop registado,
> medido e versionado — nunca prompt solto.

## FASE 0 — Auditoria do estado ✅
Estado real confirmado por git + transcript da sessão crashada (prompt original recuperado
de `~/.claude/projects/.../240b7ea9*.jsonl`):
- Fases 0–3 da noite ✅ (relatório) · Fase 4 🟡 pronta-para-PC (RAM) · **Fase 5 incompleta**
  → completada AGORA (evolution-engine + telemetria 49 skills + 3 agentes, ver
  `relatorio-noite-total-2026-07-09.md`) · **Fase 6 inexistente** → construída AGORA (Concierge
  com 3 provas reais) · **Fase 7** → em curso (single-device).
- Ordem ativa `ordem-20260710101114-ef7d` executada e **aprovada** (autorização explícita do
  Danilo na nota da ordem): analyze 216/0 erros · 37/37 testes · push `36bceb9`.
  Desvio registado: o commit `aa4fd18` incluiu também os ficheiros testados do loop noturno
  (cart_feedback, re-skin do carrinho, chatbot contactos) além do escopo estrito — tudo verde.

## FASE 1 — Loop Registry + Constituição + Decision Brain ✅
- **`permanente/semantica/loops.md`**: 14 loops registados com as **5 perguntas + cor + dono**
  (🟢6 · 🔵2 · 🟡3 · 🟣2 · ⚫1) + secção **Loop Economy** (custo_acumulado × retorno; heurística
  única de custo: tokens ≈ chars/4 × preço do modelo). Verificado contra os crons reais da VPS.
- **`permanente/semantica/constituicao.md`**: 10 princípios com ponteiros (só índice) — §10 é o
  princípio novo dos loops, texto exato do Danilo. **31 contratos de agentes** citam a
  constituição no topo (rollout idempotente `constituicao_rollout.py`).
- **`permanente/procedural/decision-brain.md`**: checklist 8 critérios → score 0–16 + saída de
  3 linhas. Integrado nos contratos do **CEO-AI** e do **maestro-autonomia**.
- Convenções: regra "loop novo nasce no registry" gravada; evolution-engine agora propõe
  melhorias de **loops** (não só skills) — agente + engine atualizados.

## FASE 2 — Estado Vivo + Watchdog + Cost lite ✅
- **`permanente/semantica/estado-vivo.md`** (única página que se REESCREVE — exceção
  documentada): estrutura canónica + snapshot; o daily-pulse reescreve `/opt/data/estado-vivo.md`
  na VPS toda noite (extensão instalada no `hermes-daily-pulse.sh`); o Hermes lê via `estado`.
- **Watchdog** (`/usr/local/bin/hermes-watchdog.sh`, cron 2h): ordem executando >3h · travada
  >12h · daily-pulse parado >26h · campainha morta · container down · espelho velho · disco/RAM
  ≥85% · fila >10. Severidade pela COR do registry (🟢 = alarme VERMELHO). **SÓ AVISA.**
  Limitação documentada: job logs do pg_cron exigem service key → checagem fica do lado PC/MCP.
- **Cost lite:** heurística única em `loops.md` §Loop Economy; nota no cabeçalho de
  `skills-metrics.md`; estado-vivo soma o dia (VPS ~0€ — modelos grátis).

## FASE 3 — Mission Engine lite ✅ (plano aguarda aprovação)
- Tipo de página `orquestracao/missao-<slug>.md` definido; regra no maestro (decompor via
  decision-brain, UMA ordem de cada vez) e rota 7 do Concierge (plano ANTES da 1.ª ordem).
- **`orquestracao/missao-lancamento-play-store.md`** criada: 8 ordens em sequência com scores
  (#1 ✅ feita, #2 em curso via Fase 7, #3 = triagem dos 44 crashes/7d — 1.ª ordem nova após
  o teu OK). **Nenhuma ordem nova criada** (regra respeitada). Plano segue no Telegram.

## FASE 4 — Sócio-AI Fase B + higiene ✅
- **Relatório estratégico semanal**: `/usr/local/bin/hermes-relatorio-semanal.sh` + cron
  domingo 21h00 Lisboa (30 min após o marketing-loop) — perguntas do DNA + recomendação única
  via decision-brain; ≤10 linhas no Telegram + página em `/opt/data/relatorios-semanais/`.
- **Higiene**: `cortex_nightly.py` marca `aviso: ⚠️ possivelmente desatualizada` (>60d, nunca
  zona vermelha, nunca apaga) + exporta `stale-pages.json`; o evolution-report lista as 5
  piores. Validado: hoje 0 páginas >60d.

## BACKLOG GOVERNADO ✅
`wiki/decisoes/2026-07-10-backlog-pos-lancamento.md`: Simulation Engine adiado · MIRA
candidata pós-lançamento · **WhatsApp Evolution API = proposta com risco de ban explícito**
(nunca no número principal; decisão do Danilo).

## FASE 7 (missão anterior) — loop E2E single-device 🟡 (montado; smoke bloqueado em PENDENTE-HUMANO)
- **Construído:** `runner.py` com `--single-device` PADRÃO (fluxos `dois_devices` viram
  sequenciais no mesmo telemóvel com troca de papel; `manual_2_devices` = MANUAL-2-DEVICES,
  não correm nem bloqueiam) + injeção de credenciais `.env` em todos os flows + guarda de
  isolamento (aborta com estafeta real online) · `loop-noturno.py` (classifica BUG DO TESTE
  vs BUG DO APP, re-corre só falhados, verde 2 ciclos = para exceto críticos, adb reconnect,
  nunca crasha) · `run-tudo.cmd` · flows cliente/comum/estafeta + registry.
- **Debug do smoke (login cliente) — trilha de diagnóstico real:** conta de teste OK
  (bora_role=client, confirmada) · AUTH REST 200 com a password do .env · app no build 396
  do CI · internet do device OK · **logcat apanhou a causa: a app recebe
  `invalid_credentials 400`** — a password digitada pelo Maestro chega adulterada ao campo.
  Password rodada para alfanumérica de 24 (AUTH 200 ✅); o re-run ficou bloqueado porque o
  restart do adb deixou o Xiaomi `unauthorized`.
- **PENDENTE-HUMANO:** tocar **"Permitir depuração USB" (Permitir sempre)** no Xiaomi →
  o loop noturno (já a correr em background) retoma sozinho e re-testa.
- **Descoberta paralela:** `teste-estafeta@bora.app` NÃO existe no Auth (drivers usam email
  sintético `{phone}@driver.bora.app`) — o loop de fluxos de estafeta valida isto no 1.º ciclo.

## Bugs/sinais fora de escopo (reportar TODOS)
1. 🔴 **44 crashes em 7 dias (5 ontem)** — risco Play Store; ordem #3 da missão de lançamento.
2. 2 ordens `travada` de 2026-07-09 na fila à espera do Danilo (ver `estado`).
3. Path dos pulsos errado no 1.º install do `estado` (corrigido: `/opt/data/daily-pulse`).
4. Herdados da Fase 1 da noite: no-show €3.50 não implementado · rejeição de parceiro sem
   motivo · BUG #15 (PIN client-side) · ecrãs legado duplicados.

## ⚠️ Lista Vermelha (nada aplicado por mim)
Migrations `tvde_tokens_*` estão em git; **se ainda não estiverem aplicadas no banco, a
aplicação é tua** ("vai"). Nenhum preço/fee/token/Stripe foi alterado nesta sessão.

## PENDENTE-HUMANO
Postiz no PC (Docker + OAuth) · Play Console (Conteúdo da app + países, conta
boraappbora@gmail.com) · aprovação do plano da missão Play Store · telemóvel ligado para o
loop E2E (se estiver desligado no fecho).
