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
- **Dois motores de vetores, sempre com reserva (03/11/2026, missão embeddings-supabase-2026-11-03)**:
  gte-small grátis dentro da Edge Function (384, `Supabase.ai.Session`) e Gemini (768). Código único em
  `supabase/functions/_shared/embeddings.ts` (cascata, cache por motor, orçamento). Ordem por assunto em
  `platform_settings`: `embeddings_motor_primario_produtos` = **gte** (passou a prova: 35/40 contra 32/40
  do Gemini e do texto) e `embeddings_motor_primario_ajuda` = **gemini** (o gte não passou no manual: 7/12
  contra 10/12). Vetores gte em `product_embeddings_gte` (tabela ao lado; a de 768 fica igual),
  `support_knowledge_chunks.embedding_gte` e cache `embedding_cache_gte`. `assistant_search_products` e
  `match_knowledge` têm a MESMA assinatura e escolhem a coluna pelo tamanho do vetor (384/768) — por isso o
  `assistant_basket_quote` não mudou. Limiares gte próprios: `assistant_gte_vec_bons_min` 0.86,
  `assistant_gte_vec_boa_min` 0.89, `embeddings_gte_ajuda_min_sim` 0.82. Enchimento e manutenção pela
  função `embeddings-gte` (só servidor/admin) e pelos agendamentos `embeddings-gte-manter` (2 min) e
  `embeddings-gemini-novos` (hora a hora, 20). Provar a reserva sem mexer no código:
  `embeddings_teste_falha = {"modo":"gte|gemini|todos","ate":"<ISO até 30 min>"}` e depois `{}`.
  A resposta do assistente traz `motor_vetores` (também em `assistant_chat_messages.structured`).
  ARMADILHA: o gte gasta PROCESSADOR da função (~115 ms por texto); acima de ~2 s por pedido a Edge
  Function morre com 546 "CPU Time exceeded". Por isso `embeddings_gte_max_por_pedido` = 6 (o resto vai
  pela reserva) e o enchimento faz ~10 textos por pedido. Os LOTES do Gemini têm quota diária pequena
  (429 depois de ~900 num dia); as perguntas simples continuam a passar.
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

## v8/v9 (01/11/2026, missão assistente-cliente-2026-11-01) — Claude primeiro + as 3 melhorias de 10/10
- **Motor**: Claude primeiro (robô `edge-assistente`, P1, `platform_settings.claude_robos`) pelo
  `_shared/claude.ts`; quando `claudePrimeiro` devolve null (sem crédito, porteiro `ia_claude_pode`
  diz não, 429/5xx, timeout 20 s) o Gemini de sempre continua com as mesmas ferramentas, e as
  ferramentas já corridas pelo Claude passam como notas ⟦⟧ (nunca se repetem). Gastos em `ia_gastos`.
  `assistant_model_primary`/`_fallback` continuam a ser os modelos Gemini de reserva (se o painel puser
  um `claude-*` em `assistant_model_primary`, força esse modelo no Claude).
- **Várias fotos**: pedido aceita `images: [{base64, mime}]` (até 6, 6M chars cada, 16M no total) além
  de `image_base64`. Uma leitura só (Claude visão → Gemini de reserva).
- **Compara com a Glovo/Uber**: a visão devolve `origem: 'carrinho_outra_app'`, `app`, `total_outra_app_eur`;
  o servidor corre `basket_quote` logo e devolve `comparacao` {app, total_outra_app_cents,
  total_bora_cents, loja_bora, diferenca_cents, bora_mais_barato, em_falta}. A diferença é feita em
  código; o texto da resposta é um molde fixo (nunca o modelo). Sem morada → `comparacao_pendente`
  fica no `structured` e fecha-se na volta seguinte (depois do "Está certo, compara as lojas").
- **Aprende**: ferramentas `search_help(question)` (RAG do suporte `match_knowledge`; o que encontra
  fica em `assistant_learned` kind=resposta) e `learn_lesson(what_went_wrong, rule)` (kind=licao, sem
  dinheiro). O bloco "LIÇÕES E PERGUNTAS JÁ APRENDIDAS" entra no prompt (20 lições + 15 respostas).
  Tabela `assistant_learned`: migração `20261101210000_assistente_aprende_2026_11_01.sql` (DDL ficou
  na gaveta `platform_settings.staged_assistant_learned_20261101` — o conector cancelou a confirmação;
  a função ignora a tabela enquanto não existir).
- **Prefácio**: texto que o modelo escreve no mesmo turno em que só chama ferramentas leves
  (`suggest_action`, `remember`, `forget`, `learn_lesson`, `report_gap`) junta-se à resposta final
  (v9: antes perdia-se a 1.ª frase de "onde está o meu pedido").
- **App (feito 01/11/2026, missão app-fechar B6)**: galeria escolhe até 4 fotos
  (`SafeImagePicker.pickMultiImage`, `kAssistantMaxFotos`); `montarCorpoAssistente` manda 1 foto por
  `image_base64` e 2+ por `images[]` (tipo pelos bytes, `mimeDaImagem`); cartão
  `AssistantComparacaoCard` ("Na Glovo deu X; no Bora, <loja> dá Y — mais barato Z"); painel
  `/admin/assistente` separador "Aprendidas" (`admin_assistente_aprendidas.dart`: lista e liga/desliga
  `assistant_learned` direto pela RLS `is_admin()`). Testes: `test/assistente_fotos_comparacao_test.dart`,
  `test/admin_assistente_aprendidas_test.dart`.

## Amigo Bora (v11, 08/11/2026 — missão m4-amigo-bora-v1)
- Nome ao cliente "Amigo Bora". Interruptor `assistant_personality_enabled` (desligado ou sem a migração
  `20261108210000_amigo_bora_v1.sql` = assistente de compras como antes). `deixa_promocoes_enabled`,
  `assistant_amigo_model` (conversa livre, Haiku, robô `edge-amigo`), `assistant_amigo_welcome_text`.
- Entrada ÚNICA: botão "Ajuda-me a escolher" por baixo da pesquisa da home
  (`lib/screens/client/assistant/amigo_bora_entrada.dart`, avatar `assets/branding/amigo_bora.png`);
  `BoraClientFabs` ficou só com o suporte; faixa permanente do assistente desligada.
- Memória por cliente: `assistant_client_profile` (perfil JSON, `lembrar`, `esquecido_em`), refrescado
  pela Edge `assistant-profile-refresh` (cron `amigo-bora-perfis` de hora a hora; factos por SQL
  `assistant_amigo_factos`, conversa só com 3+ mensagens novas no Haiku `edge-amigo-perfil`). Contexto
  do modelo: `assistant_amigo_contexto` (perfil ≤ ~600 tokens + últimos 5 pedidos + promoções + parceiros
  novos 14 dias). Perfil do cliente: "O que o Amigo Bora sabe de mim" (`assistant_amigo_esquecer`,
  `assistant_amigo_lembrar`).
- `abrir: true` na Edge = saudação sem modelo e sem quota; hábito ("sexta à noite: Jyosmi") → último
  pedido dessa loja em `assistant_propose_cart` + ação `repetir_habitual`.
- Compra/marcação acaba numa ação (`ACAO_NUDGE`, `suggest_action` `pedir_favor` / `marcar_limpeza`).
- Comparação: `comparar_outra_app` (preços escritos) e prints com `preco_eur` por linha → linhas em
  código (`amigo.ts` `compararLinhas`), guardadas em `assistant_comparacoes`. Nunca preço da outra app
  que o cliente não deu.
- Deixa: escolhida em código (`candidatasDeixa`: tokens a expirar > check-in > parceiro novo > promoção),
  rotação 24 h em `assistant_deixas`; nunca em compras, fotos, comparações, ajuda/suporte.
- Painel: separador "Amigo Bora" em `/admin/assistente` (`admin_amigo_overview`,
  `admin_amigo_ver_perfil` com motivo e auditoria). Lógica pura e testes: `amigo.ts`/`amigo_test.ts`,
  `assistant-profile-refresh/perfil.ts`, `test/amigo_bora_test.dart`.

## v12 (11/11/2026, missão fechar-tudo-2026-11-11, bloco 2)
- **Pesquisa na internet**: ferramenta do servidor `web_search_20250305` (básica de propósito: custo previsível,
  serve Haiku e Sonnet) pelo `_shared/claude.ts` (`PedidoClaude.pesquisaWeb`). Só tempo, agenda/eventos da Guarda,
  notícias, futebol, farmácia de serviço. Definições `assistant_web_search_enabled` / `assistant_web_search_max_uses`
  (1 a 5, por MENSAGEM). 0,01 USD por pesquisa no `custo_usd` de `ia_gastos` + contagem em `ia_gastos.pesquisas_web`.
  400 com a pesquisa → o mesmo pedido sem ela; `pause_turn` continua até 2 vezes; sem a ferramenta, os blocos de
  pesquisa saem do histórico. Testes: `_shared/claude_pesquisa_test.ts`.
- **lojas_abertas** (RPC `assistant_lojas_abertas`, `is_partner_open` por loja; reserva pelo horário guardado com
  `abertaPeloHorario`) e **parceiro primeiro** em `search_products` (RPC `assistant_produtos_parceiro_aberto`: nome,
  secção ou descrição do produto; "açaí" → bowls do Goola).
- **"quero"/"sim"/"pode ser"** logo a seguir a uma sugestão: carrinho montado em código a partir de
  `structured.ultima_sugestao` (`eConfirmacaoDeCompra` + `confirmacaoEParaOCarrinho` — não dispara se a resposta
  anterior perguntou outra coisa ou pediu para guardar uma alergia). A última rede também tenta montar antes do
  "não consegui". Lógica pura em `client-assistant/sugestao.ts` (testes `sugestao_test.ts`).
- Conversa livre do Amigo no `claude-sonnet-5-5` (`assistant_amigo_model` e `claude_robos.edge-amigo.modelo`).
- Painel: secção "Pesquisa na internet" (`admin_amigo_pesquisa_secao.dart`, `admin_amigo_pesquisa_overview` /
  `admin_amigo_pesquisa_definir`). Migração `20261111090000_amigo_pesquisa_e_lojas_abertas.sql`.

## 11/11/2026, 10:54 (ordem do Danilo no iPhone) — Amigo mais humano
- **Aviso de IA fora da fala**: nem saudação nem 1.ª resposta dizem "Sou uma inteligência artificial…"
  (`semAvisoIA` no servidor e na app tira a frase antiga do histórico). O aviso vive na etiqueta
  "assistente virtual" do cabeçalho do ecrã do Amigo e na Informação legal (`kAvisoLegalAssistente`).
  O support-human-chat NÃO mudou.
- **Fala** (`client-assistant/estilo.ts`, testes `estilo_test.ts`): nunca se reapresenta (a não ser que
  perguntem quem é), não abre pelo nome nem repete o nome, parabéns uma vez, UMA sugestão só (tira
  "se preferires, também há…"; `podeOutroCarrinho` recusa um 2.º carrinho num pedido de uma coisa só).
  Bloco "COMO FALAS" no prompt. Histórico ao modelo = últimas 20 mensagens (antes 24 linhas com ferramentas).
- **Ecrã**: botão "Voltar" cheio (seta + palavra, ≥48 px, `Key('amigo-voltar')`), `maybePop` e, sem para
  onde voltar, `popUntil(isFirst)`; o deslizar do iOS funciona (MaterialPageRoute, sem PopScope).

## Armadilhas já vistas (07/10/2026)
- O conector "claude ai Supabase" (apply_migration/execute_sql) prendeu 3× nesse dia: SQL vai pela
  gaveta `platform_settings.staged_<nome>_<data>` (JSON com sql/estado/motivo/prova) e a Claude.ai aplica.
- No Git Bash, `node x.cjs POST "/rest/v1/..."` sem query string converte o caminho (MSYS):
  usar `MSYS_NO_PATHCONV=1` ou PowerShell.
- `home_banners.tipo_destino` tem CHECK fechado: a faixa usa 'categoria' + destino 'assistente'.
- `_haversine_km` tem duas sobrecargas (double precision e numeric): no SQL passar sempre o mesmo tipo.
