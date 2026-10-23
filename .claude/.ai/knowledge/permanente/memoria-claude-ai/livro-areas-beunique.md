---
id: memoria-claude-ai-livro-areas-beunique
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# BeUnique Beauty & Academy (salão beleza, Guarda) — negócio NÃO fechou; loja desligada do app a 28/08. Histórico do que chegou a ser montado

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-beunique`, origem `claude-ai`, atualizada em 2026-10-23T05:34:57.805479+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas beunique · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/beunique.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: beunique
description: BeUnique Beauty & Academy (salão beleza, Guarda) — negócio NÃO fechou; loja desligada do app a 28/08. Histórico do que chegou a ser montado
sources: [chat]
aliases: [BeUnique, Be Unique, BeUnique Beauty and Academy, beunique.beauty.academy]
---
- [stated] BeUnique Beauty & Academy — salão de estética/beleza na Guarda. JÁ É PARCEIRO de Serviços APROVADO no [[bora-app]] (correção: antes eu tinha anotado que NÃO estava cadastrado — está sim, desde 2026-07-18). service_provider id 192c7d0b-b8ef-4d52-bac3-307895fbbf8e, owner user_id 9ad600b6-2a78-4a86-b962-96e7b496b9a2, LOGIN beunique@bora.app, category 'beauty', approved, is_online. Danilo vai presentear com mini-site cinematográfico (esquema [[ouro-e-prata]]/[[sabores-de-casa]]).
- [stated] Contato na loja: BRUNA (funcionária; Danilo conheceu-a no TVDE, já lhe explicou o app; disse que passaria lá quando estivesse pronto).
- [stated] Dados (banco): "R. Calouste Gulbenkian, Lote 11, 6300-670 Guarda"; phone 966383255; horário Ter–Sex 9–19h, Sáb 9–17h, Seg/Dom fechado; avg_rating 4,8 / 209 avaliações. Descrição no app: cabelo, unhas, estética, sobrancelhas, pestanas, micropigmentação, massagem, depilação, medicina estética.
- [stated] Online: sem site próprio (Google cai no IG). IG @beunique.beauty.academy (e @beunique_beauty_academy, lema "Be Unique, but don't forget to be true to yourself"). Marcações Noona (noona.app/beuniquebeauty, 209 avals + vouchers). Facebook por achar.
- [stated] ASSETS reais no storage PÚBLICO Supabase: logo restaurant-assets/192c7d0b-b8ef-4d52-bac3-307895fbbf8e/logo-1784473769249.png + hero .../hero-1784416088923.jpeg. (Container do Claude.ai NÃO alcança supabase.co → não dá pra baixar/embutir por aqui.) Tb tenho o LOGO do BeUnique que o Danilo enviou por upload no chat — esse DÁ pra embutir base64 no site.
- [stated] Perfil rico VAZIO no banco: about_text=null, gallery_urls=[], social_instagram/facebook=null (mesmas colunas do [[ouro-e-prata]]). OPORTUNIDADE: preencher história+galeria+redes e, REGRA PAINEL ADMIN, garantir gestão no painel.
- [stated] LIÇÃO IMAGENS: no visualizador de artifacts do app do Danilo, imagem por LINK EXTERNO não renderiza — só base64/SVG inline. Google Fonts CDN funciona. Container não alcança noona.app/res.cloudinary.com/supabase.co (fora da allowlist), mas alcança raw.githubusercontent.com (repos públicos).
- [stated] LOGO REAL do Bora: repo público bora-site/assets/img/bora_logo.png (embutido base64 no site). QR real gerado por segno p/ o link apps/testing (base64).
- [stated] SITE v3 beunique.html (~347KB self-contained): tema rose gold + preto; hero decorativo; galeria = 6 ilustrações simbólicas SVG; faixa Bora com logo real + QR real; CTAs → https://play.google.com/apps/testing/pt.boraapp.bora. NÃO publicado ainda (vai como ficheiro; deploy Cloudflare beunique.pages.dev quando Danilo mandar).
- [stated] ONBOARDING BRUNA (2026-07-21): SENHA TEMPORÁRIA de parceiro definida por MCP (login beunique@bora.app; valor da senha NÃO guardado aqui — é temporária, ela troca). Mensagem redigida (2 versões curtas): cortesia (site) + experimentar app em bora-app-web.pages.dev (cliente + parceira com login/senha) + pedir feedback (gostou? ajustes? fotos/serviços/preços → manda pro Danilo).
- [stated] Links Bora: app no navegador (cliente + login parceiro) = bora-app-web.pages.dev. Publicação do site-presente = Cloudflare Pages .pages.dev (wrangler + CLOUDFLARE_API_TOKEN de bora-site/.env).
- [stated] PENDENTE: (1) fotos reais do salão pro site (Danilo envia print Noona/IG → embuto base64; ou baixar logo/hero do storage se der); (2) serviços + preços reais (Noona); (3) handle Facebook; (4) idioma PT-PT + Noona vs só Bora; (5) preencher perfil rico (about/galeria/redes) + painel admin; (6) publicar o site.
- [stated] PROMPT Claude Code entregue (2026-07-21, SONNET, PROMPT_publicar_beunique.md): publicar beunique.html no Cloudflare Pages → beunique.pages.dev (Danilo salva como Desktop\beunique\index.html; wrangler pages deploy --project-name=beunique; token de bora-site/.env; verificar curl 200; relatório em DEPLOY_REPORT.txt). Estado: entregue, aguarda Danilo correr. Mensagem v2 pra Bruna passou a INCLUIR o link do site (beunique.pages.dev) além do app (bora-app-web.pages.dev) + login/senha. Ordem: publicar primeiro → link ativo → mandar a mensagem.
- [stated] 2026-07-31: Danilo AINDA NÃO FECHOU com a BeUnique. Por isso ficou marcada `coming_soon=true` em service_providers (via MCP): aparece na categoria Beleza com selo "Em breve", cliente entra e vê o perfil/serviços mas não pode marcar nem pagar. Tirar a flag quando fechar.
- [stated] 2026-08-13: mesmo pedido do Danilo (publicar todos os sites pendentes) — prompt consolidado entregue (SONNET, sessão interativa): PROMPT_publicar_sites_pendentes_2026-08-13.md, refazendo a publicação do BeUnique em beunique.pages.dev já que o prompt de 21/07 (PROMPT_publicar_beunique.md) ficou sem correr
- [stated] 2026-08-13 (execução): beunique.html NÃO existe mais no PC — busca exaustiva feita, nada encontrado; o PROMPT_publicar_beunique.md de 21/07 também sumiu. Só sobreviveram relatorio-beunique-equipa.md, relatorio-beunique-fotos.sql e uma pasta vazia tools/beunique — nenhum é o site. Publicação travada até o Danilo achar o HTML e colocar em Downloads
- [stated] 2026-08-28, FIM: o Danilo disse que a BeUnique "não acertou" com ele — o negócio não se fez. Mandou desligá-la e deixá-la de fora por enquanto, e concentrar-se na [[ouro-e-prata]]. EXECUTADO por MCP em `service_providers`: is_online=false, is_active_admin=false, coming_soon=true. Não voltar a ligar nem a trabalhar nela sem ele mandar.

