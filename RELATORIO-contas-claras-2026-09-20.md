# Relatório — contas claras — 20/09/2026

Missão `contas-claras-2026-09-20` · run `contas-claras-20260920` · Claude Code (Opus) no PC · ramo `autonomous-night-2026-04-29`.

## Acessos

Base de dados Supabase `ojykpzwqrtusfeakzrna`, por MCP. Conta de admin nos testes: nilofulfarotuga@gmail.com (o teu email, só para simular a sessão nas provas, tudo em rollback). Não foi criada nenhuma conta nova em lado nenhum. As duas coisas que a Trava do PC recusou ficaram em `platform_settings` nas chaves `staged_contas_claras_20260920` (já aplicada pela Claude.ai) e `staged_contas_claras_20260920_b2` (por aplicar).

## O que NÃO foi feito, logo no início

Não empurrei nada para o GitHub. O código novo está commitado no PC, mas o push é publicação e a ordem diz que não se publica sem o autoteste dos três perfis verde, e esse autoteste precisa de telemóvel ou emulador, que esta máquina não tinha hoje. Enquanto o web não for publicado, o painel admin que tens no ar ainda mostra o botão antigo "Marcar pago" nos talões, que credita a carteira. Se pagares um talão por MB Way antes da publicação, não uses esse botão: diz à Claude.ai, que chama a função nova por MCP.

Não toquei na Isabel Rebelo. Ela continua com quatro euros e nove no histórico e um euro no saldo, por tua ordem. Está registada como caso conhecido no vigia, que não vai gritar por ela.

Não corrigi os desacertos que encontrei. O mapa e o vigia apontam, e a decisão é tua. Estão listados no fim, com um "vai" por cada um.

Falta uma peça pequena que a Trava não deixou aplicar daqui: a previsão da semana em curso para o admin ver a semana de outra pessoa. Para o próprio estafeta já funciona.

## O que ficou feito, bloco a bloco

Bloco zero, o mapa. Escrevi `docs/MAPA-DO-DINHEIRO.md` com as onze arcas de dinheiro que existem em produção, quem escreve em cada uma, quem lê, em que unidade, e os doze sítios onde a mesma verdade está guardada duas vezes. Medido tudo por SELECT. O que apareceu: o cliente tinha duas verdades na carteira que não conversavam, e a função que marca o talão pago escrevia numa e não na outra, exactamente como a Claude.ai tinha apurado. O estafeta tem quatro verdades para o mesmo dinheiro, com o sinal trocado entre duas tabelas. O motorista TVDE tem uma quinta arca só dele, que nenhum acerto semanal lê, e a Bora deve trinta e um euros e cinquenta ao Valdemir de corridas pagas na app que ninguém sabia. Três compensações de cancelamento de um euro e cinquenta estão no livro-razão e no ecrã de ganhos mas nunca entraram em acerto nenhum. O ecrã de ganhos do parceiro calculava em Dart e mostrava onze euros e quarenta e cinco onde a loja recebe dez euros e noventa.

Bloco um, uma verdade só. O saldo da carteira passou a ser sempre a soma do histórico, por gatilho no servidor que corre no fecho de cada transacção, para todas as funções presentes e futuras, sem reescrever nenhuma das catorze. O histórico deixou de poder ser reescrito ou apagado. A coluna de saldo dentro do histórico passou a vir sempre da soma. Provado em rollback: um talão inserido sem tocar no saldo faz o saldo subir os oito euros e vinte; tokens não mexem no saldo; uma função que actualiza o saldo e depois insere não conta a dobrar; apagar e alterar linhas é recusado. O talão passou a ter dois caminhos no painel admin, com nome: "Pagar na carteira do estafeta" e "Já paguei por fora (MB Way ou dinheiro)", cada um com a sua função, forma e data gravadas, e o do Valdemir ficou registado como pago por MB Way a dezanove de Setembro. A idempotência do reembolso dividido, que a Trava recusou daqui, foi aplicada pela Claude.ai às vinte e vinte e nove e confirmei no ar.

Bloco dois, o extrato do estafeta e do motorista. Antes de desenhar, li no navegador as páginas públicas de ajuda do Uber Driver e do Glovo e escrevi `docs/REFERENCIA-EXTRATOS.md` com o que eles mostram e por que ordem. Depois fiz uma RPC só, `extrato_prestador`, que devolve tudo: hoje, esta semana e a semana passada; cada trabalho numa linha, entrega ou corrida, de onde para onde, o que a pessoa recebeu, e um toque abre as parcelas; o que a Bora lhe deve e o que ela deve à Bora, cada um com as linhas que o compõem; o dinheiro em mão, pedido a pedido, com o total que é da Bora; o último acerto, quanto, quando, se está pago e o comprovativo; os talões pelo nome do caminho, "reembolso pago por MB Way a dezanove de Setembro". O ecrã de ganhos antigo passou a ler dos mesmos trabalhos, e provei que os dois dão os mesmos números. Com a identidade real do Valdemir, o extrato bate ao cêntimo com as arcas do bloco zero: entregas um euro e vinte e oito, TVDE trinta e um e cinquenta, e a Bora deve-lhe trinta e seis euros e cinquenta ao todo. O Flutter não faz contas: o widget novo só mostra o que a RPC devolve, e valor que o servidor não souber aparece como um traço com a razão.

Bloco três, o extrato do parceiro. RPC `extrato_parceiro`: pedido a pedido, quanto o cliente pagou, quanto era de produtos, quanto fica para a loja, quanto é da Bora e sobre o quê, o que já foi transferido e quando, o que falta transferir, a semana em curso pela fórmula oficial do fecho e o estado da conta Stripe. Provado com a Goola: cinquenta e dois euros e cinquenta em três arcas iguais, quarenta e um e sessenta já transferidos, dez e noventa por transferir, e a conta Stripe está desligada, o que quer dizer que os pagamentos à Goola foram por MB Way. O ecrã de ganhos do parceiro deixou de calcular em Dart e passou a mostrar a RPC.

Bloco quatro, a tua folha. RPC `admin_extrato_dono` e um ecrã novo no painel, "Contas claras (a folha do dono)": quanto entrou por dia ou por mês e por que meio, separando o que chegou à Bora pela app do que ficou em dinheiro nas mãos de quem entregou; quanto saiu, linha a linha; quanto está retido; a quem a Bora deve e quem deve à Bora, com nome, valor, motivo e o botão de marcar pago; e as arcas de hoje, com o número de achados do vigia por resolver. De um a vinte de Setembro entraram quatrocentos e vinte e três euros e cinquenta e cinco, cento e sessenta e oito pela app e duzentos e cinquenta e cinco em dinheiro; saíram sessenta e cinco e oitenta e seis; a Bora deve cento e trinta e sete euros e dezasseis a sete pessoas, e devem à Bora cinco euros e quarenta e três.

Bloco cinco, o vigia. Todos os dias às seis e dez compara histórico com saldo em todas as arcas e pontas, escreve os casos na tabela de achados que já existia e manda aviso ao Telegram com nome, valor e pedido, só quando há caso novo. Nunca corrige. Provado nos dois sentidos: plantei um cêntimo a mais na carteira do Valdemir dentro de uma transacção desfeita e ele apanhou; com a base como está, a primeira corrida gritou nove casos reais e a segunda calou-se. Tem ecrã no painel para ver, resolver com nota e correr à mão.

Bloco seis, painel e fecho. Cada coisa criada tem correspondência no painel: os dois botões do talão, a folha do dono com marcar pago e CSV, o vigia com resolver e correr agora, e "Extratos por pessoa", onde abres o extrato de qualquer estafeta ou parceiro e copias o CSV. Análise estática a zero erros, quinhentos e sessenta e nove testes verdes, chão anti-batota limpo.

## Os achados que precisam de um "vai" teu

Cada um destes está no vigia como caso aberto. Nenhum foi tocado.

Um. Corridas TVDE anteriores a esta semana que nenhum acerto contou: dezanove euros e cinquenta ao Valdemir e dezoito e trinta a ti. Desde as vinte e cinquenta e dois de hoje o TVDE entra no acerto, mas o fecho só apanha a semana que acaba; o que ficou para trás precisa de um acerto extraordinário ou de um pagamento por fora marcado à mão. Dinheiro real: preparo quando disseres.

Dois. Três compensações de cancelamento de um euro e cinquenta, uma delas do Valdemir, estão no livro-razão e no ecrã mas nunca entraram no acerto. A proposta é o acerto contar as compensações. Também dinheiro real.

Três. O teu TVDE tem catorze euros e vinte de diferença entre o saldo e a soma das corridas. Não sei a causa sem ir corrida a corrida; se quiseres, faço.

Quatro. Os payouts antigos da Goola e do teu perfil de estafeta ficaram em "pendente" enquanto os acertos já estão pagos. É uma tabela gémea parada; a proposta é marcá-los como pagos com a data do acerto, ou deixar de a usar.

Cinco. A Sabores do Brasil tem dez euros e vinte e nove no livro-razão de um pedido antigo sem linha financeira nem acerto. Conferir se foi pago.

Seis. A Isabel: quando quiseres fechar o caso nos registos sem lhe dar nada, é uma linha de estorno de três euros e nove com o motivo "caso fechado pelo Danilo a vinte de Setembro". Só com o teu "vai".

Sete. A conta Stripe Connect da Goola está desligada, transferências inactivas. Se a ideia é pagar por Stripe, precisa de ser activada; se é MB Way, está tudo certo e o extrato já diz isso.

## Adenda das vinte e duas horas: o TVDE já entra no acerto

Depois do fecho, a Claude.ai aplicou por MCP quatro migrations que confirmei em `supabase_migrations.schema_migrations`: o invólucro da semana em curso que eu tinha deixado em staged, e três que põem as corridas TVDE dentro do acerto semanal, com três colunas novas e o fecho de segunda a percorrer também quem só fez corridas. Espelhei as quatro no repo. Voltei ao extrato e à tua folha para não contar o TVDE a dobrar: a semana em curso passa a usar a previsão viva, e a linha de TVDE passou a ser só a das semanas anteriores que nenhum acerto contou. Conferido com o Valdemir: dezassete euros da semana em curso mais dezanove e cinquenta de corridas antigas, os mesmos trinta e seis e cinquenta de antes, sem duplicar. O achado número um da lista abaixo passa a ser só a parte antiga: dezanove e cinquenta ao Valdemir e dezoito e trinta a ti, de corridas anteriores a esta semana, que o fecho de segunda não vai apanhar porque só olha para a semana passada. Fica à espera do teu "vai" para as pagar por fora ou criar um acerto extraordinário.


## Adenda das vinte e três horas: as corridas "sem tarifa" — o que era e o que ficou

Fui à causa, como pediste, antes de mexer. A tarifa não "deixa de ficar gravada": nos pacotes de ida e volta e nos planos, a função que fecha a corrida grava de propósito na corrida só as paragens, porque o preço do pacote vive no vale (oito euros pagos uma vez, na ida) e o do plano vive na assinatura. Das dezassete corridas apontadas, dez são voltas de pacote, onde não há dinheiro nenhum a mudar de mão, e uma é de plano, também sem dinheiro. As que realmente tiveram dinheiro em mão e ficaram a zero são as idas de pacote pagas em dinheiro: o motorista recebeu os oito euros e a corrida diz zero. Nenhuma é de balcão; a de dezanove de Setembro tem os dez e os quatro bem gravados.

Isto muda a conclusão da regra aplicada às vinte e uma horas, a de deduzir a tarifa por ganho mais corte. Medido corrida a corrida contra o registo de fecho de cada uma: em treze corridas a regra cobra dinheiro que nunca existiu, três euros e cinquenta por cada volta de pacote e quatro euros no plano, e nas idas em dinheiro cobra quatro e cinquenta em vez de oito. Para ti dá sessenta e oito euros a mais a dever à Bora; para o Valdemir os dois erros anulam-se. A identidade tarifa igual a ganho mais corte só vale nas corridas normais; foi também por isso que as cinco corridas antigas de trinta e um de Julho e trinta de Agosto pareciam erradas e não estão: nas quatro idas de pacote faltam os três e cinquenta da reserva do motorista da volta, e na de plano a tarifa são só as duas paragens.

O que fiz: cada corrida passa a levar gravado, ao fechar, o dinheiro que o motorista recebeu em mão, pela mesma regra que o servidor já usa para o saldo, e quando uma corrida normal em dinheiro fechar sem tarifa, o valor é deduzido, a corrida fica marcada, e o vigia grita no Telegram na hora. Decidi não recusar o fecho: o passageiro está a sair do carro e recusar deixaria o motorista preso sem ganhar nada. As sessenta e quatro corridas antigas ficaram preenchidas e batem com o registo de fecho em sessenta e três; a única diferença é uma corrida tua de dezoito de Setembro cujo registo de fecho ficou com cinquenta quilómetros e a corrida foi depois corrigida para dois e meio, e aí a coluna nova é que está certa.

Falta uma peça, e é tua: o acerto semanal ainda lê a regra de deduzir. A versão que lê o dinheiro em mão da corrida está pronta em `staged_contas_claras_20260920_b8` e no repo, à espera do "vai" para a Claude.ai aplicar. No ecrã do motorista, numa corrida em dinheiro, passou a ver-se antes e depois: recebes do passageiro dez, fica para ti quatro, entregas à Bora seis, com o quatro a ser o número grande.

## Publicação

Commit local feito com os caminhos explícitos desta missão. Push por fazer, pela razão do início. Quando o autoteste dos três perfis correr verde, o push publica o Android e o web de uma vez.

## Onde está tudo

Mapa em `docs/MAPA-DO-DINHEIRO.md`. Referência do Uber e Glovo em `docs/REFERENCIA-EXTRATOS.md`. Migrations em `supabase/migrations/20260920190000` a `20260920220000`, mais a `20260920202900` aplicada pela Claude.ai e a proposta `20260920204500`. Provas em `.claude/.ai/provas/contas-claras-20260920/`. Linhas no `e2e_log`, fluxo `contas-claras-2026-09-20`. Ecrãs: `lib/widgets/extrato_prestador_section.dart`, `lib/screens/partner_earnings_screen.dart`, `lib/screens/admin/admin_extrato_dono_screen.dart`, `admin_vigia_dinheiro_screen.dart`, `admin_extratos_pessoas_screen.dart`, `admin_receipts_screen.dart`.
