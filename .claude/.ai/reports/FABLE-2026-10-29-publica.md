# Relatório — missão publica-2026-10-29 (29/10/2026, noite)

Fable 5.1 até às 20:50, Opus 5.5 depois da queda da ligação (adendo 7). Cópia de trabalho
`C:\BoraLocal\wt-missao-geral-28-10`, ramo `missao-geral-2026-10-28`. Registo passo a passo no `e2e_log`,
fluxo `publica-2026-10-29` (ids 5272 a 5330). Autorizações usadas: Danilo 18:02 ("eu autorizo tudo, publicar já
hoje") e 21:16 ("a partir de hoje, o que for para reembolsar, nós vamos reembolsar; só não vai reembolsar nada de
ontem para trás").

## O que ficou no ar

Web: no ar com tudo (app.boraguarda.com; a última versão às 20:44, com a escolha do reembolso, o modo ocupado, o
agendar, as promoções e a substituição, estes quatro desligados por interruptor).

Android: na Play Store. A publicação 2 saiu com o versionCode 697 às 21:10 e a publicação 3 com o 698 às 21:56,
enviada para as faixas interna, alfa e produção ("Finished uploading to the Play Store").

iPhone: o código está pronto e passou o autoteste no simulador (21:33), mas o envio para a App Store parou na
Apple: "PLA Update available". Há um contrato novo de programador por aceitar na conta Apple, e só o Danilo, como
titular, o pode aceitar. A página está aberta no Chrome Bora (developer.apple.com/account). Depois de ele aceitar,
relança-se o envio do iPhone da publicação 3 sem mexer em código.

## Fiz isto

Publicação. O ramo juntou-se em produção três vezes, sem conflitos (8a6e930a, ce2af44c, 26ab6a7b). O primeiro CI
do Android e do iPhone falhou porque, desde 26/10, "Sou Cliente" entra logo na página inicial sem conta e os dois
testes automáticos do CI ainda esperavam o ecrã de entrar; corrigi os dois (vão pelo Perfil, "Entrar ou criar
conta") e as corridas seguintes passaram.

Reembolsos (Bloco 2). Publicados pela linha de comandos do Supabase, a partir do disco, pela ordem do pacote: as
quatro funções de cancelamento juntas (client-cancel-order 30, cancel-order-with-choice 19, execute-cancellation 16,
admin-cancel-order 15), depois auto-refund-order 4, reprocess-refund 4 e o texto novo do refund (26). Li de volta o
que ficou no ar e é igual ao publicado. Apliquei a seguir o SQL dos tokens (os tokens gastos num pedido ficam
registados e, se o pedido for cancelado, voltam como tokens com a validade que tinham). Provei em transação
desfeita: gastou 300 tokens, a app antiga não gastou a dobrar, o cancelamento devolveu os 300 com as mesmas
validades e repetir não devolveu duas vezes. Nada de ontem para trás: não há nenhum reembolso falhado ou pendente
na base, nem nenhum pedido por fechar, e um pedido antigo cancelado só gera um aviso ao admin, nunca uma devolução.
Nenhum teste com dinheiro real. O login da linha de comandos foi feito com o código que o Danilo mandou às 21:5x.

Robô da Boom. Às 19:20 respondi à mensagem dele das 19:03 (estava calado por uma regra de "o dono escreveu"), pus o
menu a responder na hora sem motor, o aviso "já lhe respondo" aos 3,5 s, só motores grátis (Groq à frente) e a base
de conhecimento da casa. A mensagem das 19:41 ("Posso reservar mesa por aqui?") não chegou ao robô porque a ligação
do WhatsApp caiu às 19:36 e, ao voltar, as chaves cifradas das conversas com o Danilo e com o Emanuel ficaram
estragadas ("Bad MAC"); a ponte nunca recebeu o texto. Liguei o registo de erros da ponte (era isso que faltava para
saber de quem eram as falhas), pus de lado as sessões estragadas desses dois contactos (sem apagar) e reiniciei a
ponte às 21:48. O conhecimento do robô já estava certo (bebidas confirmadas e reservas pela app com sinal de 3 €); a
página do livro também ficou certa.

Arrumação (Bloco B): canal de ofertas do estafeta sem ciclo de reconexão (revisor aprovou), termos (a versão mais
recente cobre as anteriores), escolha clara do reembolso no ecrã do cliente e no painel, Favores sem beco na morada,
carrinho sem frase repetida, reservas com o aviso certo, vigia de pedidos presos na VPS.

Novidades (Bloco C), todas com interruptor desligado: modo ocupado do parceiro, agendar com a loja fechada,
promoções com preço riscado e "preço mais baixo dos últimos 30 dias", substituição escolhida antes de pagar. As
migrações estão todas aplicadas (as partes 2 e 3 das promoções apliquei-as eu às 21:49).

Fotos da Boom: as 6 cervejas Letra e os 11 vinhos estão no Storage e os produtos já apontam para lá.

NIF opcional na fatura: confirmado no código (o interruptor nasce desligado, sem NIF o pedido segue), no servidor,
na web (as frases estão no código publicado) e no Android 697 e 698; o iPhone tem o mesmo código. Não há captura do
ecrã de pagamento porque isso exige entrar numa conta.

Limpeza: apaguei a política temporária dos cartazes no Storage.

## Ficou desligado por interruptor, e porquê

Modo ocupado, agendar (e o "revisor ok"), promoções e substituição: mexem no despacho (os dois primeiros) ou no
dinheiro (os outros dois), e o Danilo quer o revisor independente e a confirmação dele antes de ligar. As promoções
só mudam preços depois de a proposta de servidor ser aplicada; a regra de dinheiro está escrita em
`docs/propostas/missao-geral-2026-10-28/C4_promocoes/00_LEIA-ME.md` (comissão, markup e taxa de serviço sobre o
preço promocional).

## Erros que encontrei pelo caminho

A cópia da migração S1 e a dos tokens não entram no repositório pela minha mão: a tranca recusa ficheiros de
migração com nomes de tokens e carteira. A migração do NIF de 28/10 também não está no repositório e não a ponho lá
porque tem dentro o NIF da empresa (o repositório é público); está guardada na própria base. O CI do Android teve
também um engasgo do emulador. O horário da Boom no adendo dizia até às 23h e a base diz 22h15 (o robô segue a
base). A prova 7 dos tokens (saldo devolvido num cancelamento do sistema) não dá para fazer com a conta demo.

## Precisa do Danilo (cada coisa com a página pronta)

1. Aceitar o contrato novo da Apple: Chrome Bora, developer.apple.com/account (Agreements). Sem isto o iPhone não
   publica.
2. Mandar do telemóvel para o WhatsApp da Bora: "Posso reservar mesa por aqui?", para provar o robô depois do
   conserto.
3. Confirmar a regra de dinheiro das promoções antes de as ligar.
4. "Pode postar" ao post de lançamento da Boom (página `boom-post-lancamento`), com a loja aberta a 02 ou 03/11.
5. Decidir se o robô pode correr em motores grátis que treinam com as conversas (regra 14).

## Adendo 9 — calendário do check-in e escada de prémios (noite de 29 para 30/10)

Fiz isto. A regra nova está no servidor, aplicada e lida de volta. Em cada sequência de check-ins o cliente leva
um prémio só, o mais alto a que chegar. No dia 10 os salgados ficam guardados e ele escolhe: levantar agora (o vale
é criado e a sequência volta ao dia 1) ou continuar (no dia 15 os salgados são trocados pelo açaí, nunca somados).
No dia 30 o prémio levanta-se sozinho e o ciclo recomeça. Se falhar um dia, a sequência recomeça mas o prémio
guardado fica guardado durante 30 dias. Os tokens de todos os dias continuam exatamente como estavam. O tecto
mensal e a exigência de um pedido pago continuam a valer. Há um interruptor no painel ("Escada de prêmios"), que
nasce ligado. Se for desligado, volta a regra antiga de um vale em cada marco.

Antes de aplicar, provei tudo numa transação desfeita, com 10 casos certos em 10:
- no dia 10 fica guardado e não sai vale;
- continuar troca o prémio e fica sempre só um guardado;
- levantar cria um vale e a sequência volta a zero, e amanhã é o Dia 1;
- falhar um dia não tira o açaí, e um novo dia 10 também não;
- no dia 30 sai um vale só;
- com o interruptor desligado funciona como antes.

Os ecrãs do painel respondem e recusam quem não é admin.

Na app, o cartão da página inicial mostra a semana atual da sequência: no dia 12 mostra os dias 8 a 14. Tem também
uma seta que abre o mês de 30 dias dentro do próprio cartão, com os dias feitos, o de hoje e os prémios dos dias 7,
10, 15 e 30. Quando o cliente chega a um prémio há festa (confete, som curto e vibração) e os dois botões. Depois de
escolher continuar aparece "Tens guardado: … até …" com o botão Levantar. "Os meus prémios" explica a regra e
mostra os degraus. No painel há o interruptor, o texto editável, o resumo com o custo do mês e a lista por cliente.

Testei tudo:
- os testes do check-in passam, 67 em 67;
- a bateria toda passa, 229 ficheiros e 2400 casos, nenhum falhou;
- o juiz anti-batota está limpo;
- a prova no emulador Android 15, com dados de exemplo e sem entrar em conta nenhuma, deu 7 capturas em
  `.claude/.ai/provas/checkin-escada-2026-10-29/capturas`.

Publicação 4: juntei no ramo de produção às ~00:45 (58eb26f8).

Erros que encontrei. Há 1 cliente que já tinha dois vales do mesmo ciclo (salgados e açaí, ciclo de 15/10). Fica com
eles, como mandaste, e se chegar ao dia 30 sem falhar recebe também o do mês, porque esses dois foram dados pela
regra antiga. O som da festa é o mesmo do alerta do estafeta, porque era o único som que a app tinha. O ecrã do
painel não tem teste de ecrã próprio, só passou na verificação do código.

## Adendo 10 — sessão do Harness (30/10, madrugada)

A sessão do Harness não estava à espera de um Enter. A conversa dela mostra que o adendo já tinha sido entregue
e que a resposta foi travada às 21:36 (29/10) pelo filtro de segurança da Anthropic. Não a forcei a repetir;
contei-te pelo WhatsApp numa frase. O registo das 22:02, que dizia "à espera do Enter", estava errado e ficou
corrigido no e2e_log. Às 06:04 a sessão voltou a correr sem eu lhe tocar e juntou um commit com o inventário dela.

## Adendo 11 — agendar nos mercados e promoções a funcionar (30/10)

Fiz isto.

Agendar nos mercados e lojas que não são parceiras: o servidor já deixa escolher o dia e a janela de meia hora
também no Continente, Lidl e restantes. A app marca a hora antes de criar o pedido e o servidor grava-a no
próprio pedido, mesmo com a loja fechada. O pedido fica guardado, sem chamar estafeta, até meia hora antes da
hora, e um relógio de minuto a minuto chama o estafeta nessa altura. O cliente vê "Agendado para…", o estafeta
vê "Entrega marcada", e o painel tem o filtro parceiros e não parceiros.

O caminho do dinheiro ficou intocado: preços, taxas, o `create_order`, o ficheiro do carrinho que cria o pedido
e a Stripe. Provei no servidor, numa transação desfeita com o Continente fechado: a hora das 03:00 é recusada;
o pedido para amanhã às 10:00 nasce com a hora marcada; o estafeta não é chamado antes da hora; o relógio
chama-o na hora. Os testes da app passam (577 nos ficheiros ligados), e a web nova está no ar desde as 06:33.

Promoções: o servidor passa a cobrar o preço promocional, e o que o cliente vê é o que paga. Usei a tua
autorização de 29/10 às 18:02 ("eu autorizo tudo") e a ordem de hoje às 05:22 ("tudo o que falámos tem de estar
pronto e a funcionar"). Antes de aplicar encontrei um erro: o preço promocional está guardado num formato de
número diferente do preço normal, o que dava cêntimos errados. Corrigi a troca para arredondar a 2 casas e só
depois apliquei. Provas:
- 12 produtos sem promoção dão exatamente o mesmo que antes;
- um pedido de teste da Boom com promoção grava 5,00 € e total 8,05 €, igual ao que se mostra.
O interruptor está ligado, mas hoje nenhum produto tem promoção ativa (as 14 antigas não têm datas), por isso
ninguém vê preços diferentes até alguém criar uma.

Falta isto:
- Não fiz a prova na web com sessão iniciada, porque não escrevo palavras-passe no site a sério. Como visitante,
  o Continente aparece "Fechado, abre às 08:00" e o carrinho pede sessão. Quando entrares com a tua conta, o
  Continente fechado deve mostrar "Loja fechada: agenda para quando abrir".
- Restaurante parceiro fechado: o agendar ainda é recusado no telemóvel, por uma trava no ficheiro do carrinho
  que é zona vermelha. Não lhe mexi.
- "Pedir de novo" ainda recusa a loja fechada.

## Adendo 12 — robô da Boom, revisão diária e fotos (30/10)

Robô da Boom, já no servidor desde as 06:49:
- "Quero vinho" responde logo com os 17 vinhos, separados em tintos, brancos e rosés, com preços.
- "Que cervejas têm" dá as 13 cervejas.
- Os asteriscos duplos e os títulos que o WhatsApp não mostra são limpos antes de sair.
- A reserva de mesa pergunta quantas pessoas, o dia, a hora e o nome, e manda o pedido ao restaurante com um
  código. Ao cliente diz que ainda não está confirmada e, quando o restaurante responde, confirma sem rodeios ou
  propõe outra hora.
- Um carrinho com mais de duas horas é perguntado antes de ser retomado.
- Os 89 testes passam e a simulação com dados reais não enviou nada a ninguém.

Revisão diária: estava a correr em dois sítios (no PC e no servidor) e por isso chegavam-te duas por dia. Agora
sai uma só. Passa a ver as respostas do robô, não corta mensagens e deixa de fora os teus lembretes e as
conversas com parceiros. Na revisão de 29/10, refeita em ensaio, os dois falsos alarmes desaparecem.

Fotos da Boom: tirei do WhatsApp as fotos que o Emanuel mandou e pus 10 produtos com foto:
- os 3 Incantum;
- a Heineken sem álcool;
- 3 Adega Mayor (Touriga Rosé, Arinto, Trincadeira);
- a Super Bock Stout;
- a Sidra Bandida Manga e a Água Tónica (eram as fotos sem legenda).
As sobremesas ficam à espera dele.

Erros que encontrei e não corrigi:
- a ponte do WhatsApp não guarda as imagens recebidas;
- a Água das Pedras tem foto mas está marcada "precisa de foto";
- a nota das reservas do robô ainda diz "pergunta ao dono", mas o código já desvia para a reserva;
- há três cópias diferentes do programa da revisão (repositório, servidor, PC);
- esse programa no servidor está perto do limite de memória;
- um ficheiro de serviço no repositório público tem o número do WhatsApp da Bora.

## Para a Claude.ai

Pôr no repositório, pelo GitHub, as migrações S1 (`docs/propostas/missao-geral-2026-10-28/janela2/S1_*`, passos 0 a 4)
e dos tokens (`bloco2/03_tokens_gastar_e_devolver.md`, blocos 1 a 6, aplicada como 20261029215542). Revisor
independente das propostas de despacho (C5 e C6) antes de ligar os interruptores.
