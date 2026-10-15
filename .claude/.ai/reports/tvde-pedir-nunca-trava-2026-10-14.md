# Pedir corrida nunca trava — 14 e 15/10/2026

> Missão `tvde-pedir-nunca-trava-2026-10-14`. Motor Opus, Claude Code no PC do Danilo,
> ramo `autonomous-night-2026-04-29`. RAM medida antes de compilar: 1677 MB, 1666 MB e
> 2070 MB disponíveis (acima do portão de 800). Durante o build web desceu a 379 MB. O
> único processo pesado era o próprio compilador (2,1 GB), por isso deixei-o acabar.

## O que NÃO ficou feito (primeiro, como manda a regra 3.9)

1. **A migração do banco não foi aplicada.** Está escrita em
   `supabase/migrations/20261014190000_pedido_travado_saude_web.sql`. Quando a tentei
   aplicar em produção, a sessão recusou. Por isso não voltei a tentar. Sem ela, o app
   já tenta gravar o evento `pedido_travado`, mas o banco recusa-o em silêncio, porque a
   regra da tabela ainda não conhece esse nome. Também não há ainda alarme nem nomes no
   painel. O painel continua a abrir e lê a tabela como antes.
2. **Não criei nem cancelei nenhuma corrida de verdade.** Às 06:11 havia 2 motoristas
   ligados com sinal. A conta demo não tem nenhuma proteção no TVDE: uma corrida em
   dinheiro de teste seria oferecida a gente real, como já aconteceu a 05/09.
   - A única forma segura que está registada exige mexer diretamente na tabela
     `tvde_rides`.
   - As regras de 16/09 proíbem isso.

   A prova web foi até ao botão "Solicitar corrida" ativo, com o preço calculado e as
   moradas escritas à mão, e parou antes do último toque.
3. **Não houve prova no emulador Android.** O APK novo compilou (187 s) e instalou
   ("Success"). O emulador arrancou, mas o PC desceu a 470 MB livres e o Android do
   emulador ficou em "System UI isn't responding" (captura `a01-arranque.png`, `a02.png`).
   Desliguei-o para não derrubar as outras sessões do Claude abertas neste PC. O caminho
   do telemóvel (serviço `io`, que fala com a Google por HTTP) ficou provado por teste com
   um cliente HTTP falso. O resto do código é o mesmo que foi provado na web.
4. **iPhone:** não há como provar num PC Windows. Entra com o build do CI depois do envio.
5. **Não enviei para o servidor** (`git push`), como pediste. O commit está feito
   localmente.

## O que mudou, em palavras simples

**Bloco A — a morada escrita conta sempre.** O campo de morada é o mesmo em todo o app.
Agora, quando alguém escreve a morada e sai do campo, carrega em "concluído" ou carrega
no botão de pedir **sem tocar numa sugestão**, o app procura essa morada no mapa e
aceita-a, com coordenadas. Por baixo do campo aparece "No mapa: …" com a morada que o
Google encontrou, para a pessoa confirmar.
- O texto que ela escreveu fica, com o número da porta, porque o motorista precisa dele.
- Se nem assim houver coordenadas, o próprio campo diz "Não encontrei esta morada no mapa.
  Escolhe uma sugestão ou acrescenta a cidade (ex.: Guarda)", e o ecrã de corrida mostra
  o aviso de sempre. Nunca fica em silêncio.

**Bloco B — a pesquisa tolera números e abreviaturas.** Se a pesquisa com o texto todo
vier vazia, o app tenta outra vez com as abreviaturas por extenso ("Av." passa a
"Avenida", "R." a "Rua") e depois sem o número da porta nem o andar.
- "Av. Cidade de Safed n8 a 1d, Guarda" passa a "Avenida Cidade de Safed, Guarda".
- Números que fazem parte do nome da rua ficam, como em "Rua 5 de Outubro".
- O viés da Guarda continua.
- Na procura no mapa, o app escolhe o melhor resultado na Guarda e recusa "a cidade
  inteira", porque o Google devolve "Guarda" quando não percebe o texto.

**Bloco C — moradas guardadas com um toque.** Por baixo da recolha e por baixo do destino
aparecem botões com as moradas guardadas do cliente ("Casa", por exemplo) e até 3
destinos recentes das corridas dele, sem repetidos. Um toque preenche a morada e as
coordenadas. A Stela tem a "Casa" guardada com coordenadas e teria pedido com um toque.

**Bloco D — o botão diz o que falta.** O botão de pedir já não fica cinzento e mudo. Mostra:
- "Escolhe o ponto de recolha"
- "Escolhe o destino"
- "A calcular o preço…"
- "A procurar a tua localização…"

Tocado nesse estado, primeiro tenta aceitar a morada escrita. Se continuar a faltar, diz
o que falta e leva o teclado ao campo certo.

A mesma ideia foi aplicada noutros sítios:
- **"Chamar a minha volta":** foi onde a Stela escreveu "De onde sais" a 15/09.
- **"Mudar destino" de uma reserva:** era o único outro botão cinzento e mudo.

**Bloco E — nada fica preso a carregar.**
- **Morada a partir do GPS:** desiste aos 8 segundos.
- **GPS:** as perguntas ao telemóvel têm limite de 5 segundos, e o pedido de permissão
  tem 30.
- **Rota para o preço:** desiste aos 10 segundos.
- **Ecrã:** "a procurar" e "a calcular" voltam sempre a desligar, e uma resposta atrasada
  de uma rota antiga já não põe o preço por cima da nova.
- **GPS negado ou desligado:** o campo da recolha diz "Liga a localização ou escreve a
  morada".
- **Escrever durante a procura do GPS:** se a pessoa escreve a recolha enquanto o GPS
  procura, ganha o que ela escreveu.

**Bloco F — painel e alarme.**
- **No app:** quando o cliente toca em pedir e não consegue, o app grava `pedido_travado`
  com o motivo (`sem_recolha`, `sem_destino`, `geocode_falhou` ou `gps_falhou`) e a
  plataforma.
- **No painel:** a tela "Saúde da Web" saiu do Arquivado e está em "Operação do dia". No
  topo mostra "Clientes que não conseguiram pedir", com nome, quantas vezes, o porquê e
  um botão para ligar.
- **No banco (ainda por aplicar):** a migração acrescenta a função só de admin que traz
  nome, telefone e email, e o alarme. Ao 3.º toque falhado do mesmo cliente em 10
  minutos, segue um aviso pelo caminho que já existe (push persistente, Telegram e caixa
  do painel). O aviso abre diretamente a "Saúde da Web".

**Ecrãs que usam o campo de morada.** Revi os 20 sítios. Em 18 a confirmação automática
só guarda a morada.
- Desliguei-a em dois, onde escolher morada faz mais do que guardar: na folha de paragens
  da corrida (fecha a folha e cobra a paragem) e na pesquisa de morada da home (abre o
  "Guardar como Casa?"). Aí continua a ser preciso tocar numa sugestão.
- No resto (entregas, favores, limpeza, lavagem, candidaturas, perfil, balcão admin) passa
  a valer o Bloco A.

## Provas

- **Testes novos** (`test/pedir_nunca_trava_test.dart`, 23 testes), mais os 11 antigos
  do campo de morada e do viés da Guarda: **34 de 34 verdes**. Cobrem os 5 casos pedidos:
  - texto escrito sem tocar na sugestão é aceite;
  - "Av. Cidade de Safed n8 a 1d, Guarda" encontra a avenida;
  - o atalho "Casa" preenche a morada e as coordenadas;
  - o GPS negado deixa a mensagem no campo;
  - a morada a partir do GPS, quando é lenta, desiste aos 8 s.
- **Mutação:** desliguei de propósito a pesquisa tolerante e a confirmação ao sair do
  campo. Ficaram **6 testes vermelhos**. Os ficheiros voltaram ao original, confirmado
  por grep.
- **Testes de guarda:** traduções (`l10n_cobertura`), menu do painel e botão sem `busy`
  global estão todos verdes. Os 10 textos novos têm inglês.
- **`flutter analyze`:** 0 erros. Os 6 avisos são de ficheiros em que não mexi.
- **Juiz anti-trapaça:** chão limpo.
- **Caminho do telemóvel** (`test/morada_escrita_io_test.dart`, serviço `io` real com
  HTTP falso): 3 testes verdes, mais os 4 antigos do viés da Guarda.
  - O pedido leva a caixa da Guarda e `country:PT`.
  - Fica com a rua na Guarda e recusa a "cidade inteira".
  - Recusa a rua de Lisboa quando se escreveu "Guarda".
  - A cascata chega à "Avenida Cidade de Safed, Guarda".
- **Bateria alargada** (os 16 ficheiros que montam os ecrãs mexidos, mais traduções e
  menu): **199 de 199 verdes**.
- **Bateria inteira** (`test/*_test.dart`): **1238 de 1238 verdes**. Correu sem a pasta
  das fotos, que tem PNG por gravar de outra sessão.
  - A foto do menu do painel, que a minha mudança afeta, correu à parte: 3/3, sem estouro
    de layout.
  - Os PNG da outra sessão foram guardados antes e repostos byte a byte.
- **Web: build real, servido no PC, conta demo, GPS recusado de propósito.** Capturas e
  árvores em `.claude/.ai/provas/tvde-pedir-nunca-trava-2026-10-14/`, log em
  `prova-web.log`.
  1. **Entrada no ecrã** (`06-tvde-gps-negado`): campo da recolha com "Liga a localização
     ou escreve a morada", botão "Escolhe o ponto de recolha" e o atalho de um destino
     recente.
  2. **Recolha** (`11-recolha-aceite-ao-sair`): escrevi "Av. Cidade de Safed n8 a 1d,
     Guarda", a morada da Stela, e carreguei em Tab, sem tocar na lista. Ficou aceite
     com "No mapa: Av. Cidade de Safed, Guarda, Portugal", e o botão passou a "Escolhe o
     destino".
  3. **Destino com sugestões erradas** (`12-…`): em "Av. Rainha D. Amélia 14, Guarda" a
     lista só sugeria Lisboa, Sintra e Beja. A procura no mapa com a Guarda encontrou
     "Av. Rainha Dona Amélia 14, 6300-749 Guarda", com €5.00 · 2.6 km, e o botão ficou
     "Solicitar corrida".
  4. **Morada inexistente** (`20-…`): "Rua Inventada Xyzqw 999, Guarda" ficou recusada,
     com o aviso vermelho no campo e o botão a dizer "Escolhe o destino". A rede registou
     `geocode_manual_falhou` (201).
  5. **Toque no botão nesse estado** (`21-…`): o app enviou `pedido_travado` /
     `geocode_falhou` / `web`. **O banco respondeu 400**, porque a migração ainda não
     está aplicada. É a prova de que o app já envia e só falta o banco aceitar.
  6. **Destino certo** (`22-pronto-para-pedir`): "Av. Monsenhor Mendes do Carmo nº 5,
     Guarda" + Enter. Ficou "No mapa: … 5, 6300-586 Guarda", com €5.00 · 1.0 km, e o botão
     "Solicitar corrida".
  7. **Folha de pagamento** (`23-folha-pagamento-dinheiro`): abriu com "Dinheiro"
     marcado e "Pagar €5.00 em dinheiro". **Não confirmei.** A rede não registou nenhuma
     chamada a `tvde_request_ride`. Confirmado por SELECT: 0 corridas da conta demo nas
     últimas 3 horas (a última é de 12/10). Nada ficou pendurado.
- **Dois bugs que a prova web apanhou e que corrigi na hora** (com teste novo e com
  mutação que os põe vermelhos):
  - A primeira versão aceitaria a mesma rua em Lisboa quando a pessoa escreveu "Guarda".
    Agora recusa e avisa.
  - "Rua Inventada Xyzqw 999, Guarda" era aceite como "Rua, Portugal", a 6 km. Era um
    resultado à toa perto da Guarda. Agora o resultado tem de partilhar uma palavra a
    sério com o que se escreveu.

## Erros que encontrei e não corrigi

- **Preço com erro de rede.** Se o cálculo do preço (`tvde_calculate_fare`) falhar, o
  ecrã recebe -1 como preço (`estimateFareCents` devolve -1 em erro) e o botão fica
  ativo com esse valor. Não mexi: é a zona do preço.
- **Balcão admin, mudança de destino do admin e "Enviar encomenda".** Os campos de morada
  não limpam as coordenadas antigas quando se edita o texto à mão. A confirmação
  automática nova corrige a maior parte dos casos, mas a falta do `onChanged` continua.
- **Web sem o SDK do Google.** Quando o SDK do Google não carrega, a procura no servidor
  (`places-proxy`) devolve só coordenadas, sem dizer se é a cidade inteira. Nesse caso
  raro não dá para recusar o resultado "Guarda" genérico.

## PARA O DANILO

1. **Aplicar a migração do banco** (painel com nome e telefone, mais o alarme). Não toca
   em dinheiro. Diz "sim" e aplico-a junto com o envio.
2. **Prova ponta a ponta com corrida real.** Para fazer a prova até ao fim sem chamar
   motoristas reais, preciso de uma de três coisas:
   - um momento sem motoristas ligados;
   - ou o guião de 01/10 (`tvde-oferta-fantasma/emulador/pedir_corrida_demo.py`), que
     pede em Lisboa com o motorista demo e cancela sozinho se a oferta for para outra
     pessoa. Funciona, mas em Lisboa e não na Guarda;
   - ou uma proteção "conta demo só vai ao motorista demo" no TVDE, como já existe nas
     entregas. Esta última é zona de despacho, por isso só proponho.
3. **Depois de publicar,** a Stela tem de atualizar a app para o conserto lhe chegar. É a
   lição antiga do "APK antigo".
