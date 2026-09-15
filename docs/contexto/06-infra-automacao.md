# 06 — INFRA DE AUTOMAÇÃO (Hermes, Córtex, Loop, Robôs)

## Cadeia de orquestração

**Claude.ai → Córtex → carteiro.sh → Claude Code (PC) → Juiz → Telegram (Hermes)**

- Claude.ai é o CEO/orquestrador: decide, cria ordens, verifica por MCP (Supabase/Stripe/Córtex).
- Córtex Bora = cérebro/base de conhecimento na VPS, com MCP (`cortex_buscar/ler/listar/escrever/propor/nova_ordem/debt`). Governança por zonas: verde (escrita livre) / vermelha (proposta na fila do admin). `cortex_nova_ordem` exige paths de output exatos dentro da árvore indexada. OAuth se perde a cada redeploy do cortex-mcp — reconectar manual.
- carteiro.sh roda na VPS, entrega ordens ao Claude Code no PC do Danilo via SSH/Tailscale.
- Juiz: veredito mecânico 0–10 + `anti_trapaca.py`; `juiz_capture.py` pra prova visual.
- Hermes (@BoraHermesbot, Telegram): VPS `srv1786862.hstgr.cloud`, container `hermes-agent-fvnc-hermes-agent-1`, SOUL em `/opt/data/SOUL.md`, `.env` em `/docker/hermes-agent-fvnc/.env` (fora do container), `docker exec -u hermes`, restart sempre por `docker restart`. Bridge PC: `hermes@100.71.105.7` (Tailscale), `run-claude.cmd`. Comandos: `pc`, `websearch`, `readpage`, `vault`, `browse` (transporte base64 no `pc`). Modelo: OpenRouter `openai/gpt-oss-120b:free` + fallbacks. faster-whisper + Tailscale reinstalam via `bora-bridge-up.sh` após recriação do container. Danilo é a ponte Claude.ai↔Hermes (digests em code block pra ele colar).

## Regras operacionais do loop

- **Uma ordem em voo por vez** (4 simultâneas derrubaram o terminal). Consolidar tudo numa `cortex_nova_ordem`; esperar approved/cancelled antes da próxima.
- Tarefa cabe em <15 min, senão dividir. Só considerar travada após 15+ min sem output novo.
- `executor.lock` impede múltiplos `claude.exe` no PC 4GB.
- Classificador zona-vermelha: loga-e-executa (só os 3 ficheiros financeiros core são barreira dura). Trava `protege-dinheiro.sh` + `permissions.deny` protegem `.claude/settings.json` — edição só manual pelo Danilo.
- Aprovador-vermelho (30º agente, cron */10min): tria `robot_suggestions`; Balde A (não-$) auto-aprova, Balde B espera "vai" do Danilo no chat.
- Heartbeat: schtask Bora-heartbeat-desktop a cada 60min (separado do executor).
- Os "3 robôs" no Hermes: `-aprv` (aprovador, o barulhento), `-evol` (~07:25 = só contagem dry-run pro daily-pulse; análise real só manual), `-e2e` (só aparece quando o loop E2E noturno trava; o loop em si é manual).
- Robot B (Gemini, cron horário) ativo; Robot B v4 em design: 3 níveis de autonomia (L1 auto-exec reversível, L2 aprovação 1-clique, L3 proposta-only pra $/auth/Stripe/Flutter). 45+ skills; TestSprite 10/10.
- Central de Autonomia no admin: kill switch + dial de confiança. RPCs `maestro_link_suggestion` / `maestro_mark_preexisting` contra cascas ocas.

## Motor de Conhecimento (C1–C4) — COMPLETO e provado ponta-a-ponta

- **C1**: `_tools/consolidador.py` gera digest `permanente/procedural/estado-atual-consolidado.md` (teto 12KB), schtask 04:00/16:00, ordenação por peso (dinheiro-em-movimento > preço-de-catálogo), kill switch em `platform_settings` (`knowledge_consolidador_enabled`).
- **C2**: hook nativo `SessionStart` no `.claude/settings.json` injeta o digest em TODA sessão do Claude Code (executor e interativa), fail-open. Provado com canário + logs.
- **C4**: falha TRAVADA → lição-rascunho no inbox (reflexao.py formatador + pc_judge pro "certo", dedupe por hash, sem lição retroativa) → Bibliotecário promove. 3 lições reais caíram sozinhas — ciclo fechado.
- **C3 (falta)**: cartão "Motor de Conhecimento" no AdminRobotSuggestionsScreen, fonte `digest-status.json`. Só leitura, seguro.
- Pendência menor: pc_judge dentro do C4 devolve erro de cmd → "certo" fica PENDENTE (degrada em segurança; investigar com calma).
- O digest local NÃO é legível via Córtex MCP enquanto não sincronizado — pra revisar, pedir cat ao Claude Code. `business_rules.md` vive no vault Obsidian, fora deste Córtex.
- Trabalho do motor vive na branch isolada `motor-conhecimento-2026-07-20` (worktree P1); só FASE 1.10 e C4 deployados na VPS.

## E2E autônomo

- `e2e_log` no Supabase = prova real (SELECT lá, nunca a palavra do executor).
- Web headless na VPS NÃO renderiza Flutter CanvasKit (`GPU stall due to ReadPixels` — limitação de GPU; SwiftShader e xvfb falharam; GitHub Actions teria o mesmo problema). Caminho definitivo: `flutter drive` + `integration_test` (zero GPU, inspeciona a árvore de widgets). Compile web na VPS deu OOM >2.3GB → fix: swap 6G (`fallocate` + fstab). Harness: integration_test conduz só a instância CLIENTE; lado motorista/estafeta avança por SQL/RPC com prova por SELECT.
- Celular Android do Danilo por USB com USB Debugging = usar automático pra capturas.
