---
id: memoria-claude-ai-digest-2026-09-14-leonidas
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-14
zona: verde
confianca: alta
estado: atual
---

# Sessão 14/09 — Leonidas Chocolates Guarda: loja no app, conta de parceiro, painel admin, site de presente

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-14-leonidas`, origem `claude-code`, atualizada em 2026-09-14T11:27:03.292899+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 14 leonidas · memoria claude.ai · claude_ai_memoria

FEITO (Claude Code, Opus): loja leonidas-guarda criada em produção — parceira, aprovada, coming_soon=true (não vende), category=restaurant + extra_categories={sobremesa}, partner_commission_billing=client, horário seg-sex 9-19 / sáb 9-17 / domingo closed=true, morada Praça Luís de Camões 6, tel +351271237188, email chocolatesleonidasguarda@gmail.com, Instagram real @leonidasguarda (o @leonidaschocolatesguarda da ordem não existe), logo/capa/hero/4 galeria no Storage restaurant-assets/leonidas-guarda/. Catálogo: 93 produtos do site nacional leonidas-lovers.pt (menos Natal, Reglette 110 anos e saco), 7 categorias PT-PT, foto real da marca no Storage, partner_shelf_price = balcão do site nacional (source=rascunho_site_nacional_2026_09_14), price=round(balcão*1.10,2), needs_review=true; backup bkp_leonidas_precos_20260914 (93 linhas); SQL de recálculo em leonidas-site/data/recalcular_precos.sql. Conta de parceiro chocolatesleonidasguarda@gmail.com (uid 1014b534-…), papéis partner+client, ligada em user_id e user_, login 200; senha temporária só pelo Telegram. Painel admin: extra_categories passou a ser editável (chips no diálogo de editar parceiro; analyze limpo). Sobremesas já existia desde 27/08. Site: https://leonidas-guarda.pages.dev (projecto Pages leonidas-guarda), pasta C:\BoraLocal\projetosflutter\leonidas-site (git local 4654f33), método site-premio completo, catálogo lido da base no build, filme das fotos reais, /diag.html.
DECISÃO PENDENTE (dinheiro): partner_commission_billing é só rótulo — partner_store_share devolve sempre subtotal*0.90/1.05 (85,71 %); com price=balcão+10 % a loja recebe 94,29 % do balcão (−0,85 € num ballotin de 14,95). Proposta em supabase/migrations/20260914120000_PROPOSTA_repasse_parceiro_comissao_paga_pelo_cliente.sql (A: gravar a +16,67 % como a Goola; B: função lê o rótulo). Só se aplica com "vai".
FALTA: tabela de preços da dona, horário/morada/telefone/email confirmados (ficha 2023 da marca diz outra coisa), preços de café/chocolate quente/gelado, WhatsApp, NIF e IBAN; subdomínio leonidas.boraguarda.com só depois de ela confirmar. PADRAO_BORA ganhou 2.7, 2.8 e 3.14.
