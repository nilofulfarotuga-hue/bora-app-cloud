# ESPEC — embeddings-supabase-2026-11-03

## Objetivo
Pôr o motor grátis do próprio Supabase (gte-small, 384 dimensões, `Supabase.ai.Session`) a gerar os
vetores da "pesquisa por significado" do Bora Assistente (search_products, basket_quote, search_help)
e do chat de ajuda (support-chatbot → match_knowledge), com o Gemini (gemini-embedding-001, 768)
sempre de reserva. Se os dois falharem, a pesquisa segue só por texto, como hoje.

## Quem usa
Clientes no assistente (web, Android, iPhone) e no chat de ajuda. Painel admin vê o estado.

## Fronteiras (o que NÃO se toca)
- Preços, comissões, ganhos, Stripe, catálogo (só vetores). `assistant_basket_quote` e
  `quote_order_pricing` não mudam.
- Colunas de 768 (`product_embeddings.embedding`, `support_knowledge_chunks.embedding`,
  `assistant_embedding_cache.embedding`, `support_embedding_cache.embedding`) ficam intactas.
- Nada renomeado nem apagado. App Flutter não muda.

## Decisões (03/11/2026)
1. gte vive ao lado do Gemini:
   - manual: coluna nova `support_knowledge_chunks.embedding_gte vector(384)` + HNSW;
   - produtos: tabela nova `product_embeddings_gte` (a `product_embeddings.embedding` é NOT NULL e
     só 213 dos 47 745 produtos elegíveis têm vetor Gemini; pôr o gte numa coluna obrigava a mexer
     nessa restrição e enganava o `assistant_products_without_embedding` e o contador do painel);
   - perguntas: tabela nova `embedding_cache_gte (scope, query_hash)` pela mesma razão
     (`embedding` NOT NULL nas duas caches).
2. Mesmas funções, mesma assinatura: `assistant_search_products` e `match_knowledge` passam a ver o
   TAMANHO do vetor (384 = gte, 768 = Gemini). Acrescentar um parâmetro `p_embedding_gte` criava uma
   segunda versão com os mesmos nomes e o PostgREST deixava de saber qual chamar (as chamadas antigas
   partiam). Assim as chamadas antigas não mudam e o `assistant_basket_quote` (que passa o vetor por
   dentro) funciona sem lhe tocar. Backup das definições antigas em `bkp_embeddings_funcoes_20261103`.
3. Ordem dos motores por assunto, em `platform_settings`: `embeddings_motor_primario_produtos` e
   `embeddings_motor_primario_ajuda` (`gemini` até a prova passar). O outro é sempre a reserva.
4. Os limiares de semelhança do gte são próprios (o gte dá números mais altos que o Gemini para
   tudo): `assistant_gte_vec_bons_min`, `assistant_gte_vec_boa_min`, `embeddings_gte_ajuda_min_sim`,
   calibrados num conjunto de CALIBRAÇÃO separado das 40 perguntas da prova.

## Regra da prova de qualidade (escrita ANTES de correr)
- 40 perguntas reais de clientes em português (PT-PT e PT-BR, erros de escrita), cada uma com o
  critério de acerto escrito antes (expressão sobre o nome do produto). Acerto = pelo menos um produto
  certo nos 5 primeiros.
- Três corridas na pesquisa real (`assistant_search_products`, catálogo todo): TEXTO (sem vetor),
  GEMINI (vetor Gemini), GTE (vetor gte).
- Uma corrida "motor contra motor" (só vetores) num mesmo conjunto de produtos para os dois motores
  (candidatos tirados por texto + os que batem com o critério + 1000 ao acaso), com o Gemini a
  calcular os vetores na hora (não se guardam) — é a régua.
- O gte passa a PRIMEIRO nos produtos só se: GTE >= TEXTO e GTE >= 0,9 × GEMINI na pesquisa real.
  A corrida motor-contra-motor reporta-se sempre e, se o gte ficar a mais de 10% do Gemini, isso
  fica escrito no relatório como aviso.
- Ajuda (manual): 12 perguntas com critério sobre o trecho; gte primeiro na ajuda só se acertar
  >= 0,9 × o Gemini.
- Se não passar: Gemini fica primeiro, gte fica de reserva, e reporta-se. Não se força.
