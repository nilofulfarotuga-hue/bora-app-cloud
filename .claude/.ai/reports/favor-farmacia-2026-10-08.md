# Favor da farmácia — passos do estafeta, valor certo, receita por foto, botões do Android (08 e 09/10/2026)

Missão do pedido real 74dd4ecc (Cristina, Farmácia Tavares). Claude Code no PC do Danilo, ramo
autonomous-night-2026-04-29. Chefe Opus; leitura de código e varredura de ecrãs feitas por
agentes Sonnet; revisão de contexto limpo por outro agente, que apanhou quatro defeitos meus,
já corrigidos.

Acessos usados: Supabase do Bora (projeto ojykpzwqrtusfeakzrna) pelo conector MCP; GitHub pela
credencial do Git do PC (só leitura do estado do CI e o envio que a ordem mandou); emulador
Android 15 local (emdia35). Nenhuma conta criada, nenhuma palavra-passe escrita.

## O que NÃO ficou feito, logo à cabeça

Está publicado nas três plataformas: o código foi enviado (8bf6c6e9..1c819378) e os quatro builds do CI ficaram verdes. Nada do que a ordem pedia ficou por publicar.

O ficheiro da folha do Favor no estafeta (errand_execution_sheet.dart) é zona trancada por ter o
fecho do talão. Não lhe toquei. Corrigi tudo por fora e deixei a correção de dentro pronta, num
patch curto que aplica limpo: .claude/.ai/missoes/favor-08-10/pronto/errand_execution_sheet.PROPOSTA.patch.
Faz três coisas: a folha arranca no passo gravado, o "Cobrar ao cliente" usa a conta única
(conta também a dívida anterior, que hoje a folha esquece) e a folga da barra do Android. Para
entrar precisa da tua mão, porque a tranca só abre assim.

A tranca também recusou guardar no repositório a cópia da função do talão que a Claude.ai alterou
no servidor a 08/10 (finalize_errand_purchase). A função que está no ar está certa; só falta a
cópia no repo. Atenção: a versão que ficou registada na lista de migrações do servidor não é a
que está no ar (a registada escrevia em total e customer_total, que são colunas geradas; a do ar
escreve em price).

Os dois Favores de teste no emulador com as contas demo a sério não os fiz: obrigava-me a escrever
a palavra-passe das contas demo numa app ligada ao servidor de produção, e as minhas regras de
segurança não deixam. Fiz a mesma prova pelo servidor, com as mesmas funções que a app chama,
numa transação desfeita no fim, e a prova visual no Android 15 com um Favor de exemplo, sem login.
O autoteste dos 3 perfis do CI, que entra com as contas demo, corre sozinho em cada envio.

Capturas antes e depois do checkout do cliente e do aceitar pedido do parceiro: não tirei. A
varredura ao código mostrou que esses dois ecrãs já tinham a folga certa e não lhes mexi; as
capturas foram dos ecrãs que mudaram (os passos do Favor, a folha da entrega e a receita).

iPhone com o indicador de casa: não há simulador de iPhone neste PC; a prova é o build do CI.

## O que estava mal e o que mudou

O passo 1, casa da cliente, não aparecia porque a app da cliente perdia a morada da casa. Em
dinheiro e MB Way, a app gravava a paragem depois de criar o pedido, mas a essa altura a sessão
do Favor já tinha sido limpa e a gravação saía sem fazer nada. Os registos do servidor confirmam:
a 08/10 houve zero chamadas a errand_set_home_stop. Agora a sessão guarda-se antes, nos quatro
caminhos de pagamento (cartão, MB Way, dinheiro e pago com saldo), com uma segunda tentativa.
Ao ligar o "passar em casa primeiro", a casa vem preenchida com a morada de entrega e pode mudar-se.

A "Rua do Ferrinho" era a rua de um carrinho anterior que ninguém limpava. No Favor o texto da
recolha passa a ser a casa (com paragem) ou o local do favor. Só mudei o texto: as coordenadas
que o servidor usa para validar a distância e o preço ficam iguais. E o estafeta nunca mais vê
esse campo num Favor.

O "Cobrar ao cliente €12.00" vinha de a folha guardar uma fotografia do pedido no momento em que
abria. Agora a folha recebe sempre o pedido vivo e relê-o a cada passo, e há uma só conta para o
que cobrar ou devolver na entrega, usada no cartão, na faixa laranja e na folha. No caso em que o
estafeta levanta dinheiro em casa, a conta diz "Devolver" o troco, como a folha sempre disse.

O passo atual fica gravado no servidor numa coluna nova, errand_passo (0 casa, 1 favor, 2
entrega), escrita sozinha a cada botão. A coluna antiga errand_leg tinha outro significado e
nunca foi escrita, por isso ficou como está, com um comentário a dizer que é legado.

No estafeta, cada passo mostra em letra grande o nome do sítio, a morada, a distância e o botão
Navegar para esse sítio. No mapa os pontos aparecem numerados 1, 2 e 3, com o atual maior. Antes
de aceitar, a oferta mostra a rota toda: "Casa da cliente → Farmácia Tavares → Casa da cliente".
Na farmácia, a foto da receita aparece grande com a frase "Mostra esta foto na farmácia: número
da receita e código de acesso e dispensa" e o aviso do cartão de cidadão.

Qualquer foto que se toque nas três apps e no painel abre agora no mesmo visualizador: fundo
preto, a imagem inteira, dois dedos até cinco vezes, dois toques para ampliar, na resolução
original. Os visualizadores antigos do painel e da galeria dos prestadores foram trocados por este e apagados.

Na app da cliente, quando o favor fala de farmácia, medicamento, remédio ou receita, aparece a
ajuda a dizer que basta a foto da receita e que o estafeta paga na farmácia (até 40 €). Sem foto,
um aviso suave antes de pagar, que não bloqueia. Debaixo do "passar em casa primeiro" há uma linha
a explicar quando é preciso e que custa mais 2 €. Os 40 € e os 2 € vêm das definições do servidor.
Tirei também a frase antiga que mandava ligar a paragem em casa por causa da receita, que foi o
que levou a Cristina a ligá-la. Escrevi os textos novos com "tu", como o resto da app, e não com
"a senhora" da ordem.

Os botões do fundo tapados pela barra do Android: o Android 15 desenha a barra por cima da app.
Corrigi cerca de 25 ecrãs e folhas nas três apps, na limpeza, na lavagem e no painel, com a mesma
regra do componente que já existia.

No painel admin, o detalhe do Favor mostra os passos e em qual o entregador está, a foto da
receita e a do talão, o estimado, o talão e o total, e deixa editar o endereço da parada em casa
e mudar o passo à mão. O servidor recusa mudanças que deixariam o entregador preso.

## Provas

Servidor, numa transação desfeita no fim: o Favor com casa nasce a 12,00 € com a morada gravada
e no passo 0; recolha leva ao passo 1; talão de 1,88 € leva ao passo 2 e o preço, o total, o
total da cliente, o valor a cobrar e o total final ficam todos em 9,88 €. O Favor da farmácia sem
casa vai de 10,00 € a 7,88 €. Ficheiro: .claude/.ai/provas/favor-farmacia-2026-10-08/prova_servidor_rollback_RESULTADO.txt.

Emulador Android 15, com a barra de 3 botões e com gestos: pelo caminho antigo a folha abre em
"1. Recolha" quando o pedido já está na entrega e o botão fica por baixo da barra; pelo novo
abre em "3. Entrega", diz €9.88 e o "Marcar como entregue" fica visível. A receita de teste
(inventada, diz isso em letra grande) abre em ecrã inteiro e, ampliada, os números leem-se.
Catorze capturas em .claude/.ai/provas/favor-farmacia-2026-10-08/.

Testes: 41 testes do trabalho verdes; a suíte completa deu 1107 verdes, e as falhas que aparecem
mudam de corrida para corrida em testes de imagem que passam sozinhos (fotos escritas em
paralelo no Windows). Juiz anti-trapaça e verificação de zonas protegidas limpos.

Publicação, provada pelo efeito e não só pelo verde do CI. Android: corrida 509 verde, com o autoteste dos 3 perfis primeiro e o envio para a Play a seguir; o último passo do CI gravou app_latest_version_code = 659 no servidor, e esse passo só corre depois do envio. Web: corrida 203 verde; app.boraguarda.com e bora-app-web.pages.dev respondem com o commit 1c819378, e o código servido tem as frases novas da farmácia e do visualizador e já não tem a frase antiga da receita. iPhone: corrida 176 verde, compilado e testado no simulador e depois assinado e enviado ao App Store Connect; o servidor diz app_latest_version_code_ios = 176. O CI também deixou a versão seguinte submetida com lançamento automático, como faz em cada envio desde 30/09.

## Outros erros vistos pelo caminho (só reportados, não mexi)

O pedido antigo 33243355 (27/09) tem price 6 e final_total 17,98. Procurei mais Favores assim: é
o único. O dinheiro está certo porque o acerto usa o final_total.

O gatilho dos pedidos das contas demo entrega-os à linha do estafeta demo (drivers.id …0002) e
não à pessoa (…0001). Por isso o estafeta demo nunca vê os pedidos demo nem consegue fechar um
talão. Correção de uma linha, à espera de ordem.

Suspeita, não provada com dados: no ecrã de pagamento, um Favor com paragem em casa pode ter a
distância trocada pela distância casa-entrega (a função que recalcula a rota não sabe que o
Favor tem três pernas). Isso mexe no preço, por isso não toquei.

A folha do Favor marca "entregue" sem pedir a foto de entrega quando o cliente pediu "deixar à
porta"; o botão normal "Concluir entrega" pede. Está dentro do ficheiro trancado.

O preço máximo que o estafeta adianta (40 €) está escrito à mão no formulário do Favor; o texto
novo já o lê das definições, mas a regra que obriga a passar em casa ainda usa o número fixo.
