---
id: memoria-claude-ai-sistema-motores-e-portas
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-17
zona: verde
confianca: alta
estado: atual
---

# Quem faz o quê — uma porta só (atualizado 17/09/2026)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `sistema-motores-e-portas`, origem `claude-ai`, atualizada em 2026-09-17T13:29:01.834178+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: sistema motores e portas · memoria claude.ai · claude_ai_memoria

QUEM FAZ O QUÊ — atualizado 17/09/2026 pela Claude.ai (substitui a regra das 3 portas de 13/09).

REGRA DO DANILO (17/09, repetida e chateado): ele não quer comandar várias ferramentas nem copiar e colar entre elas. Abre SÓ o Claude Code (ou fala com a Claude.ai). O Claude Code é o CHEFE e reparte sozinho o trabalho pelos outros motores, por dentro da mesma sessão. Nenhum prompt manda o Danilo abrir o OpenCode, o ChatGPT ou o Gemini; só se ele próprio pedir.

COMO SE REPARTE: ChatGPT (conta Plus) e GLM/Qwen (plano Go) pelo comando opencode run -m <modelo> (provado a 13/09; o OpenCode usa a sessão OAuth do Codex); Codex CLI (codex exec) como reserva do ChatGPT; Gemini pela sessão paga no navegador (perfil Bora) para imagem e vídeo e pelo Gemini CLI para ler documentos longos; tudo o que precisa de clique vai pelo agente de clique no perfil certo do Chrome (skill contas-e-navegadores). Os trabalhadores fazem numa cópia ou worktree e devolvem o resultado; o Claude relê com contexto limpo, testa e é o ÚNICO que mexe em git, produção e zonas vermelhas.

FACTO QUE CONTINUA A MANDAR: pelos termos da Anthropic (ToS 19/02/2026, bloqueio 04/04/2026) a assinatura Claude só funciona dentro do Claude Code e da Claude.ai. Por isso o chefe tem de ser o Claude Code e os outros são chamados por ele — nunca o contrário.

DIVISÃO DE TAREFAS: FABLE = só o crítico (dinheiro, dispatch, wallet, publicação), enquanto houver. OPUS = chefe das missões, zonas protegidas, multi-ficheiro difícil, Chrome e clique, loop do carteiro. CHATGPT = código médio, refactors, testes, Edge Functions, scripts, imagens de propaganda (gerar também no Gemini e ficar com a melhor). GLM/QWEN = volume, bugs simples, telas, traduções, rascunhos, conselho. GEMINI = imagem e vídeo (pago primeiro), documentos longos, juiz de visão, reserva grátis. Dinheiro, dispatch, wallet, RLS, git push e publicação NUNCA se delegam. Escolher sempre o mais barato que dê conta com segurança; quem faz não verifica.

FORMATO DOS PROMPTS: no topo escreve-se o MOTOR do chefe; a porta é sempre o Claude Code. O loop automático corre no Claude Code e reparte da mesma maneira.

MISSÃO QUE TRANSFORMA ISTO EM SKILLS: PROMPT_uma_porta_habilidades_2026-09-17.md (skills globais contas-e-navegadores e distribuir-trabalho + vigia de habilidades). Executada 17/09 de manhã (sessão uma-porta-17-09, fecho e2e_log 1964): skills globais contas-e-navegadores e distribuir-trabalho ativas, delegar.ps1 e MOTORES.json no PC, vigia às 23:30. Nesse dia os motores pagos de fora estavam parados: ChatGPT Plus com a cota do Codex gasta até 19/09 09:08 e plano Go sem saldo; a cascata desceu para Sonnet e Zen grátis.

SINCRONIA: tudo o que o Danilo fala com a Claude.ai chega a esta tabela e ao Córtex; o ChatGPT lê por conector do Modo de programador e o OpenCode por MCP. Sem exceção.
