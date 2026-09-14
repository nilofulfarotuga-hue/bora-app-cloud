# Relatório — parceiro-edita-preco-14-09 (Claude Code · Opus · 14/09/2026)

## Acessos e o que foi criado nesta sessão

Conta usada na prova real: a do dono da Sabores de Casa, kauanmtsaru@gmail.com, por um link
de entrada de uma vez gerado pela API de administração do Supabase, sem email enviado e sem
tocar na palavra-passe. Essa sessão de prova foi fechada no fim. Nada mais foi criado em
contas: nem utilizadores, nem chaves, nem definições.

Na base de dados de produção nasceram duas funções novas, só aditivas: admin_list_products_by_partner_v2
e admin_update_product_prices (migration 20260914170000_admin_precos_parceiro_balcao_e_app.sql,
aplicada e no repo). Nenhuma função que reparte dinheiro foi alterada e a tabela de definições
da plataforma ficou intocada.

No repo: commit b5759549 empurrado para autonomous-night-2026-04-29 (push 01e6c0ce..db7a4b9a),
o que dispara o build Android e o deploy web. Provas em
.claude/.ai/provas/parceiro-edita-preco-2026-09-14/PROVAS.md.

## O que NÃO foi feito, ou ficou com aviso

Primeiro o aviso mais importante. Ao fechar a sessão de prova do dono da Sabores de Casa
usei um logout global em vez de local. Isso fecha todas as sessões daquela conta, incluindo a
do telemóvel dele, se estava aberta. Não consigo saber se estava: a base já não guarda as
sessões antigas. Se ele disser que a app lhe pediu para entrar outra vez, foi isto, e basta
entrar de novo com o email e a palavra-passe dele. Fica registado na memória para não voltar
a acontecer: logout de prova é sempre só da sessão de prova.

Não provei o ecrã novo a correr no navegador com a conta dele. A prova real foi feita com a
sessão dele a enviar exactamente o mesmo pedido que a app envia ao guardar, e o SELECT
confirmou o resultado — mas os botões novos só ficam visíveis a ele depois de o build deste
push chegar ao telemóvel (versão Android e web saem juntas). A regra da casa diz que testar a
app da loja antes do build prova a app velha, por isso não o fiz.

O Córtex não estava autenticado nesta sessão (o servidor pede login) — não consultei nem
memorizei lá. A memória partilhada da claude_ai_memoria foi lida no arranque e recebe o digest
no fim.

Não mexi na aba de catálogo da ficha do parceiro no admin para além do preço: o interruptor
de disponibilidade dessa aba continua a chamar a função antiga sem o motivo que ela exige,
por isso falha (bug anterior a esta missão, fora do tema). O Catálogo principal do admin
pede o motivo e funciona.

A foto no modo de edição usa o mesmo caminho de envio que o criar (câmara, galeria ou URL).
Uma limitação herdada: apagar a foto de um produto já criado não fica gravado — o store
trata "vazio" como "mantém a foto actual". Trocar por outra foto funciona.

O botão de apagar produto apaga mesmo a linha na base (o store já fazia assim), e as opções e
variantes desse produto vão junto — as duas chaves estrangeiras para products estão em
cascata, confirmado na base. Os pedidos antigos não são tocados, guardam a sua própria cópia
do que foi comprado. Não apaguei nenhum produto real do dono para provar o botão; a permissão
de apagar do parceiro (products_delete_owner) está na base e o deleteProduct já existia.

## A regra de preço, como ficou no código

O parceiro escreve o preço de balcão, o que ele quer receber. A app soma a comissão por cima,
sozinha. Gravam-se as duas colunas: partner_shelf_price com o número que ele escreveu e price
com balcão a dividir por um menos a comissão visível, vezes um mais o markup oculto,
arredondado a dois cêntimos. As duas percentagens são lidas de platform_settings de cada vez
que o ecrã abre — no código não há 0,90 nem 1,05 escritos à mão, e o teste prova que mudar a
percentagem muda o preço. Com os valores de hoje dá balcão vezes 1,1667: etiqueta 8,00 € →
o cliente vê 9,33 € → o parceiro recebe 8,00 € certinho.

Uma coisa que encontrei na base e que a ordem não mencionava: a função que reparte o dinheiro
em produção, partner_store_share, tem hoje uma segunda versão que recebe a loja e olha para
restaurants.app_markup_pct. Quando essa coluna está preenchida (Leonidas com 0,10 e Mr Kebab
com 0,15, o modelo "comissão paga pelo cliente"), o parceiro recebe o preço a dividir por um
mais essa percentagem; quando está vazia (Sabores de Casa, Goola, Sabores do Brasil), aplica a
fórmula da plataforma. As duas funções que fazem a repartição já chamam esta versão. Por isso
o código Dart espelha exactamente essa função, com os dois ramos — não é uma variante nova,
é a leitura ao contrário da função que já reparte o dinheiro. Para a Sabores de Casa e a
Goola o resultado é o que a ordem pede, ao cêntimo. Ponto a registar: o repo tem uma
proposta (20260914120000_PROPOSTA_repasse_parceiro_comissao_paga_pelo_cliente.sql) com outra
forma desta função, baseada em partner_commission_billing; o que está no ar é a versão por
app_markup_pct, aplicada por outro motor e ainda sem migration no repo. Não mexi nisso —
é dinheiro — mas o ar está à frente do repo nessa função.

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO — só para constar: esta missão não alterou nenhuma
função de repartição nem a tabela de definições. A coluna partner_shelf_price passou a ser
escrita pela app do parceiro e pelo admin, por ordem explícita da missão. Não há nada à
espera de "vai".

## Bloco 1 — Editar produto no lado do parceiro

Cada produto na lista do parceiro tem agora "Editar produto", que abre o mesmo ecrã de criar
em modo de edição, com nome, descrição, "Preço que recebes" (pré-preenchido com o balcão
gravado; se o produto ainda não tiver balcão, cai para o preço actual), categoria (o dropdown
já vem com a categoria do produto escolhida), foto (câmara, galeria ou URL, o mesmo caminho de
envio para o bucket product-images) e alergénios. Por baixo do preço, a cada tecla, duas linhas:
"Recebes: 8,00 €" e "O cliente vê: 9,33 €". Ao guardar grava as duas colunas pelo updateProduct
que já existia. Se não conseguir ler as percentagens da plataforma, não grava e diz porquê, com
botão para tentar outra vez. O diálogo solto de categoria foi retirado. O cartão de cada produto
passou a mostrar "Recebes 8,00 €" e "O cliente vê 9,33 €". Mensagens em PT-PT.

## Bloco 2 — Adicionar produto com a mesma regra

O campo chama-se "Preço que recebes", com a mesma pré-visualização, e o insert grava
partner_shelf_price e price calculado. O bug de gravar o número cru em price, que fazia o
parceiro receber menos 14 % sem saber, acabou. Se a loja não for parceira o ecrã continua a
gravar só price, como antes — a ordem manda não mexer nas não-parceiras.

## Bloco 3 — Apagar produto

Botão "Apagar" em cada produto, com diálogo "Apagar <nome>? Esta ação não pode ser desfeita."
e o deleteProduct que já existia no store. Mensagem de sucesso ou de erro em PT-PT.

## Bloco 4 — Painel admin (PT-BR)

No Catálogo do admin cada produto de loja parceira mostra "Balcão €8,00 → App €9,33". O lápis
abre um diálogo com os dois campos: escrever o balcão recalcula o preço no app; escrever o preço
no app recalcula o balcão pela fórmula inversa. Mostra a regra em vigor (da plataforma, ou a
percentagem própria da loja) e a frase "Parceiro recebe X de cada Y que o cliente paga". Motivo
obrigatório. Grava pela função nova admin_update_product_prices, que exige admin, valida os
valores, recusa um par incoerente (a leitura do servidor tem de devolver o balcão), grava as duas
colunas de uma vez e regista no admin_audit_log com valores antigos e novos. Loja não-parceira
continua no diálogo antigo. A ficha do parceiro no admin usa o mesmo diálogo e a lista v2, e
passou a enviar o motivo que a função antiga exigia (essa chamada falhava sempre).

Autoridade do Danilo: ver as duas colunas, sim; editar as duas, sim; criar produto, pelo
registo do parceiro ou pela app do parceiro (o admin não tem formulário de criar produto —
já não tinha); apagar produto, o admin tem permissão na base (política products_delete_admin)
mas não tem botão no painel — também não tinha antes. Se quiseres os dois botões no painel,
é uma missão pequena à parte.

## Bloco 5 — Provas

flutter analyze lib: zero erros. Teste novo test/partner_price_rules_test.dart com onze casos:
o exemplo real 8,00 → 9,33 → 8,00, a Goola 7,90 → 9,22 → 7,90, um varrimento de todos os
preços de 0,01 € a 200,00 € nos dois sentidos, percentagens diferentes (12 e 3, 0 e 0) a darem
resultados diferentes, e as lojas com percentagem própria (Leonidas 14,95 → 16,45 → 14,95;
Mr Kebab +15 %). Suite completa: 532 testes verdes. Do lado do servidor, o mesmo varrimento
em SQL com as percentagens lidas de platform_settings: 20 000 em 20 000 fecham ao cêntimo.
Juiz anti-trapaça sobre o diff: limpo.

Prova real com a conta do dono da Sabores de Casa: com a sessão dele, o mesmo pedido que a
app envia ao guardar mudou o "Copo Grande" de balcão 8,00 para 8,50; o SELECT mostrou
partner_shelf_price 8,50, price 9,92 e partner_store_share(9,92) igual a 8,50 nas duas versões
da função, coerente. Depois repus 8,00, e o SELECT final dá 9,33 / 8,00 / 8,00. Nada dele
ficou diferente do que estava.

Commit b5759549 e push feitos; o versionCode ficou para o CI (estava em 605 antes do push).

## PARA O DANILO

Nada exige acção tua. Só isto para saberes: quando o build chegar, o dono da Sabores de Casa
vê os botões "Editar produto" e "Apagar" e o campo "Preço que recebes". E se ele te disser
que a app lhe pediu login outra vez, foi o meu logout de prova — ele entra de novo e pronto.

Fim da missão: /ctx doctor e /ctx stats correm a seguir.
