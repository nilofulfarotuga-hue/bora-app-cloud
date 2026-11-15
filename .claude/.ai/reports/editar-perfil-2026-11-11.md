# Relatório — Editar perfil do cliente (11/11/2026)

Missão editar-perfil-2026-11-11, autorizada pelo Danilo às 16:54 e às 17:00. Registo passo a passo no e2e_log, fluxo editar-perfil-2026-11-11.

## Fiz isto

Primeiro arrumei o robô do suporte. A ficha de perguntas gerais (GENERAL_FAQ) mandava o cliente para ecrãs que não existem: "Os meus pedidos", um separador "Pedidos", "Carteira", "Editar perfil" e "Ajuda". Guardei uma cópia (tabela bkp_support_skills_general_faq_20261111) e troquei a parte da navegação pelos nomes reais que estão na app: menu de baixo com Início, Entrega, Reservas e Perfil; histórico em Perfil, Histórico de pedidos; saldo em Perfil, Saldo Bora; tokens no cartão Tokens ou no checkout; moradas, cartões e NIF nos sítios certos do Perfil; foto na máquina fotográfica; suporte em Perfil, Suporte, ou no botão laranja. Para mudar nome ou telemóvel, o robô agora diz que ainda não há botão, pergunta o que a pessoa quer mudar, confirma e abre o pedido para a equipa. O email não se muda porque é o login. A ficha passou da versão 1 para a 2. Depois revi as outras fichas e a base de conhecimento. Corrigi a ficha do estafeta (DRIVER_FAQ), que mandava para um "Histórico de entregas" que não existe; agora manda para Perfil, Extrato, ou Perfil, Os meus ganhos. Corrigi também uma ficha de conhecimento que chamava "Os meus pedidos" ao ecrã que na app se chama Histórico de pedidos. As duas têm cópia de segurança. As outras ocorrências que apareceram na busca eram o verbo "ajudar", não um menu.

Depois fiz o "Editar perfil" na app do cliente. No Perfil, debaixo do nome e da foto, há um botão "Editar perfil". Abre um ecrã com o nome, o telemóvel e o email só para ler, com a frase "O email é o teu acesso e não se altera". O nome tem de ter entre 2 e 60 letras e tira os espaços a mais. O telemóvel aceita +351 e grava só os 9 números, como já se grava hoje. O botão Guardar fica desligado enquanto nada mudou, mostra a rodinha enquanto grava e não aceita dois toques. Se a internet cair, aparece uma mensagem clara e o que a pessoa escreveu fica lá. Quando grava, o nome novo aparece logo no Perfil e no "Olá, X!" do Início.

No servidor preparei a gravação nova. É uma função que só deixa mudar a própria conta, porque vai buscar a pessoa ao login dela e nunca a um número que venha de fora. Valida tudo outra vez do lado do servidor, recusa quem não tem sessão e a conta de convidado, e tem um travão de 10 mudanças por dia. Cada mudança fica numa tabela de histórico nova, com quem mudou, de onde, como estava antes e como ficou depois. A guarda usa o login da pessoa e a lista de administradores, nunca o truque do current_user que deu erro a 10/11. Não há código por SMS na app (só o email da senha usa um código), por isso o telemóvel muda sem SMS.

Descobri uma coisa importante pelo caminho. A app lê o nome do cliente dos dados do login, não da tabela de utilizadores. Por isso, quando hoje à tarde se mudou o nome da cliente à mão no servidor, só mudou num dos dois sítios, e na app dela continua o nome antigo. A gravação nova muda os dois sítios ao mesmo tempo, e a app passou a ir buscar o nome ao servidor quando abre e quando se entra no Perfil. Assim, uma mudança feita no painel ou aprovada no suporte chega ao telemóvel. Não mexi na conta da cliente, como pediste.

No painel admin, a ficha do cliente já tinha "Editar nome e telefone". Pus essa edição a passar pela mesma gravação, por isso agora guarda o antes e o depois e avisa o cliente na app. Acrescentei no menu de cada cliente a opção "Histórico de mudanças do perfil", que mostra quem mudou, quando (hora de Lisboa), de onde, e o antes e o depois; as mudanças antigas, de antes deste histórico, também aparecem. A lista dos pedidos do robô com Aprovar e Rejeitar já existia (Propostas do robô). O que faltava era a aprovação fazer a mudança como deve ser: agora, ao aprovar um pedido de mudança de dados, muda o nome e o telemóvel nos dois sítios, normaliza o número, guarda no histórico, marca o pedido como feito e o cliente recebe um aviso no sino da app e no telemóvel. Se o pedido trouxer outra coisa que não seja nome ou telemóvel, ou um número mal escrito, fica como falhado e não mexe em nada.

## Provas

O texto do robô: SELECT da ficha GENERAL_FAQ mostra versão 2, md5 c3385c24…, sem "Editar perfil", sem "Os meus pedidos" e sem "Carteira". DRIVER_FAQ na versão 2. As três cópias de segurança têm 1 linha cada.

A parte do servidor foi provada no PC numa base Postgres local (PGlite), com 25 situações, todas certas: grava nome e telemóvel e tira o +351; grava também nos dados do login sem apagar o resto; gravar igual não conta como mudança; nomes "A", "12" e com 61 letras recusados; números 812… e curtos recusados; sem sessão e convidado recusados; limite de 10 por dia; um cliente não consegue usar a função do admin nem ver o histórico; o admin edita, fica registado e o cliente é avisado; aprovar o pedido do robô muda de verdade, marca como feito e avisa; pedido com campo proibido ou número mau fica falhado sem mexer na ficha; carregar duas vezes em Aprovar é recusado; o histórico mostra antes e depois; ninguém de fora consegue chamar as funções internas; e as outras partes da função de aprovação ficaram iguais, letra a letra. Guião e resultado em .claude/.ai/reports/editar-perfil-2026-11-11/.

A app: 4 testes automáticos novos, todos verdes (o Guardar desligado sem mudanças, grava e o "Olá, X!" muda logo, nome inválido não chama o servidor, sem rede mostra a mensagem e não perde o texto). O teste das traduções em inglês está verde. A análise do código não tem avisos novos. Corri também os 8 ficheiros de testes que tocam no Perfil, no login e no painel de clientes: 133 certos e 1 errado, e esse errado é um teste antigo do Livro de Reclamações que já falha com o Flutter mais novo deste PC (é um aviso do Flutter 3.47; o CI usa a 3.41.2). A memória livre no PC estava em 615 MB quando corri esses testes, abaixo dos 800 da regra; corri um ficheiro de cada vez por isso.

## Falta isto (e porquê)

Aplicar no servidor as duas migrações. A trava do PC recusou, as duas vezes, com a frase "migração é publicar: publica o Claude.ai", até numa prova que se desfazia no fim. Não contornei. Os ficheiros estão no ramo de ensaio ai/2026-11-11-editar-perfil, no pedido de revisão número 12 (https://github.com/nilofulfarotuga-hue/bora-app-cloud/pull/12), e no livro, na página entrega-editar-perfil-2026-11-11, com o md5 de cada um: 20261111180000_editar_perfil_cliente.sql (md5 99ce60a8…) e depois 20261111180100_aprovar_account_update_pelo_nucleo.sql (md5 29e4a8b3…).

Publicar nas 3 lojas e as capturas das 3 a gravar o nome. Não enviei para o ramo de produção de propósito: sem as migrações aplicadas, o botão Guardar ia dar erro a todos os clientes. A ordem certa é: aplicar as duas migrações, juntar o ramo ai/2026-11-11-editar-perfil ao de produção, e o CI publica Android, iPhone e web. Também não consegui gravar capturas no telemóvel: este PC não compila a app nova para o emulador (a trava não deixa ler as chaves) e não tem memória para o emulador.

Bloco 4 (o robô dizer "Perfil → Editar perfil") só depois de publicado nas 3. Fica por fazer.

## Erros que encontrei (Bloco 5 e pelo caminho) — só reportados

a) O "Acesso negado" no painel web. A app não tem lista de emails: deixa entrar quem tem o papel admin no login (ou o papel antigo bora_role admin). O banco deixa entrar quem tem o papel admin ou um de dois emails. A conta nilofulfarotuga@gmail.com tem o papel admin no banco, por isso as duas regras dizem que sim. O mais provável é a sessão aberta nesse navegador ser outra conta (por exemplo a de convidado que a app cria sozinha) ou um login antigo; o ecrã do painel não renova o login antes de recusar, embora a função para isso já exista. As duas regras não batem noutro caso: a conta nilofulfaro@gmail.com é admin para o banco (pelo email) mas não para a app (não tem o papel). A mensagem "não está na lista de administradores" engana, porque não há lista na app.

b) Fuku Sushi: o horário no banco é 12:00 às 23:00 seguido, todos os dias. Às 16:48 a Glovo mostrava a loja fechada. Não mexi.

c) "Hambúrguer do mês" no Fuku: não aparece a nenhum cliente, porque o Fuku não tem produto em destaque. É o valor por defeito da coluna e está igual em 31 lojas, 30 delas sem produto. Só se vê no editor de destaque do painel.

d) Caixa Mix 36 peças do Fuku: 21,50 € ao balcão. O Fuku não é parceiro, por isso leva os 15% e dá 24,725, que a app arredonda ao cêntimo para 24,73 €. Na web (app.boraguarda.com) vi e capturei "Caixa Mix 36 peças · 24,73 €" (web-fuku-caixa-mix-36-24-73.png). No Android e no iPhone a conta é feita pelo mesmo código, mas não tenho captura.

e) A função antiga do painel para editar o contacto tinha uma armadilha: se a tabela de auditoria faltasse, desfazia a gravação e mesmo assim dizia "ok". A versão nova tira isso.

f) A aprovação de pedidos do robô aceitava o telemóvel com +351, o que criava duas formas do mesmo número. A versão nova normaliza.

g) A função de aprovação que está no repositório não é igual à que está no servidor (o servidor tem uma versão mais nova). O remendo foi feito para funcionar nas duas.

h) No browser do perfil Bora, a loja do Fuku mostra um carrinho com 15,56 € de alguém que usou esse browser. Não mexi.

## PARA O DANILO

1. Deixar o Claude.ai aplicar as duas migrações e juntar o ramo ai/2026-11-11-editar-perfil ao de produção, por esta ordem.
2. A cliente de hoje continua a ver o nome antigo na app até a versão nova chegar ao telemóvel dela, ou até alguém pôr o nome também nos dados do login dela. Não mexi, como pediste.

## Próximo passo

Depois de aplicadas as migrações e publicada a versão: provar nas 3 plataformas com a conta de teste, e fazer o Bloco 4 no robô.
