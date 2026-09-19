---
id: memoria-claude-ai-mapa-sessoes-contas
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-18
zona: verde
confianca: alta
estado: atual
---

# Mapa de sessões e contas — que conta está em que sítio (provado no ecrã a 17/09/2026)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `mapa-sessoes-contas`, origem `claude-code`, atualizada em 2026-09-18T13:42:14.53873+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: mapa sessoes contas · memoria claude.ai · claude_ai_memoria

PROVADO NO ECRÃ a 17/09/2026 (missão uma-porta-2026-09-17, Claude Code) — substitui as versões de 13/09 e 16/09. Fonte de dados para os executores: ~/.claude/contas/MAPA-CONTAS.json (script ~/.claude/contas/abrir-site.ps1 <site>; skill global contas-e-navegadores). Regra: antes de abrir um site corre-se o script, escolhe-se o perfil pelo mapa, confirma-se a conta e o plano no ecrã, e MUDA-SE de perfil em vez de fazer login no perfil errado. Nunca sair de contas. Nunca confiar nos nomes "Browser 1/2" da extensão: usar o deviceId.

CONTRADIÇÕES RESOLVIDAS: (a) a conta do ChatGPT Plus é nilofulfaro@gmail.com (visto no rodapé "Danilo Fulfaro · Plus" em chatgpt.com no perfil Danilo do Chrome; o token do Codex diz o mesmo email e plano plus). A versão de 16/09 que dizia nilofulfarotuga estava errada: nilofulfarotuga é a conta GOOGLE do perfil, não a do ChatGPT. O ChatGPT do perfil Bora é boraappbora Free: proibido. (b) Google Ads (144-763-8091 Jai Agarwal) e Search Console (jaiagarwala.com): caminho PRINCIPAL = perfil Danilo (Default), conta nilofulfarotuga, abre direto sem authuser; RESERVA = perfil Bora com ?authuser=1 (a URL fica /u/1/). O navegador embutido da app Claude ficou SEM SESSÃO NENHUMA a 17/09 (pediu login no GSC, ChatGPT e Gemini) e sai do mapa como caminho.

CHROME perfil "Danilo" (pasta Default) = conta Google nilofulfarotuga@gmail.com (nilofulfaro@gmail.com como conta secundária, authuser=1). Extensão Claude in Chrome deviceId 5b260cdd-9d4f-49d6-842b-ebfbfea69c75 (visto como "Browser 1"). É o perfil que o Danilo chama "Nilo Fufaro Tuga". Aqui vivem: ChatGPT Plus (nilofulfaro@gmail.com); Search Console e Google Ads do Jai; Firebase com o projeto boraapp-d2bea (o da app, google-services.json) e BoraApp; Google Cloud da app; painel do Supabase (org Bora); Cloudflare conta 2cd0212b… (Nilofulfarotuga; jai-site e bora-site); GitHub nilofulfarotuga-hue; Gmail u/0 nilofulfarotuga e u/1 nilofulfaro; Drive pessoal; claude.ai (Max); WhatsApp Web também ligado. Gemini aqui é GRÁTIS (não usar para gerar); Play Console cai em "Creating a developer account".

CHROME perfil "Bora" (pasta Profile 1) = boraappbora@gmail.com (nilofulfarotuga como secundária, authuser=1). deviceId d9e862e0-a5ea-486f-b054-f333ef51b46a (visto como "Browser 2"). Aqui vivem: Gemini Google AI Plus ("Subscrição da Google"); Flow/Veo com PLUS e créditos; AI Studio (projeto gen-lang-client-0518472552); Play Console (conta de programador); Firebase projeto "Bora" (NÃO é o da app); Google Cloud projeto gen-lang-client-0806232393 (chaves Gemini); Gmail u/0 boraappbora; Drive da equipa; Cloudflare conta 6864b594… (Boraappbora; zonas por confirmar); GitHub (mesma conta); Meta Business Suite (business 1401256558818980, página 1230974540107256); Instagram boraappbora; WhatsApp Web da loja; Bing Webmaster Tools (SSO boraappbora, jaiagarwala.com); Wikidata DaniloFulfaroDaSilva; Resend; claude.ai (Max). O ChatGPT aqui é Free: proibido.

SEM SESSÃO EM NENHUM PERFIL a 17/09: Stripe (dashboard), Hostinger hPanel, Codemagic, Canva, opencode.ai (site), Apple App Store Connect/developer (às 10:05 de 17/09 estava expirada nos dois perfis; às 12:15 voltou a estar VIVA no perfil Bora, Apple Account boraappbora, página da app 6809954739 — a sessão Apple expira em dias). Para estes: primeiro o caminho sem navegador (MCP Supabase, MCP Canva, ssh srv1786862.hstgr.cloud, chaves já existentes, API da Apple); só em último recurso LOGIN NO NAVEGADOR PRÓPRIO no perfil certo (Apple/Stripe/Hostinger/Canva = perfil Bora) com aviso ao Danilo pelo Telegram numa linha. Postiz (social.srv1786862) dá 403 pelo navegador do PC: usa-se a API/MCP na VPS.

EDGE Perfil 1 = danilofulfaro@hotmail.com; extensão instalada mas não ligada à conta Claude (sem automação); sessões de sites não verificadas hoje.
CHATGPT PLUS PELA LINHA DE COMANDOS: opencode run -m openai/<modelo> e codex exec usam a mesma conta Plus (OAuth do Codex, ~/.codex/auth.json). A 17/09 o limite semanal estava esgotado ("try again at Sep 19th 9:08 AM"); o plano Go do OpenCode está sem saldo ("Insufficient balance" — precisa de pagamento do Danilo); os modelos grátis do Zen (opencode/nemotron-3-ultra-free, opencode/big-pickle) respondem e passaram o teste anti-mentira; o Gemini CLI não está instalado.
TELEGRAM do Danilo: chat 6731890157; envia-se pela VPS (/opt/data/voz/voz.py para voz+texto). GMAIL MCP do Claude Code = boraappbora. VPS srv1786862.hstgr.cloud por ssh pelo nome (pelo IP da tailnet fica pendurado).

ARMADILHAS PROVADAS: o separador que a extensão cria nasce numa janela em segundo plano — as apps da Google não renderizam e a captura falha com "0 width" enquanto o Danilo usa outro separador (esperar, não roubar o foco); se ele mexer nos separadores o grupo da extensão desaparece (recriar com tabs_context_mcp createIfEmpty); o javascript_tool da extensão é bloqueado em ads.google.com, business.facebook.com, opencode.ai e App Store Connect (usar find/read_page/captura); o Enter chega com keyCode 0 nas apps da Google; o save_to_disk das capturas não devolveu caminho — guardar as saídas literais como prova.

COMO SE ATUALIZA: sessão nova confirmada no ecrã → editar MAPA-CONTAS.json (campo confirmado com a data), o MAPA-CONTAS.md e esta página, com a data. Nunca escrever senhas, tokens ou chaves.

ACTUALIZAÇÃO 18/09/2026 13:20 UTC (missão ios-portugal-2026-09-18): Apple App Store Connect e developer.apple.com com sessão VIVA no perfil Bora (Negócios abriu sem login; abrir-site.ps1 exit 0). O Gmail u/0 boraappbora nesse perfil serve para anexar ficheiros a casos da Apple (file_upload no input Filedata). O separador criado pela extensão ficou visível desta vez; a captura em branco do developer.apple.com era só o SPA a carregar (esperar e ler o texto). MAPA-CONTAS.json: entrada apple confirmado 2026-09-18 13:20.
