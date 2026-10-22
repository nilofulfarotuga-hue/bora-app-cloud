---
id: memoria-claude-ai-digest-2026-10-15-site-botoes-lojas
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-15
zona: verde
confianca: alta
estado: atual
---

# Claude Code 15/10 — site: botões das lojas iPhone/Android

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-15-site-botoes-lojas`, origem `claude-code`, atualizada em 2026-10-15T06:48:00.339163+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 15 site botoes lojas · memoria claude.ai · claude_ai_memoria

Desde 15/10/2026 (manhã) todos os botões de descarregar do site boraguarda.com — página inicial, Entregas, Viagens, Beleza, Festas, E ainda, Ser parceiro e as 5 páginas de loja — vão para https://www.boraguarda.com/baixar?de=site-<pagina>. No iPhone abre a App Store (id6809954739), no Android a Google Play (pt.boraapp.bora), no computador a página com as duas lojas e o QR. Provado no endereço público com Playwright em iPhone 15, Pixel 7 e computador: 31 cliques, 0 errados; provas em boraguarda.com/provas/2026-10-15-botoes-lojas/. A página inicial tem os selos oficiais App Store e Google Play em português lado a lado (a loja do aparelho primeiro e maior) e um QR único para boraguarda.com/baixar?de=qr-site; acabaram o "iOS brevemente" e o "funciona no iPhone". Os botões vão para o www de propósito: no boraguarda.com sem www há uma regra de redireccionamento da Cloudflare que manda o computador para a Play Store e não conta a visita; no www a função functions/baixar.js conta por origem em link_clicks. Essa regra continua lá: os QR em papel e o da página inicial levam à loja certa no telemóvel mas não são contados até alguém a apagar no painel da Cloudflare (nenhum token do PC tem permissão de Rules). O bora-site vive em C:\BoraLocal\projetosflutter\bora-site, ramo botoes-lojas-2026-10-15, agora também no GitHub com PR #2 em rascunho para o main (traz os commits de 05-21/09 que só existiam no PC). Publica-se só com bash deploy-cloudflare.sh. Atenção: correr gerar_paginas.py contra a base hoje mete no site uma loja de teste, a Mister Navalha e a Goola; a 15/10 gerou-se com o dados/parceiros.json publicado. Falta: decidir apagar a regra da Cloudflare do apex; o mini-site Sabores do Brasil (sites-parceiros) ainda tem QR só da Play Store.
