---
id: memoria-claude-ai-prompt-boom-hamburguer-mes-2026-11-02
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-02
zona: verde
confianca: alta
estado: atual
---

# Prompt missão Boom hambúrguer do mês (02/11/2026)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `prompt-boom-hamburguer-mes-2026-11-02`, origem `claude-ai`, atualizada em 2026-11-02T21:12:07.048598+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: prompt boom hamburguer mes 2026 11 02 · memoria claude.ai · claude_ai_memoria


⚠️ MODO PROTECÇÃO TOTAL ⚠️

MOTOR: Opus 5.5 · PORTA: app Claude no PC do Danilo, separador Code, "Este computador", pasta do repo bora-app-cloud (bora_app), modo "Ignorar permissões"
MISSÃO: boom-hamburguer-mes-2026-11-02 (e2e_log fluxo = boom-hamburguer-mes-2026-11-02, um passo por bloco)
Entra pelo orquestrador CEO-AI (.claude/skills/ceo-ai/). Antes de abrir sites: skill navegadores-e-contas. Ler primeiro erros-aprendidos, regras-do-danilo e areas boom-burger no livro.

AUTORIZAÇÃO (Danilo, 02/11/2026 21:05, texto literal): "Eu autorizo todos os síncronos, todas essas síncronas opções aí. [...] E já pode fazer um stories aí, um reels com o hambúrguer do mês. E marca o hambúrguer lá. Faz tudo, faz de tudo para nós alavancar. [...] E aí colocar lá a novidade no painel aqui, no painel principal do app, que é o hambúrguer, né? Entrou. E divulgar bem aí, para ele ficar satisfeito."
Não mexe em preços, comissões, Stripe nem dinheiro. O Café de Paris fica ao preço normal, SEM desconto.

O QUE JÁ ESTÁ FEITO (pela Claude.ai, por MCP, 02/11 20:40-21:15) — não refazer, só verificar:
- products f2ac93d2-9e77-4f02-8cbe-11a17ce91b32 (Boom! Café de Paris): category='Hambúrguer do Mês', sort_order=0, is_popular=true, descrição começa "Hambúrguer do mês. ". Backup: bkp_products_boom_20261102. Abre em primeiro na loja (RestaurantMenuScreen agrupa por ordem de sort_order).
- home_banners id 419e43f7-3cc7-4340-ad55-c9d38ae82faf: "Hambúrguer do mês na Boom!", ordem 0, tipo_destino 'produto' → o Café de Paris, fim 2026-12-01. Sem imagem (gradiente laranja).
- assistant_tenants slug boom-burger: nota nova em knowledge.ficha.notas sobre o hambúrguer do mês. Backup: bkp_assistant_tenants_boom_20261102.
- assistant_contacts (boom-burger, 351966810585): silenciado_ate 03/11 09:08 UTC, porque o robô não se calou quando o Danilo escreveu à mão.

BLOCO A — AS 5 FOTOS QUE O EMANUEL MANDOU (porquê: produtos sem foto; a Claude.ai não conseguiu subir ao Storage daqui)
1. WhatsApp Web da BORA (número 351937501673; no Chrome 5b260cdd — confirmar o número da conta aberta antes de mexer), conversa com +351 966 810 585 (Emanuel, Boom! Burger). NÃO escrever nada nessa conversa.
2. Tirar o ORIGINAL de cada foto (sem cortar, sem filtros, sem IA): 
   - foto com legenda "Boom! Café de Paris / Pão brioche com sementes sésamo…" (mandada antes de hoje; hoje às 19:28 o Emanuel citou-a) → products f2ac93d2-9e77-4f02-8cbe-11a17ce91b32
   - foto "Encaminhada" das 15:32 seguida do texto "Brownie chocolate com nozes e Gelado" → boom-brownie-chocolate-nozes-gelado
   - hoje 19:28 "Cheescake Caramelo Salgado" → boom-cheesecake-caramelo-salgado
   - hoje 19:29 "Bolo chocolate com creme pistachio" → boom-bolo-chocolate-pistacho-gelado
   - hoje 19:29 "Palitos Nutella" (no número da Bora a foto pode estar só no WhatsApp pessoal do Danilo, Chrome d9e862e0, mesma conversa "Emanuel") → boom-palitos-de-nutella
   A Claude.ai já viu as 5 e confirmou que cada foto bate com o produto.
3. Subir a restaurant-assets/boom-burger-guarda/produtos/<id>.jpg (chave do servidor pela regra da casa) e pôr photo_url + needs_photo=false nesses 5 ids. Provar: SELECT dos 5 + HTTP 200 em cada URL.
4. Pôr a foto do Café de Paris como imagem_url da faixa 419e43f7… e ver na app (web + emulador) se a faixa fica bonita com foto; se ficar pior, volta a null e reporta.

BLOCO B — ROBÔ DA BOOM PARA QUANDO O DANILO ESCREVE (porquê: às 19:29 o Danilo escreveu à mão ao Emanuel e às 19:30 o robô continuou a pedir nome e morada)
Causa achada: ferramentas/assistente-negocio/assistente.py, dono_falou(): em modo teste, qualquer número da allowlist nunca é silenciado (regra do adendo 4 de 29/10, feita para o número de teste do próprio Danilo). Hoje às 11:40 o Emanuel (351966810585) entrou na allowlist, por isso a mensagem à mão do Danilo não calou o robô.
Regra nova do Danilo (02/11): o Emanuel continua a ser tratado como CLIENTE (é ele que testa), mas quando o Danilo escreve à mão numa conversa, o robô para nessa conversa (12 h, como já está). Única exceção: o número do próprio Danilo (dono_destino, 351931992662).
Fazer: mudar a condição para só não silenciar quando numero == dono_destino; teste em simular.py com os dois casos (Danilo escreve ao Emanuel → robô calado; mensagem à mão para o 931 → robô não se cala); publicar na VPS (serviço do assistente-negocio) e provar com uma troca simulada e o registo em assistant_messages (decisao='silencio-dono-assumiu'). Verificar também que o robô usa a nota do hambúrguer do mês ("o que há de novo?" → apresenta o Café de Paris, preço normal).

BLOCO C — DESTAQUE GRANDE "HAMBÚRGUER DO MÊS" NA LOJA (porquê: o Danilo autorizou a opção 1; padrão Glovo/Uber Eats de produto em destaque no topo da loja)
- Dados: coluna nova em restaurants (ex.: produto_destaque_id text + produto_destaque_rotulo text, defeito 'Hambúrguer do mês'); migração no repo (supabase/migrations). Preencher a da Boom com o Café de Paris.
- App cliente (RestaurantMenuScreen, PT-PT): cartão largo no topo da loja com a foto, selo "Hambúrguer do mês", nome, preço por PricingService (sem calcular no ecrã) e botão adicionar. Sem produto em destaque = nada muda. Emoji da secção 'hambúrguer do mês' = 🔥 no mapa _categoryEmoji.
- Painel do parceiro (PT-PT): o Emanuel escolhe o produto do mês e o rótulo, ou tira.
- Painel admin (PT-BR): ver, trocar e tirar o destaque de qualquer loja.
- Gate do Juiz completo, flutter analyze limpo, testes verdes. Publicar nas 3 (Play, App Store/TestFlight, web) e provar nas 3. Não mexer no versionCode.

BLOCO D — STORY + REEL DO HAMBÚRGUER DO MÊS (porquê: o Danilo pediu para divulgar bem e deixar o Emanuel satisfeito)
- Base: a FOTO REAL do Café de Paris (Bloco A) — o hambúrguer não pode ser trocado nem redesenhado por IA. Movimento só de câmara (zoom lento, deslizar), texto e logos por cima. Pode haver fundo/arte de cinema gerada pelo Gemini ou ChatGPT à volta, nunca no lugar do hambúrguer.
- Leva o logo da Boom E o da Bora. Texto curto e com curiosidade: "Hambúrguer do mês" · "Boom! Café de Paris" · molho Café de Paris, cogumelos e bacon · "Peça na app Bora" · código BEMVINDO · link boraguarda.com/baixar?de=reel-boom-cafe-paris. Parte da app (se aparecer) devagar, cada ecrã parado 2-3 s.
- Story 9:16 e reel 9:16 (8-15 s, com música livre de direitos).
- Juiz com visão antes de publicar (regra 31/10): nada cortado ou sobreposto, o hambúrguer é o Café de Paris da foto, texto legível a 200 px, logos certos, sem erros de português.
- Publicar no Instagram e Facebook da Bora (boraappbora) como story e como reel, MARCANDO a Boom (achar o @ do Instagram da Boom a partir da página de Facebook dela https://www.facebook.com/people/Boom-Burger-Hamburgueria-Artesanal/61571813637975/ e gravar em restaurants.social_instagram), convite de colaboração no reel se der. Estado do WhatsApp da Bora e grupo "Marketing, vendas e propaganda Guarda" (só esse grupo). Tudo pelas contas da Bora, nunca pelas pessoais.
- Já existe um vídeo de 10 s da Boom agendado para 03/11 10:00 (fluxo boom-lancamento-2026-11-02): não o apagar nem publicar por cima à mesma hora.
- No fim, mandar ao Danilo (WhatsApp da Bora → 931992662) os links do story e do reel.

BLOCO E — FECHO
- Qualquer outro erro encontrado pelo caminho: REPORTAR no e2e_log e no relatório, não corrigir calado.
- git add só dos ficheiros desta missão; git push origin autonomous-night-2026-04-29.
- Relatório curto em texto corrido ("fiz isto, falta isto"), digest digest-2026-11-02-boom-hamburguer-mes no livro.
- /ctx doctor
- /ctx stats

