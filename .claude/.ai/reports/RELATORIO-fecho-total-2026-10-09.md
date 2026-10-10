# Relatório — missão fecho-total-2026-10-09

Missão de 09/10/2026, das 21h48 de 09/10 às 06h05 de 10/10 (hora de Lisboa). O PC esteve
parado cerca de 5 horas a meio, entre as 23h10 e as 04h28. Corri no Claude Code do PC (Opus 5.5).
Em cada passo ficou uma linha no `e2e_log` com `fluxo = 'fecho-total-2026-10-09'`.
As provas estão em `.claude/.ai/provas/fecho-total-2026-10-09/`.

## Antes de tudo — o que precisa de ti

1. **NIF dos estafetas até 15/10.** Já está no servidor a regra que bloqueia, a partir de 15/10, quem
   não confirmou na app o NIF e a atividade aberta. A tabela dessas confirmações está **vazia**:
   ninguém confirmou ainda, nem a tua conta de estafeta, nem o Valdemir, a Erika, o Euliney ou a
   conta "Danilo Fulfaro". Se ninguém confirmar até dia 15, nenhum estafeta consegue aceitar
   entregas. A app já os avisa; o melhor é falares com eles esta semana.
2. **Duas coisas que a tranca não deixa fazer** (são proibições, não há botão "Permitir"):
   o patch da folha do Favor (`errand_execution_sheet.dart`) e a cópia no repo da função do talão
   do Favor (`finalize_errand_purchase`). Só passam numa sessão aberta em `claude --safe-mode` por
   ordem tua, ou feitas pela Claude.ai.
3. **Achado de dinheiro (não mexi).** Numa loja parceira, com o pedido abaixo de 15 €, o carrinho
   mostra a taxa de pedido pequeno de 1,39 €, mas o pedido nasce sem ela, porque a tua regra de
   22/09 diz que o parceiro não paga essa taxa. O orçamento do carrinho não recebe o nome da loja.
   Exemplo: Goola Bowl, o carrinho mostra 13,87 € e o pedido fica em 12,48 €. Falta confirmar se o
   pagamento com cartão cobra os 13,87 € antes de o pedido nascer.

   **⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO.** Não preparei a correção sem saberes; diz-me se queres
   que o carrinho deixe de mostrar a taxa nas lojas parceiras.

## Bloco 0 — arranque e proteção — feito e provado

- RAM 4461 MB livres, não foi preciso fechar nada.
- Tag `antes-fecho-total-2026-10-09` no remoto, a apontar para b684a273.
- Guardei o código que estava NO AR de 11 Edge Functions em
  `supabase/functions/_arquivo/2026-10-09/`. É uma cópia byte a byte do que o servidor devolveu
  (o token da CLI está expirado desde 21/09; li tudo pelo MCP).

## Bloco 1 — Guarda FC, fotos dos 23 jogadores — feito e provado

- O ramo `principal` tinha andado 8 commits (o robô). Reapliquei os 3 commits das fotos por cima e
  juntei a lista de imagens: 150 imagens, build com 23 jogadores sem erro.
- Envio normal, sem forçar: `principal` passou de 0319376 para f7c3b6a.
- Disparei o jardineiro: publicou às 21h55 (`d4f2df6b.guarda-fc.pages.dev`), e a lista do que
  publicou tem as fichas novas.
- A cópia do Jai serve a foto nova do Bernardo Santos (35942 bytes, igual ao commit; a antiga
  tinha 28218), e respondem as 3 fichas novas.
- O guardafcsad.com tem palavra-passe (401), por isso não li os bytes lá.
- Só reportado: a notícia "plantel-renovado-2026-27" diz "Onze reforços"; no zerozero estão o
  Yohaan Benjamin (#88) e o Jovane Camará (#28) sem cartão da Diana.
- Ficou a pasta temporária `C:\BoraLocal\wt-gfc-fotos-0910` com páginas geradas pelo build. A tranca
  não me deixou descartá-las; podes apagar a pasta.

## Bloco 2 — repo igual ao ar

- **2.1 — feito.** `client-assistant` v6 no repo (cmp igual ao ar, 903 linhas).
- **2.2 — feito.** `notify-cleaner` v9 no repo. A migração foi gravada com a versão real do servidor,
  `20261009122152_cleaning_offer_reping_20261009.sql`, e não com `20261009_`; o md5 da função é igual
  ao do servidor.
- **2.3 — bloqueado.** A tranca proíbe gravar a migração do `finalize_errand_purchase` (tem a palavra
  "stripe"). A definição do ar não mudou: md5 2245262e.
- **2.4 — feito.** O `support-chatbot` v27 já estava no disco; entrou no commit.

## Bloco 3 — servidor: duas regras paradas

- **3.1 — feito e provado.** A regra do NIF entrou no `driver_accept_offer`
  (migração 20261009210533). Antes de aplicar provei numa transação desfeita, com 5 casos:
  1. antes do prazo, sem NIF, aceita;
  2. depois do prazo, sem NIF, recusa, e o pedido continua em oferta;
  3. quem já tinha aceitado continua aceite;
  4. com NIF válido, aceita;
  5. a conta demo aceita.

  A função do ar ficou igual à provada (md5 8cabacd2). A gaveta `staged_fecho_mensal_20260929`
  ficou "aplicado". A terceira parte (o despacho não oferecer a quem está bloqueado) é na Edge
  `dispatch-engine` e ficou por fazer. Os bloqueados a 15/10 estão no ponto 1 acima.
- **3.2 — superado.** A função que cria o pedido já tem a correção C7. Nas lojas não-parceiras o
  pedido sai igual ao carrinho ao cêntimo (Wells: 9,01 €, taxa 1,39 €, tampão 10,36 €; acima do
  mínimo, taxa 0). A gaveta `staged_contas_claras_20260921_c7` ficou "superado". Não mudei nenhum
  valor. O achado das lojas parceiras está no ponto 3 acima.

## Bloco 4 — limpeza e lavagem

O caso: a Mayra só faz limpeza e ficou no ecrã do estafeta, e o aviso não tocou a sério.

- **Servidor — feito e provado** (migração 20261009212830, testada numa transação desfeita):
  - conta cada toque da oferta;
  - a repetição de minuto a minuto passa a dizer o ganho da profissional, e não o total do cliente;
  - função de trabalho pendente por papel;
  - funções do painel para ver e ligar/desligar papéis com motivo e registo, para as ofertas com
    toques e aparelho, e para o interruptor do toque repetido.
- **4.A — feito.** A oferta de limpeza e de lavagem toca como a do estafeta: notificação de ecrã
  inteiro, som em ciclo, e os botões Aceitar (abre a app e aceita) e Recusar (recusa sem abrir a
  app). Com a app aberta aparece um cartão por cima de qualquer ecrã e de qualquer papel, com o
  ganho em grande, a hora de Lisboa e a contagem do prazo. As ofertas ligam-se logo a seguir ao
  login. No iPhone, o som `bora_alert.wav` está no pacote e o servidor manda o alerta com texto e
  esse som; não há iPhone aqui para provar com um aviso real.
- **4.B — feito.** Quem só tem limpeza entra direto na limpeza. Com vários papéis entra-se primeiro
  no papel com trabalho à espera, senão no último modo usado; o "Mudar de modo" grava-o.
  A causa da Mayra:
  - a linha de estafeta dela nasceu no registo antigo de estafeta (01/10 às 12h05, minuto e meio
    antes da de limpeza);
  - foi aprovada a 02/10 às 12h42 sem administrador registado: foi o desbloqueio manual desse dia,
    não a app;
  - esse caminho por arrasto está fechado desde 02/10 (a prova "PROVA Limpeza 2" já não ganhou
    linha de estafeta).
- **4.C — feito.** A lavagem chegava sem texto porque a app só lia o bloco `notification`, que não
  vem. Agora lê o título e o texto do `data`, na limpeza e na lavagem. Na web, as ofertas de
  trabalho ficam no ecrã até a pessoa responder.
- **4.D — superado.** Já estava corrigido e publicado a 08/10 (commit 6a561727).
- **4.E — feito.** No painel (PT-BR), na lista das profissionais e dos lavadores:
  - "Papéis desta pessoa", com interruptor por papel, motivo obrigatório e registo;
  - "Ofertas em aberto", com quantas vezes tocou, se tem aparelho registado e o interruptor
    "Repetir o toque da oferta".

## Bloco 5 — favor

- **5.1 — bloqueado.** A tranca proíbe editar `errand_execution_sheet.dart` ("BLOQUEADO Edit"). O
  patch ainda encaixa limpo (`git apply --check`). Não mexi no FolhaFavor publicado.
- **5.2 — superado.** A correção da loja fechada (c541de97) foi publicada a 05/10 como 311f8371, e a
  hora de Lisboa entrou a 06/10. Desde 06/10 o autoteste do emulador passou nas quatro corridas da
  madrugada (00h, 04h, 05h e 04h).

## Bloco 6 — pequenos que ficaram

- **6.1 — superado.** O aviso urgente já chega ao teu Telegram: hoje há "telegram sent OK" depois de
  cada aviso, incluindo a limpeza nova das 12h59. O chat é o teu. Não mexi.
- **6.2 — feito.**
  - Apagadas no painel do Supabase as 5 funções temporárias: `tmp-connect-link`,
    `tmp-admin-upload-gallery`, `tmp-importar-fotos-parceiro`, `diag-env-names` e
    `gemini-diagnostic`. Todas tinham 0 referências e 0 chamadas em 14 dias. O servidor confirma
    "Function not found" nas 5, e o código está no `_arquivo`.
  - Mantida a `aplicar-gaveta`, porque foi chamada 14 vezes a 07 e 08/10.
- **6.3 — superado.** A skill já existia desde 26/09; acrescentei os CTT e a Google Cloud da Bora
  (perfil Bora) e o DeepSeek (pessoal).
- **6.4 — feito.** Fechei as abas que abri.

## Bloco 7 — testes, Android 15 e publicação

- **7.1 — feito e provado.**
  - A suite completa passou antes e depois: 1129 testes verdes na linha de base (numa cópia limpa
    do ramo) e 1162 verdes depois das alterações, 0 falhas.
  - `flutter analyze`: os mesmos 261 avisos antes e depois, 0 erros e 0 avisos novos.
  - Juiz (`anti_trapaca.py`): "CLEAN" sobre todos os commits da missão, com mais 39 casos de teste.
  - **A revisão por um agente de contexto limpo encontrou 2 problemas graves**, ambos corrigidos
    antes do envio (commit f4f346b7):
    1. "Mudar de modo" para a limpeza desmontava o ecrã do estafeta, mesmo com ele online (o mesmo
       padrão do caso Ney);
    2. o "Aceitar" da notificação com a app fechada perdia-se.

    Também corrigi os médios: o cartão já não tapa a oferta de entrega quando o estafeta está a
    trabalhar (fica uma faixa compacta, sem som), uma falha de rede já não faz perder a oferta, e
    o último modo é esquecido quando a pessoa sai da conta.
- **7.2 — feito, com limite.** Emulador Android 15 (`emdia35`), 4734 MB de RAM livres antes de
  arrancar. Arranquei o serviço em primeiro plano do estafeta (o mesmo `BoraForegroundService` da
  app; tipos `dataSync|remoteMessaging`) e deixei-o 6 minutos: esteve sempre a correr, com 47
  batidas no logcat. Encurtei por `adb` o limite de 6 horas do Android 15 para 2 minutos e não
  houve fim de tempo nem rebentamento da app. **Isto não prova as 6 horas reais**: o plugin 8.17
  não trata esse fim de tempo, e o teste com um estafeta real online ficou por fazer, para não
  receber ofertas de produção.

  Observação: no arranque do APK de depuração houve um "não responde". Foi o serviço de
  localização do plugin `geolocator` a demorar 20 s, com o emulador sobrecarregado (carga 43,9).
- **7.3 — feito.** No emulador, com a app de prova (sem login nem servidor):
  - a oferta de lavagem em ecrã inteiro por cima do ecrã do estafeta, com €9,00 em grande, a hora
    de Lisboa, a morada, a contagem e Recusar/Aceitar;
  - a notificação real do Android com o texto do `data` e os botões Aceitar e Recusar.

  A foto da limpeza ficou tapada pelo "não responde" do arranque; vê-se o cartão por trás.
  Fotos em `.claude/.ai/provas/fecho-total-2026-10-09/emulador/capturas/`. Não houve pagamentos
  de teste (nada desta missão cobra).
- **7.4 — envio feito.** `git push` normal, sem forçar: o ramo de produção passou de 6d79118d para
  ee18e039. Antes de enviar juntei o espelho do Córtex das 23h07, que entrou no último segundo; o
  PC esteve parado cerca de 5 horas entre as 22h10 e as 03h28 UTC.
  - **Web — provado.** A corrida #204 deu sucesso. O `versao.json` em app.boraguarda.com e em
    bora-app-web.pages.dev mostra o commit ee18e039, e o `main.dart.js` publicado tem os textos
    novos ("Repetir o toque da oferta").
  - **Android — provado.** A corrida #510 deu sucesso: o autoteste dos 3 perfis passou e o envio ao
    Google Play (interno + alfa) também. O versionCode no servidor passou de 659 para 660, e o commit
    "ci: bump versionCode to 660" (241d12c3) entrou logo a seguir ao meu.
  - **iPhone — build VALID, submissão por fazer.** A corrida #177 passou o simulador e a varredura.
    O IPA subiu sem erros e o registo diz **"build 177: VALID"**. O CI criou a versão 1.0.15 (com
    lançamento automático depois da aprovação), ligou-lhe a build 177 e meteu-a na submissão. No
    último clique ("Submeter"), o servidor da **Apple respondeu com erro 500** ("An unexpected error
    occurred on the server side"), por isso a corrida ficou marcada como falhada. A build está no
    TestFlight.
    - A submissão volta a ser tentada sozinha no próximo envio que mexa em `lib/`, porque o script
      reaproveita a 1.0.15.
    - Também se pode fazer com um clique em "Submeter para revisão" no App Store Connect, que não
      tem sessão aberta no perfil Bora.

## Bloco 8 — Jai, camisolas nos CTT — feito (só leitura)

Usei o perfil Bora, com a sessão já iniciada. O envio LT108385772GB:
- expedido a 03/09;
- chegou a Portugal a 07/09;
- "Informação em falta" a 22/09 às 11h55;
- **"Em Validação de Informação CTT" desde 22/09 às 12h07** — há 17 dias parado aqui.

Faltam "Aguarda procedimentos declarativos" e "Conclusão". O sino tem 0 avisos, ou seja, nenhum
pedido novo dos CTT. Não enviei nada.

## Outros erros encontrados e NÃO corrigidos

1. **10 migrações aplicadas entre 07 e 09/10 não estão no repo.** São estas: 20261007033508,
   033530, 033618, 033627, 123823, 181227, 181506, 20261008195223 (a do Favor, bloqueada),
   203605 e 220113. Só guardei as duas que a missão pedia.
2. A gaveta da regra do NIF tinha uma terceira parte, que ficou por fazer: o despacho não oferecer
   a quem está bloqueado. Sem ela, um estafeta bloqueado pode receber uma oferta que não consegue
   aceitar, e o pedido espera 40 s até passar a outro.
3. Android 15: o serviço em primeiro plano do estafeta é do tipo `dataSync`, e o plugin 8.17 não
   trata o fim do limite de 6 horas (`onTimeout`). Ver Bloco 7.2.
4. A lista de quem confirmou o NIF está vazia (ponto 1 no topo).
5. Quem tem o cliente como modo base não abre sozinho na limpeza quando há trabalho pendente; só o
   portão do estafeta faz isso. A oferta, essa, aparece por cima de qualquer ecrã.
6. Entrada com o estafeta ligado e uma limpeza a decorrer ao mesmo tempo: abre o ecrã do estafeta.
   A regra 1.24 do padrão pediria a limpeza; é um caso raro e ficou por afinar.
7. Pontos baixos da revisão que ficaram por fazer:
   - o gancho `abrirTrabalho` pode abrir um segundo ecrã da limpeza por cima do que já é a entrada;
   - na web, o aviso que fica no ecrã até à resposta não se fecha sozinho quando a oferta morre;
   - `my_trabalho_pendente` não olha para corridas TVDE ativas.
8. **Outra sessão está a mexer na mesma pasta do repo agora mesmo.** Tem por gravar cerca de 20
   ficheiros (canal de alarme `bora_offers_alarm_v4`, `main.dart`, `foreground_service.dart`,
   `oferta_trabalho_aviso.dart` e ecrãs do cliente). Não toquei em nada disso nem o gravei. O meu
   trabalho foi enviado antes.
9. A aplicação iOS: o envio para revisão da Apple falhou com erro 500 do servidor (ver 7.4).
10. No emulador, o APK de depuração deu "não responde" no arranque, porque o serviço do `geolocator`
    demorou 20 s com a máquina sobrecarregada. Não se viu em produção; fica registado.

## PARA O DANILO

- Queres que o carrinho deixe de mostrar a taxa de pedido pequeno nas lojas parceiras? (Ponto 3 do topo.)
- Abres uma sessão em `--safe-mode` para eu aplicar o patch do Favor e guardar a migração do talão?
