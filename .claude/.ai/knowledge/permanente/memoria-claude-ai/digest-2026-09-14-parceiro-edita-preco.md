---
id: memoria-claude-ai-digest-2026-09-14-parceiro-edita-preco
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-14
zona: verde
confianca: alta
estado: atual
---

# Claude Code Opus 14/09 — parceiro edita preço (balcão → preço do app)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-14-parceiro-edita-preco`, origem `claude-code`, atualizada em 2026-09-14T19:36:27.197794+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 14 parceiro edita preco · memoria claude.ai · claude_ai_memoria

Feito e empurrado (commit b5759549, push 01e6c0ce..db7a4b9a em autonomous-night-2026-04-29; build Android e web a sair pelo CI, versionCode estava em 605). O parceiro passa a ter, em cada produto, "Editar produto" (nome, descrição, Preço que recebes, categoria, foto, alergénios) e "Apagar" com confirmação; ao criar produto o campo chama-se "Preço que recebes". Regra gravada nas duas colunas: partner_shelf_price = o que ele escreveu (balcão) e price = round(balcão ÷ (1 − partner_visible_commission_pct) × (1 + partner_hidden_markup_pct), 2), percentagens lidas de platform_settings ao abrir o ecrã, nunca cravadas (hoje dá ×1,1667: 8,00 → 9,33 → recebe 8,00). O código Dart (lib/services/partner_price_rules.dart) é o espelho ao contrário da função de produção partner_store_share(price, restaurant_id), incluindo o ramo de restaurants.app_markup_pct (Leonidas 0,10 e Mr Kebab 0,15 recebem price ÷ (1+pct)) — atenção: essa versão de 2 argumentos está no ar e é chamada por apply_order_financial_split e post_order_to_ledger, mas o repo só tem a PROPOSTA baseada em partner_commission_billing; o ar está à frente do repo nessa função, ninguém a alterou nesta missão. Painel admin: diálogo com balcão e preço no app (um recalcula o outro), RPC nova admin_update_product_prices (recusa par incoerente, audita) e lista admin_list_products_by_partner_v2 — migration 20260914170000 aditiva, aplicada e provada em rollback; a antiga admin_update_product_price fica para lojas não-parceiras. Provas: analyze 0 erros, 11 testes novos (varrimento 0,01–200,00 € nos dois sentidos, percentagens diferentes), suite 532 verde, SQL 20000/20000 fecham ao cêntimo, Juiz anti-trapaça limpo; prova real com a sessão do dono da Sabores de Casa (magiclink via admin/generate_link): Copo Grande 8,00 → 8,50 gravou price 9,92 e partner_store_share(9,92) = 8,50; reposto a 8,00/9,33. AVISO: o logout dessa sessão de prova foi global e pode ter fechado a sessão do dono no telemóvel — se ele disser que a app pediu login, é isso; a partir de agora logout de prova é scope=local. Ficou por fazer: interruptor de disponibilidade na aba catálogo da ficha do parceiro (admin) chama a RPC antiga sem motivo e falha (bug anterior); admin não tem botão de apagar nem de criar produto (não tinha antes). Relatório: .claude/.ai/reports/OPUS-2026-09-14-parceiro-edita-preco.md; provas: .claude/.ai/provas/parceiro-edita-preco-2026-09-14/PROVAS.md. Córtex MCP estava sem autenticação nesta sessão.
