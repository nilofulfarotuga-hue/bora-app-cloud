# Mudanças nos roteiros — 15/11 noite

Ordem da Claude.ai (18:13 e 18:15), com a decisão do Danilo das 18:14 ("Personagens primeiro"). Feito pelo ajudante dos roteiros. Só texto; ainda falta passar pelo Juiz e pelo Refinador.

Usados (vistos no e2e_log, fluxo conteudo-ia-15-11, passos video-por-verificar e video-aprovado) e por isso deixados como estavam, menos o "testado": lucia-r001, lucia-r003, vo-celeste-r001, vo-celeste-r002, malu-r001, malu-r002, vo-tonico-r001.

## Lúcia (roteiros-lucia.jsonl, agora 106 linhas)

- 98 roteiros por usar (r002, r004 a r100) passaram a paráfrase própria do versículo, com a referência falada (livro cap:vers). O resto da fala (gancho, aplicação e chamada) ficou igual.
- Medido com Python contra o texto da Almeida que lá estava: no máximo 5 palavras seguidas iguais em qualquer campo (roteiro, gancho, legenda, título, miniatura e descrição). Distribuição da maior sequência igual: 1 palavra em 5 roteiros, 2 em 28, 3 em 26, 4 em 32 e 5 em 13.
- 30 títulos do YouTube que citavam a Almeida com mais de 5 palavras foram reescritos: r012, r015, r027, r028, r031, r033, r034, r037, r042, r043, r045, r047, r053, r054, r057, r059, r066, r067, r070, r079, r080, r082, r083, r084, r091, r093, r094, r095, r096 e r099.
- Descrição: "na tradução Almeida…" passou a "em paráfrase própria (com as nossas palavras e a referência para você conferir na sua Bíblia)". O campo "traducao" passou a "parafrase-propria".
- r009: tirei a frase repetida "A misericórdia de Deus se renova com o sol." para não passar das 38 palavras.
- Todos os roteiros de 15 s da Lúcia ficam entre 29 e 38 palavras.
- 6 novos de 30 s, também em paráfrase, conferidos da mesma forma contra a Almeida desses versículos (máximo de 5 palavras seguidas iguais): lucia-t001 (Salmos 23:4, 76 palavras), t002 (Isaías 43:2, 70), t003 (Filipenses 4:6-7, 75), t004 (Mateus 6:26, 73), t005 (Romanos 8:38-39, 78) e t006 (Lucas 15:20, 75).
- Atenção: os vídeos lucia-r001 e lucia-r003 já foram gerados e aprovados com o texto da Almeida. Não mexi neles porque já foram usados. Se forem publicados, a Claude.ai é que decide.

## Vó Celeste (roteiros-vo-celeste.jsonl, agora 106 linhas)

- "testado" saiu das 34 descrições que diziam "Truque de casa simples e testado." (passou a "Truque de casa simples.").
- Celeste passa a ser a avó do dinheiro. Dos 98 roteiros por usar, metade é agora de dinheiro da casa e metade é de casa:
  - 49 novos de dinheiro, vo-celeste-d001 a d049, com 30 a 37 palavras: orçamento, contas, poupar no mercado, dívidas, golpes e cartão. Não há conselho financeiro, promessas nem valores. A descrição diz "Não é conselho financeiro: cada família tem a sua realidade."
  - 49 de casa (receitas e truques) continuam como estavam.
  - 49 retirados do ficheiro (ficam no histórico do git): os 32 "remedios" por usar (eram de saúde: r005, r008, r011, r014, r017, r020, r023, r026, r029, r032, r035, r038, r041, r044, r047, r050, r053, r056, r059, r062, r065, r068, r071, r074, r077, r080, r083, r086, r089, r092, r095 e r098) e mais 17 de casa (r012, r022, r027, r043, r046, r054, r058, r063, r064, r069, r070, r081 (repetia o vídeo vo-celeste-02f, o do arroz queimado), r082, r084, r088, r096 e r097).
  - A ordem no ficheiro alterna um de dinheiro e um de casa, depois dos dois já usados.
- 6 novos de 30 s, todos de dinheiro: vo-celeste-t001 a t006 (as três partes do mês, a compra do mês, as dívidas, a conta de luz, o cofrinho do susto e o golpe do dinheiro fácil), com 70 a 76 palavras.

## Malu (roteiros-malu.jsonl, agora 106 linhas)

- "testada" saiu das 100 descrições. "Dica rápida e testada para a casa e o dia a dia. Uma dica nova todo dia para economizar tempo e dinheiro." passou a "Dica rápida para a casa e o dia a dia. Uma dica nova todo dia para ajudar a economizar tempo e dinheiro."
- 6 novos de 30 s, de mercado e casa: malu-t001 a t006 (lista por corredor, geladeira organizada, faxina de 20 minutos, a etiqueta do mercado, o cheiro de guardado e as marmitas da semana), com 71 a 77 palavras.

## Vô Tonico (roteiros-vo-tonico.jsonl, agora 106 linhas)

- 6 novos de 30 s, com conselhos de vida e nada de saúde: vo-tonico-t001 a t006 (as três lições do pai, não dormir brigado, o amigo e o dinheiro emprestado, começar por baixo, ouvir os mais velhos e a horta do vizinho), com 72 a 76 palavras.

## Regras conferidas com Python em todos os novos ou mudados

- O campo "palavras" foi recontado.
- O gancho tem no máximo 8 palavras e o roteiro começa por ele.
- Os roteiros de 15 s têm até 38 palavras e os de 30 s entre 70 e 80, com "duracao": 30.
- Não aparece "testado", nem a marca Bora, nem números ou preços na fala.
- A descrição do YouTube diz "Personagem criado com IA."
- O texto está em PT-BR.
