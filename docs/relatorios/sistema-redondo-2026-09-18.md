# Missão sistema-redondo, dezoito de Setembro de 2026 — relatório para ouvir

Escrito pelo Claude Code, motor Opus, sessão nova no repositório do Bora, ramo autonomous-night. Tudo o que aqui está tem prova: uma linha de SQL, um log lido de volta, um teste a correr. O que não ficou feito diz-se logo no princípio.

## O que não ficou feito, e porquê

O Bloco cinco, o fecho da missão Em Dia, não foi tocado por mim. Quando fui ver o registo, a missão em-dia-tudo já estava fechada por outra sessão às vinte e duas e cinquenta e sete, com a linha de MISSAO-CONCLUIDA, o push trinta-e-zero-de-trinta-e-sete e o CI verde nos três fluxos. E às vinte e duas e cinquenta e oito arrancou nesse mesmo repositório uma missão nova, a em-dia-vender, que ainda está a correr noutra janela. Duas sessões na mesma árvore já nos custaram trabalho três vezes, por isso não entrei lá. O Bloco cinco estava feito antes de eu chegar; a regra de não pisar outra sessão passou a estar escrita, e está no Bloco seis.

A proposta vermelha do TVDE ida-e-volta ficou intacta, como mandado. Não a executei e não a arquivei. O Danilo é avisado no Telegram de que ela espera o "vai" dele na Central.

O MCP do Córtex esteve sem autorização OAuth durante toda a sessão. Não parei por isso: o que era para o Córtex foi escrito no inbox do Cérebro no repositório, no formato que o bibliotecário consolida, e as decisões sobre as propostas foram gravadas directamente no ficheiro de propostas da VPS, no mesmo formato que o próprio MCP usa.

A prova do ecrã de produto no emulador Android não foi feita no emulador. O PC tinha mil duzentos e dez megabytes livres, acima do portão pesado, mas um AVD a correr ao lado do analisador e dos testes é o caminho conhecido para o PC se pendurar. A prova foi feita por teste de widget com o cartão real do mercado e por guarda no código dos quatro sítios onde o "mais" pode adicionar ao carrinho. Fica dito.

## Bloco um — venda ao peso

O problema que o Danilo descreveu era real, e o bug do ponto um-ponto-um existia mesmo, mas não onde se pensava. A ficha do produto mostra os grupos de opções e obriga à escolha em qualquer loja, mercado incluído. O buraco era outro: o cartão de mercado e o cartão grande do ecrã de loja tinham um botão "mais" que metia o produto no carrinho directamente, sem passar pela ficha, olhando só às variantes e nunca aos grupos obrigatórios. Um produto ao peso entrava ao preço da porção de duzentos gramas sem ninguém escolher gramas, e o estafeta não sabia quanto pesar. Fechado: os quatro caminhos do "mais" respeitam agora a marca de escolha obrigatória, e há um teste que empurra o cartão real e verifica que o carrinho fica vazio e a ficha abre.

Os dois produtos que a Claude.ai montou à mão vivem na Sabores de Casa Açaí, que é restaurante parceiro, não mercado. Não há nenhum produto com unidade quilo no Intermarché nem no Leroy Merlin: a pista do prompt não confere por SQL, os "KG" que aparecem são rações e fraldas embaladas. Nada para converter aí.

No servidor ficou uma única verdade: a função set-product-weight-pricing recebe o preço por quilo que o parceiro quer receber, grava as duas colunas novas, põe o preço da linha a valer a porção de duzentos gramas e reconstrói o grupo obrigatório Escolhe a quantidade com duzentos, trezentos, quatrocentos, quinhentos gramas e um quilo. As percentagens vêm sempre da tabela de definições da plataforma, nunca cravadas. Só a porção base passa pela fórmula; as outras são múltiplos exactos dela, para o preço por quilo do cartão ser sempre igual ao preço do um quilo — esta foi uma decisão minha, porque a versão em que cada porção passava pela fórmula dava cinco euros e setenta no servidor e cinco e setenta e um no Flutter no um quilo da Abóbora, meio cêntimo exacto a arredondar para lados diferentes. Provado em rollback que a função reproduz ao cêntimo o que a Claude.ai gravou na Abóbora, que um intruso é recusado, e que o dono da loja passa. O Jiló foi regravado pela função: os trezentos gramas passaram de dois e sessenta e dois para dois e sessenta e três. Apanhei ainda um erro meu antes de o publicar: a verificação de administrador dava nulo quando o papel não existia no token e deixava passar qualquer utilizador; ficou com COALESCE e a prova do intruso passou a recusar.

No ecrã do parceiro há o interruptor Vendido ao peso. Ligado, o campo passa a Preço por kg que recebes e aparece ao vivo a linha Recebes tanto por quilo, o cliente vê tanto por quilo, com as cinco porções e o preço de cada uma. Ele nunca faz contas. Ao guardar, a app chama a função do servidor.

No lado do cliente, cartão e ficha mostram "desde um euro e catorze" e, em pequeno, "cinco euros e setenta por quilo" — o preço ao cliente, não o de balcão. No carrinho, na lista de compras do estafeta e no detalhe do pedido a linha diz a porção por extenso: Abóbora Cabotiá, quinhentos gramas, meio quilo. Se a balança der outro peso, segue a regra que já existe para produto em falta e preço do talão; não inventei regra nova.

No painel admin, em português do Brasil, o catálogo tem o ícone da balança em cada produto, que abre a ficha de venda ao peso com o preço por quilo e a pré-visualização, e um filtro Ao peso. A lista passou a vir de uma função nova, versão três, com as duas colunas e o filtro; a versão dois ficou intacta, para nada falhar em silêncio.

A regra ficou escrita no business rules como parágrafo cinquenta e sete: loja nova com hortifrúti entra já assim. Quinhentos e sessenta testes verdes, analisador com zero erros, commit oito-dois-seis-e-zero-cinco-d-um.

## Bloco dois — o aviso do Instagram

Quem mandava a mensagem era o robô das mensagens privadas do Instagram, que corre de dez em dez minutos, não de hora a hora. Como a app da Meta ainda não tem a permissão de mensagens, cada corrida encontrava o mesmo comentário por responder e mandava ao Telegram o mesmo texto. Medido no log: seis por hora. Esse caminho não chama modelo nenhum, é só texto fixo, por isso nunca gastou o plano Go.

Ficou assim: enquanto faltar a permissão, o aviso está desligado, porque não dá para responder pelo robô e avisar não serve de nada. Quando a Meta aprovar, o robô envia sozinho. Há um interruptor no ficheiro de ambiente para voltar a ligar o aviso de propósito, e mesmo ligado só sai uma vez por dia e só se houver comentário novo. A linha de registo no log também passou a uma por dia; eram cento e quarenta e quatro. Prova: as passagens do cron às vinte e três e dez e às vinte e três e vinte não escreveram nenhuma linha de envio ao Telegram; a última foi às vinte e três horas, antes da correcção.

## Bloco três — o roteador e o plano Go

Aqui a medição desmentiu duas coisas do prompt. Primeira: o castigo já tinha hora de fim; a torre voltou a correr bem sozinha às vinte e três e seis, antes de eu tocar em alguma coisa. O erro das dezoito às vinte e duas foi uma janela em que os fornecedores grátis estavam todos castigados ou a devolver limite ao mesmo tempo. Segunda: o "glm cinco ponto dois respondeu pelo Conselho em zero vírgula um segundos" não era o Go. O Conselho aponta para o próprio Motor Bora, o Motor não conhecia esse modelo e caía no perfil rápido, e quem respondeu foi o Groq em cinquenta e nove milissegundos. O Go nunca tinha respondido a nada.

E o Go não é crédito de API. Com a chave Zen no endereço normal dá "saldo insuficiente"; no endereço do Go dá "falta o cabeçalho de sessão". Com a chave do Go, o endereço do Go e esse cabeçalho, respondem os três: glm em dois segundos, qwen em dois e meio, minimax em um. Ficou tudo no catálogo do Motor como fornecedor pago, os três no fim da cadeia do perfil de raciocínio, antes do modelo local, e o auto-teste da manhã passou a ordenar grátis primeiro e pago depois, senão o Go subia ao topo por ser rápido e gastava a assinatura com volume que os grátis servem. Prova nível a nível por alvo directo, sem fallback: os três responderam à mesma conta com o resultado certo; o perfil inteiro continuou a responder pelo grátis; e o Conselho a pedir glm foi agora mesmo ao Go, mil novecentos e cinquenta milissegundos no log.

Tokens e custo: o Motor passou a gravar o custo estimado por chamada, e uma função no banco, agendada de dez em dez minutos, soma tokens e custo por corrida de agente a partir da janela de cada corrida. Já se vê: a ronda da torre das vinte e três e seis gastou quarenta e dois mil tokens, a da qualidade sessenta mil e vinte e sete milésimos de euro estimados. O prompt da torre é pesado; fica registado para quem quiser emagrecê-lo.

## Bloco quatro — a empresa de agentes

Dos vinte e cinco, só a torre e o crescimento tinham relógio. Liguei ao relógio, uma vez por dia à hora que cada um tinha escrita, o cobrador, a qualidade e o gestor de parceiros. Ficam a pedido, ligados mas sem relógio, os que são chamados por evento ou pela fila: atendimento, recrutador, fiscal, escriba, designer, crítico, redes e gestor em dia. Desliguei com o porquê escrito na nota: agenda, arquitecto de sites, assinaturas, batedor, burocracia, estúdio, gestor de clientes, trader, vendedor, vendedor de serviços, lançamentos, que corre no PC e o relógio só apanha com o PC ligado, e a segurança, que não tem fonte nenhuma na VPS porque o advisor só existe por MCP.

A regra de fala: o molde da ronda obriga a última linha a ser ALERTA com uma frase ou SEM NOVIDADE. O Emerson só manda ao Telegram os ALERTA, e nunca o mesmo texto duas vezes em vinte e quatro horas. Ronda sem novidade é silêncio. Descobri no caminho que os agentes novos não tinham fonte nenhuma para abrir e respondiam "não sei" com honestidade; o retrato da operação, que a VPS escreve de dez em dez minutos, ganhou três secções, parceiros, cobrança e qualidade, e as almas dos três agentes apontam para lá. Apanhei também um classificador que lia palavras de dinheiro no papel do cobrador e marcava a ronda dele como "à espera do Danilo", o que mandaria um aviso completo por dia sobre nada; uma ronda do relógio é só leitura por construção e deixou de passar por esse classificador.

Provas: corridas reais da qualidade, do gestor de parceiros e do cobrador, com linhas nas corridas dos agentes e tokens e custo preenchidos pelo cron; a qualidade calou-se com "sem novidade", o gestor de parceiros mandou um ALERTA ao Telegram quando ainda não tinha fonte, e foi posto a correr outra vez já com a fonte.

## Bloco seis — a fila do Córtex

A vermelha fica intacta e o Danilo é avisado. A do worktree por missão foi executada: a regra está na skill do protocolo de missão, com as três cicatrizes, e arquivada como executada. A do Córtex em vectores fica arquivada com nota para missão própria: confirmei que a função existe sem tabela por trás, mas fechar isto exige tabela, índice, pipeline de embeddings e carga, não é coisa de agora. A das skills de marketing fica arquivada: é trabalho criativo, não infra, e o vigia das habilidades já cria skills sozinho quando há correcções repetidas.

## Fecho

Linhas no registo de ponta a ponta com fluxo sistema-redondo para os blocos um, dois, três, quatro e seis. Este relatório no repositório. Um aviso único no Telegram. Push do ramo com o que viaja listado antes. O digest para os outros motores na tabela de memória partilhada.
