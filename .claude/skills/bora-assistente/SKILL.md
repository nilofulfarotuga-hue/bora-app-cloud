---
name: bora-assistente
description: Regras e mapa do "Bora Assistente" — o assistente de compras do cliente (Edge Function client-assistant + RPCs assistant_* + UI Flutter). Ler antes de mexer no assistente, nas suas ferramentas, no catálogo/embeddings, no painel admin do assistente, ou quando o Danilo pedir "o agente virtual do cliente".
metadata:
  versao: 1.0
  criada_por: Claude Code Fable, missão da noite 07/10/2026
  zona: verde (nunca escreve preço; totais vêm de quote_order_pricing)
---

# Bora Assistente — como está montado e o que nunca se faz

## O que é
O cérebro de compras do cliente: conversa (texto, voz, foto), procura em TODAS as lojas, compara o
cesto inteiro COM a entrega incluída, propõe a loja mais barata (e "dividir em 2 lojas" quando poupa),
enche o carrinho com um toque e responde a tudo sobre a app. Nenhuma app de entregas faz a comparação
do cesto com entrega (pesquisa em `claude_ai_memoria.pesquisa-assistente-cliente-2026-10-07`).

## Onde vive
- **Edge Function** `supabase/functions/client-assistant/index.ts` (verify_jwt=true; copiada da
  `support-chatbot` v27). Modelo primário/reserva em `platform_settings.assistant_model_primary` /
  `assistant_model_fallback` (Gemini Flash-Lite PAGO — os termos da Gemini API proíbem o nível grátis
  para utilizadores na Europa; reserva opcional por `GEMINI_API_KEY_FALLBACK`).
- **Migração** `supabase/migrations/20261007220000_bora_assistente.sql`: tabelas `assistant_*`,
  `product_embeddings` (HNSW, 768d gemini-embedding-001), `canonical_products`/`product_matches`,
  view `assistant_lojas`, RPCs `assistant_search_products` (FTS 'portuguese' + unaccent + pg_trgm +
  pgvector, fusão RRF), `assistant_basket_quote` (cesto por loja via `quote_order_pricing`),
  `assistant_favor_quote`, `assistant_propose_cart`, `assistant_mark_proposal`,
  `assistant_quota_increment`, `assistant_set_embeddings` (só service_role),
  `assistant_products_without_embedding`, `admin_assistant_overview`, `assistant_conversation_add_usage`.
- **Embeddings dos produtos**: job retomável `.claude/.ai/provas/bora-assistente-20261007/embed_products.cjs`
  (`MSYS_NO_PATHCONV=1 node embed_products.cjs`); corre em lote de 100, só os que faltam.
- **Flutter**: `lib/screens/client/assistant/assistant_chat_screen.dart` (cartões, voz, foto, "Encher o
  carrinho"), FAB `BoraAssistantFab`, faixa da home (`home_banners` com tipo_destino='categoria',
  destino='assistente' — o CHECK da tabela não aceita 'assistente'), rota `/assistente`, memória do
  cliente no Perfil, painel admin `/admin/assistente` (PT-BR).
- **Definições** (`platform_settings`): `assistant_enabled` (kill-switch), `assistant_daily_quota`,
  `assistant_max_message_chars`, `assistant_max_tool_iterations`, `assistant_coverage_min_pct`,
  `assistant_split_min_saving_cents`/`_pct`, `assistant_road_factor`, `assistant_cost_usd_per_mtok_in/out`,
  `assistant_welcome_text`. Nenhuma é financeira.

## Contrato da Edge Function
Pedido: `{conversation_id?, message?, image_base64?, image_mime?, platform?, dropoff_lat?, dropoff_lng?, apartment_delivery?}`.
Resposta: `{ok, conversation_id, texto, propostas[], divisao, favores[], favor_preco, lista_extraida, acoes[], handoff, ticket_id, messages_remaining_today, poupanca_acumulada_cents, usage}`.
A resposta estruturada fica em `assistant_chat_messages.structured` para redesenhar os cartões.

## As regras que não se quebram
1. **O modelo nunca escreve um preço nem faz contas.** Todo o dinheiro vem de ferramentas; os totais
   são de `quote_order_pricing` (a mesma função do checkout). Nunca duplicar regras de preço.
2. **Nenhuma ferramenta de pagamento.** `propose_cart`/`basket_quote` gravam rascunhos; o cliente
   carrega em "Encher o carrinho" e paga no ecrã normal; o servidor recalcula tudo.
3. **Tabaco/álcool nunca vão para supermercado**: vão para Favores (`favor_price`) com aviso +18
   (usa `produto_e_maior_18` e a marcação `products.age_restricted` da missão +18).
4. **Artigos em falta nunca entram calados**: ficam em `missing_items`; sem loja nenhuma → Favores.
5. **Só vê dados do próprio cliente** (RLS; RPCs do suporte com JWT do utilizador).
6. **Não sabe → `report_gap` + [HANDOFF_HUMAN]** (abre ticket). Nunca inventa regras nem prazos.
7. **Anti-injeção** como no suporte: delimitadores `<<<SYSTEM>>>` proibidos na mensagem, controlo de
   caracteres, quota diária, limite de iterações.
8. **Correspondência duvidosa pesa menos** e aparece "parecido, confirma" (`confidence`).
9. **Dividir em 2 lojas** só se poupar ≥ `assistant_split_min_saving_cents` ou ≥ `_pct`.

## Provas obrigatórias (SELECT / e2e_log, fluxo "bora-assistente")
- Lista "arroz, leite, ovos, azeite, papel higiénico" → 2+ propostas com total incluindo entrega, a
  mais barata primeiro; total = `quote_order_pricing` para a mesma morada (diferença 0).
- "quero um cheeseburger" → propostas de restaurantes; abre carrinho cheio.
- "tabaco" → Favores com preço e aviso +18; nunca supermercado.
- "onde está o meu pedido?" / "quantos tokens tenho?" → responde pelas ferramentas.
- Foto de lista → lista extraída e confirmada (`lista_extraida` + ação `confirmar_lista`).
- Fora do âmbito → educado, volta ao assunto. Produto inexistente → "não encontrei", nunca preço inventado.
- Pagamento nos testes: dinheiro; apagar pedidos de teste no fim.

## Armadilhas já vistas (07/10/2026)
- O conector "claude ai Supabase" (apply_migration/execute_sql) prendeu 3× nesse dia: SQL vai pela
  gaveta `platform_settings.staged_<nome>_<data>` (JSON com sql/estado/motivo/prova) e a Claude.ai aplica.
- No Git Bash, `node x.cjs POST "/rest/v1/..."` sem query string converte o caminho (MSYS):
  usar `MSYS_NO_PATHCONV=1` ou PowerShell.
- `home_banners.tipo_destino` tem CHECK fechado: a faixa usa 'categoria' + destino 'assistente'.
- `_haversine_km` tem duas sobrecargas (double precision e numeric): no SQL passar sempre o mesmo tipo.
