# Missão tvde-pacote-mapas-senha — 2026-08-30

## Acessos e contas usadas nesta sessão

Supabase do projecto ojykpzwqrtusfeakzrna, entrado com o token pessoal do `.supabase-token.env` (CLI e Management API) e com a chave de servidor do `backend/.env` (só para a prova da palavra-passe). Foi criada uma conta de teste nova, teste-senha-bloco7@bora.app, palavra-passe actual SenhaNova456 — serviu a prova do Bloco 7 e pode ficar ou ser apagada. Nenhuma conta real foi tocada. Nenhum dinheiro real foi movido.

## O que NÃO foi feito (a ler primeiro)

Primeiro: a prova no telemóvel não foi feita — não há nenhum Android ligado por USB a este computador. Falta provar ao vivo o pacote em dinheiro ponta a ponta a mostrar 8 euros no fim, o MB Way de pacote com a app fechada a meio, e as capturas do tracking novo e do mapa do motorista. E há um agravante que precisa de atenção: o repositório tem alterações por committar de OUTRA sessão que não compilam — o main.dart, o client_main_screen.dart e o provider_detail_screen.dart importam dois ficheiros que não existem em lado nenhum (deep_link_store_screen.dart e destino_pendente.dart). Enquanto isso não for resolvido, nem sequer dá para correr a app neste computador, nem web nem Android, e um push desses ficheiros partiria o build do CI. Não toquei nesses ficheiros nem os incluí no commit.

Segundo: o passo final do Bloco 7 — trocar o template do email de recuperação — está preparado mas NÃO aplicado, de propósito. O ecrã novo que entende o link à prova de prefetch só existe no código desta missão; se o template fosse trocado já, os emails novos apontariam para um formato que o site publicado ainda não entende, e a recuperação partia para toda a gente. Assim que o web app com este código estiver no ar, corre-se o script que ficou pronto em `.claude/.ai/tmp/bloco7-trocar-template-recovery.ps1` e o assunto fecha.

Terceiro: o Bloco 3 não levou deploy nenhum — e ainda bem, porque o deploy pedido teria feito estrago. Explico já abaixo.

## Bloco 3 — o preço do pacote online (a descoberta mais importante do dia)

A ordem dizia que a Edge tvde-plan-payment no ar cobrava sempre 8 euros fixos e mandava corrigir o ficheiro do repo e deployar. Fui primeiro ver o que está mesmo no ar, como manda a regra da prova — e o que está no ar (versão 7, de 25/08) é MAIS avançado do que o ficheiro do repo: já cobra o pacote pela distância (chama a tvde_roundtrip_price_for_km quando o distance_km chega no pedido), já cai no piso quando a distância não vem, e ainda trata os planos por quilómetro e guarda a distância nos metadados do pagamento. O ficheiro do repo é que estava duas gerações atrás. Se eu tivesse deployado o repo por cima, teria feito um retrocesso em produção e partido a activação dos planos por km.

Fiz o contrário: puxei a versão 7 do ar para o repo com a CLI oficial (supabase functions download), para os gémeos ficarem iguais, e provei a fórmula viva na base de dados com um SELECT: 20 km dá 30,40 euros, 10 km dá 14,40, 2 km dá o piso de 8,00. O hash do ficheiro no disco ficou registado (3800C4528272776CC1AA183A505DBB52E1C7A5112F1A64AE8D42CDF9D3BA27D0). A app já manda o distance_km nas duas acções do pacote — isso confirmei no tvde_store.dart. Então porque é que os pacotes reais cobram 8 euros? Porque na Guarda as corridas são curtas e o preço por km dessas distâncias É o piso — e porque a app instalada nos telemóveis pode ser anterior ao envio do distance_km, caso em que o servidor usa o piso de propósito, exactamente como o Danilo mandou hoje. Não há dinheiro a fugir na versão que está no ar.

## Bloco 1 — o app ficou imune ao 16 euros

O TvdeFareView, na perna do pacote, confiava que o final_fare_cents do servidor trazia só as paradas. Esse contrato já foi quebrado uma vez e custou uma cobrança dobrada à Sandra. Agora as paradas vêm SEMPRE do acumulado extra_stops_fee_cents e o final_fare_cents é ignorado nessa perna — venha o que vier do servidor, um pacote de 8 euros mostra 8 euros. Ficaram dois testes novos a travar a regressão: ida com final contaminado a 800 tem de dar 8,00 (e nunca 16,00), e volta com o mesmo contágio tem de dar 0. Os catorze testes do ficheiro passam. Nota fora do âmbito: o ramo das corridas cobertas por plano ainda usa o mesmo padrão de confiança no final — não mexi porque a ordem limitava ao pacote, mas fica apontado.

## Bloco 2 — o MB Way do pacote já não morre com o ecrã

O caso da Sandra tinha três buracos e os três ficaram tapados. Um: o par corrida-de-ida mais pagamento fica agora guardado no telemóvel no momento em que o pagamento nasce, e quando a app reabre o próprio arranque retoma sozinho a activação do vale, sem precisar do diálogo — o servidor, desde as correcções de hoje por MCP, até encontra a ida sozinho quando o id não vai. Dois: nenhum sítio no app volta a cancelar uma corrida como pagamento-falhado sem antes perguntar ao servidor se o pagamento passou — se o servidor disser que passou, a corrida segue; se disser que está a processar, mantém-se e diz-se a verdade; só se o estado for mesmo terminal é que se cancela. Isto entrou nos quatro caminhos: o diálogo do MB Way do pacote, o da corrida normal, a desistência do cartão e o cancelamento a partir do tracking. Três: o realtime do tracking agora reata a ligação ao voltar do fundo (o canal morria em silêncio e era por isso que a tela dela ficou presa) além de reler o servidor, e enquanto o pagamento online não está confirmado o título do ecrã diz "A confirmar pagamento…" em vez de "À procura de motorista".

## Bloco 4 — impossível comprar o pacote duas vezes sem querer

Com um vale de volta activo, o fluxo normal de pedir corrida passa a reconhecê-lo: o cartão do valor mostra "Grátis — volta incluída no pacote", o interruptor de garantir a volta desaparece, e o botão principal passa a "Chamar a volta" — usa o vale com as moradas que a pessoa preencheu, sem cobrar nada. E a folha de chamar a volta deixou de ser folha: é um ecrã inteiro, com os campos e o botão sempre visíveis mesmo com o teclado aberto.

## Bloco 5 — tracking do cliente estilo Uber

Depois de o motorista aceitar, o cartão grande deu lugar a uma fitinha em baixo com o estado, o tempo e o preço, que se puxa para cima para ver o resto (motorista, paradas, mensagem, ligar, cancelar). O mapa fica quase inteiro. Além da rota grossa recolha-destino que já existia, desenha-se agora a rota do próprio motorista — até à recolha antes de embarcar, até ao destino em viagem — refeita quando o carro se afasta do traçado. A mira de centralizar ficou acima da fitinha e a posição do carro continua a animar suave como já animava.

## Bloco 6 — mapa do motorista estilo Waze

O ecrã do motorista já guiava com rota desenhada, câmara a seguir o carro com a frente para cima e tempo estimado — isso confirmei e ficou como estava. O que faltava e entrou: em "Viagem em curso" o painel abre recolhido, só com a linha do estado e do ganho, com o mapa quase todo livre — puxa-se para cima quando se quer o botão de finalizar, que assim deixa de ficar fora do alcance; o tempo estimado passou a viver nessa primeira linha, visível mesmo recolhido; e a mira de centralizar acompanha agora a altura real do painel, em vez de ficar escondida atrás dele.

## Bloco 7 — a palavra-passe no site

A evidência de hoje encaixa toda numa causa só: o link do email é de uso único e passa pelo verificador do Supabase, e o leitor de email (ou um duplo clique) gasta-o ANTES de a pessoa chegar ao ecrã — o "login" das 10:38:58 terá sido isso, e por isso os cliques seguintes davam o erro de token já consumido. A cura é o caminho que a ordem apontava: o link novo traz um código guardado que só se gasta quando a pessoa carrega em "Guardar" no ecrã. O ecrã já sabe ler esse link, mostra logo os dois campos, troca o código por sessão só no toque final, e quando o código já foi usado ou expirou diz em português claro o que aconteceu, com o botão de pedir email novo. Os links antigos continuam a funcionar como antes. A prova real do caminho novo foi feita hoje contra o Supabase de produção com a conta de teste, sem esperar por deploy: gerou-se o link a sério pela Admin API, trocou-se o código por sessão, definiu-se palavra-passe nova, o login com ela deu certo, o login com a antiga foi recusado, e a reutilização do mesmo código foi recusada — cinco em cinco. Falta só o passo do template descrito lá em cima, gatilhado ao deploy web.

## Provas desta sessão

Os testes: os 57 testes TVDE passam, incluindo os dois novos do 16 euros. A análise estática não tem um único erro nem aviso nos ficheiros desta missão — os 14 erros que o analyze acusa são todos dos ficheiros quebrados da outra sessão, que ficaram fora do commit. A fórmula do preço: SELECT em produção devolveu 3040 para 20 km, 1440 para 10, 800 para 2, piso 800. A palavra-passe: sequência de cinco passos contra produção, toda verde, descrita no bloco acima. O espelho da Edge: download oficial da versão 7 activa, hash registado.

## Bugs fora do âmbito encontrados (não corrigidos)

Um, o mais grave: as alterações por committar de outra sessão deixaram o repo sem compilar (imports de ficheiros inexistentes no main.dart, client_main_screen.dart e provider_detail_screen.dart) — enquanto durar, não há prova de ecrã possível nesta máquina e qualquer push desses ficheiros parte o CI. Dois: o ramo do plano no TvdeFareView tem o mesmo padrão de confiança no final_fare_cents que causou o 16 euros no pacote. Três: o CLAUDE.md ainda aponta o caminho antigo do projecto no Desktop e a branch autonomous-night como actuais — o trabalho real está em C:\BoraLocal e na branch tvde/reserva-agendada-2026-08-20. Quatro: a skill do CEO-AI continua a falar de contagens de Edge Functions desactualizadas. Nada disto toca zona protegida excepto nada — são todos seguros de corrigir em missão própria.

## O que falta para fechar de vez

A prova no telemóvel quando houver um ligado (pacote em dinheiro ponta a ponta, MB Way com a app fechada a meio, capturas dos mapas novos). O script do template do Bloco 7 depois do deploy web. E alguém tem de decidir o destino do trabalho quebrado da outra sessão — completar os dois ficheiros em falta ou reverter os três tocados.
