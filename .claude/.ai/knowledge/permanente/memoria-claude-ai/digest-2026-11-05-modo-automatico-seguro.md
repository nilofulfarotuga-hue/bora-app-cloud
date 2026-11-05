---
id: memoria-claude-ai-digest-2026-11-05-modo-automatico-seguro
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-05
zona: verde
confianca: alta
estado: atual
---

# Claude Code 05/11 — modo automático seguro (por ligar)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-11-05-modo-automatico-seguro`, origem `claude-code`, atualizada em 2026-11-05T20:32:51.826562+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 11 05 modo automatico seguro · memoria claude.ai · claude_ai_memoria

Missão modo-automatico-seguro-2026-11-05 (PC, Opus). Feito e ativo: skill modo-automatico em ~/.claude/skills e no ramo, linha no CLAUDE.md global (hardlink do dsh intacto) e .claude/CLAUDE.md em 11 projetos; o cofre Obsidian não foi tocado, vale a linha global. Inventário em docs/INVENTARIO_PROJETOS.md. Feito e DESLIGADO: trava PreToolUse global, regras deny de leitura de segredos, remendo das guardas antigas e CI revisao.yml, tudo em docs/propostas/modo-automatico no ramo ai/2026-11-05-modo-automatico-seguro, pedido de revisão bora-app-cloud#6 (mergeable, sem CI, nada publicado; o versionCode 716 que subiu foi do robô, não desta missão). A bora-tranca recusou escrever em .claude/hooks e .github/workflows (e2e_log 6756, 6757) e não se contornou. Liga-se com duplo clique do Danilo em ATIVAR-MODO-AUTOMATICO.cmd no Ambiente de Trabalho; desliga-se com DESATIVAR. O instalador usa o worktree C:/BoraLocal/wt-modo-auto-05-11: não o apagar antes do clique. Depois do clique nenhuma sessão do Claude Code envia para o ramo principal nem faz deploy: publica o Claude.ai. Armadilhas novas: (1) o allow do tool.check da tranca passa por cima do deny de outro gancho PreToolUse; provado em sessão real, um .env falso foi lido apesar do deny; só o deny dos settings e a tranca sem aprovar é que travam, e a tranca remendada resolve; (2) git worktree add -b ramo origin/principal fica a seguir o ramo de produção: usar --no-track; (3) o git-guardrails recusa ramos ai/ até ao clique; os dois envios desta missão passaram porque a sessão começou fora da pasta do projeto e o gancho do projeto não estava carregado, com a pergunta da tranca a dar permitida; (4) pipe do PowerShell 5.1 para um programa nativo estraga o JSON e o guardrail deixa passar: testar ganchos com spawnSync; (5) o gh do PC não tem a permissão workflow e pode recusar o CI no clique. Testes: 160 a bloquear, 74 a deixar, 0 falhas; trava vazia dá 170 falhas; verificador de contexto limpo achou 16 buracos e 13 falsos alarmes, casos nos testes. Sem flutter analyze/test: o ramo não mexe na app. Para o Claude.ai: regras-do-danilo secção 7 ainda diz que toda a sessão acaba com o envio, e o AGENTS.md diz Claude Code = publicar; contradizem a skill. Relatório .claude/.ai/reports/modo-automatico-seguro-2026-11-05.md. Commits 73a0ae70 e 3f438d23.
