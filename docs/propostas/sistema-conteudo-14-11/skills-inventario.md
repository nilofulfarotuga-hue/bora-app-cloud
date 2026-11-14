# Skills — inventário com uso real e arrumação (bloco 2-bis, 14/11/2026)

Missão `sistema-conteudo-14-11`. Tabela completa ao lado: `skills-inventario.csv` (uma linha por
skill: usos nas transcrições, leituras do SKILL.md, última data, telemetria, referências, bytes da
descrição antes e depois, ação).

## Fiz isto

Contei o uso real das skills por script em stream (nada lido para o contexto): 2011 transcrições
do PC (cerca de 609 mil linhas, de 02/09 a 14/11/2026), chamadas `Skill`, linhas
`Launching skill:`, comandos `/nome` e leituras diretas de `skills/<nome>/SKILL.md`; mais a tabela
`skills-metrics.md`, o frontmatter `execucoes` e as referências em `.claude/`, `ferramentas/`,
agentes, ganchos e vigia do PC (ignorando ficheiros que são listas de skills).

O uso é muito concentrado: só 26 nomes foram chamados pela ferramenta Skill. `ceo-ai` 157 vezes,
`protocolo-missao-bora` 15, `chrome-browser` 12, o resto 1 a 5. Por leitura direta do SKILL.md:
ceo-ai 382, protocolo-missao-bora 326, usar-deepseek-harness 185, site-premio 96,
modo-automatico 90. Das 162 skills das duas pastas, só 51 tiveram algum uso; 111 nunca foram
chamadas nem lidas neste PC.

Juntei as duplicadas (a que fica absorve o essencial; as outras foram para `_arquivo/`):
- `entrevista` (nova) ← grilling, grill-me, grill-with-docs, interview-me. Inclui o modo Diretriz
  (entrevista por voz).
- `aprender` ← learning_engine, evolution-engine. O motor `evolution-engine/scripts/evolution_engine.py`
  fica no mesmo caminho (sem SKILL.md, com LEIA-ME), porque o daily-pulse da VPS e o agente
  `evolution-engine` o chamam lá.
- `contas-e-navegadores` ← navegadores-e-contas (fica a que o gancho e o CLAUDE.md global citam).
- `tdd` ← test-driven-development (o CLAUDE.md global cita `tdd`).
- `diagnosing-bugs` ← debugging-and-error-recovery (o SOUL do Hermes cita `diagnosing-bugs`).
As referências nas outras skills, no `AGENTS.md` e no `SOUL-base.md` do Hermes foram trocadas.

Arquivei 13 mortas (0 usos, 0 leituras, 0 métricas, nenhuma referência fora de listas, não são de
dinheiro nem segurança): canvas-design, ci-cd-and-automation, code-simplification,
documentation-and-adrs, file-form, frontend-ui-engineering, generate-skills-readme, mcp-builder,
setup-matt-pocock-skills, skill-creator (fica a do plugin `anthropic-skills`), theme-factory,
using-agent-skills, web-artifacts-builder. Arquivadas nas duas pastas; nada apagado.

Encurtei 94 descrições para uma ou duas frases (máximo 224 caracteres) mantendo o gatilho, nas duas
pastas. E corrigi 7 frontmatters que estavam partidos (YAML inválido): contas-e-navegadores,
distribuir-trabalho, memory, decision_engine, decision_registry, market-data-cleaner e
pasta-fora-da-sessao-bloqueada. Nestas o Claude Code mostrava só o título da página em vez da
descrição, ou seja o gatilho nunca aparecia. Antes, a lista de skills da sessão também já cortava as
descrições a partir de meio do alfabeto (só o nome); agora cabem todas.

O espelho `espelhar-skills.mjs` (cópia do PC e do repo) passou a saltar skills que estão em
`_arquivo/`, senão o checkout principal devolvia-as ao PC até este ramo entrar.

## Números (prova)

| | Antes | Depois |
|---|---|---|
| Skills no repo | 153 | 133 |
| Skills no PC | 157 | 137 |
| Caracteres das descrições, repo | 51 020 (≈12 755 tokens) | 24 624 (≈6 156 tokens) |
| Caracteres das descrições, PC | 53 076 (≈13 269 tokens) | 26 080 (≈6 520 tokens) |
| skills-doctor `[X]` | 0 de 153 | 0 de 133 |
| Frontmatter YAML inválido | 6 repo, 7 PC | 0 e 0 |

Ainda acima de 250 caracteres: `ceo-ai` (274, não se toca) e `testsprite-onboard`/`testsprite-verify`
(licença de terceiros, só no PC).

## Falta isto

- `ceo-ai` (acabada de reescrever, não lhe mexi) ainda cita `interview-me`/`grilling` (linha 48) e
  `navegadores-e-contas` (linhas 32 e 166): trocar por `entrevista` e `contas-e-navegadores`.
- O CLAUDE.md global (secção 11) cita `grilling`, `grill-me`, `grill-with-docs`: trocar por
  `entrevista` (o ficheiro é hardlink com o AGENTS.md do dsh; não lhe mexi).
- O dsh tem cópias próprias em `~/.dsh/skills-ponte` (learning-engine, contas-e-navegadores) com o
  texto antigo.
- Skills que faltam: o quadro Sim/Não (`quadro-sim-nao`, esqueleto criado; espera a migração
  `PROPOSTA_20261114_quadro_sim_nao_painel_admin.sql`) e a entrevista por voz (modo Diretriz dentro
  de `entrevista`; falta ligá-la à voz do Telegram pelo porteiro).

## Não arquivei (dizer antes)

Dinheiro, com 0 usos: cancel-unsubscribe, return-refund, financial-calculator, refund-assistant,
run-weekly-payouts, audit-ledger-entries, manage-promo-codes. Segurança, com 0 usos:
hermes-desbloqueio-zona-vermelha, audit-protected-zones, auditoria-seguranca-bora,
security-and-hardening, ban-or-reactivate-entity, force-driver-logout. As `hermes-*` correm na VPS,
fora destas transcrições, por isso ficam.

Candidatas fracas para uma próxima ronda (0 usos, só citadas por skills irmãs ou pelo `roteador`):
o conjunto de engenharia genérica (api-and-interface-design, browser-testing-with-devtools,
context-engineering, deprecation-and-migration, git-workflow-and-versioning,
observability-and-instrumentation, performance-optimization, source-driven-development,
spec-driven-development, shipping-and-launch, planning-and-task-breakdown,
incremental-implementation, doubt-driven-development, code-review-and-quality, idea-refine);
`category-mapper-v2` e `taxonomy-mapper` sobrepõem-se; as cinco armadilhas do Windows
(python, powershell, bash-heredoc, gh, ripgrep) podiam ser uma só.

## Erros que encontrei

Os 7 frontmatters partidos acima. 15 skills têm conteúdo diferente entre o repo e o PC (o espelho
repo→PC acerta-as na próxima corrida). A memória livre do PC estava em 351 MB no arranque (abaixo do
portão de 400 MB do trabalho leve); só corri scripts em stream com 256 MB de teto.
