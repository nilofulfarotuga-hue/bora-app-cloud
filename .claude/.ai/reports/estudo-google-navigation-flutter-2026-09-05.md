# Estudo: google_navigation_flutter no Bora — vale a pena trocar o mapa do motorista?

Missão TVDE 05/09, Bloco 6. Estudo apenas. Nada disto foi aplicado e nenhum ficheiro do
repositório foi alterado — o único ficheiro escrito nesta tarefa é este relatório.

Data: 5 de Setembro de 2026. RAM medida no arranque: 1286 MB disponíveis, acima do portão
de 800 MB, logo houve folga para o trabalho feito. Não existia estudo anterior sobre isto:
procurei em `.claude/.ai/reports/`, em `.claude/.ai/knowledge/`, em `docs/` e no Córtex pela
palavra navigation e por google_navigation_flutter, e não apareceu nada. Este é o primeiro.

---

## O resumo em trinta segundos

O plugin é real, é oficial da Google, e faz mesmo o que precisamos: voz, faixa de rodagem,
recálculo automático, encaixe na estrada, e continua a trabalhar com a app em segundo plano.
O preço é baixíssimo para o nosso volume. O requisito de Android está quase todo cumprido —
falta mudar uma linha.

O problema não é nada disso. O problema é que o Navigation SDK traz o motor de mapas dentro
dele, e nós já temos outro motor de mapas na app através do google_maps_flutter. Pôr os dois
no mesmo Android pode partir a compilação inteira — e se partir, não parte só o ecrã do
motorista: parte o mapa do cliente e o do painel admin ao mesmo tempo, porque é o build que
falha, não o ecrã.

Não consegui provar se parte ou não, e digo já porquê mais abaixo.

---

## Primeiro, as correcções ao que me foi dito

Quatro pontos do briefing estavam desactualizados ou imprecisos. É isto que dá valor ao
relatório, por isso começo por aqui.

**A versão não é a 0.10.0 de Julho.** É a **0.11.0, publicada a 31 de Agosto de 2026**, ou
seja há cinco dias. Facto verificado na página do pub.dev e no ficheiro de alterações do
projecto. E não é uma actualização inocente: a 0.11.0 traz uma alteração que quebra código
existente, sobre a forma como o preenchimento do mapa passa a ser medido em pontos
independentes da densidade do ecrã. Isto é relevante para o ponto seis e volto lá.

**As mil grátis por mês não são rotas, são destinos.** Facto verificado na documentação de
faturação do Navigation SDK. A conta é feita por destino pedido no cálculo de rota, e uma
chamada pode levar vários destinos. Para nós, uma corrida TVDE normal é um destino, portanto
na prática a leitura popular está certa — mas se um dia fizermos rotas com paragens
múltiplas, cada paragem conta.

**O que acontece depois das mil grátis não me foi dito, e é o número que interessa mesmo.**
A partir da milésima primeira, o preço é de vinte e cinco dólares por cada mil destinos, o
que dá **dois cêntimos e meio por corrida**. Facto verificado na tabela de preços da Google,
onde o artigo se chama Navigation Request. Numa corrida de vários euros, dois cêntimos e meio
é ruído. E as mil grátis por mês dão para cerca de trinta e três corridas por dia sem pagar
nada. Do lado do dinheiro, isto não é um obstáculo — é barato.

**A questão do contrato Mobility está confirmada, mas com uma nuance.** Facto verificado: a
documentação diz que só quem é cliente de Mobility Services precisa de falar com o comercial
da Google; quem não é, segue o caminho normal de criar um projecto na Google Cloud. A nuance
é que o artigo de faturação está catalogado na categoria Enterprise, que é o escalão mais
caro da Google Maps Platform. Não impede nada, mas explica porque é que o preço por unidade é
mais alto do que o das outras APIs de rotas.

**Uma coisa que o briefing acertou em cheio:** os recálculos não custam nada. Isto está
escrito de forma literal na documentação, e cito o essencial: não há encargos adicionais por
mudanças de rota depois de o destino já ter sido pedido, incluindo mudanças por trânsito,
estradas cortadas ou desvio do trajecto previsto. Facto verificado. É exactamente o
comportamento que queríamos e é grátis.

---

## Ponto um: convivência com o google_maps_flutter

O briefing dizia que são treze ficheiros. **São treze exactamente**, facto verificado por
busca. Contando também a pasta de testes são quinze, mas dentro de `lib/` são treze.

Desses treze, três são utilitários que não desenham nada — `lib/utils/map_utils.dart`,
`lib/utils/map_marker_helper.dart` e `lib/utils/constants.dart`. Os outros dez desenham
mesmo um mapa no ecrã. Desses dez, e isto é importante para decidir o tamanho do estrago,
só três são do lado do motorista e só esses precisariam de navegação a sério:
`lib/screens/driver_map_screen.dart`, `lib/screens/driver/tvde/tvde_ride_active_screen.dart`
e `lib/screens/driver/tvde/tvde_driver_home_screen.dart`. Os restantes sete são do cliente e
do painel admin, e esses só precisam de mostrar um mapa — não precisam de navegar coisa
nenhuma.

Agora a pergunta a sério: os dois convivem?

**Ao nível do Dart e do pub, convivem. Isto está provado com saída literal.** Criei um
projecto Flutter novo e vazio no scratchpad, completamente fora do repositório, meti-lhe as
duas dependências, e corri a resolução. Correu bem. A saída literal foi esta:

```
+ google_maps_flutter 2.18.0
+ google_maps_flutter_android 2.19.13
+ google_maps_flutter_ios 2.18.6
+ google_navigation_flutter 0.11.0
Changed 15 dependencies!
PUBGET_EXIT=0
```

E repare-se num pormenor que dá peso à prova: as versões que o resolvedor escolheu —
2.18.0 e 2.19.13 — são exactamente as mesmas que o Bora tem hoje travadas no seu ficheiro de
bloqueio. Ou seja, não foi um teste com versões diferentes das nossas; foi com as nossas.

**Mas isto não prova quase nada do que interessa, e é preciso dizê-lo com todas as letras.**
A resolução do pub só verifica o lado Dart. O conflito de que o README avisa é do lado nativo,
no Android, e esse só aparece quando se compila. Fui à raiz do assunto e encontrei o mecanismo
exacto, que passo a explicar porque é o coração deste relatório.

O plugin de navegação, no seu próprio ficheiro de configuração do Android, declara uma coisa
curiosa: exclui explicitamente o módulo `play-services-maps` das suas dependências. Depois
puxa o Navigation SDK, versão 7.8.0. Fui ver a ficha de dependências publicada dessa versão
7.8.0 na Maven da Google: tem trinta dependências declaradas e **nem uma única menciona mapas
ou play-services**. Facto verificado.

Isto diz-nos o essencial: o Navigation SDK não depende do motor de mapas da Google — ele
**traz o motor de mapas dentro de si**, empacotado. Por isso o plugin põe aquela exclusão
defensiva. Só que o `google_maps_flutter_android` que nós já usamos puxa, esse sim,
`play-services-maps` na versão 20.0.0. Facto verificado no ficheiro de configuração do próprio
pacote, na cache local.

Resultado provável: duas cópias das mesmas classes de mapas no mesmo Android, e o compilador
a queixar-se de classe duplicada na fase de junção. É precisamente isto que a secção de
problemas conhecidos do README descreve quando diz que se podem encontrar erros de compilação
por conflito de versões e que se recomenda evitar usar vários pacotes com dependências de
mapas.

**Por confirmar, e é a incógnita central deste estudo:** se o conflito rebenta mesmo, ou se
a Google empacotou as classes com nomes diferentes de forma a poderem coexistir. Só um build
Android completo responde, e esse eu não podia fazer.

Vale a pena registar que o README oferece uma saída: o mesmo plugin traz um widget chamado
`GoogleMapsMapView`, que é um mapa normal sem navegação. Isto quer dizer que, se o conflito
for real, o caminho não é impossível — é trocar os dez ecrãs todos para o widget do plugin de
navegação e deixar cair o google_maps_flutter por completo. Deixa de haver conflito porque
deixa de haver dois motores. Mas passa a ser uma migração de dez ecrãs em vez de três.

---

## Ponto dois: requisitos de Android, o que já temos e o que falta

Fui ler os ficheiros reais do projecto. Estado actual contra estado exigido, com os números.

**A versão mínima de Android está cumprida.** O nosso ficheiro
`android/app/build.gradle.kts` não escreve o número à mão, usa `flutter.minSdkVersion`. Fui
ver quanto vale isso na versão do Flutter instalada, que é a 3.47.2, e no ficheiro
`FlutterExtension.kt` a linha vinte e seis diz que vale vinte e quatro. O plugin exige vinte
e quatro. Passa. Facto verificado. Nota lateral: há um comentário no nosso build a dizer que
o mínimo é vinte e um, e esse comentário está desactualizado — o valor real é vinte e quatro.
Não é problema nenhum para este assunto, mas convém saber que o comentário mente.

**O Kotlin está cumprido, e por pouco.** Nós temos 2.3.10, declarado no
`android/settings.gradle.kts` e forçado outra vez por uma estratégia de resolução no
`build.gradle.kts` da aplicação. O briefing dizia que o plugin exige Kotlin 2.0 ou superior,
e a página do pub.dev ainda diz isso — mas o ficheiro de alterações mostra que na versão
0.10.0, em Julho, o mínimo real subiu para 2.3.0. Nós estamos em 2.3.10, portanto passa. Mas
passa com dez pontinhos de folga, e isto é um aviso para o ponto seis.

**O desugaring está ligado, mas com a biblioteca errada.** Nós já temos
`isCoreLibraryDesugaringEnabled = true` e puxamos `com.android.tools:desugar_jdk_libs:2.0.3`.
O plugin exige `com.android.tools:desugar_jdk_libs_nio:2.0.4` — repare-se que é outra
biblioteca, com o sufixo nio, e uma versão acima. **Esta é a única alteração obrigatória que
encontrei no nosso Gradle: uma linha.** Facto verificado nos dois lados.

**O Java está cumprido.** Nós compilamos em Java 17 e alinhamos todos os plugins em Java 17.
O plugin de navegação também compila em Java 17. Passa.

**O plugin de compilação do Android está cumprido.** Nós usamos a versão 8.9.1. O plugin de
navegação tem código que trata especificamente de versões abaixo da nove, portanto está
preparado para nós. Passa.

**Uma dependência sobe sozinha.** Nós puxamos `androidx.appcompat` na versão 1.7.0 e o
Navigation SDK quer a 1.7.1. O Gradle resolve para cima automaticamente, não é preciso fazer
nada, mas fica registado que uma biblioteca partilhada vai subir de versão sem ninguém pedir.

**Falta uma coisa que não é código: a chave da Google.** A mesma chave que já usamos para os
mapas tem de passar a ter o Navigation SDK activado no projecto da Google Cloud. Não é um
ficheiro que se edite, é um botão na consola. E como activa um artigo faturável novo, isto
cai do lado das decisões que são do Danilo — está no bloco do fim.

**E há um custo que ninguém mencionou: o tamanho da aplicação.** Fui medir o pacote do
Navigation SDK 7.8.0 no servidor da Google e pesa **32,7 megabytes**. Facto verificado por
pedido HTTP, que respondeu 200 e declarou 34.307.293 bytes. Nós enviamos duas arquitecturas
no mesmo APK, arm64 e armeabi, portanto o crescimento real vai ser sentido. Para uma
aplicação que vai para a Play e é instalada por estafetas com telemóveis modestos, trinta e
poucos megabytes a mais não é detalhe.

---

## Ponto três: o diálogo de termos da Google, onde encaixa

Confirmado que é obrigatório. O padrão do próprio README é perguntar primeiro se os termos já
foram aceites, através de `GoogleMapsNavigator.areTermsAccepted()`, e só se não tiverem sido é
que se mostra o diálogo com `showTermsAndConditionsDialog`, ao qual se passa um título e o
nome da empresa. Só depois disso é que se pode iniciar a sessão de navegação. Facto verificado
no README.

Agora onde é que isso encaixa no que já existe. Fui procurar e encontrei três sítios
relevantes, e a resposta certa não é a óbvia.

**O sítio óbvio é o gate de permissões do estafeta de entregas.** Vive em
`lib/services/permission_gate_service.dart`, na função `ensureDriverOnlinePermissions`, que
começa na linha sessenta. É um gate sequencial de quatro permissões — notificações, janela
sobreposta, ecrã cheio e optimização de bateria — em que cada passo mostra um diálogo
explicativo antes de abrir o pedido nativo, e a função só devolve verdadeiro quando as quatro
estão concedidas. É chamado de `lib/screens/driver_home_screen.dart`, nas linhas cento e
quarenta e nove e duzentos e noventa e dois. Acrescentar o diálogo da Google como quinto
passo desta sequência seria trivial e encaixaria no padrão que já lá está.

**Mas para o TVDE isso não serve, e é aqui que está a subtileza.** O ecrã do motorista TVDE,
em `lib/screens/driver/tvde/tvde_driver_home_screen.dart`, na linha quatrocentos e trinta e
dois, não chama essa função. Chama outra, `ensureMinimumOnlinePermissions`, que é o gate
reduzido — e o comentário no código diz explicitamente que esse gate **nunca bloqueia o
motorista de ficar online**, porque foi feito a pensar em telemóveis fracos e Android antigo.
Ora, o diálogo da Google é bloqueante por natureza: sem ele aceite, não há navegação. Meter
uma coisa bloqueante dentro de um gate que foi desenhado para nunca bloquear seria contrariar
uma decisão já tomada, e provavelmente com cicatriz.

**Portanto, a recomendação concreta:** para o TVDE, o diálogo deve aparecer no arranque da
navegação, no momento em que o motorista aceita a corrida e o mapa de navegação vai abrir, e
não no momento de ficar online. Assim quem nunca navega nunca é incomodado, e quem vai
navegar aceita uma vez na vida.

**E há um terceiro sítio, para o estado.** Existe
`lib/screens/driver_permissions_screen.dart`, com duzentas e trinta e seis linhas, que é o
ecrã de diagnóstico onde o estafeta vê o estado de cada permissão. É chamado a partir do
perfil, em `lib/screens/profile_screen.dart` na linha quinhentos e setenta e um. Seria o sítio
natural para mostrar também se os termos da Google já foram aceites ou não.

**Um aviso para não haver confusão:** já existe consentimento nesta aplicação, mas é outro.
Há um `lib/stores/consent_store.dart` que guarda consentimento de localização, análise e
notificações, e há consentimento com versão registada no registo do estafeta, em
`lib/screens/driver_signup_screen.dart` entre as linhas duzentos e setenta e um e duzentos e
noventa e nove, que grava a data e a versão aceite. Isso é o consentimento da Bora, para
efeitos de protecção de dados. **Não substitui o da Google e não pode ser reaproveitado** — a
Google exige o dela, mostrada pelo código dela.

---

## Ponto quatro: o que foi provado e o que não foi

Sou directo: **a navegação a funcionar não foi provada. Não corri navegação nenhuma, não vi
um mapa a navegar, e não tenho capturas.** Quem ler isto não deve ficar com a impressão de
que houve um teste em campo, porque não houve.

O que foi provado, com saída literal, está no ponto um: as duas dependências resolvem juntas
num projecto novo fora do repositório, com código de saída zero, e nas versões exactas que o
Bora usa. Isso é verdadeiro e é útil, mas é o degrau mais baixo da escada.

Também foram verificados, com saída literal, os requisitos de Android contra os nossos
ficheiros, os números de preço na documentação da Google, o peso do pacote nativo, e a
ausência de dependência de mapas na ficha do Navigation SDK.

O que ficou por provar, e porquê: **o build Android**, que é exactamente onde o conflito
apareceria. Não o fiz por três razões somadas. A primeira e decisiva é a ordem desta missão —
não podia tocar em nenhum ficheiro do repositório, e havia outros quatro agentes a editar
código ao mesmo tempo no mesmo sítio; mexer no ficheiro de dependências partia-lhes o
trabalho. A segunda é que um build Android neste computador de quatro gigabytes demora
dezenas de minutos e o próprio ficheiro de configuração do Gradle tem comentários a documentar
que já houve falhas de memória aqui. A terceira é que, mesmo num projecto de teste no
scratchpad, um build completo teria de descarregar o pacote de trinta e três megabytes mais a
cadeia toda do Android, e isso não cabia no tempo desta tarefa.

**Como se prova mais tarde, e é barato:** basta pegar no projecto de teste que ficou no
scratchpad, que já tem as duas dependências resolvidas, e correr um build de depuração para
Android. Se der classe duplicada, a resposta é não convivem. Se compilar, convivem e o
caminho fica muito mais curto. É um comando e uma espera, e responde à única pergunta que
ficou aberta.

---

## Ponto cinco: quanto custa e o que quebra primeiro

Separo em dois cenários, porque são muito diferentes.

**Cenário reduzido, só o motorista, atrás de interruptor de desligar.** Toca em três ecrãs de
motorista, mais o gate de permissões, mais uma linha de Gradle. Estimo entre oito e catorze
horas de trabalho, assumindo que o conflito nativo não existe. Se existir, este cenário morre
à nascença, porque não há maneira de ter os dois motores ao mesmo tempo.

**Cenário completo, tudo migrado para o widget do plugin de navegação.** Dez ecrãs a desenhar
mapa, com um total de cerca de cento e vinte e três utilizações da interface de mapas
espalhadas por eles — marcadores, linhas, controlos de câmara, ícones. O ecrã mais pesado é
`lib/screens/driver_map_screen.dart`, sozinho com vinte e quatro dessas utilizações, seguido
de `lib/screens/client/tvde/tvde_ride_tracking_screen.dart` com catorze. Estimo entre trinta e
quarenta e cinco horas, mais o tempo de voltar a testar tudo à mão.

**O que quebra primeiro, e a resposta surpreende:** não é um ecrã. **É a compilação.** Se o
conflito nativo for real, a aplicação deixa de compilar antes de qualquer ecrã chegar a
abrir. E isso significa que o risco não está contido ao motorista: parte o mapa do cliente,
parte o rastreio da encomenda, e parte o mapa ao vivo do painel admin, todos ao mesmo tempo,
porque nenhum deles chega a existir se o APK não se construir. Numa aplicação que está em
produção com pagamentos reais e que publica por integração contínua para a Play, isto quer
dizer que uma tentativa mal medida bloqueia a capacidade de publicar seja o que for.

**Depois da compilação, o segundo a quebrar seria o toque nos botões sobre o mapa.** O README
avisa que o mapa é desenhado como vista nativa e que os widgets Flutter colocados por cima
não travam os toques, que passam para o mapa por baixo — e que a solução é embrulhar cada
controlo num pacote chamado pointer_interceptor. Todos os nossos ecrãs de mapa têm painéis e
botões por cima do mapa, portanto isto seria trabalho garantido, ecrã a ecrã.

---

## Ponto seis: estar em versão 0.x preocupa-me, e digo porquê com números

Preocupa. E não é uma preocupação de princípio, é aritmética.

Fui contar as versões que quebraram código no historial do projecto. Encontrei seis ao todo, e
o ritmo recente é este: **0.7.0 em vinte de Novembro de 2025, 0.8.0 em quinze de Dezembro de
2025, 0.9.0 em vinte e quatro de Abril de 2026, 0.10.0 em dois de Julho de 2026, e 0.11.0 em
trinta e um de Agosto de 2026.** São **cinco alterações que quebram código em cerca de dez
meses**, ou seja aproximadamente uma a cada dois meses. Facto verificado no ficheiro de
alterações do projecto.

E não são todas cosméticas. A 0.8.0 tornou quase todos os campos de informação de passo
anuláveis, o que obriga a rever cada leitura desses campos. A 0.10.0 subiu o Kotlin mínimo
para 2.3.0. A 0.11.0, de há cinco dias, mudou a forma como o preenchimento do mapa é medido.

**Porque é que isto pesa mais no nosso caso do que pesaria noutro.** Uma subida forçada de
Kotlin ou do plugin de compilação obriga a mexer no Gradle deste projecto, e o Gradle deste
projecto não é um Gradle qualquer — tem pelo menos três remendos com cicatriz documentada em
comentário: o alinhamento de Java 17 em todos os plugins, feito depois de uma tentativa
anterior ter partido o classpath; o recuo forçado do novo modelo de configuração do plugin de
compilação; e a limitação a um único trabalhador do Gradle por causa da memória do computador.
Cada uma dessas linhas está lá porque alguma coisa rebentou antes. Uma actualização forçada
de dois em dois meses tem uma probabilidade real de tocar nessa zona.

**E há um ponto que fecha o argumento, escrito pela própria Google no README.** A biblioteca
não é um serviço central da Google Maps Platform, e por isso **não tem acordo de nível de
serviço, não tem serviços de suporte técnico e não tem política de depreciação**. Diz ainda,
literalmente, que enquanto estiver em versão 0.x podem ser introduzidas alterações
incompatíveis a qualquer momento. Facto verificado.

Traduzindo para a realidade do Bora: fundador solo, sem equipa para absorver uma migração de
emergência, aplicação em produção a cobrar dinheiro a sério, e publicação por integração
contínua para a Play. Se uma actualização obrigatória aparecer numa altura má, não há a quem
delegar e não há suporte a quem ligar. A dependência não é técnica apenas — é operacional.

---

## Recomendação

**Migrar depois do lançamento, e mesmo aí só o lado do motorista, atrás de um interruptor de
desligar.**

A razão em duas frases: o valor é real e o preço é irrisório, mas o risco não está contido ao
ecrã que se quer melhorar — se os dois motores de mapa não puderem coexistir, o que parte é a
compilação, e com ela vão juntos o mapa do cliente e o do painel admin numa aplicação que já
está a cobrar dinheiro. Antes de mexer seja no que for, faz-se o build de teste no scratchpad
que respondeu a esta única pergunta em aberto, porque é meia hora de trabalho que decide entre
uma tarefa de dez horas e uma de quarenta.

O passo imediato, e o único que recomendo já, é esse build de teste. Não toca no repositório,
não custa dinheiro, e transforma a maior incógnita deste relatório num facto.

---

## PARA O DANILO

Há duas decisões neste assunto que são tuas e não minhas.

**A primeira é a chave da Google.** Para isto funcionar, é preciso ir à consola da Google
Cloud e activar o Navigation SDK no projecto onde já vivem os mapas. Isso liga um artigo
faturável novo, com mil destinos grátis por mês e dois cêntimos e meio por corrida a partir
daí. É pouco dinheiro, mas é dinheiro real e é um botão que só tu podes carregar. Se quiseres,
deixo-te a página aberta no sítio certo.

**A segunda é o tamanho da aplicação.** O motor de navegação da Google pesa trinta e três
megabytes, e a aplicação dos estafetas é instalada em telemóveis modestos. Queres pagar esse
peso em troca de voz e recálculo automático, ou preferes que os estafetas continuem a saltar
para o Google Maps por fora quando precisam de navegar? Isso é uma decisão de produto, não de
engenharia.

---

## Onde está o que verifiquei

Ficheiros do repositório que li, todos sem alterar nada:
`pubspec.yaml`, `pubspec.lock`, `android/app/build.gradle.kts`, `android/build.gradle.kts`,
`android/settings.gradle.kts`, `android/gradle.properties`,
`android/gradle/wrapper/gradle-wrapper.properties`, `android/local.properties`,
`lib/services/permission_gate_service.dart`, `lib/screens/driver_permissions_screen.dart`,
`lib/screens/driver_signup_screen.dart`, e os treze ficheiros que usam mapas.

Fora do repositório: `FlutterExtension.kt` do SDK do Flutter instalado, e os ficheiros de
configuração de Android do `google_maps_flutter_android-2.19.13` e do
`google_navigation_flutter-0.11.0` na cache local de pacotes.

Fontes em linha consultadas: a página do pub.dev do plugin e o seu historial de versões, o
README e o ficheiro de alterações no GitHub do projecto flutter-navigation-sdk, a ficha de
dependências do Navigation SDK 7.8.0 na Maven da Google, a documentação de utilização e
faturação do Navigation SDK para Android, e a tabela de preços da Google Maps Platform.

Projecto de teste isolado, que fica disponível para o build que falta:
`C:\Users\danil\AppData\Local\Temp\claude\C--BoraLocal-projetosflutter-bora-app\176da9f0-56cb-4063-acb7-3802f35b55db\scratchpad\resolvtest\navtest`
