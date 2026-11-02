# Missão app-fechar-2026-11-01 — relatório para o Danilo

Data: 01/11/2026 (noite) a 02/11/2026. Porta: Claude Code no PC. Ramo de trabalho
`app-fechar-2026-11-01`, saído do servidor (`582d84e3`), juntado ao ramo de produção no fim.
Fluxo no e2e_log: `app-fechar-2026-11-01` (ids a partir de 6032).
RAM: ao arrancar havia 293 MB livres (abaixo do portão de 400 MB para trabalho leve; avancei só
com leitura e escrita de ficheiros e SQL); depois subiu para 1,1–1,5 GB e os testes correram acima
do portão de 800 MB.

## Em poucas palavras

Fiz isto: consertei no servidor a Casa (o profissional já consegue gravar os dados fiscais e enviar
o comprovativo de atividade; os avisos da Casa já saem), publiquei a função de avisos da Casa,
arrumei a melancia do Continente, mudei o aviso do peso para quem paga com cartão ou MB Way, deixei
o cliente e a profissional verem se a série de limpeza está parada, e cadastrei-te como profissional
da Casa (pendente). Na app (5 agentes em paralelo, cada um nos seus ficheiros) entraram os oito
blocos: Casa, peso, compra sem conta, estafeta não aprovado, série de limpeza, assistente, robô dos
documentos e suspensão com revisão humana. Provei na web em produção que "Finalizar" como
visitante abre o ecrã de entrar. Publiquei nas 3: web (commit 280e50db no ar), Android (versão
704 no Play) e iPhone (ver "Publicação").

Falta isto: a tua parte para a Casa (dados fiscais e comprovativo); as decisões de dinheiro da
lista lá em baixo; e a prova do "Finalizar" na versão nova com uma loja aberta (às 23h estavam
todas fechadas). As três correções do servidor que o classificador do PC recusou já foram
aplicadas pela Claude.ai às 23h e eu confirmei-as.

## ⚠️ ISTO MEXE EM DINHEIRO — está tudo pronto, decides de uma vez

Nada disto foi mudado. Responde com os números que queres (ex.: "1 sim 300 €, 2b, 3 autorizo, 4 não").

1. Casa — limite de dinheiro. Hoje a Casa só aceita dinheiro e usa o limite geral das entregas,
   40 €. Com isso metade do catálogo não se consegue pedir (pendurar TV 2 h = 60 €, montar móvel
   2 h = 50 €, quase todos os orçamentos). Proposta: um limite só da Casa, por exemplo 300 €
   (chave nova `casa_max_cash_cents`, lida pelo servidor em `casa_config`, `casa_criar_pedido`,
   `casa_aceitar_orcamento` e `casa_responder_extra`). A app já lê o limite do servidor; não
   precisa de nova versão.
2. Casa — taxa de cancelamento. Se o cliente cancela a menos de 12 h, a app diz que paga metade
   (a menos de 2 h, o total). Como é tudo em dinheiro, ninguém cobra nada e o profissional que já
   ia a caminho não recebe. Escolhe: (a) o acerto semanal passa a contar essa taxa (e defines a
   parte do profissional), ou (b) a app deixa de prometer esse custo.
3. Casa — ligar a sério. Valores atuais à espera do teu "autorizo": comissão Bora 15 %, sem
   comissão para os 5 primeiros profissionais durante 2 meses, cancelamento grátis até 12 h antes,
   metade até 2 h. Passo único teu: no painel → Casa → Definições → "Autorizar valores" com um
   texto que diga "autorizo", e depois o interruptor da Casa. Hoje: Casa desligada, valores por
   autorizar.
4. Peso ao quilo — margem. O estafeta só pode ajustar ±30 % do peso previsto. Numa peça única
   (melancia de 4 kg que sai com 5,6 kg) isso obriga a "Não há". Proposta: ±50 % só para as peças
   vendidas ao quilo. Mudei só a frase ("escolhe uma peça mais perto de 4 kg").
5. Peso ao quilo — cartão e MB Way. Hoje, quando o peso real sai mais caro, a Bora paga a
   diferença (`weight_adjust_card_charge_enabled` = desligado). O aviso ao cliente agora diz isso.
   Ligar a cobrança da diferença é decisão tua.
6. Limpeza — parar a série. "Parar a série toda" cancela também as limpezas já marcadas a mais
   de 24 h, mas não devolve o que foi pago por cartão ou MB Way (não há devolução automática
   nesse caminho). Precisa de decidir: devolver sempre, ou só cancelar as que ainda não foram pagas.

## PARA O DANILO (só tu podes fazer)

- Casa, para ficares como profissional aprovado: abre a app → Casa (faz-tudo) → completar os
  dados fiscais (IBAN, data de nascimento, morada, autocertificação) e enviar o comprovativo de
  atividade (início de atividade nas Finanças, PDF ou foto). A candidatura já está criada por ti
  (Montagem de móveis e Pendurar e fixar, todos os dias das 9h às 20h, Guarda, 15 km). Assim que
  enviares, aprovo no painel a pessoa e os dois ofícios. Tentei aprovar já e o servidor recusou,
  como deve: "atividade_por_aprovar".
- O teste a dinheiro da Casa faz-se com a conta boraappbora@gmail.com como cliente (já está na
  lista de testadores da Casa; os pedidos de testador ficam fora do acerto) e tu como profissional.
- Peso ao quilo: o teu teste com um pedido real no Continente, a dinheiro, com banana ao quilo.

## O que fiz, bloco a bloco

### B1 — Casa & Manutenção
Servidor (aplicado e provado por SELECT):
- C1: a função dos dados fiscais aceitava todos os papéis menos o da Casa; agora grava o nome
  legal, NIF, morada, IBAN, data de nascimento e autocertificação na ficha do profissional da Casa.
- C3: o comprovativo de atividade passou a conhecer a Casa (papel "casa"), e o painel de
  conformidade legal passou a listar os profissionais da Casa.
- C4: a função de avisos da Casa (`notify-handyman`) está publicada. Sem chave responde 401; o
  servidor chamou-a com a chave dele e ela respondeu 200 (chegou ao Firebase, sem enviar push a
  ninguém). Antes, nenhum aviso da Casa saía do telemóvel.
- C15: o convite a orçar dizia "Vê as fotos" antes de as fotos subirem; agora diz "Abre o pedido
  e envia o teu preço".
- C12/C13: a conta da Bora ficou testadora da Casa; a tua candidatura de profissional criada.
App e painel (agente B1): ofertas relidas de 10 em 10 s quando há ofertas por responder (C5);
extrato do profissional já não mostra "a pagar" quando é a Bora que paga, nem "-3,00 €" (C8);
todos os erros do servidor têm frase em PT-PT (C9); aviso "Sem horários não recebes trabalhos"
(C10); fotos com a extensão certa (C14); separador "Ofertas" no painel da Casa (C16); painel da
Casa revisto para PT-BR; dois botões que ficavam mudos agora explicam porquê.

### B2 — Peso ao quilo
- Melancia do Continente: tinha o preço de uma balança (9,06 €). Ficou 2,19 €/kg × 4 kg = 8,76 €,
  com o nome "(~4 kg)" (cópia de segurança `bkp_products_melancia_20261101`). A Melancia Riscada
  e os melões do Continente também têm preço de balança, mas não tenho o preço do quilo real deles:
  ficam por arrumar.
- Aviso ao cliente quando o estafeta ajusta o peso: com cartão ou MB Way já não diz "Novo total"
  (que não se cobra); diz que a Bora assume a diferença ou que a diferença vai para a carteira.
- App: o cartão "Ajustado ao peso" mostra a linha "Diferença: +1,92 €" e a frase certa para cada
  forma de pagamento; quando a peça sai fora da margem, a app diz ao estafeta "escolhe uma peça
  mais perto de 4 kg". Confirmado que o "Não há" do talão anula o ajuste (usa o mesmo id do produto).

### B3 — Compra sem conta
- Provado na web em produção (app.boraguarda.com, versão 21cb44ed, que já tem o conserto de 28/10):
  como visitante, Continente → produto → carrinho → "Finalizar pedido" abre o ecrã "Para finalizar
  o pedido, entra na tua conta ou cria uma — o teu carrinho fica guardado". Capturas em
  `.claude/.ai/provas/app-fechar-2026-11-01/`.
- Teste novo que reproduz o toque no carrinho verdadeiro.
- Depois de criar conta no carrinho, o cliente novo aceita os termos antes de pagar (antes ficavam
  por baixo).
- O interruptor "sessão de convidado" ficou trancado no painel, com a nota de que a função do
  servidor não está publicada (evita erros em cada arranque se alguém o ligasse).
- O botão "Finalizar" já não fica cinzento mudo quando falta escolher a hora: leva ao cartão e diz
  "Escolhe a hora da entrega".

### B4 — Estafeta não aprovado
- O botão "Online" pergunta primeiro ao servidor. Conta por aprovar, recusada ou bloqueada não liga
  e aparece: "A tua conta ainda não está aprovada. Quando for aprovada recebes um aviso e podes
  ficar online." O botão só fica verde quando o servidor confirma; se o servidor recusar, volta a
  offline. O batimento de presença não arranca sem aprovação. Igual no TVDE.
- Erro encontrado e corrigido: o "ficar online" mandava o id errado ("driver-main") em alguns casos.
- Produção (leitura): nenhum estafeta não aprovado está online.

### B5 — Série de limpeza
- Servidor: o cliente e a profissional da série passaram a poder ver se a série está parada
  (provado: o dono vê, outra conta não vê nada).
- App: "Cancelar limpeza" numa série diz "Cancelas só esta limpeza. A série continua na próxima
  data." e tem o botão "Parar a série toda"; a marcação mostra "Semanal · próxima: dia/hora" (hora
  de Lisboa) ou "Série parada"; a lista agrupa com o selo da série; a profissional vê "Semanal" e
  "Cliente habitual". Duas horas que apareciam no fuso do telemóvel passaram para Lisboa.

### B6 — Assistente do cliente (as 3 melhorias)
Várias fotos de uma vez (até 4), cartão de comparação ("Na Glovo deu X; no Bora, Continente dá Y —
mais barato Z"), e no painel o separador "Aprendidas" para ver e desligar o que o assistente aprendeu.
Corrigido pelo caminho: as fotos PNG iam marcadas como JPEG.

### B7 — Robô dos documentos (painel)
Separador "Avisos enviados" (nome, o que falta, email, estado, data em Lisboa) e o interruptor
"Emails automáticos" (`robo_documentos_avisos_ativo`, hoje ligado).

### B8 — Suspensão e revisão humana (Diretiva UE 2024/2831)
- App (estafeta, motorista, limpeza, lavagem, Casa e parceiro): ecrã "A minha conta foi suspensa"
  com o motivo, a data, até quando, "Decidido por: Equipa Bora", botão "Pedir revisão" e a resposta.
  Substitui o ecrã que só dizia "Contacta o suporte".
- "Como o Bora decide" em Informação legal, com o texto de `docs/legal/gestao-algoritmica-prestadores.md`,
  e ligação nas candidaturas.
- Painel: ecrã "Revisões" (responder, decidir proposta, registar pedido do WhatsApp, reativar) e
  "Suspender com motivo" nas fichas; os botões antigos de banir/suspender/desligar loja pedem o
  motivo (10 letras), senão o servidor recusa.
- Erros encontrados em produção: "Desativar loja" e o interruptor das barbearias faziam uma
  gravação direta que o gatilho novo recusa (consertado na app); "Papéis da pessoa → desligar
  limpeza/lavagem" falhava no servidor (corrigido às 23:03, ver Trancas). Uma suspensão com data
  de um estafeta nunca acabava (corrigido às 23:03); por segurança o painel desta versão ainda não
  oferece a suspensão com data a estafetas — volta na próxima publicação.

## Trancas — o que ficou pronto mas não pude aplicar

O classificador do PC recusou três migrações do servidor depois de quatro terem passado pelo
mesmo caminho. Não contornei: deixei-as escritas como PROPOSTA_ e registadas em `docs/TRANCAS.md`.
ATUALIZAÇÃO 23:45: a Claude.ai aplicou as três por MCP às 23:03 (commit `f62a9cf3`); confirmei por
SELECT que estão no ar e pus os ficheiros do repositório com os números com que ficaram registadas
(20261101230323, 20261101230359, 20261101230415). O que se segue fica como história do que eram.

1. `PROPOSTA_20261101_suspensao_temporaria_estafeta_expira_e_guarda_pedido.sql` — a mais
   importante (o revisor marcou ALTA): quando acaba uma suspensão com data de um estafeta, o
   servidor avisa "já podes ficar online" mas ele continua bloqueado para sempre. Enquanto não for
   aplicada, o painel deixou de oferecer suspensão com data a estafetas (só sem data, e reativar em
   Revisões). Também faz a guarda "não suspender a meio de uma entrega" encontrar todos os pedidos.
2. `PROPOSTA_20261101_suspensao_motivo_papel_e_fecho_ao_reativar.sql` — "Papéis da pessoa →
   desligar limpeza/lavagem" está partido no servidor desde a trava de 01/11 (recusa por falta de
   motivo). Até lá usar "Suspender com motivo" na ficha. Também fecha o registo de suspensão
   quando se reativa por botões antigos.
3. `PROPOSTA_20261101_assistente_aprendidas_auditoria_e_serie_proxima_guarda.sql` — risco baixo:
   auditoria de ligar/desligar "Aprendidas" e a próxima data da série só para quem é da série.

E a tranca do repositório não deixou mexer em `lib/stores/order_store.dart` (tem o
`finalizePurchase`); o online do estafeta foi feito no `DriverStore`, sem mexer nesse ficheiro.

## Provas

- e2e_log, fluxo `app-fechar-2026-11-01`: arranque 6032; C1/C3 6034; notify-handyman 6035; testes
  completos 6071; e os passos de cada bloco entre eles.
- Migrações aplicadas e registadas em `schema_migrations`: 20261101231000 (Casa C1/C3),
  20261101231500 (série parada), 20261101232000 (texto do peso), 20261101233500 (convite da Casa).
- `flutter analyze` com o Flutter do servidor de build (3.41.2): 0 erros; os 6 avisos e 260 notas
  já existiam; nenhum em linhas desta missão.
- `flutter test` com o mesmo Flutter: 258 ficheiros, 2847 casos, 0 falhas. Depois das correções
  do revisor, 41 ficheiros / 500 casos outra vez verdes.
- Juiz anti-trapaça (`--base HEAD`): um só aviso, legítimo (o painel da Casa passou de 8 para 9
  separadores com "Ofertas").
- Revisor independente (contexto limpo): 7 pontos; os 3 da app corrigidos, os 2 do servidor em
  proposta (acima), 1 informação (uma barbearia aprovada tem a loja desligada pelo painel: vai ver
  o ecrã "loja desligada" com o botão "Entrar no painel na mesma" — confirmar se foi de propósito).
- Web em produção como visitante: capturas em `.claude/.ai/provas/app-fechar-2026-11-01/`.

## Erros encontrados pelo caminho (reportados; os que não são dinheiro já corrigidos)

- Corrigidos: "ficar online" com o id errado; fotos do assistente PNG marcadas como JPEG; horas no
  fuso do telemóvel no histórico do robô, na agenda e na lista da limpeza; botões mudos na Casa;
  corrida no arranque que podia apagar o modo visitante; fila de botões que transbordava no ecrã
  de suspensão; "Desativar loja" e o interruptor das barbearias que o gatilho novo recusava.
- Por corrigir (servidor): a série de limpeza que já morreu antes do conserto não recomeça
  sozinha; `robot_apply_suggestion` pode banir sem motivo de 10 letras (por rever); em
  `order_purchase_items_v2` os ids de catálogo de texto ficam vazios (não afeta o peso).
- Melancia Riscada e melões do Continente com preço de balança (sem preço do quilo real).

## Publicação — as 3

Envio `1a946c67..280e50db` no ramo de produção (108 ficheiros, juntados por caminho; sem marca de
saltar o build).
- Web: build 41359440785 verde às 22:57; `app.boraguarda.com/versao.json` mostra o commit
  `280e50db` (run 251).
- Android: build 41359440799 verde às 23:38; versão 704 (commit automático "bump versionCode to 704"
  às 23:29); `app_latest_version_code` = 704, que só se grava depois de o Play receber o pacote.
- iPhone: build 41359440800 verde; versão 1.0.34, build 222, submetida à Apple a 02/11 às 00:48,
  estado "à espera de revisão", lançamento automático depois de aprovada;
  `app_latest_version_code_ios` = 222.
- O "olho" dos ecrãs (olho-golden) também verde.

Verificação dos consertos nas 3: o caminho do visitante foi provado na web em produção às 21:50
(versão anterior, mesmo código até ao ecrã de entrar). Às 23h, na versão nova, todas as lojas
estavam fechadas e o carrinho não aceita produtos, por isso a repetição fica para amanhã com uma
loja aberta. Android e iPhone: provados pelos testes de ecrã (o do visitante corre o carrinho
verdadeiro) e pelo autoteste do simulador do iPhone (verde); não houve emulador nem iPhone físico
nesta sessão.

## Comandos finais

`/ctx doctor` e `/ctx stats` corridos no fim da sessão.
