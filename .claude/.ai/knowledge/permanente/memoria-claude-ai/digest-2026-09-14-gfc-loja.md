---
id: memoria-claude-ai-digest-2026-09-14-gfc-loja
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-16
zona: verde
confianca: alta
estado: atual
---

# Digest — loja online do Guarda FC (missao gfc-loja, 14–17 set 2026)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-14-gfc-loja`, origem `claude-code`, atualizada em 2026-09-16T23:48:20.739886+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 14 gfc loja · memoria claude.ai · claude_ai_memoria

A loja online do Guarda FC existe como copia de trabalho em https://guarda-fc-loja.pages.dev/loja/ (sem palavra-passe, noindex) com o painel do clube em /loja/admin/; o site vivo guardafcsad.com nao foi tocado (build sem flag byte-igual em todos os blocos). Provas publicas com video de 60 s em https://boraguarda.com/provas/guarda-fc-loja/. Codigo no ramo loja-2026-09-14 do repo guarda-fc-site (18 commits, do 248bf45 ao e389a3c); relatorio em loja/RELATORIO-2026-09-14.md e copia em Desktop/Bora/Projetos; ordem de continuacao em loja/ordens/CONTINUACAO.md.
O que funciona agora: catalogo real de 19 pecas (renders do fornecedor UIN/Select, nenhuma imagem de IA; a camisola 3D foi reprovada e apagada), nome e numero compostos sobre a imagem real no browser, 4 idiomas (hindi a serio), carrinho, checkout Stripe SO EM MODO DE TESTE (cartao + MB Way; a chave so e aceite se for sk_test_; as chaves vivas serao as da conta do clube, nunca da Bora), base D1, webhook assinado e idempotente, pagina da encomenda, painel do clube PT/EN (pedidos e estados, precos por versao, stock por tamanho, edicao limitada numerada, lista de espera, cupoes, muro, grupos, CSV), pedido em grupo com um link so, packs pai/filho e mae/filha, muro dos adeptos, contagem da proxima leva, pagina de levantar no estadio com o jogo real. Fiscal visual: home 100/100 (tambem online), ficha 94, configurador 94, movimento reduzido 0 falhas, 102 imagens com origem.
Como se usa: em local, `bash loja/deploy-loja.sh --so-stage` + `wrangler pages dev dist-loja --d1 DB` + `python loja/ferramentas/stripe_falsa.py 8791` e os scripts de prova (fluxo_pagamento_local.py, testar_api.py, testar_admin.py, provar_b5.py, capturar_b*.py); guia completo em loja/functions/README.md. Publicar: `bash loja/deploy-loja.sh` (token da Cloudflare do bora-site; o wrangler empacota functions/ do cwd, por isso o deploy corre de dentro do stage).
O que falta e so o Danilo pode dar: login na Cloudflare (pagina aberta no Chrome, perfil boraappbora) para criar a D1 guarda-fc-loja, o binding DB e as variaveis (ADMIN_PASSWORD, STRIPE_SECRET_KEY sk_test_, STRIPE_WEBHOOK_SECRET, RESEND_API_KEY, EMAIL_FROM, TELEGRAM_*); login na Stripe de teste do clube (chaves + endpoint /api/loja/webhook). Ate la a loja mostra tudo mas a API responde 503 "por configurar". Depois disso: compra ponta a ponta na previa com cartao 4242 e MB Way de teste, com gravacao. Ficam tambem: precos reais no painel (os atuais sao de demonstracao), fotos do produto final quando as camisolas chegarem, textos legais revistos pela Dina, ligacao a Bora (so desenho em loja/INTEGRACAO-BORA.md).
Licoes: o Codex (gpt-5.5) bateu no limite de uso tres vezes; os blocos de dinheiro (3-6) foram do Opus. O modelo 3D por codigo nao passa por fotografia — a solucao foi a imagem real do fornecedor com composicao por cima. A Cloudflare devolve 403 cod. 1010 ao user-agent do urllib (usar UA de browser). O token da Cloudflare do PC nao tem D1. Em heredocs do Bash as barras desaparecem — scripts grandes via Write.
