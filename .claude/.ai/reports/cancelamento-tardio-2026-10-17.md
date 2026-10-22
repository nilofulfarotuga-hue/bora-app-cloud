# Cancelamento tardio TVDE — app, painel e publicação (17/10/2026)

Missão `cancelamento-tardio-app-painel-2026-10-17` · run_id `cancelamento-tardio-20261017` ·
porta Claude Code no PC do Danilo (Controlo Remoto) · relatório para a Claude.ai.

Acessos: nenhuma conta nova criada. Supabase pelo MCP (projeto `ojykpzwqrtusfeakzrna`: só
leituras e linhas no `e2e_log`), GitHub Actions pela credencial do Git do PC (só leitura),
Córtex pelo MCP (uma proposta, `prop-d2fcdfed`). Nenhuma senha escrita, nenhum dinheiro
mexido, nenhuma corrida, compensação ou movimento criado; nenhum SQL nem Edge Function
alterados.

## O que NÃO foi feito (primeiro)

- **Prova visual do painel** (captura de `/admin/tvde/cancelamentos` e das definições): esta
  sessão não tem a extensão do Chrome ligada, por isso não abri o perfil da Bora. A prova é
  pelos testes (lógica, textos, totais, CSV). Fica para a Claude.ai.
- **Página do Córtex das regras de negócio**: é zona vermelha, por isso não escrevi — deixei
  a proposta `prop-d2fcdfed` na fila do admin. A regra está escrita por inteiro em
  `.claude/.ai/business_rules.md` §58 (no repo).
- **Etiqueta da taxa fixa**: o pedido mandava escrever "(blindada: só leitura)". Não é
  verdade — desde 06/09 (autoridade total) as chaves de dinheiro editam-se no painel pelo
  caminho com motivo e auditoria. Escrevi "(muda-se com motivo e fica auditada)".
- **`integration_test` em aparelho real**: corri-o no motor de testes do PC
  (`-d flutter-tester`, 5/5 verdes). Não abri emulador (RAM do PC entre 1,4 e 2 GB; a regra
  pede ≥ 3 GB).
- **Do lado do servidor nada foi corrigido** (ordem do prompt): os achados estão abaixo.

## Bloco a bloco, com prova

**Arranque.** `e2e_log` 3837 (`00-arranque`) e prompt gravado em
`C:/Users/danil/Desktop/Bora/prompts/PROMPT_cancelamento_tardio_2026-10-17.md`. SELECT de
confirmação do servidor: migração `20261017143124` presente (1 statement, 25 741 caracteres),
`tvde_cancel_driver_fee_cents = 375`, `tvde_cancel_full_after_grace = true`,
`cancel_grace_seconds = 180`, `tvde_cancel_fee_cents = 250`, `tvde_cancel_compensations` = 0
linhas. Trabalhei numa worktree limpa (`C:/BoraLocal/wt-cancelamento-17-10`, a partir do
`origin`), porque a árvore principal tinha 356 ficheiros de outras sessões e estava atrás
do servidor. Linha de base: analyze 0 erros / 6 warnings / 258 infos; `flutter test`
1336/1336.

**Bloco A+B (commit 3e235f78) — app do cliente.** Modelo novo `TvdeCancelQuote`
(`lib/models/tvde_cancel_quote.dart`), `TvdeStore.cancelQuote` (timeout `kAcaoTimeout`, nunca
lança, `ok:false`/erro → null) e diálogo novo `lib/widgets/tvde/tvde_cancel_dialog.dart`: a
cotação pede-se antes de abrir (até 3 s; depois, aviso neutro sem números); terminal →
SnackBar "já tinha terminado / já estava cancelada" e sai (`sem_motorista` segue como sem
custo); `dentro_da_graca` com contador mm:ss e nova cotação a zero; `corrida_inteira` com
caixa vermelha e como se cobra; `taxa_fixa`; botões "Voltar" e "Sim, cancelar" / "Cancelar e
pagar X €". Ao confirmar há nova cotação: se subiu, o diálogo volta com o valor novo. Saiu o
cálculo local por `createdAt` (o `_cancelGraceSeconds` fica só para os minutos do aviso
neutro). `cancelRide` devolve `Future<int>` com a taxa real; a chamada de reembolso à Edge
ficou igual. SnackBar "Corrida cancelada. Foram cobrados X €." / "Sem custo.". Histórico:
`TvdeRide.cancelFeeCents` e, nas canceladas, a taxa cobrada ou "Sem custo". Inglês das 17
frases novas à mão em `strings_en.dart` + `tool/l10n/traducoes/pt-en-21-cancelamento-tardio.json`.

**Bloco C (commit 73cfb88c) — app do motorista.** `admin_message` entrou nas categorias
persistentes (fundo e app aberta), com o desenho do `admin_generic` (título e texto do
`data`, id por kind+relatedId, uma notificação e um som por mensagem); o toque abre o ecrã de
notificações (app viva e a frio) e tira a notificação; `setupBroadcastDeepLink` também na
home do motorista só de TVDE. Sino: `Icons.euro` para `tvde_cancel_comp`. Ganhos: compensação
de corrida com o ícone do carro (só o ícone). Ecrã da corrida: SnackBar uma vez quando o
cliente cancela, com o texto da notificação da compensação ou "O cliente cancelou a
corrida."; navegação, `clearActive` e fila iguais. C4 (só leitura): o extrato mostra a linha
`compensacao` com `Icons.replay` verde, e o painel usa o mesmo widget
(`admin_extratos_pessoas_screen.dart:185`).

**Bloco D (commit 8b11d61d) — painel PT-BR.** Cancelamentos TVDE: segunda chamada
`admin_tvde_cancel_comps(200)` em try/catch (a lista de cima nunca cai por causa dela);
resumo no topo (compensações, cobrado aos clientes, pago aos motoristas, fica para a Bora com
sinal, NÃO COBRADO a vermelho) e a frase da regra com os valores lidos por `get_setting`; em
cada cartão a compensação, o cobrado e como, regra automática/admin e acerto da semana;
pagamento só quando há dados (lido de `tvde_rides`); saiu "Dinheiro — sem reembolso" e a
etiqueta da janela de cortesia desde o pedido; botão "Compensar motorista" (valor por omissão
da definição, 0,01–50 €, motivo ≥ 3 letras, confirmação com nome e valor, erros em PT-BR);
CSV com ";". Lista de corridas: totais tiram à Bora o que foi para o motorista; linha
"Cancelamento tardio · compensação ao motorista X € · a Bora fica com Y €"; corrida cobrada
por inteiro diz "nada a devolver" e não tem botão de reembolso. Definições:
`tvde_cancel_driver_fee_cents` editável com motivo e auditoria (o histórico
`admin_list_cancel_setting_audit` filtra pela acção, logo inclui a chave nova) e etiquetas
PT-BR locais. Alertas `tvde_compensacao_falhou` e `tvde_cancel_fee_nao_cobrada` com nome e
ícone; o toque abre `/admin/tvde/cancelamentos` (deep_link gravado por `notify_admin_event`,
rota em `main.dart`). Menu: "Corridas canceladas, taxas cobradas e compensação ao motorista".
D6: o ecrã Pagamentos TVDE dizia "Já estornado" numa corrida que ficou com o valor todo →
agora "Nada a devolver". O ecrã de no-shows só lista `no_show` — não é afectado.

**Bloco E (commit b25885f8 + notas 8b206eee).** Migração no repo com o texto exacto da base:
md5 `be14735358fc9f8dcfe659a8090bf350`, 25 880 bytes, igual no servidor, no ficheiro e no blob
do commit (`.claude/.ai/provas/cancelamento-tardio-20261017/migracao_md5.txt`). Nenhum
workflow aplica migrações e a versão já consta na base. `business_rules.md` §58. Testes
novos: cotação e textos de cada regra, terminal, erro e campos em falta; `cancelRide` devolve
a taxa (store com cliente falso); decisão da notificação de `admin_message`; junção e totais;
CSV; diálogo (contador, corrida inteira online e carteira, falha → neutro, subida ao
confirmar) em widget test e em `integration_test` (5/5 no flutter-tester). Notas de versão do
iPhone com a frase pedida.

**Revisão independente antes de publicar (commit b05c56c9).** Um agente separado, só a ler,
tentou partir o trabalho. Corrigi o que apanhou: (1, alta) se a cotação ao confirmar
falhasse, a app cancelava a quem tinha visto "grátis" — agora volta ao aviso neutro; e com
menos de 5 s de janela grátis o diálogo volta a mostrar-se, porque o pedido pode chegar ao
servidor já fora da janela; (2) a notificação aberta a frio ficava presa na barra; (3) nas
Definições, "3.75" numa chave em cêntimos seria gravado como 4 cêntimos — agora só número
inteiro e aviso abaixo de 50; (5) o total da Bora contava a taxa de uma cobrança falhada;
(6) `setState` depois de sair do ecrã; o `@pragma('vm:entry-point')` tinha saltado para a
função nova e voltou à de sempre.

Suite depois de cada bloco (`.claude/.ai/provas/cancelamento-tardio-20261017/suite_por_bloco.txt`):
1336 → 1361 → 1371 → 1384 → 1389, sempre todos verdes; analyze sempre 0 erros e os mesmos 6
warnings antigos. Anti-trapaça do Juiz (`--base HEAD`) CLEAN em todos os commits.

## Bloco G — achados (confirmados por leitura no servidor; nada corrigido)

- (a) **Confirmado.** `tvde_mark_noshow` grava `driver_earn_cents` = 3,50 €, mas
  `compute_driver_settlement` só soma corridas `finalizada` — o no-show nunca entra no acerto
  do motorista. E não cobra o cliente em dinheiro (não chama a carteira). Há 1 no-show na base.
- (b) **Confirmado em parte.** A compensação de entrega (1,50 €) aparece no extrato
  (`_prestador_trabalhos`, ramo do livro-razão) e `compute_driver_settlement` não lê o
  livro-razão. A vigia `vigia_compensacao_fora_do_acerto` **não existe** na base (nem função,
  nem cron, nem tabela) — se existir, vive fora do Supabase.
- (c) **Confirmado.** A descrição de `tvde_noshow_driver_fee_cents` fala de "cancelamento
  tardio de corrida coberta pelo plano", que não paga nada ao motorista.
- (d) **Confirmado.** `tvde_cancel_ride` só verifica que quem chama é admin, o cliente ou o
  motorista; não liga `p_actor` ao papel (o cliente pode mandar `motorista` ou `no_show`). A
  regra nova está protegida (exige `v_uid = client_id`).
- (e) **Não consegui confirmar** (não encontrei o "extrato do dono" a que se refere).
- (f) **Confirmado pela descrição**: `tvde_electronic_payment_only` (false) esconde o
  dinheiro e o servidor recusa `cash` — por desenho (Art. 15.º n.º 7).
- (g) **Confirmado.** `tvde_request_ride` não menciona a carteira: a dívida não é aplicada nas
  corridas seguintes.
- (h) **Confirmado.** `wallet_debit_cancel_fee` grava "Taxa de cancelamento after_accept
  (pedido <id>)" — código em inglês e "pedido" numa corrida.
- (i) **Confirmado.** 3 corridas têm o evento `cancelada_cliente` duplicado.
- (j) **Confirmado no código do repo**: `notify-admin-message` manda para iOS um push de fundo
  (`apns-push-type: background`, só `content-available`) — pode não chegar com a app fechada;
  o canal fiável é o sino. E lê **um só** `users.fcm_token` (não `provider_push_tokens`).
- (k) **Confirmado.** `tvde_cancel_ride` lê `service_role_key` do cofre para chamar a Edge —
  a missão chave-nova-16-10 (Bloco 3) tem de a incluir.
- (l) **Confirmado.** `cancel_grace_seconds` diz "logo após o pedido" (errado: conta desde o
  aceitar), `tvde_cancel_fee_cents` diz "(placeholder)", `tvde_cancel_full_after_grace` não diz
  que é só corrida normal. A app mostra etiquetas locais.

## Outros achados do caminho (não corrigidos)

- O motorista recebe **dois** avisos no cancelamento tardio (o `tvde_ride_cancelled` de
  sempre e o da compensação) e, com a app aberta, a SnackBar. Juntar é do servidor.
- `push-clientes-alvo` usa `type = 'admin_message'` por omissão, com bloco `notification`. Hoje
  os chamadores passam o seu tipo (`checkin_diario`, `receita_do_dia`, reactivação); se um
  dia algum não passar, com a mudança desta missão a notificação aparece duas vezes.
- `admin_tvde_cancel_comp_grant` não manda push ao motorista (só a linha no sino).
- `_cancelFalhou` (ecrã do cliente) tem "A corrida já estava cancelada." sem `.tr` (antigo).
- O `analysis_options.yaml` e os ficheiros gerados de Linux/Windows/macOS ficam alterados
  pelo Flutter 3.47 do PC sempre que se corre — não entraram em commit nenhum.

## Versões publicadas (envio 9038a2ce..b05c56c9, só os 6 commits desta missão)

Os 2 commits locais da chave-nova-16-10 (`d5d8f127`, `bf58dc11`) vivem no ramo
`chave-nova-16-10` (worktree `C:/BoraLocal/wt-chave-nova-16-10`) e **não** viajaram.

- **Web:** run `39051765011` verde. `https://bora-app-web.pages.dev/versao.json` →
  `{"commit":"b05c56c9…","run":"222","data":"2026-10-17T17:01:16Z"}` (antes `219f0e7f`, 221).
  O `main.dart.js` no ar contém "Cancelar na mesma", `tvde_cancel_quote`,
  `admin_tvde_cancel_comps` e "Compensar motorista".
- **Android:** run `39051765097` verde — autoteste dos 3 perfis verde, commit do CI
  `85a447e0 ci: bump versionCode to 676`, passo "Upload to Google Play (internal + alpha +
  production)" verde; `platform_settings.app_latest_version_code` 675 → **676**.
- **iPhone:** run `39051765044` = **build 194** verde (simulador + IPA). Log do
  `ios_publicar.py`: `build 194: VALID`, `versao 1.0.21 criada`, `releaseType ja e
  AFTER_APPROVAL`, `build ligada a versao: 194`, notas pt-PT com a frase do cancelamento,
  `submissao lida de volta: {"submittedDate": "2026-10-17T18:30:05.079Z", "state":
  "WAITING_FOR_REVIEW"}`. `app_latest_version_code_ios` 193 → **194**. A Apple analisa em 1–2
  dias; sai sozinha quando aprovar. A build fica também no TestFlight.

No fim, SELECT: `tvde_cancel_compensations` = 0 linhas; `tvde_cancel_driver_fee_cents` = 375,
`tvde_cancel_full_after_grace` = true, `cancel_grace_seconds` = 180 (nada mudou no servidor).

## Para a Claude.ai

- Prova visual do painel (`/admin/tvde/cancelamentos` e definições de cancelamento) com a
  sessão de admin do perfil da Bora.
- Decidir os achados do Bloco G e os dois avisos ao motorista no mesmo cancelamento.
- Aprovar (ou não) a proposta do Córtex `prop-d2fcdfed`.
