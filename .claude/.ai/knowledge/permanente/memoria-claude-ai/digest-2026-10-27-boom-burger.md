---
id: memoria-claude-ai-digest-2026-10-27-boom-burger
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-27
zona: verde
confianca: alta
estado: atual
---

# Claude Code 27/10 — Boom! Burger: loja Em breve + site boomburger.boraguarda.com

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-27-boom-burger`, origem `claude-code`, atualizada em 2026-10-27T15:31:20.772488+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 27 boom burger · memoria claude.ai · claude_ai_memoria

A missão boom-burger-2026-10-27 criou a loja parceira restaurants.id boom-burger-guarda (approved, coming_soon=true "Em breve", partner_commission_billing=client, horário com break_start/break_end ter-sáb) e a conta boomburger@bora.app (uid 6d9a1fe4…, user_id e user_, papéis client+partner; palavra-passe só no Telegram do Danilo). Logótipo, capa, galeria e as fotos dos 49 produtos estão no Storage restaurant-assets/boom-burger-guarda/. O menu NÃO está na base: os preços do dono não chegaram (última mensagem 08:24). Está pronto em bora-site/sites-parceiros/boom-burger/fonte/menu-preparacao.json e entra com fonte/inserir_menu.py (regra 5, ajuste ±0,01 para partner_store_share = loja; Glovo só em product_price_sources). O site https://boomburger.boraguarda.com (Pages boom-burger, noindex) tem o logótipo do dono a montar-se em CSS e o Portobello real em 3 camadas pelo contorno (tools/camadas/fatiar.py, componente 14), com position:sticky e sem pin do GSAP, porque o pin dava CLS 1,5. Medidas: Lighthouse telemóvel com mediana de 5 a 90/100/100, LCP 2,42 s, CLS 0; fiscal 100/100; 3 segundos contra a Glovo GANHA três vezes. A nota visual dos juízes independentes ficou em 71/100 (pedido 90); o que falta são as fotos novas do dono daqui a 15 dias. Lacunas reportadas: a app e o is_partner_open ignoram a pausa do almoço dos restaurantes; o portão DSA não volta a correr ao tirar o Em breve; o horário do VisitGuarda é diferente do Google. Provas em https://provas.boom-burger-778.pages.dev. Relatório em bora-site/.claude/.ai/reports/BOOM-BURGER-2026-10-27.md (commit 93df9a9, ramo botoes-lojas-2026-10-15). Próximo: adendo 2 com os preços → inserir, provar ao cêntimo, refazer a prova web, publicar o site.
