# Reembolsos — o que está certo, o que está errado e o que proponho

Danilo, isto é o resumo para ouvires. Não apliquei nada: só li a base de dados e o código. Está tudo pronto à espera do teu "vai".

## O que já está certo

Quando é o sistema a cancelar um pedido pago (por exemplo, ninguém aceitou a entrega), o dinheiro volta sozinho ao MB Way ou ao cartão, sem tokens. Foi o que aconteceu com a Solaidy no dia 7: o pedido do McDonald's de 18,68 euros voltou inteiro ao MB Way dela.

O TVDE também está certo. Nos últimos 30 dias houve 18 corridas pagas por MB Way que foram canceladas, e todas voltaram ao MB Way, sem taxa quando não havia motorista.

Quando o cliente cancela pelo ecrã de seguimento do pedido, o dinheiro também volta ao MB Way ou ao cartão.

## O que está errado

O problema principal é o ecrã de cancelar na página de detalhes do pedido. Quando o cliente pagou por MB Way, a app desliga a opção de devolver ao MB Way e obriga a escolher a carteira. Depois o servidor divide: 80 por cento em saldo e 20 por cento em tokens. Foi isso que aconteceu ao Divan ontem à noite. Pagou 6 euros por MB Way num Favor, cancelou três minutos depois porque não havia estafeta, e recebeu 4,80 euros de saldo mais 240 tokens, que valem 1,20 euros. A Stripe nunca devolveu nada. Ele ainda não gastou nada disso.

Há mais quatro sítios que mandam dinheiro pago para a carteira com tokens: quando o admin aprova um pedido de cancelamento (o ecrã vem com carteira escolhida por defeito), o cancelamento pelo admin na parte paga com saldo, o botão de reprocessar reembolsos falhados (que manda sempre o MB Way para a carteira), e o cancelamento do cliente quando ele escolhe carteira.

Nenhum caminho cancela um MB Way que ainda está à espera de aprovação, e ninguém avisa o cliente quando a Stripe confirma o reembolso. O webhook da Stripe só escreve uma linha no registo.

Encontrei também um erro com os tokens. A app só gasta os tokens depois de o pagamento passar. Até ao dia 5, se o MB Way falhasse e o pedido fosse cancelado, o sistema achava que os tokens tinham sido pagos e dava esse valor em saldo livre. Foi o que se passou com o pedido do Burger King do Divan, a 3 de outubro: 31,49 euros por MB Way, o MB Way falhou e nada foi cobrado, mas ele tinha posto 1101 tokens. O cancelamento deu-lhe 5,51 euros de saldo livre, e dois minutos depois ele fez outro pedido do Burger King, pago em dinheiro, e gastou esses mesmos tokens. Ou seja, ficou com 5,51 euros de saldo que nasceram do nada, e ainda não os gastou. O motivo "payment_failed" que viste vem daí: é a própria app que cancela o pedido quando o pagamento falha. Desde o dia 5 isto já não acontece, mas agora acontece o contrário: quem cancela um pedido pago com tokens perde os tokens.

Na limpeza, a taxa de cancelamento é cobrada mesmo quando ainda não há profissional. E quatro botões do painel (cancelar limpeza, cancelar lavagem, cancelar marcação e cancelar reserva em nome do cliente) escrevem "reembolsado" sem nunca chamar a Stripe. Nos últimos 30 dias não houve nenhum destes casos com dinheiro pago, por isso não há ninguém prejudicado agora, mas o próximo vai ser.

## O que proponho

Primeiro, mudar uma definição: a divisão da carteira passa de 80 por cento para 100 por cento em saldo. Isso acaba com os tokens em vez de dinheiro em todos os caminhos antigos no mesmo minuto, sem mexer em pedidos passados.

Segundo, a regra que decidiste, no servidor e na app. Pago por MB Way volta sempre ao MB Way. Pago por cartão volta ao cartão, com o texto "Devolvemos ao teu cartão. Pode demorar 5 a 10 dias úteis a aparecer no extrato", e só vai para a carteira se o cliente carregar em "Quero já em saldo na carteira". Aí fica guardado o consentimento, com o texto que ele viu, e vai tudo em saldo, nunca em tokens. Se o pagamento ainda não foi cobrado, cancela-se a reserva na Stripe. Sem estafeta, nunca há taxa. Os tokens usados voltam como tokens, nunca como saldo. E quando a Stripe confirma, o cliente recebe a notificação "Reembolso confirmado".

Terceiro, um botão no painel, na ficha do pedido, chamado "Devolver ao meio de pagamento". Mostra quanto foi cobrado, quanto foi para a carteira e quanto o cliente já gastou. Faz o reembolso na Stripe, e só quando a Stripe confirma é que tira da carteira o saldo e os tokens que esse pedido criou, tudo de uma vez e sem poder repetir. Se o cliente já gastou uma parte, só se devolve o que ainda não foi gasto.

## Quanto dinheiro está em jogo

Nos últimos 30 dias, foram para a carteira 13,07 euros de dinheiro pago por MB Way, em dois pedidos. Um é o do Divan, 6 euros, que ainda dá para devolver por inteiro. O outro é o envio de pacote da Dayane, 7,07 euros, cancelado por ti a 12 de setembro sem culpa dela. Esse já tinha estafeta. Nesse dia o sistema creditou-a oito vezes seguidas por engano, 40,76 euros de saldo em vez de 5,66; os 35,10 euros a mais foram retirados 14 minutos depois, e os tokens repetidos nunca chegaram a ser criados. Ela já gastou o saldo e os tokens desse pedido, por isso não há nada a devolver e proponho deixar como está.

Houve ainda 5,75 euros de saldo dados sem nenhum pagamento, por causa do erro dos tokens. São 5,51 euros do Divan, que ainda não os gastou, e 24 cêntimos da Rosa, que já os gastou.

O pedido do restaurante parceiro de 16,16 euros que citaste é o da Rosa. O MB Way dela falhou e nunca foi cobrado; para a carteira só foram esses 24 cêntimos. O envio de pacote de 7,07 euros é o da Dayane.

Hoje o Divan tem 10,31 euros de saldo, que são 5,51 mais 4,80, e 240 tokens deste último pedido. Com o botão, recebe 6 euros no MB Way e fica com 5,51 euros de saldo. Se decidires anular também os 5,51, fica a zero; a linha para isso já está escrita, comentada, no ficheiro SQL.

## O que preciso que decidas

Primeiro, se aplico tudo: o SQL, o servidor, o webhook, o botão e a mudança na app.

Segundo, os 5,51 euros do Divan: fica como oferta ou anulo?

Terceiro, o sinal que se perde numa reserva de mesa cancelada a menos de 2 horas, ou numa marcação de barbearia a menos de 24 horas, conta como taxa com profissional? Hoje o código fica com o sinal.

Os ficheiros estão nesta pasta: o SQL da regra nova, o SQL do botão, a Edge nova completa, a explicação da Edge e do webhook, o desenho do botão, e um anexo com o caminho de cada categoria.

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.
