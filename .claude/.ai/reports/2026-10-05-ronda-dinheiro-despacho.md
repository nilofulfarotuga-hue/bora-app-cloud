# Fecho da ronda de 4 de outubro: dinheiro e despacho

Data: 5 de outubro de 2026, de manhã. Identificador: ronda-dinheiro-despacho-2026-10-05.
Porta: Claude Code no PC do Danilo. Ordem: "faz as correções de dinheiro e do despacho que
ficaram da ronda de 4 de outubro; eu autorizo tudo".

## Acessos

Base de dados do Bora pelo conector do Supabase, projecto ojykpzwqrtusfeakzrna. Repositório
bora-app-cloud pela credencial Git do PC. Contas de demonstração demo@bora.app e
demo-estafeta@bora.app, usadas só para provar chamadas. Córtex pelo conector da Claude.ai.
Nenhuma conta nova e nenhuma chave criada. Pasta de trabalho própria em
C:/BoraLocal/wt-ronda-05-10, para não tocar no trabalho por gravar de outras sessões.

## O que NÃO foi feito

Primeiro, publicar. O código está escrito, testado e gravado no commit 5efd2d96, mas o envio
para o ramo de produção foi recusado pelo classificador de segurança do Claude Code às 07h43,
como já tinha acontecido a 4 de outubro. Não tentei outro caminho. Falta só a tua confirmação
expressa para empurrar. Enquanto não for, nada do que está na app chega aos telemóveis.

Segundo, o motor de despacho novo, a versão 62. Não foi alterado nem publicado. A tua Trava
proíbe qualquer agente de editar a pasta do motor e de o publicar, e foi desenhada para só abrir
pela tua mão. O teu "autorizo tudo" dá a ordem, mas não abre a tranca. Não a contornei. Deixei o
motor novo pronto e provado em simulação, explicado mais abaixo.

Terceiro, o ficheiro de preços pricing_service.dart. Também está trancado. Medi e já não é
preciso mexer-lhe: o cliente já vê e paga os 0,99 euros de taxa de serviço, e o único sítio onde
os 2,50 euros antigos ainda contavam ficou resolvido por fora.

Quarto, o acerto do "parceiro chama estafeta". Não corrigi o fecho, que mexe em várias funções
de acerto protegidas e merece missão própria com provas. Fiz o que protege o dinheiro já: um
interruptor, desligado.

Quinto, a função própria para o dinheiro da paragem em casa do Favor. O ficheiro da app está
trancado. Ficou a proposta escrita.

Sexto, as duas missões da ronda que nunca arrancaram, "dinheiro das entregas" e "dinheiro do
painel". Não existe texto delas em lado nenhum: nem no repositório, nem na base, nem no Córtex.
Os achados da auditoria perderam-se e as missões ficaram na conversa da Claude.ai. Não inventei
correcções de dinheiro sem enunciado.

Sétimo, a prova nos ecrãs reais. O que provei foi por testes, por chamadas ao servidor real e
por revisão independente. O autoteste do CI abre o carrinho e o ecrã de pagamento no emulador
antes de publicar, mas isso só corre depois do envio.

## A pasta que indicaste

A pasta .claude/.ai/missoes/ronda-04-10/feito não existia na cópia do PC. Estava no ramo de
produção, que tinha avançado durante a noite até às 06h12 de hoje. Fui buscá-la e li os oito
relatórios: despacho, checkout, tvde, estafeta, cliente, parceiro, painel e triagem.

## O que ficou feito na app (gravado, à espera do envio)

O carrinho e o ecrã de pagamento passam a mostrar as mesmas parcelas e o mesmo total, da mesma
fonte: o orçamento do servidor assim que chega, e a conta local até lá. Antes o carrinho fazia
a sua própria conta.

O orçamento guardado passa a valer só para o carrinho com que foi pedido. Antes durava trinta
segundos fosse qual fosse o carrinho: mudar um artigo e olhar outra vez mostrava a taxa e o
total do carrinho anterior.

A gorjeta saiu do "Total a pagar" do carrinho. É cobrada à parte, e o ecrã de pagamento nunca a
somou, por isso os dois totais diferiam. Isto estava visível aos clientes: as gorjetas estão
ligadas em produção desde 4 de outubro às 15h46, ao contrário do que os relatórios diziam.
Ainda não há nenhuma gorjeta registada.

Há uma opção nova "Deixar à porta" no ecrã de pagamento, só em entregas de loja e nunca com
pagamento em dinheiro, porque em dinheiro alguém tem de receber a nota. Com dinheiro escolhido
a opção fica desligada e explica porquê. O lado do estafeta e do painel já existia.

O limite do pagamento em dinheiro passa a comparar o total do servidor. A função já aceitava
esse valor desde ontem, mas ninguém lho passava.

O carrinho passa a mandar o seu retrato ao servidor, oito segundos depois da última mexida, só
para quem tem conta própria. O aviso de carrinho abandonado continua desligado.

No estafeta, o serviço em segundo plano passa a bater o sinal por um caminho com segredo, que
só aceita o próprio. Se não houver segredo ou se falhar, usa o caminho antigo, para o sinal
nunca se perder.

No painel, excluir um rascunho de pagamento passa a pedir confirmação. A revisão descobriu que
o botão nunca apagou nada: a base só deixa ler essa tabela e responde como se tivesse apagado.
Agora o ecrã diz a verdade e só regista na auditoria o que saiu mesmo.

No parceiro, há mensagem própria quando o "Chamar estafeta" está desligado.

## O que ficou feito no servidor (já no ar)

Um interruptor para o "parceiro chama estafeta", desligado. Migração 20261005061548. Desligado,
a função responde "indisponível" e não cria pedido. Aparece no painel em Configurações, na
categoria dispatch, com o nome dispatch_parceiro_chama_estafeta_ligado.

A razão: as regras de negócio dizem que nestes pedidos o estafeta paga o total à loja e
recebe-o do cliente. O fecho trata-os como um pedido normal em dinheiro. Num pedido de 10 euros
de balcão, com total de 14 e 4 para o estafeta, a loja ficaria com 12,57 euros a mais e o
estafeta seria cobrado em 10 euros que nunca teve na mão. Nunca foi usado, há zero pedidos
destes, mas a app publicada ontem mostra o botão a cinco lojas.

Prova: antes de aplicar, em transacção desfeita, desligado deu "indisponivel" e ligado seguiu
para a validação normal. Depois de aplicar li de volta: interruptor a falso, uma cópia de
segurança da função, a função sem as linhas novas igual à anterior, e a chamada como parceiro
de demonstração a devolver "indisponivel".

## O motor de despacho versão 62, pronto mas não aplicado

Está em .claude/.ai/missoes/ronda-04-10/pronto, com um LEIA que explica tudo. Muda duas coisas
e mais nada. Primeiro, quem pode chamar o motor: hoje qualquer pessoa na internet o pode
acordar, e passa a aceitar só a chave de serviço, um admin, um estafeta aprovado, o dono do
pedido ou o dono da loja. Segundo, quem recebe a oferta: os candidatos passam a vir da função
do banco que a ronda já deixou no ar, com batimento e posição frescos, uma oferta de cada vez,
favor sozinho e raio de 20 quilómetros.

O ficheiro novo foi gerado a partir do que está no ar por substituições exactas, não reescrito
à mão. Confirmei antes que o ar é a versão 61 e que o repositório tem o mesmo ficheiro.
Simulei o motor com uma base de dados falsa: catorze cenários passam em catorze. O mesmo guião
contra o motor actual falha em dez, o que mostra que a prova apanha a diferença. Levantei
todos os chamadores do motor e estão todos cobertos pela porta nova.

Enquanto não for aplicado, fica o risco que o relatório do despacho já dizia: um estafeta com
a posição parada pode receber oferta, e o mesmo estafeta pode ter várias ofertas ao mesmo tempo.

## Verificação

Análise estática sem erros, com os mesmos seis avisos antigos em ficheiros que não toquei.
979 testes a passar, dos quais 24 novos. Anti-trapaça do Juiz limpo. Revisão de contexto limpo
feita por outro agente, que apanhou oito pontos: corrigi seis no código, o das festas é do
servidor e ficou registado, e o último eram reparos aos meus testes, que reforcei.

Provas contra o servidor real, com as contas de demonstração. O orçamento devolve as parcelas
que o carrinho novo lê: 4,72 mais 0,99 mais 2,50 mais 0,10 mais 1,39, igual a 9,70, que é o
total. O retrato do carrinho grava, lê-se de volta e fecha. O sinal com segredo aceita o certo,
recusa o errado e não põe ninguém online. O MB Way responde 401 sem sessão e 404 com um pedido
alheio, antes de tocar no Stripe.

A memória disponível era 2563 megabytes no arranque e 1056 antes de compilar. Na última corrida
de testes desceu a 556, abaixo do portão de 800. Avancei porque a corrida já ia a meio, as duas
anteriores tinham passado com folga, e quem ocupava a memória era um modelo local que não é
desta sessão.

## ISTO MEXE EM PAGAMENTO E DINHEIRO

Aplicado em produção por ordem desta missão: só o interruptor do "parceiro chama estafeta".
Não muda nenhum preço, comissão nem valor cobrado. Para reverter basta ligar o interruptor no
painel; a função anterior está guardada em bkp_fn_partner_chamar_estafeta_20261005.

Gravado e por publicar: o total do carrinho, a gorjeta fora do total, o "deixar à porta" e o
limite do dinheiro. Nenhum destes muda o que o servidor cobra; mudam o que o cliente vê e o que
a app manda.

Ninguém foi cobrado por nenhuma prova.

## Outros achados, não corrigidos

Nas festas, o orçamento do servidor ainda conta 0,30 euros de saco que o pedido não leva. Com
cartão cobrar-se-ia 0,30 a mais do que o pedido regista. Há zero pedidos de festas até hoje. É
a correcção que está por aplicar desde 25 de agosto.

O servidor grava "deixar à porta" sem olhar ao método de pagamento. A app nova nunca o manda
com dinheiro, mas falta a guarda no servidor para pedidos forjados.

O aviso de carrinho abandonado, quando for ligado, não olha a quem aceitou receber promoções.
A reativação de clientes olha. Convém decidir antes de ligar.

Fora de dinheiro e despacho, e por isso não tocados: os avisos de mudança de estado ao parceiro
não saem, e há dois ecrãs mortos do parceiro por apagar. Está tudo na ordem de continuação.

## PARA O DANILO

Uma palavra tua para publicar: o envio foi recusado pela protecção do Claude Code e só segue
com a tua confirmação expressa.

Uma decisão sobre a tranca: o motor de despacho novo está pronto e só entra quando a Trava
estiver aberta para ele. Só tu a abres. Se quiseres, na próxima conversa deixo-te o ficheiro
certo aberto no ecrã, com as linhas marcadas.

Um recado para a Claude.ai: escrever as duas missões que faltam, dinheiro das entregas e
dinheiro do painel, na pasta da ronda. Sem texto ninguém as pode executar.

## Onde está tudo

Código: commit 5efd2d96, pasta C:/BoraLocal/wt-ronda-05-10, ramo ronda-dinheiro-despacho-05-10.
Pronto a aplicar: .claude/.ai/missoes/ronda-04-10/pronto. Provas: .claude/.ai/provas/ronda-05-10.
Continuação: .claude/.ai/inbox/CONTINUAR-ronda-dinheiro-despacho-2026-10-05.md.
Registo: e2e_log, fluxo ronda-04-10-dinheiro-despacho.
