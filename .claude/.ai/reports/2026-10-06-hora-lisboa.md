# Loja aberta ou fechada pela hora de Lisboa — 06/10/2026

Missão `hora-lisboa-2026-10-06` · Claude Code (Opus 5.5) · PC do Danilo · ramo
`autonomous-night-2026-04-29` · pasta de trabalho `C:/BoraLocal/wt-ronda-05-10` (ramo local
`hora-lisboa-06-10`).

Acessos usados: nenhum login novo. Supabase pelo conector MCP (projecto `ojykpzwqrtusfeakzrna`),
GitHub pela credencial do Git já guardada no PC. Nada criado em contas.

## O que NÃO ficou feito (primeiro)

- A hora da reserva de mesa continua a ser enviada pelo fuso do telemóvel. O envio
  (`reserved_for`) vive dentro das duas funções que criam o pagamento do sinal de 3 euros
  (`createReservationPaymentIntent` e a do MB Way, em `lib/stores/reservation_store.dart`).
  Na dúvida tratei como zona de dinheiro e não mexi. A receita é uma linha em cada:
  trocar `reservedFor.toUtc()` por `instanteDeLisboa(reservedFor)`. Num telemóvel em Portugal
  não muda nada; num telemóvel noutro fuso, a mesa das 20h fica marcada à hora errada.
- As horas das marcações (barbearias) aparecem no fuso do telemóvel (`.toLocal()` em
  `services_store.dart`). É só mostrar, não decide aberto ou fechado, e mexe em muitos ecrãs.
  Ficou reportado, não mexido.
- A app continua a não ler os dias fechados do parceiro (feriados, `special_dates`), que o
  servidor lê. Num feriado marcado, a app diz "Aberto" e deixa encher o carrinho; o servidor
  recusa no fim. É outro gémeo, achado pelo caminho — reportado, não corrigido.
- A prova com um telemóvel na mão, noutro fuso, não foi feita; foi feita por testes com o
  relógio do processo em quatro fusos (B1), pelo emulador do CI em UTC e ao vivo na web
  publicada com o navegador em fuso de Tóquio (B2).
- No iPhone a correção está no TestFlight (1.0.12, build 168) mas não na App Store: a 1.0.11
  ainda espera a revisão da Apple, e só depois disso o próximo envio submete a 1.0.12.
- O Córtex pede nova autorização (conector `cortex` na lista dos que precisam de login) e o
  `context-mode` não ligou nesta sessão, por isso não há `/ctx doctor` nem `/ctx stats`.

## B0 — Estado encontrado

- RAM ao arrancar: 503 MB disponíveis; 270 e 241 MB antes dos testes. Abaixo do portão de
  800 MB. Os consumidores pesados eram 50 processos de outras sessões do Claude (cerca de
  2 GB), que matar destruiria trabalho; o `playwright` e o `nano-banana` não estavam a correr
  (o nano-banana nem ligou). Avancei com um ficheiro de teste de cada vez. Custo real: um
  analyze leva 17 a 20 minutos e uma corrida de testes chegou a 14.
- Ramo local igual ao remoto (`3ab89eb7`). Nenhuma outra missão de código no `e2e_log` das
  últimas 10 horas. A árvore principal tinha ficheiros mexidos por outros processos, por isso
  trabalhei no worktree da missão anterior, num ramo novo.
- O servidor (`is_partner_open`) já decidia pela hora de Lisboa: converte o instante com
  `AT TIME ZONE 'Europe/Lisbon'` e só depois lê o dia da semana e os minutos.

## B1 — A correção

O que mudou, ficheiro a ficheiro, e porquê:

- `lib/models/restaurant_model.dart` — `isOpenNow`, `statusLabel` e o aviso do carrinho
  (`avisoLojaFechada`, agora com `avisoLojaFechadaEm(instante)`) tiram o dia da semana e a
  hora do relógio de Lisboa, e não do telemóvel. A pausa do parceiro continua a comparar
  instantes (não muda).
- `lib/utils/hora_lisboa.dart` — duas peças novas: `paredeLisboa()` (o relógio de Lisboa
  marcado UTC, para ler dia e hora sem o fuso do telemóvel se meter, nem nos buracos da
  mudança de hora de outros países) e `instanteDeLisboa()` (o inverso: a hora escolhida no
  relógio da loja passa a instante certo para mandar ao servidor).
- `lib/screens/festas_quando_screen.dart` — o dia mínimo das encomendas de festa (dia
  seguinte) conta-se pelo dia de Lisboa.
- `lib/screens/payment_method_screen.dart` e `lib/stores/cart_store.dart` — a data da festa
  vai ao servidor (`festas_set_schedule`) por `instanteDeLisboa()`. Só muda a data enviada,
  nenhum valor.
- `lib/screens/client/reservation/reservation_availability_screen.dart` — o calendário e o
  aviso "a hora escolhida já passou" usam a hora de Lisboa.
- `lib/screens/partner_hours_screen.dart` — os dias fechados do parceiro escondem os que já
  passaram pelo dia de Lisboa.
- `lib/screens/admin/admin_partner_detail_screen.dart` — painel admin, "forçar abrir ou
  fechar até dia X": grava a meia-noite de Lisboa, não a do fuso do navegador.
- `PADRAO_BORA.md` §1.27 — a nota "gémeos por unificar" passou a dizer o que ficou unificado,
  a regra (`paredeLisboa` para ler, `instanteDeLisboa` para enviar) e o que ainda diverge.

Painel admin, confirmado no código: o estado "ABERTO/FECHADO (horário)" vem do servidor, que
já usa Lisboa; os horários editam-se como texto "HH:MM", que o servidor lê como hora de Lisboa;
o fim do "forçar" mostra-se em hora de Lisboa (`dataHoraLisboa`). O único ponto que usava o
fuso do navegador era o "forçar até dia X", corrigido.

Prova, por esta ordem:

1. Reproduzir: o teste novo `test/loja_hora_lisboa_test.dart` contra o comportamento antigo
   deu 7 falhas, com os sintomas reais — às 21h30 UTC a app dizia "aberta" quando em Lisboa já
   são 22h30; ao domingo às 23h30 UTC usava o horário de domingo quando em Lisboa já é
   segunda; o aviso dizia "Abre às 12h00" em vez de "08h00".
2. Com a correção: 14 de 14 verdes.
3. Com o relógio do próprio processo noutro fuso (a variável TZ muda o relógio do Dart no
   Windows — provado com uma sonda: UTC−2, UTC+10 e UTC), os quatro ficheiros de teste da loja
   (46 testes) passaram com o relógio em Lisboa, em UTC (como o emulador do CI), em UTC−2 e em
   UTC+10. Os testes antigos passaram a montar a janela de horário pela hora de Lisboa; nenhum
   `expect` mudou.
4. Juiz anti-trapaça: limpo, +19 casos de teste. Zonas protegidas: nenhuma no diff.
5. Verificador de contexto limpo: nenhum defeito confirmado; dois pontos plausíveis ligados à
   mudança (o relógio local nos buracos da mudança de hora de outros países, e as festas
   meio migradas) foram corrigidos e protegidos por teste.

## Achados pelo caminho (reportados, não corrigidos)

- Dias fechados (`special_dates`) e o "forçar" do admin: a app não os lê; o servidor sim.
- Horário vazio: o servidor diz "aberta sempre", a app assume 09h–22h. Dia sem chave no
  horário: o servidor diz fechada, a app 09h–22h. "24:00": o servidor trata como aberta, a app
  como 1440 minutos.
- Lojas com `is_online = false` (Lidl, Mercadona, Pizza Hut): a app diz fechadas, o servidor
  não olha para isso (já reportado a 05/10).
- TVDE: o "fim de semana" do plano de viagens usa o dia do telemóvel
  (`tvde_request_ride_screen.dart:390`). É dinheiro (planos), não mexi.
- Painel admin: "forçar até hoje" expira logo (meia-noite de hoje já passou). Já era assim.
- `test/loja_fechada_test.dart`: a loja "aberta 00:00–23:59" falha no último minuto do dia
  (agora o de Lisboa). Já era assim.

## B2 — Envio e builds

Dois commits de código: `af8838f3` (a correção) e `a1aa5594` (o que o verificador apanhou:
relógio marcado UTC, festas enviadas por Lisboa, dias fechados do parceiro). Antes do envio:
analyze dos 11 ficheiros mexidos com 0 erros e 0 avisos (29 infos, todas de linhas antigas,
confirmado por `git blame`); Juiz anti-trapaça limpo com +24 casos de teste; nenhuma zona
protegida; nenhum segredo, migração, função, workflow ou `pubspec` no envio.

Enviado às 14h50 UTC: `git push origin HEAD:autonomous-night-2026-04-29`, `75e7d966..a1aa5594`,
código de saída 0.

Android, corrida #502: o autoteste dos três perfis no emulador (que anda em UTC) passou às
15h22 UTC — é a primeira vez que o emulador decide a loja pela hora de Lisboa. O CI fez o
commit `01e799ed ci: bump versionCode to 652` e o envio ao Google Play (interno, alpha e
produção) passou às 15h35 UTC. No banco, `app_latest_version_code` passou de 651 para 652.

Web, corrida #196: passou. O `main.dart.js` publicado mudou de 11 112 632 para 11 113 107
bytes (resumo `3f3215836ef3ef46` para `241e566605d2cd2a`), igual em app.boraguarda.com e em
bora-app-web.pages.dev, em três leituras seguidas.

Prova ao vivo na web publicada, com o navegador posto em fuso de Tóquio (23h57 de terça,
quando em Lisboa eram 15h58): entrei com o cliente de demonstração (a conta do autoteste do
CI) e a lista de lojas do início mostrou "Aberto" no Auchan, Continente, McDonald's, Pingo
Doce, Intermarché, KFC, Wells, Leroy Merlin, DaVinci e Fuku Sushi. No mesmo minuto o servidor
(`is_partner_open`) dizia aberta nas dez. Pela regra antiga, às 23h57 do relógio do aparelho,
nove delas apareceriam "Fechada". Ficheiro `prova_web_toquio.txt` e a foto
`web-Asia_Tokyo-02-inicio.png` em `.claude/.ai/provas/hora-lisboa-2026-10-06/`.

olho-golden, corrida #188: passou.

iPhone, corrida #168: passou. No macOS do CI (relógio em UTC) passaram a análise estática, a
suite inteira de testes unitários e goldens, a compilação, a prova da folha do cartão e a
varredura de ecrãs. Depois o IPA 1.0.12, build 168, foi enviado: "UPLOAD SUCCEEDED with no
errors". Atenção: a versão 1.0.11 continua à espera da revisão da Apple
(`WAITING_FOR_REVIEW`), por isso o build 168 fica no TestFlight e é submetido no primeiro envio
depois de a Apple aprovar a 1.0.11. Os iPhones que instalam pela App Store só recebem esta
correção nessa altura.

## Para o Danilo

Nada que só tu possas fazer nesta missão, a não ser decidir se a hora da reserva de mesa
(dentro do pagamento do sinal) passa também a ir pela hora de Lisboa — a receita está acima.
