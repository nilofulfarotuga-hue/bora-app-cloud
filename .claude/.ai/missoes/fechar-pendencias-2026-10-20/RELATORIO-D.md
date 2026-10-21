# Bloco D — prémios dos marcos do check-in — relatório (21/10/2026)

Agente-checkin, motor Opus. Ramo `checkin-20-10` (worktree `C:\BoraLocal\wt-checkin-20-10`), **sem push**.
RAM medida: 2623 MB disponíveis no arranque (trabalho de SQL e ficheiros, portão 400 MB) e 3111 MB antes do
`flutter analyze`/`flutter test` (portão 800 MB). Nenhum emulador.

## Primeiro, o que NÃO ficou feito

1. **Os marcos estão no servidor mas DESLIGADOS** (`checkin_marco_ativo = false`), e o robô de suporte que os
   explica também (`active = false`). Ligam-se depois de a versão nova da app estar nas 3 lojas (Bloco F). Sem
   isso, quem chegasse aos 10 dias recebia um aviso para um ecrã que a app instalada ainda não tem.
2. **A loja ainda não recebe o prémio no acerto semanal sozinha.** O prémio entra no pedido como um artigo a
   0,00 €, por isso o acerto automático da Keli e do Goola não o conta. A parte que faz isso escreve em
   `ledger_entries` e a bora-tranca recusa (com razão: é dinheiro). Ficou pronta como proposta
   (`d/pronto/proposta-loja-recebe-premio-no-acerto.md`). Até ao teu "vai", a Bora paga os prémios às lojas
   pela lista **"A pagar às lojas"** do painel, com o botão "Marcar como pago".
3. A prova dessa proposta não correu dentro da base (a tranca não deixa escrever no ledger nem numa prova
   desfeita). Ficou provada a conta (venda normal 5,40 € = custo do vale) e o guião para correr logo a seguir
   ao "vai".
4. O toque na notificação do prémio abre a app (página inicial, onde o cartão do check-in mostra o prémio),
   não abre direto "Os meus prémios".
5. Não publiquei nem fiz push (é do Bloco F, depois do revisor). Não escrevi no Córtex: o conector `cortex`
   desta sessão pede nova autorização.

## O que ficou feito

**Os marcos.** O servidor conta os dias seguidos de check-in (a mesma tabela `daily_checkins`). Aos 10 dias
nasce o vale dos 2 salgados da Keli, aos 15 o do açaí do Goola, aos 30 o da limpeza de 2 horas ou lavagem
exterior. O 7 é o que já existia (os 40 tokens do Dia 7) e só se mostra. Falhou um dia, volta ao dia 1 e os
marcos recomeçam; depois do dia 30 recomeça no 1. Os tokens da semana (5, 5, 10, 10, 15, 15, 40) não mudaram:
a função que dá os tokens não foi tocada. Um vale por marco por sequência, vale 30 dias, é só da própria
pessoa, e só ganha quem tem o telemóvel confirmado (o mesmo teste do check-in: número português válido na
ficha — não existe confirmação por SMS na Bora).

**As duas regras extra, ligadas e com interruptor no painel.** Tecto de 10 vales de 30 dias por mês: quem
chega depois fica com o vale "guardado" e recebe-o no dia 1 do mês seguinte, com aviso claro. E o vale dos 30
dias pede pelo menos 1 pedido pago nos últimos 30 dias: sem pedido, o ecrã diz "Falta 1 pedido para
desbloquear o prémio" e o vale espera 30 dias; assim que há um pedido entregue e pago, a tarefa de hora a hora
liberta-o sozinha.

**Como se usa (padrão dos grandes).** Ao chegar ao marco: aviso no sino, notificação no telemóvel e confete no
cartão do check-in, com a faixa "Ganhaste 2 salgados da Keli!". O vale fica em **"Os meus prémios"** (no
perfil e pela seta do cartão). "Usar" abre a loja certa e a ficha do prémio: na Keli escolhe-se o sabor de
cada salgado (coxinha ou esfirra), no Goola os 3 acompanhamentos (e os extras pagos à parte, se quiser). O
prémio entra no carrinho a 0,00 €, numa linha só, sem "+". No carrinho da loja certa aparece também
"Tens um prémio para esta loja — Aplicar". Tirar o prémio do carrinho devolve o vale. O vale só fica "usado"
quando o pedido nasce, e o servidor recusa o artigo a 0 € a quem não tem vale. Pedido cancelado ou rejeitado:
o vale volta.

**Os 30 dias.** "Escolher" → limpeza de 2 horas em casa (marca-se com 12 h de antecedência, como sempre) ou
lavagem exterior do carro. A marcação nasce com o pagamento "prémio": o cliente não paga nada e a
limpadora/lavador recebem o ganho normal no acerto da semana (o acerto já paga tudo o que não é dinheiro).
Cancelar devolve o vale.

**O ecrã do check-in.** A semana fica igual. Uma seta (só aparece com os marcos ligados) abre a vista do mês com
o teu texto tal e qual, "Estás no dia X de 30", os 4 marcos com o que se ganha e quantos dias faltam, e o
botão "Os meus prémios". PT-PT, com inglês à mão (75 frases).

**Lembretes 11h e 20h.** Passam a dizer quanto falta quando faltam até 3 dias, por exemplo: "Ontem fizeste o
dia 1 do check-in. O de hoje vale 5 tokens! Faltam 2 dias para ganhares 2 salgados da Keli." Na véspera do
marco: "… Faz o check-in de hoje e ganhas 2 salgados da Keli!". Com os marcos desligados o texto é igual ao de
antes (provado). As duas tarefas correram às 06:02 e 06:17 de Lisboa depois da mudança: "succeeded".

**Painel admin (PT-BR).** Clientes → Check-in diário → ícone do troféu (e no menu "Prêmios do check-in
(marcos)"): interruptores (marcos, teto, pedido pago), validade, ciclo, e por marco o dia, título, descrição,
valor e custo (tudo em `platform_settings`, prefixo `checkin_marco_`); resumo por estado e por marco; custo do
mês e total; "A pagar às lojas" com marcar pago; lista de vales com filtro, anular, entregue à mão, dar vale à
mão e exportar CSV. Tudo fica no registo (`admin_audit_log`). Limpeza e lavagem mostram o pagamento
"Prêmio do check-in (Bora paga)".

**Robô de suporte.** Skill `CHECKIN_MARCOS_PREMIOS` (só informação, `validate_skill.py` exit 0), desligada até
ligares os marcos.

## O desenho, e porquê

- **Vale = artigo-prémio a 0 € na loja certa** (`premio-checkin-salgados`, `premio-checkin-acai`), escondido do
  menu e da loja por uma política restritiva (cliente, loja e visitante veem 0; o servidor vê 2). Escolhi este
  caminho porque é o único que não reescreve nenhuma função de dinheiro: o pedido é um pedido normal, com o
  preço certo do princípio ao fim, e o estafeta, o cartão, o MB Way e o dinheiro acertam sozinhos. O outro
  caminho (desconto no fim, como o crédito de reservas) obrigava a mexer em 3 funções do acerto do estafeta e na
  Edge do cartão, porque o estafeta ficava a dever o desconto e o cartão cobrava antes do desconto.
- **O vale confirma-se num gatilho em `orders`** que só corre quando o pedido traz um artigo-prémio, não toca em
  nenhuma coluna do pedido e só escreve na tabela dos vales.
- **30 dias com pagamento 'premio'**: reaproveita as funções de marcar limpeza e lavagem (orçamento, regras,
  ofertas), sem mexer em nenhuma; o acerto da limpadora e do lavador já paga o que não é dinheiro.
- **Custo de cada vale em `checkin_premios_vales`** (valor para o cliente, custo para a Bora, loja, pedido ou
  marcação, datas, estado, pago à loja).

## A conta linha a linha (prova em transação desfeita, pedido demo em dinheiro)

| Linha | Pedido com o prémio (Sabores do Brasil) | O mesmo pedido a pagar |
|---|---|---|
| 2 Salgados Grandes | 0,00 € (vale −6,30 €) | 6,30 € |
| Taxa de serviço (parceiro, 5 %) | 0,00 € | 0,32 € |
| Entrega (até 4 km) | 2,50 € | 2,50 € |
| Pedido pequeno | 0,00 € (lojas parceiras não têm) | 0,00 € |
| **Total do pedido** | **2,50 €** | **9,12 €** |
| Ganho do estafeta | 4,00 € | 4,00 € |
| A loja recebe (venda normal) | 5,40 € pela lista "A pagar às lojas" (ou no acerto, com a proposta) | 5,40 € no acerto |

Goola com o vale: Goola Bowl 0,00 € + extra Oreo 1,17 € + taxa de serviço 0,06 € + entrega 2,50 € = **4,03 €**.
O Goola recebe 7,90 € (preço de balcão) pelo bowl.

Atenção a um erro antigo que apareceu na prova (não é do prémio): na Sabores do Brasil o valor a cobrar em
dinheiro sai **0,30 € acima do total** (2,80 € em vez de 2,50 €; no pedido normal 9,42 € em vez de 9,12 €),
porque o saco é tirado do total mas não do valor a cobrar. Reportado; não corrigido (é a função que cobra).

## Migrações aplicadas (texto igual no repo, md5 do texto aplicado = md5 do ficheiro)

| Versão | Nome | md5 |
|---|---|---|
| 20261021045300 | d_checkin_marcos_1_tabela_e_sequencia | 7645005c6ad8d362ee54033fb5f92bbb |
| 20261021045356 | d_checkin_marcos_2_regras_e_emissao | e71abafab9f1c66394dc0f43d60559e1 |
| 20261021045435 | d_checkin_marcos_3_cliente | e44dd6e0f8b29414ed75a10a4166bd94 |
| 20261021045533 | d_checkin_marcos_4_manutencao_e_painel | a948fe41ca9e1ba29c9c4c2654f804b2 |
| 20261021045552 | d_checkin_marcos_5_definicoes | 357ee9bfd68c3b11aa06dce79c415a5a |
| 20261021045607 | d_checkin_marcos_6_artigos_premio | 25919b74d557fb4420dcf788e37864eb |
| 20261021045621 | d_checkin_marcos_7_vale_no_pedido | 927036b0b4788b81c3e84c6d08a17b71 |
| 20261021045650 | d_checkin_marcos_8_lembretes | b939645fe1bd822d441ee713becbccde |
| 20261021050439 | d_checkin_marcos_9_pagamento_premio_nas_marcacoes | ef99068284515a515e6b84fa88d54a65 |
| 20261021050504 | d_checkin_marcos_10_limpeza_e_lavagem | c1cc5c90c9980bf109d2ce2e29b984b8 |
| 20261021050727 | d_checkin_marcos_11_robo_suporte | 73869c0c22b85c5a8b37d8267aaecc75 |

Ordem, e porquê: a Trava não deixa provar numa só instrução um gatilho novo de `orders` e chamar a função que
cria pedidos; e a tranca já não deixa inserir pedidos à mão. Por isso apliquei as peças que não mexem em
dinheiro de ninguém **com tudo desligado** (sem vales não há artigo a 0 € para ninguém), e logo a seguir fiz as
provas em transação desfeita, com o interruptor ligado só dentro da transação. A parte da limpeza e lavagem foi
provada antes de aplicar (criada dentro da transação).

Reversão: `d/reversao-bloco-d.sql` (passo 0 só desliga; o passo 1 desfaz tudo e guarda os vales numa cópia
`bkp_checkin_premios_vales_20261021` antes).

Fiscal de segurança: a tabela nova tem RLS ligada e só leitura do próprio ou do admin; ninguém sem sessão a lê
(`has_table_privilege` anon = false) e nenhum cliente escreve nela (update = false); as funções internas não se
chamam de fora (`has_function_privilege` authenticated = false); as do cliente e do painel não se chamam sem
sessão (anon = false) e as do painel recusam quem não é admin (42501). O aviso do Supabase só lista o que é de
propósito (funções com sessão que verificam quem chama, como as do check-in de 13/10).

## Provas (saídas literais em `d/prova_rollback_resultado.txt`)

- Dia 10 → vale dos salgados por usar, 630/540 cêntimos, 30 dias, aviso no sino e 1 notificação na fila
  (desfeita); toque repetido 0 tokens e nenhum vale a mais.
- Dia 15 → vale do açaí (922/790). Falhou ontem → dia 1, nenhum vale. Dia 31 = dia 1 do ciclo 2; ao dia 40 nasce
  outro vale dos salgados. Sem telemóvel → 0 vales.
- Dia 30 sem pedido → "a espera de pedido" 30 dias; com o pedido demo entregue e pago → liberta (até 20/11).
  Tecto 1 → o segundo fica "guardado até 01/11"; com lugar → sai.
- Pedido demo em dinheiro: a tabela acima; segundo pedido com o mesmo prémio → recusado; pedido do açaí
  cancelado pelo admin → o vale volta.
- Limpeza 2 h: 24,00 € de serviço, a limpadora ganha 20,40 € e o acerto dela sobe 20,40 € a pagar, 0 de dívida.
  Lavagem exterior: 12,00 €, o lavador 10,20 €, acerto +10,20 €.
- Depois das provas: 0 vales, marcos desligados, 0 pedidos com prémio, horário das lojas igual.

App: `flutter analyze` sem erros e sem avisos nos ficheiros novos (os 264 avisos do projeto são antigos);
`flutter test` verde em `checkin_premios_test.dart` (11), `checkin_premios_ecras_test.dart` (6),
`golden/checkin_diario_card_test.dart` (24), `l10n_cobertura_test.dart` (13), `carrinho_um_so_total_test.dart`
(20), `maiores_18_test.dart` (8), `loja_fechada_test.dart` (8). Anti-trapaça (base
`origin/autonomous-night-2026-04-29`): CLEAN, exit 0, +19 casos de teste; zonas protegidas: CLEAN.
Commits: `09c42742` (servidor), `2721a067` (app), `6c4ac397` (painel), mais este relatório.

## ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

**Aplicado nesta missão (autorizado a 20/10, tudo desligado até publicar):** a tabela dos vales; os 2 artigos a
0 € com as opções; o gatilho que confirma o vale no pedido; o pagamento "prémio" nas marcações de limpeza e
lavagem (o prestador recebe o ganho normal, a Bora absorve); as definições `checkin_marco_*`; a lista
"A pagar às lojas" no painel. Reverte-se com `d/reversao-bloco-d.sql` (ou só desligar: passo 0).

**Por aplicar (precisa do teu "vai"):** `d/pronto/proposta-loja-recebe-premio-no-acerto.md` — a loja recebe o
prémio no acerto semanal sozinha (linha de ganho no ledger). Sem isto, a Bora paga às lojas pela lista do painel.

## PARA O DANILO

1. **Taxa de serviço no prémio.** Escolhi a da Uber Eats e da Glovo para "artigo grátis": a taxa de serviço
   calcula-se sobre o que o cliente paga, e o prémio conta 0. Na Keli o cliente não paga os 0,32 € (5 % de
   6,30 €); no Goola não paga 0,46 €. Se quiseres cobrar a taxa sobre o preço normal, é uma mudança na função
   que cobra (zona protegida): diz e eu preparo.
2. **Pedido mínimo.** As duas lojas são parceiras, por isso não têm pedido mínimo nem taxa de pedido pequeno: o
   prémio pode ser pedido sozinho, a pagar só a entrega (2,50 € até 4 km).
3. **Quanto recebe a Keli.** Pus "como venda normal": 5,40 € pelos 2 salgados (6,00 € de balcão menos os 10 %
   de comissão dela). Se quiseres que receba os 6,00 € inteiros nos prémios, muda-se o custo no painel para
   600. O Goola recebe o balcão inteiro (7,90 €), como em qualquer venda.
4. **Qual salgado.** Usei o "Salgados Grandes" (3,15 € na app) e a escolha coxinha/esfirra para cada um. A
   esfirra não está no menu da Keli: confirma com ela que faz. Alternativa: a Coxinha com Catupiri (3,68 €).
5. **Pagar às lojas.** Enquanto não disseres "vai" à proposta, pagas os prémios às lojas pela lista "A pagar às
   lojas" (Clientes → Check-in diário → troféu).
6. **Ligar os marcos.** Depois de a app sair nas 3 lojas: `checkin_marco_ativo` no painel (e o robô
   `CHECKIN_MARCOS_PREMIOS`). Quem já estiver a meio da sequência nesse dia começa a ganhar os marcos que
   vierem a seguir; um marco que tenha passado com os marcos desligados não se dá para trás (dá-se à mão no
   painel, se quiseres).
7. **Limpeza de prémio.** São 2 horas com os produtos da casa (sem os 3 € dos produtos da profissional). Se o
   cliente cancelar, o vale volta, mesmo em cima da hora.
8. **Erros antigos que encontrei (não corrigi, mexem na função que cobra):** (a) na Sabores do Brasil o valor a
   cobrar em dinheiro sai 0,30 € acima do total (o saco); (b) desde 14/10, num pedido em dinheiro pago em parte
   com tokens, o acerto do estafeta conta o total inteiro como recebido, e o estafeta fica a dever o que o
   cliente não lhe deu. Ainda não aconteceu a ninguém. Os dois estão no e2e_log ("D-achados-fora-do-ambito").

Registos: e2e_log fluxo `fechar-pendencias-20-10`, ids 4070 a 4082 (D1 a D9, robô, as duas provas, achados).
