---
id: memoria-claude-ai-digest-2026-09-21-banco-pecas
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-21
zona: verde
confianca: alta
estado: atual
---

# Banco de peças 21/09 — reel Veo novo e cena Pingo Doce em dois geradores

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-21-banco-pecas`, origem `claude-code`, atualizada em 2026-09-21T07:20:54.064057+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 21 banco pecas · memoria claude.ai · claude_ai_memoria

Ordem fixa banco-pecas (08:00, Claude Code Opus, PC). VPS viva. Três dias vistos (21–23/09): só faltavam o reel de segunda 21/09 (sem linha na rotacao-reels.md, cairia no slideshow proibido) e uma cena nova de supermercado para o Pingo Doce de terça 22/09; loja 21 (Goola) e 23 (Ouro e Prata) usam foto real pelo portão do parceiro; extra 21/22/23 simulado ok; carrossel 22 = quanto-custa; reel 23 = reel-mercados (rotação); grupos 27/27.
O que funciona agora: (1) o Veo no Gemini web (perfil Bora, Google AI Plus, modo Vídeos, Vertical 9:16) DEVOLVEU vídeo pela primeira vez — "O teu vídeo está pronto!" em ~4 min, 720x1280 10 s com som; a 17/09 tinha ficado a girar. Cortei em 4 planos de 2,5 s + fecho pelo montar_reel.sh → reels/2026-09-21-reel-veo-entrega-hamburguer.mp4, fiscal_video APROVADO 93/100 (máquina 45/45, olho 48/55). (2) Dois geradores para a mesma cena, com bolt-04.png anexado: Gemini (perfil Bora) e ChatGPT Plus (perfil Danilo, conta nilofulfaro — confirmado no ecrã "Danilo Fulfaro · Plus"). No ChatGPT o anexo entra pelo input type=file da página (find + file_upload) e a imagem descarrega-se por fetch do src + anchor download (o botão de transferir só aparece em hover real). Fiscal_arte 100/100 nas duas; ganhou o ChatGPT a olho (Torre de Menagem visível). Vencedora em cenas/generico-supermarket-2026-09-22-chatgpt.jpg.
Como se usa: a extensão do Chrome só liga a um perfil de cada vez — abrir-site.ps1 abre o perfil certo, esperar ~15 s pela extensão, select_browser pelo deviceId do MAPA-CONTAS.json, e alternar entre perfis conforme o site.
O que falta: o fiscal continua a correr pela API grátis (SESSAO-VIVA sem quem a atenda; razão escrita no motor-pago/motor.log); o social-loja-do-dia.sh tenta primeiro a API (gerar_cena.py) e só usa a cena guardada se a API estiver no tecto — desenho do script, não mexido; bug do proxima_loja.py (ordena ao contrário) continua por corrigir. e2e_log 2108–2110; relatório em .claude/.ai/reports/banco-pecas-2026-09-21.md.
