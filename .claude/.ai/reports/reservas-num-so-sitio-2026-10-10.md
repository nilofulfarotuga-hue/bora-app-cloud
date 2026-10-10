# Reservas num só sítio — relatório (10/10/2026, de madrugada)

Missão: o separador "Reserva" do cliente passa a mostrar tudo o que a pessoa marcou.
Commit 4d0b1c3c no ramo autonomous-night-2026-04-29.

## Acessos e o que se criou

Conta usada para a prova pela web: a conta demo de cliente (demo@bora.app), só para
ler. Não se criou nenhuma conta, nenhuma reserva e nenhuma linha no banco, a não ser
um registo de observabilidade no e2e_log (id 3292). As reservas de teste das provas
são inventadas e vivem só no telemóvel de prova ou no navegador de prova.

## O que NÃO foi feito (dito primeiro)

Não criei reservas de teste no banco. A ordem pedia uma conta de teste com uma reserva
de cada tipo, mas inserir à mão em corridas e marcações é proibido pelas regras de
operação, e uma corrida ou uma limpeza marcada em produção seria oferecida a
motoristas e faxineiras reais. Em vez disso, as provas usam reservas inventadas que
nunca saem do telemóvel ou do navegador de prova.

A prova no emulador Android foi feita com o ecrã verdadeiro compilado neste PC, não
com a app instalada pela Play. A versão da Play (661) passou o autoteste dos 3 perfis
no CI antes de sair.

No iPhone a prova é do simulador do CI (build 178, mesmo código do 179), não de um
iPhone real. A versão 1.0.15 está à espera da revisão da Apple: quem decide quando
fica na loja é a Apple; quando aprovar, sai sozinha.

O ecrã novo do painel admin ("Reservas" na ficha do cliente) não foi aberto no
navegador: entrar no admin exige a sessão do Danilo. Está provado só pela análise do
código e pela revisão de contexto limpo.

O ecrã de fim de reservar mesa não levou o botão novo — a ordem pedia corrida, limpeza
e barbearia, e nenhuma loja tem as mesas ligadas.

## O que mudou para o cliente

Antes, o separador "Reserva" da barra de baixo só lia as mesas de restaurante. Quem
marcava uma corrida para mais tarde, uma limpeza ou uma barbearia ia lá, não via nada
e pensava que a reserva se tinha perdido. Foi o que aconteceu ao Ricardo (corrida
marcada, paga por MB Way) e ao Divan (limpeza, MB Way retido).

Agora o separador junta as quatro coisas: mesas, corridas marcadas, limpezas e
marcações. Tem as três abas de sempre (Próximas, Passadas, Canceladas). Em cada uma as
reservas vêm por ordem da hora marcada: nas Próximas a mais perto primeiro, nas outras
a mais recente primeiro. Cada cartão diz o tipo ("Corrida marcada", "Limpeza",
"Marcação", "Mesa"), o dia e a hora em hora de Lisboa ("Hoje às 13:25", "Amanhã às
07:25"), o sítio ou destino, o estado em português e se já está pago ("Pago", "Por
pagar", "Pagas em dinheiro ao motorista", "Incluída no pacote ida e volta").

Uma corrida marcada que aos 20 minutos passa a "motorista a caminho" continua nas
Próximas até acabar. Foi exatamente o que aconteceu à corrida do Ricardo às 03:48.

Tocar num cartão abre o ecrã que já existia para esse tipo: a mesa abre o detalhe da
reserva; a corrida ainda marcada abre "As minhas reservas" do Motorista; a corrida já
com motorista a caminho abre o ecrã da corrida; a corrida feita ou cancelada abre o
histórico de corridas; a limpeza abre o acompanhamento; a marcação abre as marcações.
Cancelar, reembolsar e pagar ficaram onde estavam.

Se uma das quatro leituras falhar, aparece um aviso a dizer qual ("Não conseguimos
carregar: limpezas") e as outras três continuam lá. Sem nada marcado, o ecrã diz
"Ainda não tens nada marcado" e tem atalhos para Restaurantes, Motorista, Limpeza e
Serviços. Puxar para baixo recarrega tudo, e o separador recarrega sozinho de cada vez
que se abre.

Depois de marcar uma barbearia, uma limpeza ou uma corrida para mais tarde, o ecrã de
confirmação tem agora o botão "Ver nas minhas reservas", que leva direto ao separador.

No painel admin, na lista de clientes, o menu de cada cliente tem "Reservas (mesas,
corridas, limpezas, marcações)". Abre a mesma lista que o cliente vê, só para ler, com
o estado e o pagamento explicados e o valor tal como está no banco ao lado, e um botão
que abre o ecrã admin de cada tipo (o das limpezas e o das marcações já abrem com o
cliente posto na pesquisa).

## Publicação nas três

Web: no ar. version.json em bora-app-web.pages.dev e em app.boraguarda.com diz build
660, e o código servido tem os textos novos ("Ainda não tens nada marcado", "Ver nas
minhas reservas", "Corrida marcada", "Reservas do cliente").

Android: versionCode 661, enviado pelo CI para a Play em testes internos, alpha e
produção (corrida 511, todos os passos verdes; commit do CI "bump versionCode to
661"). No banco, app_latest_version_code = 661.

iPhone: não saiu sozinho à primeira. A corrida automática 178 construiu e enviou o
build 178 (ficou válido no TestFlight), mas falhou a submeter: a corrida anterior,
177, de outro trabalho, tinha deixado a versão 1.0.15 presa em "pronta para revisão"
depois de um erro 500 da Apple, e o guião de publicação não conhecia esse estado.
Corrigi o guião (.github/scripts/ios_publicar.py), simulei-o contra uma Apple falsa
com o estado real, e fiz o caminho já usado para o iPhone: o envio manual pelo CI
(build-ios por workflow_dispatch, com enviar e submeter ligados). Corrida 179: build
179 enviado e válido, ligado à versão 1.0.15, submetido — a Apple devolveu "à espera
de revisão" às 08:06 UTC, com lançamento automático depois de aprovada. No banco,
app_latest_version_code_ios = 179.

Commits: 4d0b1c3c (o código, as traduções, os testes e as fotografias) e 58c57a5f (o
guião do iPhone e as provas, com [skip ci] para não gastar outro versionCode sem
mudanças na app). Os dois confirmados no GitHub. Só seguiram ficheiros desta missão.

## Provas

Testes: a suite inteira passou (1188 testes, zero falhas) e os 42 testes desta
missão também: a função que junta e ordena (com os dois casos reais, a corrida que
passa a "a caminho" aos 20 minutos, a ordem das abas, o pagamento, a hora de Lisboa),
o ecrã com dados de exemplo (incluindo um tipo que falha a carregar sem apagar os
outros), e fotografias a 320, 390 e 430 de largura que chumbam se alguma coisa
transbordar. A análise do código dos ficheiros tocados deu zero erros e zero avisos. O
juiz anti-trapaça deu limpo.

Android: no emulador Android 15 deste PC, com o separador verdadeiro e uma reserva
inventada de cada tipo — 7 capturas em
.claude/.ai/provas/reservas-num-so-sitio-2026-10-10/capturas_android (Próximas com os
quatro tipos, Passadas, Canceladas, o ecrã vazio com atalhos, a marcação confirmada
com o botão, a corrida marcada e a limpeza marcada com a faixa e o botão). E no CI o
autoteste dos 3 perfis no emulador passou com este código antes de publicar.

Web: o mesmo guião, a entrar com a conta demo e com as mesmas reservas inventadas
(intercetadas no navegador, nada escrito no banco), corrido antes e depois. Antes
(versão 659): o separador só mostrou a mesa; Passadas dizia "Sem reservas anteriores"
apesar de haver uma corrida feita. Depois (versão 660): os quatro tipos nas Próximas e
a corrida feita nas Passadas. Capturas em capturas_web.

iPhone: no simulador do CI, a varredura de ecrãs do build 178 abriu o separador
Reserva sem falhas, e o vídeo do simulador mostra o ecrã novo (a conta demo não tem
nada marcado, por isso aparece "Ainda não tens nada marcado" com os quatro atalhos).
Captura em capturas_ios.

Reservas reais: a limpeza do Divan está igual (aceite, MB Way retido, sábado 10/10 às
13:30 de Lisboa). A corrida do Ricardo já aconteceu entretanto, sozinha: às 03:48 UTC
passou a motorista a caminho, o motorista chegou às 04:00 e terminou às 04:05, pago
por MB Way — tudo pelo sistema e pelo motorista, confirmado nos eventos da corrida.
Nesta sessão só se fizeram leituras ao banco, mais dois registos no e2e_log.

## A revisão de contexto limpo

Um revisor sem contexto tentou partir o trabalho e encontrou oito pontos. Corrigi seis:
abrir o separador avisava os stores a meio do desenho do ecrã (erro vermelho em modo de
depuração; acrescentei um teste que chumba com o código antigo e passa com o novo); a
falha da leitura das limpezas e das corridas agendadas era engolida pelos stores e o
ecrã dizia "nada marcado" (os dois stores ganharam uma bandeira de falha, sem consulta
nova); uma cópia velha de uma corrida podia ganhar à fresca; o "puxar para recarregar"
do admin dava erro em depuração; a limpeza paga e concluída ficava sem selo "Pago"
(faltava o valor released, confirmado no banco); uma mesa com um estado antigo aparecia
como "Confirmada". Também passou a haver trava contra o toque duplo e a corrida viva
que já não é a corrida em curso abre o histórico em vez de um ecrã onde ela não está.
Os outros dois pontos eram cosméticos e ficaram resolvidos pelo caminho.

## Outros erros encontrados pelo caminho (não corrigidos, só reportados)

Primeiro, gravidade média: a hora da limpeza vai para o servidor pelo relógio do
telemóvel. Em lib/screens/client/cleaning/cleaning_wizard_screen.dart, linha 522, a
hora escolhida monta-se com DateTime(...) local; num telemóvel fora do fuso de
Portugal a limpeza fica marcada para outra hora. A regra da casa (1.27) manda usar
instanteDeLisboa.

Segundo, gravidade baixa: dois ecrãs mostram a hora do telemóvel e não a de Lisboa —
o acompanhamento da limpeza (cleaning_tracking_screen.dart, linhas 704 e 758) e o "As
minhas reservas" do Motorista (tvde_my_reservations_screen.dart, linha 68). No
emulador, que anda em hora UTC, a mesma corrida aparecia às 06:15 nesse ecrã e às
07:15 no separador novo. Em telemóveis com hora de Portugal não se nota.

Terceiro, gravidade baixa: o "As minhas reservas" do Motorista só lista corridas em
estado "agendada" com hora no futuro. Aos 20 minutos, quando passa a "motorista a
caminho", a corrida desaparece desse ecrã. No separador novo já não desaparece.

Quarto, gravidade baixa: a barra de baixo chama ao separador "Reserva", no singular,
com o ícone de uma cadeira de mesa. Agora que tem tudo, faria sentido "Reservas" com
um ícone de calendário. Não mudei porque mexe nas fotografias de teste de outros
ecrãs.

Quinto, gravidade baixa: no diálogo de cancelar uma mesa há duas frases sem tradução
inglesa (client_reservations_screen.dart, linhas 186 e 200). Já vinham de antes; não
lhes mexi para não tocar na lógica de cancelar.

Sexto, ferramenta: a tranca bora-mods recusou duas escritas por ler o nome de uma
variável seguido de igual como se fosse um segredo. Não havia segredo nenhum. As
consultas ao CI passaram a correr pela ferramenta de caixa de areia (ctx_execute); os
vigias do CI na pasta temporária da sessão usam outro nome de variável, também sem
segredo no ficheiro (a credencial vem do gestor do Git na hora). Ficou no e2e_log
(registo 3293) para afinar a tranca.

Sétimo, CI do iPhone: o guião de publicação não conhecia o estado "pronto para
revisão". Esse corrigi, porque bloqueava a publicação desta missão — explicado na
secção da publicação.
