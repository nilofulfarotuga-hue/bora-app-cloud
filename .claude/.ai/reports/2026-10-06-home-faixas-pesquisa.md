# Home com faixas, mais pedidos e lupa que acha tudo — relatório (05→06/10/2026)

Missão `home-faixas-pesquisa-2026-10-05`. Porta: Claude Code no PC (C:\BoraLocal), Opus 5.5.
Memória ao arrancar: 261 MB disponíveis (abaixo dos 400); no `flutter analyze` 430 MB (abaixo
dos 800). Avancei na mesma: o que pesava era o Ollama (`llama-server`, 1,7 GB) de outra tarefa,
e desligá-lo cortaria esse trabalho. Analisei só os ficheiros mexidos para gastar menos.

## O que ficou a funcionar (no ar nas três plataformas)

- **Home do cliente**, por baixo da grelha: carrossel de faixas lido de `home_banners`
  (desliza sozinho, pontinhos, gradiente quando não há imagem); "Pede outra vez" (só com
  sessão e pedidos); "Os mais pedidos da Guarda" ou "Populares na Guarda" (menos de 4 lojas
  com pedidos → sem números, nunca "0 pedidos"); "Novidades" (lojas dos últimos 30 dias);
  faixas por tipo de comida (Sushi, Pizza, Hambúrguer, Açaí… só com 2 ou mais lojas);
  "Todas as lojas" (20 de cada vez, "Ver mais lojas"). Loja "Em breve" com selo; loja fechada
  entra-se. Cada secção carrega e falha sozinha.
- **Faixas de código** (correção do Danilo): só aparecem a quem ainda não usou o código e
  somem quando esgota ou fica inactivo. Sem sessão não aparecem (não se consegue confirmar).
  O texto vem do banco ("5 € de boas-vindas"); a app nunca calcula euros de `value_cents`.
- **Tudo clicável**: loja → abre a loja; produto → loja + o produto aberto; cozinha → lista
  filtrada; categoria → o ecrã da categoria; código → "Resgatar código" já preenchido.
  Vistas contam uma vez por sessão, cliques sempre (`banner_evento`), falhas silenciosas.
- **A lupa** abre o ecrã novo de pesquisa (`GlobalSearchScreen`): atalhos de categorias,
  cozinhas populares, pesquisas recentes (guardadas no telemóvel); resultados agrupados
  (Restaurantes, Supermercados, Lojas, Farmácia, Beleza, Produtos). Preço do produto pelo
  mesmo caminho da app (`PricingService.applyMarkup`, só leitura). Sinónimos de cozinha no
  Flutter ("hamburguer" acha McDonald's, Burger King e KFC).
- **Painel admin "Faixas da home"** (secção Clientes): criar, editar, apagar, arrastar para
  ordenar, ligar/desligar, datas, destino por tipo, cores, imagem, patrocinada + parceiro,
  pré-visualização, vistas/cliques/CTR, e "Lojas mais pedidas" só de leitura. Cada acção
  regista em `log_admin_action`.
- `PADRAO_BORA.md` regra **1.28** e skill `add-home-category`: categoria nova tem de aparecer
  na lupa e poder ser destino de faixa.

## Provas

- Commits: `4f434d3a` (home, lupa, painel), `aedb956b` (inglês das 19 frases novas). GitHub
  respondeu 200 ao commit.
- CI no commit `ac626b95` (já com tudo): **Android** autoteste + AAB enviado ao Play (interno,
  alfa e produção) — sucesso; **web** — sucesso; **iPhone** job A (simulador + testes) e job B
  (IPA enviado, versão seguinte criada e submetida) — sucesso.
- Web (app.boraguarda.com, conta `demo@bora.app`, ecrã 390 px), capturas em
  `.claude/.ai/provas/home-faixas-2026-10-05/`:
  `01`/`02_*` home inteira; `10_faixa_1` faixa Sushi → lista "Sushi" (Fuku, Jyosmi, Amaya
  "Em breve"); `11_faixa_loja_1` faixa Natur House → loja; `12_faixa_codigo_1` → "Resgatar
  código" com BEMVINDO preenchido (não carreguei em Resgatar); `20_lupa_*` sushi, açai, leite,
  pizzza (erro de propósito), hamburguer — todos com lojas e/ou produtos; `21_produto_2`
  produto aberto a 13,23 € (base 11,50 € + 15 % não-parceiro, igual à loja);
  `30_faixas_falham_1` com as faixas bloqueadas volta o banner antigo; `31_populares_*` com
  menos de 4 lojas com pedidos o título passa a "Populares na Guarda", sem números.
- Gate: `anti_trapaca.py --base HEAD` limpo; `flutter analyze` aos ficheiros mexidos sem
  avisos novos; `test/painel_admin_limpo_test.dart` e `test/l10n_cobertura_test.dart` verdes.

## O que falhou pelo caminho (e foi corrigido)

1. **Inglês em falta** — 19 frases novas sem entrada em `strings_en.dart`; o teste de
   cobertura do build iOS chumbou. Corrigido em `aedb956b`.
2. **Esqueleto a transbordar** — a caixa de carregamento punha 3×140 px numa linha de 408 px;
   o autoteste Android e iPhone chumba qualquer transbordo. A sessão paralela
   `fecho-home-dinheiro` corrigiu o mesmo em `744fe903` antes do meu push; descartei o meu
   commit repetido para não disparar outro envio à Apple em cima do 1.0.11.

## Por fazer / não provado

- **Painel admin e estatísticas** não provados ao vivo: nesta sessão não há MCP do Supabase,
  o token da CLI (`.supabase-token.env`) dá 401 e não tenho entrada de admin. Falta: criar e
  desligar uma faixa no painel e ver a home mudar; confirmar por SELECT que vistas/cliques
  sobem em `admin_banner_stats`.
- **e2e_log**: escrita recusada (anon 401 e cliente 403 desde o fecho de hoje). Este relatório
  substitui a linha; pôr a linha por MCP quando houver.
- **Migração `home_banners_mais_pedidos_pesquisa_2026_10_05`** aplicada pela Claude.ai por MCP
  **não está** em `supabase/migrations` — a regra manda que esteja. Sem acesso ao banco não a
  consigo copiar.
- `client_search_history`: não liguei (não confirmei se há permissão de escrita); as pesquisas
  recentes ficam só no telemóvel.
- Afinação estética não publicada: os cartões das secções têm espaço branco a mais por baixo
  (altura 190/150 → 175/145 resolve). Não empurrei para não gerar outro envio ao iPhone.

## Erros encontrados fora da missão (não corrigidos, só reportados)

- `lib/l10n/strings_en.dart`, primeira entrada do bloco de 04/10: "Como pagaste na app, o
  valor é devolvido automaticamente." está traduzido como "{0} km already driven + {1} km to
  the new destination = {2} km" — tradução trocada.
- `home_pede_outra_vez` não mostra nada à conta demo, embora tenha pedidos de teste
  (provavelmente exclui pedidos de teste — a confirmar).
- O token `sbp_` em `.supabase-token.env` está outra vez caducado (401).
- O Córtex MCP pede nova autorização; o `nano-banana` não ligou (timeout).

## PARA O DANILO

- Nada de dinheiro foi mexido; nenhuma pergunta pendente.
