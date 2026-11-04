# Escada de prémios do check-in — 04/11/2026

Fiz isto. Confirmei por consulta ao servidor o que a Claude.ai já tinha feito: os produtos-prémio escondidos, os degraus novos e os salgados guardados do Nelson e do Divan, que não mexi. Agora cada pessoa só levanta um prémio a cada 30 dias. Se tentar antes, continua a fazer check-in e a ganhar tokens, o prémio fica guardado e a app diz em que dia fica disponível. Provei isso no servidor com o teu caso: levantaste o açaí a 29/10, por isso só podes levantar outro a 28/11.

O calendário do mês na app mostra agora os 30 dias. Nos dias de prémio aparece a foto e o nome; nos outros, os tokens do dia. Diz também que o prémio conquistado fica guardado e, se for o caso, a data do próximo prémio. O texto do check-in passou para o teu texto novo.

No painel encontrei uma falha: só mostrava 4 prémios escritos no código, e os novos (Leonidas, Burger King, McDonald's, Tiago's, Fuku, Boom) nem apareciam. Agora aparecem todos. Dá para mudar a loja e o produto de cada um, criar degraus novos, que nascem desligados, mudar os 30 dias, e ver o custo dos prémios por mês e por loja, com exportação.

Já foi publicado: a web está no ar com o calendário novo e o Android saiu com o número 712. O iPhone ainda estava a compilar quando acabei.

Falta isto. O desconto nos mercados ficou meio feito. O servidor já conhece o prémio "3 € de desconto numa compra de pelo menos 25 €", e os 6 degraus estão criados, mas desligados. Para o desconto sair no pagamento é preciso mexer na conta do pedido, que é zona protegida e a tranca não deixa. Deixei a proposta escrita em docs/propostas.

Os prémios nas lojas não parceiras ficaram desligados, como estavam. Não dá para provar com segurança. Nas parceiras a Bora paga depois à loja. Nas não parceiras o estafeta paga ao balcão, e não existe maneira de lhe devolver esse dinheiro quando o produto sai a 0 €. Além disso, o fecho da compra pelo talão pode acabar por cobrar o prémio ao cliente. A proposta para isto está no mesmo ficheiro.

Também não vi o calendário no emulador nem na web com conta aberta. O PC tinha só uns 500 MB livres, e entrar numa conta no site de produção é coisa que não faço. O desenho do calendário está provado pelos testes.

Erros que encontrei. As fotos do Fuku e do Tiago's vêm do site da Glovo. A Mercadona Beleza está ativa na app, mas lembra-te de que a Mercadona tinha sido parada até dizeres "vamos reabrir a loja". Os degraus de desconto dela estão desligados.

Próximo passo. Uma sessão com licença para a zona de preços aplicar o desconto no pagamento e o acerto do estafeta nos prémios das lojas não parceiras. Depois disso ligam-se os 11 degraus desligados.
