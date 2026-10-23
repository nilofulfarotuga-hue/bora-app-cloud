---
id: memoria-claude-ai-digest-2026-10-23-omniroute-ronda2
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Claude Code 23/10 — OmniRoute sem OpenCode Go (2.a ronda)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-23-omniroute-ronda2`, origem `claude-code`, atualizada em 2026-10-23T08:17:45.638606+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 23 omniroute ronda2 · memoria claude.ai · claude_ai_memoria

O Danilo decidiu NAO renovar o OpenCode Go. Feito: o Go saiu do OmniRoute (ligacao, combos e chaves). Combo agentes: Gemini 3.6, Gemini 3.7, NVIDIA nemotron, OpenRouter nemotron gratis, Groq x2, Cloudflare glm-4.7, Gemini 3.1 lite, Motor Bora. Combo privado (torre): Cloudflare e Groq (nao treinam). Regra nova: nunca 3 niveis seguidos do mesmo fornecedor - com chave Gemini invalida o Google da 400 e o OmniRoute desiste do combo ao 3.o 400 igual. Provado: 11 niveis sozinhos com ferramenta, descida gemini->nvidia e volta.
OpenCode do PC: sem chave Go; duas fontes - modelos gratis do OpenCode Zen DENTRO do OpenCode (lista real: beam, big-pickle, deepseek-v4.1-flash, flint-40b, glm-5.3-flash, mimo-v2.6-flash, nemotron-3-ultra, nemotron-3.5-lightning, nemotron-3.5-super-vl; defeito opencode/glm-5.3-flash-free, nao treina) e omniroute/agentes. SEM-LIMITE.cmd abre com o Zen gratis.
Carteiro: recurso quando o Claude esgota = GO_CADEIA omniroute zen-glm -> Hermes. pc-loop-go agora vai ao PC actual (bora-pc, danil) e corre run-opencode-recurso.ps1 (caminho real C:\BoraLocal\Desktop-PC-antigo\...; o Desktop\produtividade-ia e juncao que o ssh do Windows recusa). Claude Code nunca redireccionado. Provado com carteiro.sh --prova-cadeia: ficheiro C:\BoraLocal\provas-cadeia-motores\PROVA-RECURSO-OMNIROUTE.txt escrito pelo recurso.
Ponte Hermes->PC: o alias bora-pc ja estava certo; o bora-bridge-up.sh corria o teste como root. Corrigido, PONTE OK.
Falta: os ficheiros desta ronda no servidor (git push recusado pela tranca; commits no ramo local omniroute-23-10). Lembrete 30/10 no Cortex: desligar Motor Bora e passar os 18 perfis restantes se estiver estavel. Por corrigir (so reportado): fallback_providers do Hermes principal ainda com opencode-go e opencode-zen; disco 88%; firewall da VPS desligada com 32768/8090/8099/631 abertas; edge-tts falha; Cerebras 402.
