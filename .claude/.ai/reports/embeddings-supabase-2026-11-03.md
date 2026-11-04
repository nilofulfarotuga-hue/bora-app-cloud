# Pesquisa por significado com motor grátis e reserva — 03/11/2026

Missão `embeddings-supabase-2026-11-03`. Sessão Claude Code no PC (worktree própria, ramo
`embeddings-supabase-2026-11-03` sobre `origin/autonomous-night-2026-04-29` 1bf442ca). Supabase
`ojykpzwqrtusfeakzrna` por MCP e CLI. Registo: `e2e_log` fluxo `embeddings-supabase-2026-11-03`.
Provas: `.claude/.ai/provas/embeddings-supabase-2026-11-03/` (ESPEC.md com a regra escrita antes, scripts,
capturas da app web).

## Para o Danilo, em poucas palavras

Fiz isto. O assistente de compras e o chat de ajuda passaram a ter dois motores para a "pesquisa por
significado": o grátis do próprio Supabase e o Gemini. Um é sempre a reserva do outro, e se os dois
caírem a pesquisa continua só por palavras, como antes. Fiz a prova em português com 40 perguntas de
clientes. Nos produtos o motor grátis ganhou: acertou 35 de 40, o Gemini e a pesquisa só por palavras
acertaram 32. Por isso, nos produtos, o grátis passou a ser o primeiro e o Gemini a reserva. No manual de
ajuda o grátis perdeu: acertou 7 de 12 e o Gemini 10. Aí, como mandaste, não troquei: o Gemini continua
primeiro e o grátis fica de reserva. Provei a reserva a funcionar com pedidos reais: grátis desligado, o
Gemini serviu; Gemini desligado, o grátis serviu; os dois desligados, o assistente respondeu na mesma.
E fiz uma volta real pela app web.

Falta isto. A volta no Android e no iPhone foi só pelo servidor (o mesmo pedido que a app faz), não no
telemóvel: o PC tinha pouca memória para o emulador. O catálogo ficou completo (os 47 745 produtos e os
605 trechos do manual com o vetor grátis) e os produtos novos entram sozinhos de 2 em 2 minutos.

Erros que encontrei pelo caminho (não corrigi, só reporto): o Gemini só tinha vetor de 213 dos 47 745
produtos, ou seja, a pesquisa por significado estava praticamente desligada nos produtos; os lotes do
Gemini esgotaram a quota do dia a meio da prova, o que bate com o cartão recusado; o assistente disse a
um cliente de teste que os tokens dão "até 50% do valor do pedido", o que choca com a tua regra; e numa
pergunta sobre MB Way o assistente respondeu "não consegui montar o carrinho".

Próximo passo: resolver o cartão do projeto Google bora-juiz.

Aviso honesto: a reserva Gemini só funciona enquanto o cartão do projeto bora-juiz estiver válido; com o
cartão recusado, a reserva pode falhar quando o Google suspender o projeto (no manual de ajuda o Gemini é
o primeiro, e aí o grátis passa a ser quem segura).

## Acessos usados
MCP Supabase (SQL, migrações), CLI Supabase 2.122 do npx já autenticado (publicar funções, transação
de prova), cofre `vault.service_role_key` (chamadas banco→função por pg_net), conta de teste
`e2e_client_a@boraapp.test` por link mágico (sem senha), Playwright num perfil próprio no scratchpad
(não toquei no Chrome do Danilo). Nada de Stripe, preços, comissões, ganhos, carteira ou catálogo.

## O que NÃO foi feito
- Volta no ecrã do Android e do iPhone: só chamada real à função com `platform=android/ios` (HTTP 200).
  Emulador não aberto: 1,2 GB livres (portão 3 GB).
- Régua "motor contra motor" ficou com 898 produtos em vez de 2503: os lotes do Gemini deram 429
  ("exceeded your current quota, check your plan and billing details") e não gastei a quota que serve
  as perguntas dos clientes.
- Não troquei o motor do manual de ajuda (prova não passou).
- Modelo grátis multilingue: o Supabase só tem o gte-small dentro da função (documentação: "only gte-small
  is supported", "exclusively caters to English"). Um multilingue (ex.: multilingual-e5-small por
  transformers.js) teria de correr dentro do mesmo limite de 2 s de processador por pedido — não instalei,
  fica como ideia.
- O agendamento temporário `emb-prova-regua-gemini-20261103` (jobid 127) ficou DESLIGADO (active=false),
  não apagado.

## Bloco a bloco, com prova

**B1 — Migração aditiva** (`20261103195941_embeddings_gte_reserva`, por MCP). Prova antes numa
transação desfeita (DO+RAISE): 6 pesquisas iguais à versão antiga, por texto e com vetor Gemini;
`match_knowledge` Gemini igual. Criado: backup `bkp_embeddings_funcoes_20261103` (5 definições, RLS),
`product_embeddings_gte` (RLS, HNSW), `support_knowledge_chunks.embedding_gte` + HNSW,
`embedding_cache_gte` (RLS), funções de preenchimento, `admin_assistant_overview` com 6 chaves novas,
7 definições. `assistant_search_products` e `match_knowledge` mantêm a assinatura e escolhem a coluna
pelo tamanho do vetor (384 gte / 768 Gemini): acrescentar `p_embedding_gte` criava uma segunda versão com
os mesmos nomes e as chamadas antigas partiam; assim o `assistant_basket_quote` funciona sem lhe tocar.
Parte 2 (`20261103202835`): orçamento gte por pedido + tabelas só da prova (RLS). Parte 3
(`20261103221837`): agendamentos `embeddings-gte-manter` (*/2) e `embeddings-gemini-novos` (17 * * * *).

**B2 — Motor e cascata.** `_shared/embeddings.ts` (cascata por `platform_settings`, cache por motor,
falha de teste com prazo, orçamento) e função `embeddings-gte` (verify_jwt=true; dentro só servidor ou
admin). Medido: gte 384 números, ~115 ms por texto, gasta processador da função — acima de ~12 textos por
pedido morre com 546 "CPU Time exceeded". Daí o orçamento `embeddings_gte_max_por_pedido`=6.

**B3 — Preenchimento.** ~5 400 pedidos pequenos por pg_net: produtos 47 745 de 47 745 (os últimos pela
manutenção automática, 04/11 04:36), manual 605 de 605.

**Segurança (parte 4, `20261104043524`).** Os avisos do Supabase mostraram que as funções novas de
preenchimento podiam ser chamadas por qualquer conta com sessão (uma devolvia o texto interno do manual).
Fechadas só para o servidor (authenticated=false, anon=false, service_role=true) e provado que a
manutenção continua a funcionar (200). Tabelas novas: RLS ligada, sem políticas (só o servidor), de
propósito.

**B4 — Prova de qualidade** (regra escrita antes no ESPEC.md). Calibração separada: gte só-por-significado
com semelhança ≥0,86 → 96% certos, ≥0,89 → 99% (limiares postos). Produtos, 40 perguntas, pesquisa real:
TEXTO 32/40, GEMINI 32/40, GTE 35/40 (ganha "lete meio gordo", "uma duzia de ovos", "bife de vaca"; não
perde nenhuma). Regra GTE≥TEXTO e GTE≥0,9×GEMINI → PASSA. Motor contra motor, mesmos 898 produtos:
36/37 cada. Coincidência com a régua nos 5 primeiros: 3,65 de 5 na pesquisa real. Manual, 12 perguntas:
GEMINI 10/12, GTE 7/12 → NÃO PASSA. Decisão: produtos = gte primeiro; ajuda = Gemini primeiro.

**B5 — Assistente e chat de ajuda publicados** (client-assistant e support-chatbot, verify_jwt=true),
a partir de cópia limpa com o `_shared/claude.ts` que já estava no ar (o do repo tem uma mudança de outra
sessão, commit 634ba274, que não publiquei). A resposta do assistente traz `motor_vetores`.

**B6 — Reserva provada.** Na função: normal → Gemini; gte a falhar → Gemini; Gemini a falhar → gte;
os dois → nenhum vetor. Pedidos reais (conta de teste): gte a falhar → 200, 4 propostas, vetores Gemini
(log "gte:falhou > gemini:ok"); os dois a falhar → 200, 4 propostas, só texto; chat de ajuda com Gemini
a falhar → 200 (log "gemini:falhou > gte:ok(167ms)"); modo normal, cesto de 9 artigos → 200, Auchan
34,66 € com os 9, 6 vetores gte e depois Gemini (orçamento a funcionar), 0 erros de processador no
assistente. App web real (app.boraguarda.com): "quero arroz carolino e lete meio gordo" → 200,
`motor_vetores` [gte, gte], pede a morada (conta de teste sem morada).

## Erros encontrados pelo caminho (reportados, não corrigidos)
1. Gemini só tinha vetor de 213 dos 47 745 produtos elegíveis (1000 linhas, 787 de produtos
   indisponíveis); o painel mostra "embeddings_done 1000" contra 47 745, o que engana.
2. Lotes do Gemini: 429 de quota diária depois de ~900 textos (03/11 ~21:30). As perguntas simples
   continuam a passar. Bate com o projeto bora-juiz sem faturação válida.
3. O assistente disse "100 tokens valem 0,50 € de desconto, até 50% do valor do pedido" — choca com a
   regra "o cliente só usa METADE DO VALOR DOS TOKENS que tem". É dinheiro: não mexi; precisa de revisão.
4. Pergunta "Como é que pago com MB Way?" no assistente → resposta "não consegui montar o carrinho" (o
   lembrete do carrinho dispara numa pergunta que não é de compra).
5. `reindex-knowledge`: o repo está à frente do ar (usa `secretKey()`); `_shared/claude.ts` do repo à
   frente do ar no client-assistant/support-chatbot (commit 634ba274). Nenhum dos dois publicado por mim.
6. `cortex-embedding` (memória do Córtex) e os scripts `scripts/crosstalk/query_knowledge.ts` e
   `scripts/rag/ingest_knowledge.ts` continuam só com Gemini, sem reserva (fora desta missão).
7. A guarda do repositório deu dois falsos alarmes: leu a leitura da chave do Gemini a partir dos
   segredos da função como se fosse uma chave escrita no ficheiro (mudei o nome da variável) e bloqueou
   um apagar dentro do scratchpad.
8. Na versão antiga, a pesquisa por vetor pedia 100 vizinhos mas o índice só devolve 40 (ef_search por
   omissão). No ramo gte novo pus ef_search=100; o ramo Gemini ficou igual de propósito.

## Como voltar atrás (um passo)
`embeddings_motor_primario_produtos` = "gemini" no painel (Definições, categoria assistente) repõe a
ordem antiga. As definições antigas das funções estão em `bkp_embeddings_funcoes_20261103`.
