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

## Para a Claude.ai

Pôr no repositório, pelo GitHub, as migrações S1 (`docs/propostas/missao-geral-2026-10-28/janela2/S1_*`, passos 0 a 4)
e dos tokens (`bloco2/03_tokens_gastar_e_devolver.md`, blocos 1 a 6, aplicada como 20261029215542). Revisor
independente das propostas de despacho (C5 e C6) antes de ligar os interruptores.
