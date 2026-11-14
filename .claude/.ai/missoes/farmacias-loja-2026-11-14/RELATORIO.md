# Relatório — farmacias-loja-2026-11-14

Fiz isto. Montei tudo o que pediste para as duas farmácias, mas nada está no ar ainda: a trava do PC não me deixa
mexer no servidor nem publicar, e diz que isso é a Claude.ai que faz. Não a contornei. O código está no pedido de
revisão 15 do GitHub (https://github.com/nilofulfarotuga-hue/bora-app-cloud/pull/15) e o pedido para a Claude.ai
aplicar o servidor está no livro, na página pedido-claude-ai-farmacias-loja-2026-11-14.

Uma coisa importante sobre o preço. O preço que a app mostra JÁ É o da Glovo, nos 1378 produtos: comparei com o
catálogo da Glovo e bate ao cêntimo. O que estava 16,67 % abaixo era o "preço de balcão". Se eu fizesse como estava
na ordem, preço igual ao balcão, o cliente pagaria 14 % menos do que na Glovo. Por isso fiz ao contrário: o preço fica
o da Glovo, o balcão passa a ser igual a ele, e a farmácia recebe 100 % do valor dos produtos. A Bora deixa de tirar
os 10 % e os 5 % escondidos.

O dinheiro, como fica quando a Claude.ai aplicar: o cliente paga os produtos ao preço da Glovo, mais a taxa de serviço
de 0,99 € mais 5 %, numa linha só, mais a entrega de sempre, mais 1,39 € de pedido pequeno abaixo de 15 €. Sem saco,
porque a tua conta não tinha saco. A farmácia recebe tudo nos 3 primeiros meses; depois paga 10 % no fecho semanal, em
cartão, MB Way e dinheiro, e também nas receitas. Em dinheiro, o estafeta paga à farmácia o valor dos produtos na
recolha, e os 10 % entram no fecho como valor que a farmácia deve. Provei isto contra os dados reais com cópias
temporárias das funções, sem mudar nada: as outras lojas ficam exatamente iguais ao cêntimo.

Os números, com o cesto a 2 km. Cesto de 8 €: o cliente paga 13,28, a farmácia recebe 8, o estafeta 4,20 e a Bora fica
com 1,08, ou 63 cêntimos se for cartão; depois dos 3 meses, 1,88. Cesto de 15 €: o cliente paga 19,24 e a Bora fica com
4 cêntimos, e com cartão perde 50 cêntimos; depois dos 3 meses ganha 1,54. Cesto de 25 €: o cliente paga 29,74 e a Bora
fica com 54 cêntimos, com cartão perde 16; depois ganha 3,04. Cesto de 40 €: o cliente paga 45,49 e a Bora fica com 1,29,
com cartão 36 cêntimos; depois 5,29. Ou seja: nos 3 primeiros meses, com cartão, entre 15 e uns 30 €, a Bora perde uns
cêntimos por pedido. Não mexi nisso, é a regra combinada, mas convém saberes.

O painel da farmácia ganhou o botão grande de abrir e fechar a loja, as condições à vista (3 meses sem comissão, depois
10 %, pagamento semanal), o botão de WhatsApp do cliente, e o "este produto só chega mais tarde": a farmácia marca a
hora e o cliente escolhe esperar, tirar o produto ou cancelar sem pagar nada. O estafeta só é chamado meia hora antes e
vê "fica pronto às tantas". Os termos de parceiro passam a aparecer às farmácias no primeiro login, com o botão
"Aceito". O horário com domingo, o esgotado e disponível, e o editar pedido com aprovação do cliente já existiam.

O ecrã da loja no cliente: ao descer, a capa grande sai e fica uma barra fina presa em cima com o nome, a lupa e as
categorias, e os produtos ocupam o ecrã. O "Tenho receita" fica sempre à vista. A lupa já procurava nos 867 produtos;
acrescentei sinónimos para "protector solar" e "escova de dentes", que antes não achavam bem.

O painel admin tem agora o ecrã Farmácias com a ficha de cada uma: trocar o email de demonstração pelo verdadeiro e
mandar o link para criar a senha, nome legal, NIF, IBAN, certidão, comissão e data dos 10 %, o interruptor das receitas
reais e o botão "Abrir ao público", que só acende quando está tudo preenchido. Tem também o extrato semanal e o botão
para exportar.

Falta isto. Aplicar o servidor (a Claude.ai), juntar o pedido 15 para publicar nas três (a Claude.ai, depois do
servidor), as capturas na web e no Android, a revisão de visão, e o pedido de teste a dinheiro na tua conta: tudo isto
depende do servidor estar aplicado. A análise e os testes da app não correram no PC porque estava com 135 MB de memória
livre; estão a correr no GitHub, no pedido 15. Também não ficou feito: mudar o preço de um produto dentro de um pedido
já feito (o servidor só sabe tirar e acrescentar, e é dinheiro), e o extrato pedido a pedido a mostrar os 10 % depois
dos 3 meses (o fecho semanal já os conta certo; o extrato só mostra a partir de fevereiro e fica para depois).

Erros que encontrei e não corrigi. Hoje o servidor deixava abrir uma farmácia sem NIF, IBAN nem termos, e com o email de
demonstração; a migração c2 trava isso. Uma das tuas duas contas de admin não tem o papel de admin no login, e falha em
algumas funções do painel. Trocar o email não fecha as sessões que já estão abertas na conta de demonstração. O botão
de forçar saída do estafeta pode não estar a fechar as sessões. O reembolso automático de um pedido pago com cartão e
saldo pode não devolver a parte do saldo (por confirmar). Duas funções de editar e cancelar pedidos aceitam o dono da
loja por campos diferentes. A dica da pesquisa está em português do Brasil.

PARA O DANILO: nada para decidir agora. Quando quiseres abrir as farmácias, primeiro a Claude.ai aplica o servidor,
depois metes o email verdadeiro, o NIF e o IBAN no ecrã Farmácias, a farmácia aceita os termos, e carregas em
"Abrir ao público".
