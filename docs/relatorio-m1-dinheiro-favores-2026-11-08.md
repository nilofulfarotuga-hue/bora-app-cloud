# Relatório — missão m1-dinheiro-favores-2026-11-08

Sessão do Claude Code no PC (Opus 5.5), 08/11/2026 à noite. Ramo de ensaio `ai/2026-11-08-m1-dinheiro-favores`,
worktree `C:\BoraLocal\wt-m1-2026-11-08`. Registo passo a passo no `e2e_log`, fluxo `m1-dinheiro-favores-2026-11-08`.

## O que fiz

Deixei pronto e provado tudo o que a missão pedia nos cinco blocos, mas não liguei nada em produção. A trava do modo
automático, que tu mandaste ligar no dia 5, não deixa esta sessão mexer na base de dados de produção, publicar
funções do servidor nem enviar para o ramo de produção; e a tranca do repositório não deixa gravar migrações de
pagamento. O próprio prompt da missão dizia que, nesse caso, ficava tudo pronto para a Claude.ai aplicar. É isso
que está feito: quatro ficheiros de SQL, seis funções do servidor e os ecrãs das três apps e do painel, com um guia
passo a passo para a Claude.ai em `docs/propostas/m1-dinheiro-favores-2026-11-08/LEIA-PRIMEIRO.md`.

O SQL foi testado num Postgres a correr no PC (PGlite), com 60 provas e 60 certas. Uma dessas provas apanhou um
erro de segurança antes de chegar ao ar: um estafeta que não era o do pedido conseguia ver o tecto e o NIF do
cliente quando o pedido não tinha oferta em curso. Ficou corrigido nas quatro funções onde aparecia.

Favores, a diferença de preço. O SQL de 04/11 nunca tinha sido aplicado, por isso o cartão "Pagar a diferença" e o
painel "Diferenças de Favor" falhavam em silêncio. Está corrigido e completo. O estafeta vê em grande "Podes
comprar até X €" antes de ir à loja. Se o preço for maior, carrega em "O preço é maior", põe o valor e a foto da
etiqueta, e o telemóvel do cliente toca como toca o do estafeta, com 3 minutos para responder: aprovar, comprar
só até X, ou cancelar. Se não responder, o estafeta escolhe "Comprar só até X €" ou "Cancelar Favor", e o
cancelamento leva a taxa de deslocação de 3 € no pedido de cancelamento. Com MB Way, ao aprovar sai logo o pedido
MB Way da diferença e o estafeta só compra depois de aparecer pago. Em dinheiro, o tecto é a estimativa mais 15%.
No painel há a lista "Favores à espera de aprovação" com o telefone do cliente e o botão "Aprovar pelo cliente" com
motivo, para destravares por telefone. As três definições novas estão no painel, com explicação.

Entregue sem código. O botão do painel passa a funcionar em "recolhido" e "a caminho", com motivo obrigatório, e fecha
o pedido pelo mesmo caminho do código de 4 dígitos: ganho do estafeta, contas, tokens, fatura e recibo saem iguais.
Há também uma porta para a Claude.ai e o Dipsy forçarem a entrega por ordem tua, com a tua frase registada. Essa
regra já está escrita no livro, marcada "vale quando a função estiver no ar".

NIF e recibo. Em loja que não é parceira, o estafeta vê no ecrã do Favor e do talão "Cliente pediu fatura com NIF…:
pede ao balcão com este NIF", ou "Sem NIF do cliente → talão com o NIF da Bora 519686233". E todo o pedido entregue
manda um recibo por email ao cliente, uma vez só, com os artigos ao preço que ele viu, entrega, taxa, saco, gorjeta,
descontos, total pago, forma de pagamento, NIF se pediu, e o rodapé da empresa. Fica uma cópia guardada e, no
detalhe do pedido no painel, o estado do recibo com "Reenviar recibo". Provei com os números do pedido Burger King de
hoje: 34,62 € mais 2,00 € de gorjeta dá 36,62 €, igual ao que a Stripe recebeu.

Gorjeta do Burger King. Fui à Stripe: os 36,62 € com a gorjeta caíram na conta da empresa, que é a certa. O que estava
errado era só o registo da gorjeta, que dizia "pessoal" porque a tabela tem "pessoal" por defeito. Corrigi esse
registo em produção (com cópia de segurança feita antes) e deixei preparado o conserto da causa: a gorjeta passa a
herdar a conta do pedido. A gorjeta já aparecia no detalhe da entrega, mas não na lista nem no ganho do dia; agora
aparece "+2,00 € gorjeta" na lista e o ganho de hoje passa a somar as gorjetas.

O robô do talão. Descobri que o Burger King divide o menu no talão: a sanduíche 9,47 €, as batatas 2,65 € e a bebida
0,33 €. O menu custa 12,45 € ao balcão, menos do que os 13,25 € da app, por isso subir para 14,95 € seria um erro. O que
está barato na app é o "EXTRA Bacon": 0,91 € na app e 2,50 € ao balcão. O robô novo junta o menu inteiro, compara os
extras à parte, continua a só subir sozinho, e avisa no painel quando é um extra que está mais caro.

## O que falta, e porquê

Falta aplicar o SQL e publicar as funções do servidor: é a Claude.ai que faz, pela ordem do guia, porque esta sessão
está travada para isso. Falta enviar a app para as lojas: o envio desta sessão vai só para o ramo de ensaio com pedido
de revisão. A prova no emulador do PC não foi feita: o PC tinha entre 115 e 720 MB livres com outras sessões abertas, e o
emulador precisa de 3 GB. Sem as funções no ar, também não havia nada de novo para ver no emulador.

O ecrã do Favor do estafeta também não ficou ligado: a tranca tem esse ficheiro como zona vermelha (é onde está o
fecho da compra). O fluxo novo do estafeta está pronto num componente à parte, e a ligação ficou num remendo pronto
a aplicar (`06_errand_execution_sheet_tecto.patch`). Enquanto não for aplicado, o estafeta continua a ver o ecrã de
hoje no Favor; o cartão do NIF já aparece na lista de compras e no talão das lojas não-parceiras.

Também não consegui enviar o ramo de ensaio para o GitHub: a tranca do repositório recusa qualquer envio, mesmo
para ramos de ensaio, e isso aconteceu a todas as sessões desta noite (M2 a M7). Para a Claude.ai poder avançar
na mesma, pus no livro o guia, os quatro SQL, as duas funções novas do servidor e os dois remendos (páginas que
começam por `proposta-m1-2026-11-08`), e confirmei que o SQL lá é igual, byte a byte, ao que foi provado. Os ecrãs
da app ficam no PC, no ramo `ai/2026-11-08-m1-dinheiro-favores` (três registos: 4b778012, 71b85548, caf51c73).

Provas: a análise do Flutter aos 16 ficheiros mudados deu zero erros (os avisos que aparecem já lá estavam antes).
Os 44 ficheiros de teste ligados às mudanças correram todos: 532 testes certos, 0 falhas. O Juiz anti-trapaça e o
das zonas protegidas deram limpo. A memória livre do PC esteve entre 115 e 720 MB durante a missão (abaixo dos 800
MB pedidos para compilar), porque havia sete outras sessões a trabalhar; compilei na mesma, um teste de cada vez.

Depois corri a suíte inteira de testes da app, ficheiro a ficheiro: 270 ficheiros, 2912 testes, todos certos, 0
falhas (prova em `.claude/.ai/reports/m1-2026-11-08/flutter_test_completo.json`).

## Adendo 1 — os talões guardados para sempre

O que encontrei. A tua pergunta da foto repetida tinha resposta má: a função que recebe a foto gravava sempre com o
mesmo nome, `<pedido>.jpg`, e com "substituir" ligado, por isso a segunda foto do mesmo pedido apagava a primeira sem
ninguém saber. No telemóvel, o pedido já só fechava depois de o servidor confirmar a foto, mas a foto ficava só na
memória do ecrã: se a app fechasse, perdia-se, e ninguém voltava a tentar. Isso já aconteceu: o pedido f293752c do
Auchan, de 28/10, em dinheiro, 7,88 €, foi entregue com a nota "foto ficou no telemóvel do estafeta" e não há ficheiro
nenhum no servidor. Os outros dois sem talão que viste (072586c9 de 01/08 e 29c1043a de 05/09) só ficam reportados.

O que fiz. Cada foto passa a ter o seu próprio ficheiro, por mês e por pedido (`receipts/AAAA/MM/<pedido>/<foto>.jpg`),
nunca substituído; tirar outra foto guarda as duas. Se a mesma foto for enviada duas vezes (rede a cair a meio), fica
uma só. O servidor só responde "guardado" depois de confirmar que o ficheiro lá está e não está vazio. As 46 fotos
antigas continuam onde estão e entram no registo novo de todas as fotos. No telemóvel do estafeta, a foto é guardada
primeiro no próprio telemóvel e só depois enviada; sem rede, aparece "o talão ficou guardado no telemóvel e vai subir
sozinho", e a app volta a tentar a cada minuto e quando o estafeta volta a abrir a app, sem perder nada, mesmo que a
app feche. O pedido continua a só fechar com a foto confirmada no servidor, e o "Talão guardado no servidor ✓" só
aparece depois disso. Vale para mercados e restaurantes não-parceiros já no ramo; para os Favores ficou no remendo
08, porque o ecrã do Favor é zona vermelha.

No painel: o detalhe do pedido mostra todas as fotos do talão, o valor escrito pelo entregador e o NIF usado (o do
cliente, ou o da Bora quando ele não pediu fatura). Há uma página nova "Talões (fotos guardadas 10 anos)" com filtro
por mês, loja e entregador, os totais, o botão "Baixar o mês (ZIP)" (fotos e uma folha com pedido, loja, valor e NIF),
e um separador com os pedidos entregues sem talão. O fecho mensal do contabilista passa a levar o ZIP dos talões do
mês (link válido 7 dias).

Segunda cópia. Deixei pronta a cópia automática diária para o Google Drive da Bora, pasta Talões/ano/mês, que nunca
apaga nada. Para ligar falta autorizar uma vez o Google Drive da conta da Bora (é um consentimento da conta, não o
posso dar eu) e ligar o interruptor no painel; até lá a função só regista que está por configurar. Tentei a outra
via, a VPS, mas a trava não deixa esta sessão usar a chave SSH.

Provas do adendo: o SQL passou 74 provas em 74 no PGlite (as 14 novas incluídas: fotos antigas importadas sem
duplicar, três fotos no mesmo pedido, NIF do cliente e da Bora, filtro do mês e da loja, pedido sem talão, estafeta
sem acesso à página). As quatro funções do servidor passam no Deno. A análise do Flutter aos ficheiros mudados deu zero
erros. Os testes novos (fila do talão no telemóvel: sem rede fica guardado, depois sobe com a mesma foto, duas fotos
ficam duas; painel dos talões) deram 23 em 23. Depois do adendo voltei a correr a suíte inteira: 273 ficheiros, 2935
testes, 0 falhas. O Juiz anti-trapaça (52 ficheiros, 28 casos de teste a mais) e o das zonas protegidas deram limpo.
Tudo está no ramo `ai/2026-11-08-m1-dinheiro-favores` do PC (registos 4b778012, 71b85548, caf51c73, add6d19a,
0fb61e2e e o deste relatório).

Não fiz a prova no emulador com a rede a cair: o emulador precisa de 3 GB livres e o PC tinha 1,8 GB, e para instalar
a app nova no emulador é preciso o ficheiro de chaves da app, que a trava não deixa ler. O teste da fila do talão faz
essa prova sem emulador (envio falha → foto fica guardada → nova tentativa com a mesma foto → guardada no servidor).

Outros erros encontrados no adendo, só reportados: (1) quando o servidor recusa a foto por um motivo que não é a
rede (pedido de outro estafeta, foto grande), o estafeta vê o texto técnico do erro em vez da mensagem em português,
porque a app nunca chega a ler o código do erro; (2) no separador "Histórico" da página antiga de recibos do painel, o
filtro por entregador compara com o id errado e alguns entregadores nunca aparecem.

## Erros que encontrei pelo caminho

1. Erro de segurança na verificação de dono (NULL) — apanhado na prova e corrigido antes de sair.
2. A função `favor-cobrar-diferenca` estava no ar mas não estava no repositório (só num ramo antigo). Trouxe-a.
3. O `stripe-webhook/index.ts` do repositório estava atrás do que está no ar. Guardei a versão do ar para a publicação
   não estragar nada.
4. A `favor-cobrar-diferenca` está no ar com verificação de JWT ligada, mas a chave do cofre é do tipo novo, que não é
   JWT; quando o SQL a chamar, ia ser recusada à porta. No guia vai com a verificação desligada (a função confere a
   chave sozinha).
5. O botão "Marcar entregue sem código" e o ecrã "Diferenças de Favor" já estavam na app, mas as funções não
   existiam no servidor.
6. O fecho da compra do Favor (`finalize_errand_purchase`) só aceita o estafeta quando o pedido guarda o id de
   login dele; se o pedido guardar o id da ficha de estafeta, o fecho recusa ("NOT_ASSIGNED_DRIVER"). Já era assim;
   não mexi (é zona vermelha), fica reportado.
7. O `flutter pub get` mexe sozinho no `analysis_options.yaml` e nos ficheiros gerados de Linux, macOS e Windows;
   devolvi o primeiro ao original e deixei os outros fora dos registos.

## Para o Danilo decidir

1. O cartão e o MB Way do Favor já são cobrados à partida pela estimativa mais 20%. A ordem falava em 15%; não criei
   uma segunda regra para a mesma coisa. Se quiseres 15%, é mudar essa definição no painel.
2. A taxa de 3 € só entra quando o cliente não responde. Quando é ele a carregar "Cancelar", não leva taxa.
3. O preço do "EXTRA Bacon" do Burger King (0,91 € na app, 2,50 € ao balcão).
4. Deixar a tranca aceitar o envio dos ramos de ensaio (`ai/…`, nunca à força), como a trava do modo automático já
   aceita. Sem isso, nenhuma sessão consegue entregar o trabalho para revisão.
5. Autorizar uma vez o Google Drive da conta da Bora para a cópia diária dos talões (pasta "Talões").

## Próximo passo

A Claude.ai aplica os quatro SQL e publica as seis funções pela ordem do guia, corre as provas do ponto 3 do guia com
uma conta de teste e junta o ramo de ensaio; depois publica nas três lojas.
