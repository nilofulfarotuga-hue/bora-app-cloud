---
id: memoria-claude-ai-digest-2026-10-02-mods-bora
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-02
zona: verde
confianca: alta
estado: atual
---

# Claude Code 02/10 — mods do Claude Code (bora-mods)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-02-mods-bora`, origem `claude-code`, atualizada em 2026-10-02T09:08:58.28861+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 02 mods bora · memoria claude.ai · claude_ai_memoria

Desde 02/10 o Claude Code do PC do Danilo (versão 2.1.287) carrega o plugin bora-mods, em .claude/plugins/bora-mods do repo bora-app-cloud (commit f2145c48 no ramo autonomous-night-2026-04-29, [skip ci], 0 builds). Carrega pela variável de ambiente do utilizador Windows CLAUDE_CODE_PLUGIN_DIRS; sessões abertas antes das 09:00 de 02/10 não o têm até reabrirem.
São cinco mods. A tranca proíbe por código as zonas vermelhas (lista em zonas-vermelhas.json + PROTSLUG do protege-banco.sh), push forçado, git add -A, reset --hard, rm -rf fora de build, SQL destrutivo e UPDATE/INSERT/DELETE direto em orders/drivers/wallets/ledger/bora_tokens, políticas RLS de dinheiro, deploy protegido, workflows do CI, versão do pubspec e segredos; pergunta antes de git push normal, migration, DDL e deploy de outras Edge Functions (em claude -p recusa sempre); aprova sem caixa só leitura. Se rebentar, nega. Os .sh antigos da Trava continuam a correr depois.
A vigia avisa quando uma missão fica 15 min parada (ecrã, e2e_log; Telegram só com credencial no PC, que hoje não existe) ou anda em círculos. O contador mostra contexto e limite do plano. O painel do CI mostra os builds Android/web/iPhone (/ci). O contexto junta ramo, commit e WIP aos prompts que começam por MODO PROTECÇÃO TOTAL.
Comandos: /tranca, /tranca-off N (só as aprovações), /vigia, /custo, /ci, /bora. Logs em .claude/.ai/mods/. Skill: mods-bora.
Para os outros motores: se trabalharem pelo Claude Code do PC e um comando for negado pela bora-tranca, não contornem — reportem. Regra: só mods nossos, nunca de terceiros.
Provas: validate --strict ok, 43/43 testes oficiais, 84/84 verificações com ficheiros reais, prova viva (Edit no pricing_service e push --force negados, git status sem caixa).
Falta: confirmar /plugin numa sessão aberta à mão e no Controlo Remoto; credencial do Telegram no PC (decisão do Danilo). Nota: há um commit local de outra sessão (499df7f1, assistente WhatsApp, com Flutter e 2 migrations) que NÃO foi enviado — fica para quem o fez.
