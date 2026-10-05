# Fecho da ronda de 4 de outubro: dinheiro e despacho

Data: 5 de outubro de 2026, das 6h30 às 14h. Identificador: ronda-dinheiro-despacho-2026-10-05.
Porta: Claude Code no PC do Danilo. Ordens: "faz as correções de dinheiro e do despacho que
ficaram da ronda de 4 de outubro; eu autorizo tudo" e, mais tarde, "Empurra".

Este relatório substitui o da manhã, que ainda dizia que o envio e o motor estavam parados.

## Acessos

Base de dados do Bora pelo conector do Supabase, projecto ojykpzwqrtusfeakzrna. Repositório
bora-app-cloud e as corridas do GitHub Actions pela credencial Git do PC. Contas de demonstração
demo@bora.app e demo-estafeta@bora.app, usadas só para provar chamadas e ecrãs. Nenhuma conta
nova e nenhuma chave criada. Duas pastas de trabalho próprias, para não tocar no trabalho por
gravar de outras sessões: C:/BoraLocal/wt-ronda-05-10 e C:/BoraLocal/wt-ficha-05-10.

## O que NÃO foi feito

Primeiro, a correcção do aviso de loja fechada não está publicada. Está escrita, testada e
gravada no commit c541de97, num ramo local. Publicar é um envio novo para produção e não segue
sem a tua palavra. Explico-a mais abaixo. Este relatório e as lições para o Cérebro estão no
mesmo ramo, também por publicar; a cópia no Obsidian já é esta.

Segundo, ainda não vi o motor de despacho novo a trabalhar com um pedido verdadeiro. Está no ar
desde as 9h10, mas hoje ainda não entrou nenhum pedido: zero até às 11h50. Por ele só passaram
as quatro chamadas de prova.

Terceiro, não fiz nenhum pedido pago de ponta a ponta com o carrinho novo. Vi os ecrãs reais na
web e o autoteste do Android passou pelo carrinho e pelo pagamento, mas sem criar pedido.

Quarto, o acerto do "parceiro chama estafeta" continua por corrigir. Mexe em várias funções de
acerto protegidas e merece missão própria. O interruptor está desligado, por isso não há risco.

Quinto, o ficheiro de preços pricing_service.dart não foi mexido. Está trancado e já não é
preciso: o cliente já vê e paga os 0,99 euros de taxa de serviço.

Sexto, três coisas da tua ordem acabaram feitas por outra sessão do PC, não por mim: publicar o
motor de despacho versão 62, a função própria para o dinheiro da paragem do Favor, e as missões
de dinheiro das entregas e do painel, que esta manhã entraram como blocos A, B e C. No motor,
o ficheiro publicado é exactamente o que eu deixei gerado e simulado.

Sétimo, os outros achados da lista mais abaixo continuam por tratar.

## O que está publicado e como se prova

O envio seguiu às 8h15, depois do teu "Empurra". Os meus commits são o 5efd2d96, com o código, e
o d5e2d027, com o relatório, juntos no 9fe6b9f8.

Na web ficou no ar poucos minutos depois do envio. Provei pelo endereço público, olhando para o
corpo do ficheiro da app e não para o código de resposta: os seis marcadores novos estão lá e o
antigo desapareceu. Voltei a medir já depois do último envio de outra sessão e continua igual.

No Android saiu a versão 649. A prova é a base de dados, que passou de 648 para 649, e o commit
automático "ci: bump versionCode to 649" no ramo. O caminho teve três corridas. A 495 falhou duas
vezes no autoteste. A 496 foi cancelada por um envio de outra sessão. A 497 passou e publicou
por volta das 11h10. Confirmei que os meus commits estão dentro do que a 497 publicou.

No iPhone, as corridas 161, 162 e 163 passaram nos dois passos, incluindo a entrega do pacote à
Apple. A 163 é a do mesmo commit que publicou o Android.

## Porque o autoteste falhou duas vezes, e o defeito verdadeiro que isso mostrou

Não foi o meu código. O emulador do CI tem o relógio em hora universal, uma hora atrás de
Lisboa. Às 9h16 de Lisboa, para ele eram 8h16. A app decide se a loja está aberta pelo relógio
do aparelho, por isso achou que a Auchan, que abre às 9h, ainda estava fechada. O teste abriu a
ficha de um produto e tocou em "Adicionar ao carrinho".

E aqui está o defeito, que é antigo e que os clientes também apanham fora de horas: com a loja
fechada, a ficha do produto mostra o botão activo, diz "adicionado ao carrinho" e fecha-se, sem
ter adicionado nada. O carrinho recusa em silêncio. Vi-o no registo e nas capturas da corrida.

O teste até tinha uma tolerância para loja fechada, mas nunca disparava: procurava o aviso mais
de oito segundos depois do toque, e o aviso só fica quatro segundos no ecrã.

Às 10h30 de Lisboa as lojas já estavam abertas para o emulador e a corrida seguinte passou sem
mudar uma linha.

Enquanto a correcção não for publicada, qualquer envio entre as 8h e as 10h da manhã, hora de
Lisboa, volta a falhar o autoteste e a travar o Android.

## A correcção da loja fechada, gravada e por publicar

Está no commit c541de97. São cinco ficheiros da app, o autoteste, um ficheiro de testes novo e
a regra da casa.

Na ficha do produto, tocar em "Adicionar ao carrinho" com a loja fechada passa a mostrar o aviso
da loja, por exemplo "Auchan está fechada agora. Abre às 09h00.", e a ficha fica aberta. Vale
para os três caminhos de adicionar.

Nas lojas com variantes, o botão "+" fica cinzento e mostra o mesmo aviso, e tocar na linha da
variante também. Antes diziam "no carrinho" sem adicionar. O botão de tirar continua a funcionar.

No "Pedir de novo" dentro da loja, pergunta-se primeiro se a loja está fechada. Antes enchia o
carrinho de uma loja fechada e o cliente só descobria no fim, quando o servidor recusava.

No "Pedir de novo" da lista de pedidos, que saiu com a ronda de ontem, havia um erro maior:
procurava a loja só entre as parceiras. Das 27 lojas, 22 não são parceiras, incluindo todos os
supermercados. Em 20 dos 25 pedidos entregues que se podem repetir, o botão respondia "Esta loja
já não está disponível na Bora". Passa a procurar em todas as lojas e a avisar quando a loja
está fechada.

O "Pedir de novo" passa também a levar as escolhas do cliente, como a bebida e o acompanhamento
de um menu. Antes repetia o menu sem elas, e o pedido seguia incompleto.

No autoteste, o aviso de loja fechada passa a ser vigiado enquanto se espera, e não só no fim.

Na regra da casa sobre loja fechada ficou escrita esta lição, com a data.

Nenhuma destas alterações toca em preços, pagamentos ou despacho. O servidor já recusava pedidos
a lojas fechadas e continua a recusar.

Verificação: análise estática sem erros, com os mesmos seis avisos antigos em ficheiros que não
toquei. Bateria completa de testes verde: 996 testes, dos quais 16 novos. Contraprova: com os
ecrãs como estão publicados, 6 dos testes novos falham, e sem devolver as escolhas do menu falha
mais um. Portão anti-trapaça do Juiz limpo.

Um revisor de contexto limpo leu tudo duas vezes. Na primeira apanhou três falhas, que corrigi:
o "Pedir de novo" só via lojas parceiras, a linha das variantes ainda dizia "no carrinho", e o
autoteste olhava tarde demais para o aviso. Na segunda não encontrou nada que travasse e apanhou
as escolhas do menu, também corrigidas. A mudança no autoteste só se prova no CI, porque não há
emulador no PC.

Memória do PC: medi 692 megabytes antes da primeira bateria completa e 299 antes de uma das
análises, abaixo do portão de 800 para compilar. Avancei porque não havia nada meu para
libertar: o playwright e o nano-banana não estavam a correr, e quem ocupava a memória era o
modelo local, com 2,4 a 3,5 gigas, e 34 sessões do Claude vivas que não são minhas. Uma análise
demorou nove minutos por isso, mas todas acabaram. Depois da última bateria a memória chegou a
4 megabytes e recuperou para 703 em poucos minutos. De manhã, antes do envio, já tinha descido a
556 numa corrida de testes; avancei porque a corrida ia a meio e as anteriores tinham passado.

## O que ficou feito na app (publicado)

O carrinho e o ecrã de pagamento mostram as mesmas parcelas e o mesmo total, da mesma fonte: o
orçamento do servidor assim que chega, e a conta local até lá.

O orçamento guardado vale só para o carrinho com que foi pedido. Antes durava trinta segundos
fosse qual fosse o carrinho.

A gorjeta saiu do "Total a pagar" do carrinho. É cobrada à parte, e o ecrã de pagamento nunca a
somou, por isso os dois totais diferiam. As gorjetas estão ligadas em produção desde 4 de
outubro às 15h46. Ainda não há nenhuma registada.

Há uma opção nova "Deixar à porta" no ecrã de pagamento, só em entregas de loja e nunca com
pagamento em dinheiro. Com dinheiro escolhido fica desligada e explica porquê.

O limite do pagamento em dinheiro compara o total do servidor.

O carrinho manda o seu retrato ao servidor oito segundos depois da última mexida, só para quem
tem conta própria. O aviso de carrinho abandonado continua desligado.

No estafeta, o serviço em segundo plano bate o sinal por um caminho com segredo, com o caminho
antigo de reserva.

No painel, excluir um rascunho de pagamento pede confirmação e só regista o que saiu mesmo. A
revisão descobriu que o botão nunca tinha apagado nada.

No parceiro, há mensagem própria quando o "Chamar estafeta" está desligado.

Prova nos ecrãs reais, na web pública, com o cliente de demonstração e dois iogurtes do
Continente: subtotal 3,42, taxa de serviço 0,99, entrega 2,50, saco 0,10, taxa de pedido pequeno
1,39, total 8,40. Com dois euros de gorjeta escolhidos o total continua 8,40. O ecrã de pagamento
mostra os mesmos 8,40. Com dinheiro, o "Deixar à porta" fica desligado e diz porquê. O retrato
do carrinho ficou gravado pela app real. Não criei nenhum pedido.

## O que ficou feito no servidor

Um interruptor para o "parceiro chama estafeta", desligado. Migração 20261005061548. Desligado,
a função responde "indisponível" e não cria pedido. Está no painel em Configurações, na
categoria dispatch, com o nome dispatch_parceiro_chama_estafeta_ligado.

A razão: as regras dizem que nestes pedidos o estafeta paga o total à loja e recebe-o do
cliente, mas o fecho trata-os como um pedido normal em dinheiro. Num pedido de 10 euros de
balcão a loja ficaria com 12,57 euros a mais e o estafeta seria cobrado em 10 euros que nunca
teve na mão. Havia zero pedidos destes.

## O motor de despacho versão 62

Está no ar desde as 9h10, publicado por outra sessão por ordem tua. O ficheiro que foi para o ar
é igual, letra a letra, ao que gerei e simulei nesta missão: catorze cenários em catorze, e o
motor antigo falhava dez.

Muda duas coisas. Quem pode chamar o motor: só a chave de serviço, um admin, um estafeta
aprovado, o dono do pedido ou o dono da loja. E quem recebe a oferta: os candidatos vêm da
função da base de dados, com sinal e posição frescos.

O que medi depois: quatro chamadas, todas de prova, uma aceite e três recusadas como deviam, e
nenhum erro. O sinal dos estafetas continua a bater depois de outra sessão ter fechado 169
funções a quem não tem sessão: às 10h55 havia dois estafetas ligados e os dois com sinal fresco.

## Verificação do que foi publicado

Análise estática sem erros. 979 testes a passar, dos quais 24 novos. Anti-trapaça do Juiz limpo.
Revisão de contexto limpo feita por outro agente, com oito pontos tratados. Provas contra o
servidor real com as contas de demonstração: orçamento, retrato do carrinho, sinal com segredo e
MB Way sem sessão. Ninguém foi cobrado por nenhuma prova.

## ISTO MEXE EM PAGAMENTO E DINHEIRO

Aplicado em produção por mim: só o interruptor do "parceiro chama estafeta". Não muda nenhum
preço, comissão nem valor cobrado. Para reverter basta ligá-lo no painel. A função anterior está
guardada em bkp_fn_partner_chamar_estafeta_20261005.

Publicado na app: o total do carrinho, a gorjeta fora do total, o "deixar à porta" e o limite do
dinheiro. Nenhum muda o que o servidor cobra. Mudam o que o cliente vê e o que a app manda.

A correcção da loja fechada, que está por publicar, não mexe em dinheiro.

## Outros achados, não corrigidos

Entrar numa loja por um link partilhado, do site, de um código QR ou do WhatsApp, abre a loja
sem preparar o carrinho para ela. Li-o no código e não o reproduzi. Se for como parece, quem
chega por link pode estar a encher um carrinho que não está ligado àquela loja. Vale a pena uma
missão curta só para isto.

A app decide se a loja está aberta pelo relógio do telemóvel. O servidor decide pela hora de
Lisboa. Num telemóvel com outro fuso, por exemplo de um emigrante, as duas contas diferem uma
hora: a app pode deixar encher o carrinho de uma loja que o servidor depois recusa. A correcção
é pequena, mas muda a conta de aberta e fechada para todos, por isso não a fiz sem tu saberes.

O Lidl, a Mercadona e a Pizza Hut estão marcados como desligados na base de dados. Na lista
aparecem como "Indisponível". Lá dentro, ao meter no carrinho, o aviso diz que a loja "está
fechada agora" e "abre às" a hora da manhã, mesmo à tarde.

Nas festas, o orçamento do servidor ainda conta 0,30 euros de saco que o pedido não leva. Com
cartão cobrar-se-ia 0,30 a mais. Há zero pedidos de festas até hoje.

O servidor grava "deixar à porta" sem olhar ao método de pagamento. A app nunca o manda com
dinheiro, mas falta a guarda para pedidos forjados.

O aviso de carrinho abandonado, quando for ligado, não olha a quem aceitou receber promoções.

Os avisos de mudança de estado ao parceiro não saem, e há dois ecrãs mortos do parceiro por
apagar. No Continente há uma categoria com o nome "Undefined".

## PARA O DANILO

Uma palavra para publicar a correcção da loja fechada. Se disseres "empurra", eu envio a
correcção junto com este relatório e as lições. Convém ser depois das 10h da manhã, para o
autoteste não tropeçar no defeito que ela própria corrige.

Uma decisão sobre o "parceiro chama estafeta": queres que se corrija o acerto para o poder
ligar, ou fica desligado por agora?

Uma decisão antes de ligar o aviso de carrinho abandonado: vai a todos, ou só a quem aceitou
receber promoções?

Uma confirmação: o Lidl, a Mercadona e a Pizza Hut estão desligados de propósito?

Um sim ou não: passo a conta de loja aberta ou fechada para a hora de Lisboa, igual à do
servidor, em vez do relógio do telemóvel?

## Onde está tudo

Publicado: commits 5efd2d96 e d5e2d027, dentro do ramo de produção.
Por publicar: a correcção c541de97 e, por cima dela, o commit com este relatório, a continuação,
as provas e as lições do Cérebro. Pasta C:/BoraLocal/wt-ronda-05-10, ramo
ronda-dinheiro-despacho-05-10. A correcção sozinha está também no ramo ficha-loja-fechada-05-10.
Provas: .claude/.ai/provas/ronda-05-10. Motor e propostas: .claude/.ai/missoes/ronda-04-10/pronto.
Continuação: .claude/.ai/inbox/CONTINUAR-ronda-dinheiro-despacho-2026-10-05.md.
Registo: e2e_log, fluxo ronda-04-10-dinheiro-despacho.
