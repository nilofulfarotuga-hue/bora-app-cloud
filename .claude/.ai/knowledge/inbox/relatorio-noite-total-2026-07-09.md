---
id: relatorio-noite-total-2026-07-09
tipo: relatorio
origem: [missão noturna total 2026-07-09 — 7 fases: Olho do Bora + Cérebro de Marca + Evolução + Hermes em tudo]
ultima_confirmacao: 2026-07-10
zona: verde
confianca: auto
---

# 🌙 Relatório — Missão Noturna Total 2026-07-09/10

> Sessão autónoma (branch `autonomous-night-2026-04-29`). MODO PROTECÇÃO TOTAL.
> Lista Vermelha 🔴 = só proposta. Fase a fase, em ordem.

---

## FASE 0 — Hermes volta a enxergar o Córtex ✅ (concluída ~00:45)

**Diagnóstico:**
- O espelho `/opt/data/cortex-brain` **existia e estava fresco** (branch
  `autonomous-night-2026-04-29`, último commit do próprio dia — o cron do host às 06:30
  `/root/cortex-mcp/sync-brain.sh` + o Córtex MCP comitam nele). Deploy key em
  `/opt/data/.secrets/cortex_deploy_ed25519` ✅ (sem PAT em URL).
- Permissões OK: espelho é `hermes:hermes`; `docker exec -u hermes` lê o INDEX sem erro.
- **Gaps reais:** (1) SOUL.md não mencionava o Córtex — o roteador mandava "Conhecimento da
  Bora" só para o `vault` (espelho Obsidian, complemento); (2) `bora-bridge-up.sh` só
  re-garantia o tailscale, não o espelho.

**Feito:**
1. **Comando novo `cortex "<assunto>"`** no container (padrão do `vault`): pesquisa
   `/opt/data/cortex-brain/.claude/.ai/knowledge/` (INDEX por nome, grep no conteúdo com
   accent-folding + `LC_ALL=C.UTF-8`). Master em `/opt/data/bin/cortex` (volume, sobrevive
   recreate); instalado em `/usr/local/bin`.
2. **SOUL.md ensinado** (backup `SOUL.md.bak_fase0_*`): roteador agora manda "Conhecimento
   da Bora" PRIMEIRO ao `cortex` (Córtex oficial = fonte de verdade), `vault` como
   complemento; playbook "CÓRTEX DO BORA" no fim (nunca inventar regra; citar a página).
3. **`bora-bridge-up.sh`** ganhou bloco idempotente: re-garante `git`, o espelho (clone com
   deploy key se faltar) e o comando `cortex` após recreate do container. `bash -n` OK.
4. **Lição generalizável** gravada: `wiki/licoes/comando-custom-container-master-no-volume.md`.

**PROVA REAL ✅:** `hermes -z "Qual é a comissão do parceiro restaurante?"` → respondeu
**10% visível + 5% markup + 5% service fee, citando `permanente/semantica/pricing.md`**
(conteúdo real do Córtex). Progresso enviado ao Telegram do Danilo via
`hermes send --to telegram` (chat 6731890157) ✅.

**Pendências/nota:** RAM disponível na VPS = **2.3 GiB < 2.5 GiB** (regra da Fase 4) →
Postiz será deixado pronto para o PC, não instalado na VPS (números: 3.8 Gi total,
disco 35 G livre — ver Fase 4).

---

## FASE 1 — Mapa completo de fluxos ✅ (concluída ~01:30)

**Feito:** varredura fan-out (4 agentes Explore em paralelo: cliente, estafeta/TVDE,
parceiro+transversal, anti-regressão+backend) → **5 ficheiros** em
`permanente/semantica/` (padrão backend-map, todos < 8 KB):
- `mapa-de-fluxos.md` (índice + convenções de teste + isolamento de dispatch)
- `mapa-de-fluxos-cliente.md` (11 fluxos) · `mapa-de-fluxos-estafeta.md` (11)
- `mapa-de-fluxos-parceiro-transversal.md` (13) · `mapa-de-fluxos-antiregressao.md`
  (24 checks, 1 por bug de `bugs-resolvidos.md` + backend por fluxo 🔴 marcado)

**Descoberta-chave para E2E:** o dispatch NÃO tem raio duro/zona → isolar teste =
estafeta de teste é o ÚNICO online elegível. `Semantics(identifier:)` = 0 em toda a lib
→ Maestro por TEXTO (labels PT exatos catalogados); Fase 2 adiciona identifiers.

**Bugs/gaps fora de escopo detetados (reportar, não corrigir esta noite):**
1. No-show entrega €3.50 NÃO implementado (só cancel fees E1–E4 + no-show TVDE/reserva).
2. Rejeição de pedido pelo parceiro sem captura de motivo.
3. BUG #15 (P0, já conhecido): PIN validado client-side; `admin_approve_driver` duplicada.
4. Ecrãs legado a coexistir: `send_package_screen.dart`, `map_screen.dart` cliente,
   `ReservationFlowScreen` (vs PRO).
5. Split reserva na missão estava desatualizado — real: €2 parceiro + €1 Bora (BR §18).

---

## FASE 2 — Cinegrafista + Dedos + Runner 🟡 (95% — falta smoke re-run pós-build)

**Instalado e validado (Windows nativo, SEM WSL2):**
- **scrcpy 4.0** (winget) — cinegrafista grava por fluxo com sidecar de sincronização;
  MP4 de teste validado. Gotcha: modo CLI standalone morre com o shell pai → usar em
  modo módulo (o runner usa assim). `.claude/testes-e2e/README.md` documenta tudo.
- **Maestro 2.6.1** (zip GitHub + JDK 17 existente) — CLI nativo Windows funcional.
- **MCPs registados** (ativos na próxima sessão): `maestro mcp` oficial + `scrcpy-mcp`
  (npm, olhos+mãos ao vivo).
- **2 telemóveis ligados:** Samsung A36 `RZGYB1XQD2P` (app v396, papel cliente) e
  Xiaomi Redmi `N75LTG...` (papel estafeta — app em instalação via build local).
- **Semantics identifiers** (commit `3c6ee08`, só UI, analyze 0 erros): login cliente/driver,
  tiles da home, toggle online, oferta aceitar/recusar, recolher/iniciar/concluir + PIN,
  parceiro aceitar/rejeitar/chamar estafeta, cancelar pedido.
- **Runner completo** (`runner.py`): cinegrafista → Maestro → poll Supabase read-only →
  frames automáticos na falha → resultados JSON + resumo no inbox. **Guarda de isolamento**:
  fluxo 2-devices ABORTA se houver estafetas reais online.
- **Contas de teste criadas** (Auth Admin API, credenciais em `.env` gitignorado):
  `teste-estafeta@bora.app` (drivers row aprovada, OFFLINE por defeito, Guarda) +
  `teste-parceiro@bora.app`. Limpeza: `limpar-dados-teste.py` (marca `is_test_order`,
  NUNCA apaga — ledger é append-only).
- **Smoke test da cadeia** já correu ponta-a-ponta (vídeo gravado + frames extraídos na
  falha ✅); a falha foi OOM da JVM (gradle em paralelo) → fix: heap capado + regra
  "nunca Maestro durante build". Re-run após o build terminar (Fase 7 cobre).
- **Limpeza de disco autorizada pelo Danilo:** 2.6 → 15.7 GB livres (lixeira 8.1 GB +
  IPSW DrFone de fev/2024 6.8 GB + npm cache + TEMP). Override local
  `~/.gradle/gradle.properties` (Xmx1536m) — o do repo (4g) era maior que a RAM do PC.

---

## FASE 3 — Cérebro de Marca + Diretor Criativo ✅

- **`brand-brain.md`** criado em `permanente/semantica/` (cores/fonte/logo reais do repo,
  tom PT-PT, 4 personas com números verificados, regras duras, anti-slop).
- **Ferramentas anti-slop clonadas e revistas** (ambas utilizáveis, formato skill):
  `avoid-ai-design` (visual, catálogo P0/P1) + `stop-slop` (prosa) em
  `.claude/skills/diretor-criativo/referencias/`.
- **Skill `diretor-criativo` v1** com pipeline completo + telemetria no frontmatter
  (1.ª skill com o padrão da Fase 5).
- **PROVA REAL ✅ — campanha "O Bora chegou à Guarda"**: 4 personas × 3 conceitos ×
  3 formatos = **36 artes** em `marketing/campanhas/bora-chegou-a-guarda/` + estratégia +
  copy (stop-slop 39-42/50) + calendário. O gate de auto-crítica REPROVOU e refez 5 imagens
  (texto embutido, "LANCHONETE" brasileiro, matrícula legível, 2× volante à direita) —
  o filtro anti-slop funcionou na prática.
- **Proposta de paridade registada:** `inbox/proposta-admin-marketing-screen.md` (spec, não construída).
- PENDENTE-HUMANO: compor logo+texto Inter sobre as artes antes de publicar (zona limpa reservada).

---

> ⚠️ O relatório foi cortado AQUI pelo crash da sessão (bug Bun/AVX). As secções abaixo
> foram escritas na RETOMA de 2026-07-10 (auditoria de estado → completar sem refazer).

## FASE 4 — Postiz + Marketing Loop 🟡 (pronta-para-PC, por design)

- VPS **reprovada pela regra de RAM** (2.3 GiB < 2.5): números documentados; `infra/postiz-pc/`
  (docker-compose.yml + README-POSTIZ.md com o guia de 5 min de OAuth) fica pronto para o PC.
- Skills criadas: `social-publisher` (dry-run → `marketing/fila-publicacao/`) e
  `marketing-loop` + cron semanal no Hermes (domingo 20h30, `/root/marketing-loop-weekly.sh`).
- **PENDENTE-HUMANO:** Docker Desktop no PC + ligar contas Instagram/Facebook por OAuth.

## FASE 5 — Evolution Engine + telemetria + 3 agentes ✅ (completada na retoma 2026-07-10)

- **EvoSkill → opção (b)** (só conceitos nativos; zero caixa preta) — ADR
  `wiki/decisoes/2026-07-10-evolution-engine-governado.md`.
- **Telemetria universal:** 49 skills com frontmatter padrão (46 via `telemetria_rollout.py`
  idempotente + 3 nativas) + secção de registo; consolidação em `wiki/skills-metrics.md`.
- **Meta-skill `evolution-engine`** (SKILL.md + `scripts/evolution_engine.py`, stdlib):
  5 capacidades, estado anti-reproposta, saída em `inbox/evolution-report-<data>.md`.
- **Daily-pulse** ganhou o passo evolution-report (skill local + cron da VPS).
- **3 agentes novos** (26→29): `diretor-criativo`🟢 · `social-media`🟢 · `evolution-engine`🟡.
  `exercito.md` e CLAUDE.md (elenco + despacho) atualizados.
- **PROVA REAL ✅:** 1.ª execução → 26 propostas no inbox; auto-análise da noite → **v2 do
  diretor-criativo** (4 restrições pré-geração vindas das 5 reprovações do gate) aplicada
  após Juiz (anti-trapaça CLEAN). Ciclo criar→executar→medir→evoluir→julgar→versionar
  fechado na mesma missão.

## FASE 6 — Hermes Concierge ✅ (2026-07-10)

- **SOUL.md** += playbook "HERMES CONCIERGE" (backup `SOUL.md.bak_fase6_*`): 6 rotas +
  rota 7 (Mission Engine). Comandos novos no container: **`estado`** (read-only:
  estado-vivo/pulso + fila) e **`ordem`** (cria ordem respeitando UMA-ordem-de-cada-vez +
  recusa zona vermelha com o MESMO regex do carteiro). Masters em `/opt/data/bin`,
  re-garantidos pelo `bora-bridge-up.sh`. Governança: `permanente/semantica/hermes-concierge.md`.
- **PROVAS REAIS ✅ (3/3):** (1) Córtex: taxa de sacos €0,30/€0,10 citando business-rules;
  (2) banco read-only: 1 pedido ontem, GMV €36.44, 44 crashes/7d; (3) draft de mensagem ao
  grupo de testadores terminando em "Confirmas o envio? (sim/não)" SEM enviar.

## FASE 7 — Loop E2E noturno 🔄 (adaptação --single-device em curso na retoma)

- **Adaptação do Danilo (1 telemóvel):** fluxos `[2-DEVICES]` viram sequenciais no mesmo
  device (cliente cria cash `[E2E-TESTE]` → troca para `teste-estafeta@bora.app` → aceita →
  recolhe → entrega → valida no banco); parceiro via painel admin/web no PC; tempo-real
  obrigatório (TVDE ao vivo) → `MANUAL-2-DEVICES`. runner `--single-device` = padrão;
  `loop-noturno.py` + `run-tudo.cmd` novos. Resultado do smoke e estado final: ver
  `relatorio-loops-2026-07-10.md` (missão seguinte, mesma sessão).

## Encerramento da noite (na retoma)
- Ordem `ordem-20260710101114-ef7d` (fechar TVDE tokens + autocomplete) **APROVADA** com
  autorização explícita do Danilo: analyze 216/0 erros, 37/37 testes, commits
  `42a57dc`+`aa4fd18`+merge `36bceb9`, push OK. Migrations tvde_* commitadas em git —
  **⚠️ aplicar ao banco (se ainda não aplicado) é ato do Danilo (Lista Vermelha).**
- Bugs fora de escopo achados na retoma: **44 crashes/7d (5 ontem)** — prioridade máxima
  pré-lançamento (ordem #3 da missão Play Store) · 2 ordens `travada` de 2026-07-09 à
  espera do Danilo · pulso não encontrava pulsos (path corrigido para `/opt/data/daily-pulse`).
