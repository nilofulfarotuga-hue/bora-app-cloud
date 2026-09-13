---
id: memoria-claude-ai-sistema-motores-e-portas
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-13
zona: verde
confianca: alta
estado: atual
---

# Quem faz o quê — motores e portas (decidido 13/09/2026)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `sistema-motores-e-portas`, origem `claude-ai`, atualizada em 2026-09-13T18:30:27.600849+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: sistema motores e portas · memoria claude.ai · claude_ai_memoria

PLANOS a partir de 13/09: Claude Pro 20 $ (Claude Code + Claude.ai; o Max grande vai ser cancelado) + ChatGPT Plus 20 $ + OpenCode Go 10 $ + Google AI Plus. FACTO QUE MANDA: pelos termos da Anthropic (ToS 19/02/2026, bloqueio total 04/04/2026) a assinatura Claude só funciona DENTRO do Claude Code e da Claude.ai — nenhuma ferramenta de terceiros (OpenCode, Codex, Hermes) pode usá-la. Logo "um só lugar com todos os motores" é IMPOSSÍVEL por regra, não por técnica. Mínimo são DUAS PORTAS: PORTA 1 = Claude Code (só motores Claude: Opus, Sonnet; Fable só enquanto o Max durar). PORTA 2 = OpenCode (tudo o resto: conta ChatGPT Plus por /connect openai — nativo desde OpenCode v1.15.7, modelos gpt-5.x/codex; plano Go com glm-5.2, qwen3.8-max, qwen3.7-max, minimax-m3; Zen grátis; Ollama local) — troca-se o motor com /models na MESMA janela. PORTA 3 = navegador (Chrome do PC com sessões pagas): Gemini web (Veo, Nano Banana) e ChatGPT web para imagem/vídeo; pago primeiro, grátis só em último. Claude.ai = conversa, decisão, MCP direto (Supabase/Stripe), prompts; quando o limite acabar continua a conversar e manda o trabalho ao ChatGPT/OpenCode. DIVISÃO DE TAREFAS: FABLE (Claude Code) = só o crítico: dinheiro, dispatch, wallet, publicação em produção. OPUS (Claude Code, Pro) = zonas protegidas, multi-ficheiro difícil, tudo o que precisa do agente de clique/Chrome, o loop do carteiro. CHATGPT (gpt-5.x/codex, pelo OpenCode ou pela app) = código médio, refactors, testes, Edge Functions, scripts, e as imagens da propaganda/Instagram (gerar no ChatGPT e no Gemini, ficar com a melhor). GLM/QWEN (plano Go, no OpenCode) = volume, bugs simples, telas, traduções, rascunhos, conselho de modelos. GEMINI (AI Plus no navegador + API grátis + Gemini CLI) = imagem/vídeo, leitura de documentos longos, juiz de visão, reserva grátis. Escolher sempre o mais barato que dê conta com segurança; Claude só quando nenhum dos outros serve. Todo prompt marca no topo MOTOR + PORTA. O loop automático (cortex_nova_ordem → carteiro → executor no PC) corre SEMPRE no Claude Code; OpenCode é só colagem manual do Danilo. TUDO O QUE O DANILO FALA COM A CLAUDE.AI CHEGA AQUI (esta tabela) e ao Córtex: ChatGPT lê por Developer Mode > conector MCP (Supabase + Córtex), OpenCode lê por MCP remoto. Sem exceção.
