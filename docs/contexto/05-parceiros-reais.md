# 05 — PARCEIROS REAIS (Guarda) E MINI-SITES

Estratégia do Danilo: presentear comerciantes reais da Guarda com mini-sites cinematográficos gratuitos (HTML self-contained, imagens base64, publicados no Cloudflare Pages `.pages.dev`). O site divulga a loja; o CTA leva pro Bora. Onboarding: dono recebe o site + login de parceiro + link do web app pra experimentar.

**Regra dos CTAs**: usar sempre o link de adesão ao teste `https://play.google.com/apps/testing/pt.boraapp.bora` (o `/store/apps/details` NÃO abre durante teste fechado). Nota: os sites Ouro e Prata e Sabores ainda têm o link `/store` errado — trocar quando der.

## Barbearia Ouro e Prata (Gilberto)

- `service_providers` id `82e3162c-0560-443a-a44a-104dc71a95ef`, category `barbershop`, R. António Sérgio 52 CAVE, rating 5.0/58. 2º parceiro de Serviços.
- `about_text` gravado (história do Gilberto, PT-PT dramatizado). Site **PUBLICADO**: https://ouro-e-prata.pages.dev/ (tema preto+ouro+prata). QR pra parede da loja gerado (cartaz A5) — fica mesmo, confirmado.
- Google Search Console: código de verificação `XH-OlVmaCAXTHNgvuSKs7YBpsB6Feyr96xJnFofQtgE`; prompt de inserção da meta tag entregue.
- Pendente do Gilberto/Danilo: ~11 fotos reais pela galeria do painel, handles IG/FB, melhorar fundo das fotos via Gemini.

## Sabores de Casa Açaí (dono conhecido do Danilo)

- `restaurants` id `12aa2cbb-01bd-443b-a17e-633c169d4864`, is_partner=true, category `restaurant` + `extra_categories '{supermarket}'` (aparece em Restaurantes E Mercados), cuisine Açaí, login parceiro `saboresde.casa@bora.app` (senha temporária definida por MCP, não guardada). Fonte Glovo (vendor 937558).
- Mercado brasileiro + açaí: Pequeno 250ml €3,50 (2 acomp.) / Médio 330ml €5 (3) / Grande €8 (4) / Mega 500ml €12 (5); produtos BR "de saudade" (polvilho, Sonho de Valsa, Chokito, Passatempo...) + produtos africanos. Alma da marca: "matar a saudade de casa".
- Catálogo limpo por MCP (lixo apagado). Site v3 pronto (`sabores-de-casa.html`, ~1,7MB, roxo #25093a + sol #f4c231, PT-BR caloroso, só material do próprio Danilo — nada de stock da net). **NÃO publicar ainda** (decisão do Danilo); vai como ficheiro. Divergência de horário app (09–22 todos os dias) vs Google (Seg–Sex 10–12/13–19, Sáb 10–15) — confirmar com o dono.

## BeUnique Beauty & Academy (contato: Bruna)

- `service_providers` id `192c7d0b-b8ef-4d52-bac3-307895fbbf8e`, category `beauty`, aprovado desde 2026-07-18, login `beunique@bora.app` (senha temporária por MCP). R. Calouste Gulbenkian Lote 11; Ter–Sex 9–19, Sáb 9–17; 4,8/209 avaliações. IG @beunique.beauty.academy; marcações via Noona (noona.app/beuniquebeauty); sem site próprio.
- Bruna: funcionária que o Danilo conheceu no TVDE; já sabe do app.
- Site v3 pronto (`beunique.html`, ~347KB, rose gold + preto, galeria com 6 SVGs simbólicos até chegarem fotos reais). NÃO publicado — prompt de deploy entregue (`PROMPT_publicar_beunique.md`, destino beunique.pages.dev). Ordem: publicar → link ativo → mandar mensagem à Bruna (mensagem já redigida: site + web app + login/senha + pedido de feedback).
- Perfil rico no banco VAZIO (about/galeria/redes) — oportunidade de preencher.

## Outros parceiros no app

McDonald's, KFC, Burger King, Pizza Hut (paridade Glovo), Barbearia Nobre (1º parceiro Serviços). Mercados: todos não-parceiros.

## Lições de mini-site (valem pra todos os próximos)

- No visualizador de artifacts do celular do Danilo, imagem por link externo NÃO renderiza — só base64/SVG inline. Google Fonts CDN funciona.
- Container do Claude.ai não alcança supabase.co/noona.app/cloudinary — mas alcança `raw.githubusercontent.com` (repo público `bora-site` serve logo/QR/ícones do Bora).
- QR real do Play gerado com `segno`, embutido base64.
- Deploy: `wrangler pages deploy --project-name=<nome>` com token de `bora-site/.env`; verificar com curl 200.
