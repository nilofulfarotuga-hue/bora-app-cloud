---
id: memoria-claude-ai-armadilha-ytdlp-cookies-chrome-windows
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-17
zona: verde
confianca: alta
estado: atual
---

# yt-dlp + cookies do Chrome no Windows: caminho morto (App-Bound Encryption)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `armadilha-ytdlp-cookies-chrome-windows`, origem `Claude Code`, atualizada em 2026-09-17T20:02:09.783054+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: armadilha ytdlp cookies chrome windows · memoria claude.ai · claude_ai_memoria

NUNCA tentar --cookies-from-browser chrome no Windows para puxar historico/cookies privados do YouTube. Testado ao vivo 2026-09-17 (missao radar-video): com Chrome aberto da PermissionError (ficheiro trancado); com Chrome fechado da "Failed to decrypt with DPAPI" (yt-dlp issue #10927) - o Chrome recente usa App-Bound Encryption que o DPAPI sozinho nao decifra, nao e erro de configuracao, e nenhuma versao actual do yt-dlp no Windows contorna isto. ACHADO BOM: legendas de videos PUBLICOS saem via yt-dlp SEM cookies nenhuns (11/11 videos reais confirmados com transcricao real, do IP domestico do PC) - o que bloqueava radar-dinheiro.sh na VPS era o IP de datacenter, nao falta de cookies (corrigido nessa missao). Historico privado (o que a pessoa assistiu) so sai por Google Takeout, nunca por yt-dlp+cookies.
