---
id: memoria-claude-ai-digest-2026-09-18-jai-toi
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-18
zona: verde
confianca: alta
estado: atual
---

# Digest 18/09/2026 — missão jai-toi-link (link do Times of India no muro de imprensa)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-18-jai-toi`, origem `claude-code`, atualizada em 2026-09-18T10:30:58.034848+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 18 jai toi · memoria claude.ai · claude_ai_memoria

Sessão Claude Code (Opus, proteção total), pasta jai-site, manhã de 18/09/2026. O Aarambh (assessor de imprensa do Jai) mandou por WhatsApp o link da matéria do Times of India sobre a compra do Guarda FC e pediu-se para confirmar se é o que está no muro de imprensa. RESULTADO: já estava certo. O link publicado desde 15/08 (index.html linha 180 no JSON-LD sameAs e linha 471 no clip do muro; llms.txt linha 31) é igual, carácter a carácter, ao do Aarambh: https://timesofindia.indiatimes.com/sports/football/top-stories/indian-entrepreneur-jai-agarwal-buys-portuguese-club-eyes-pathway-for-asian-talent/articleshow/133239233.cms. As versões /pt /es /hi nascem do mesmo index.html pelo build-langs.mjs, e em produção as 4 línguas devolvem 200 com o link exato duas vezes cada (JSON-LD + clip), NDTV com 1 clip, 19 clips no total. O artigo abre com HTTP 200 sem redirect (319011 bytes), título "Indian entrepreneur Jai Agarwal buys Portuguese club, eyes pathway for Asian talent", autor Tanuj Lakhina, publicado 14/08/2026 16:39 IST; o SHA-256 do HTML de hoje é o mesmo da captura de 15/08 (0f3b28…), ou seja o artigo não mudou. Print 1280x2200 e capturas com hashes em jai-site/provas/imprensa-toi/ (índice PROVA-toi-2026-09-18.md); relatório em jai-site/RELATORIO_jai-toi-link_2026-09-18.md. Não se mexeu em código: sem QA, sem deploy, sem commit. LIÇÃO: os dois navegadores da app Claude (embutido e extensão Chrome) recusam o domínio timesofindia.indiatimes.com por regra de segurança da plataforma; o TOI em si não bloqueia curl com UA de desktop (200). Para prints de imprensa o caminho é o Edge headless com --user-agent entre aspas e --user-data-dir temporário. PENDENTE alheio: index.html tem 1 linha por commitar (meta msvalidate.01 do Bing, de 17/09), não tocada. Linha no skills-metrics.md não escrita porque esse ficheiro só existe nos repos da Bora e a ordem mandava não tocar na Bora.
