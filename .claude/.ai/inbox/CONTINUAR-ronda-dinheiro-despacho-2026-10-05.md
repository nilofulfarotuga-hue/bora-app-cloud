# CONTINUAR — ronda-dinheiro-despacho-2026-10-05

Relatório: `.claude/.ai/reports/2026-10-05-ronda-dinheiro-despacho.md` (reescrito ao meio-dia de
05/10 com o estado real; a versão da manhã dizia que o envio e o motor estavam parados).

## 0. Estado ao meio-dia de 05/10

- **Publicado:** `5efd2d96` (código) + `d5e2d027` (relatório), dentro do ramo de produção desde
  as 08h15 (merge `9fe6b9f8`, depois do "Empurra" do Danilo). Web no ar (corridas #189–#191),
  Android **versionCode 649** (corrida #497; `platform_settings.app_latest_version_code = 649`;
  commit `8d15f259`), iOS #161, #162 e #163 entregues à Apple (a #163 é do mesmo commit que
  publicou o Android).
- **Motor de despacho v62: no ar** desde as 09h10, publicado por outra sessão do PC (commit
  `8108952c`, digest `digest-2026-10-05-v62-favor-push`) com o ficheiro gerado nesta missão.
- **Favor (dinheiro da paragem):** feito por essa mesma sessão
  (`estafeta_registar_dinheiro_paragem`).
- **Blocos A, B e C da ronda** (dinheiro das entregas, dinheiro do painel, 169 funções fechadas
  a anon): feitos por outra sessão (digest `digest-2026-10-05-ronda-auditoria-04-10-pc`).

## 0.1 Noite de 05/10 (missão `fecho-home-dinheiro-2026-10-05`)

**O ponto 1 está FEITO.** Os dois commits foram juntados em cima de `aedb956b` sem conflitos
(`c541de97` → `311f8371`, `e5db74a6` → `c4f69adb`) e enviados às 21h29 com `744fe903`
(esqueleto da home que derrubava Android #498/#499 e iOS #165). Relatório da noite:
`.claude/.ai/reports/2026-10-05-fecho-home-dinheiro.md`. O ponto 2 (armadilha do relógio)
deixou de derrubar o autoteste: o auxiliar novo aceita loja fechada e salta o pagamento — mas a
app continua a decidir pela hora do aparelho (ponto 5, à espera do sim do Danilo).

## 1. (FEITO a 05/10 às 21h29) publicar a correcção da loja fechada

Commit `c541de97` (em cima de `6c86177d`). Está no ramo local `ronda-dinheiro-despacho-05-10`
(pasta `C:/BoraLocal/wt-ronda-05-10`), com o commit de documentos desta missão por cima, e
sozinho no ramo `ficha-loja-fechada-05-10` (pasta `C:/BoraLocal/wt-ficha-05-10`).
Cinco ficheiros da app (`product_detail_screen`, `store_products_screen`, `orders_screen`,
`market_reorder_tab`, `reorder_service`), o autoteste (`integration_test/demo_real_test.dart`,
auxiliar `_tocarEVigiar`), `test/loja_fechada_ficha_e_repetir_test.dart` (16 testes) e a
cicatriz em `PADRAO_BORA.md` §1.27. Não toca em zonas protegidas.

Os defeitos: com a loja fechada, a ficha do produto dizia "adicionado ao carrinho" e fechava-se
sem adicionar nada; o "+" e a linha das variantes diziam "no carrinho"; o "Pedir de novo" de
dentro da loja enchia o carrinho de uma loja fechada; o "Pedir de novo" da lista de pedidos
(saído a 04/10, commit `2adfca36`) procurava a loja só entre as parceiras — respondia "Esta loja
já não está disponível na Bora" a 20 dos 25 pedidos entregues repetíveis; e o `applyTo` repetia
os menus sem as escolhas do cliente (`selectedOptions`).

Como publicar, quando o Danilo disser: na pasta `C:/BoraLocal/wt-ronda-05-10`, `git fetch` e
pôr os dois commits em cima da cabeça do ramo de produção (rebase: às 14h00 de 05/10 o remoto
já tinha avançado um commit, `f8366def`, só em `supabase/functions`, sem cruzar com estes
ficheiros), correr `flutter test test/loja_fechada_ficha_e_repetir_test.dart`, empurrar
`HEAD:autonomous-night-2026-04-29` fora de hh:05–09 e **depois das 10h de Lisboa** (ver ponto 2),
e seguir a corrida mais nova do ramo com `.claude/.ai/provas/ronda-05-10/estado_ci.mjs`. O commit
de documentos de cima **não** leva `[skip ci]` (senão salta o build da correcção). Prova de
publicação no Android: `platform_settings.app_latest_version_code` sobe de 649 e aparece o
commit "ci: bump versionCode". Na web não há texto novo para procurar no `main.dart.js` (o
aviso já existia e os nomes das funções não sobrevivem à minificação): a prova é a corrida
"Build & Deploy Web" verde para o commit empurrado.

**O autoteste alterado só se prova no CI** (não há emulador no PC): na primeira corrida depois
do envio, ler o job "Autoteste 3 perfis". Se falhar por causa do auxiliar novo, o arranjo
rápido é repor as duas chamadas antigas (`_tocar` seguido de `_bombear`) nos dois toques.

## 2. Armadilha do autoteste Android (até o ponto 1 estar publicado)

O emulador do CI anda em UTC e a Auchan abre às 09h00: de verão, um envio entre as 08h e as 10h
de Lisboa falha o autoteste em `não apareceu: botao-ver-carrinho`. Não é regressão: relançar os
jobs falhados depois das 10h (`relancar_ci.mjs <run_id>`). As linhas que o provam
(`[arnes] … sao HH:MM no simulador`, `CartStore.addItem: BLOQUEADO`) só estão no
`autoteste.log` do artefacto da corrida, não no registo do job.

## 3. Ver o motor v62 com o primeiro pedido verdadeiro

A 05/10 até às 11h50 não entrou nenhum pedido. Quando entrar, nos registos da função
`dispatch-engine`: esperar `v62 INVOKED`, `[dispatch] N candidatos (de M, excl K)` e `SUCCESS`.
Desconfiar de `v62 403 motivo=papel_sem_permissao` ou `jwt_invalido` vindos da app (seria um
chamador legítimo recusado) e de `dispatch_candidatos_entrega error`. Voltar atrás = publicar a
v61, que é `git show 9fe6b9f8:supabase/functions/dispatch-engine/index.ts` (o diff para a v62
está em `.claude/.ai/missoes/ronda-04-10/pronto/dispatch-engine-v62/v61-para-v62.diff`); a pasta
do motor está trancada, por isso é o Danilo que manda.

## 4. Fecho do "parceiro chama estafeta" — missão própria, depois ligar o interruptor

Análise e números em `pronto/LEIA.md` §4. Funções a tratar: `post_order_to_ledger`,
`apply_order_financial_split`, `order_driver_reimbursement` / `apply_driver_cash_settlement`,
extractos do parceiro e fecho semanal. Provar em transacção desfeita com um pedido de 10 € de
balcão (certo: loja deve 4,00 à Bora, estafeta recebe 4,00, Bora 0).
Só depois: `dispatch_parceiro_chama_estafeta_ligado = true` (painel, Configurações → dispatch).

## 5. Achados novos de 05/10 (lidos no código, não reproduzidos)

- **Loja aberta por link partilhado** (`DeepLinkStoreScreen` → `MarketStoreScreen`, URLs
  `#/loja/{id}` do site, QR e WhatsApp): não chama `CartStore.configureSession`. Só
  `restaurants_screen`, `stores_screen` e `ReorderService.applyTo` o fazem. Quem chega por link
  enche um carrinho que não está ligado àquela loja (nome, id, morada de recolha e marca de
  fechada ficam os da sessão anterior, ou vazios). Confirmar ao vivo e corrigir: a porta do link
  tem de fazer o mesmo que `openRetailBusiness`.
- **(FEITO a 06/10, missão `hora-lisboa-2026-10-06`, commits `af8838f3` + `a1aa5594`, Android
  652 / web #196 / iPhone 1.0.12 build 168 no TestFlight — relatório
  `.claude/.ai/reports/2026-10-06-hora-lisboa.md`.)**
  **Relógio do aparelho (gémeos por unificar, registado no PADRAO §1.27):**
  `RestaurantModel.isOpenNow`, `statusLabel` e `avisoLojaFechada` usam a hora do telemóvel; o
  servidor (`is_partner_open`) usa `Europe/Lisbon`. Num aparelho noutro fuso divergem uma hora:
  a app deixa encher o carrinho e o servidor recusa (`STORE_CLOSED`), ou o contrário. Receita:
  passar o "agora" por `horaLisboa()` (`lib/utils/hora_lisboa.dart`) nesses três sítios, com
  testes por instante UTC. Muda a conta para todos os aparelhos → à espera do sim do Danilo.
- **Lojas desligadas:** Lidl, Mercadona e Pizza Hut têm `is_online = false`. A app trata-as
  como fechadas a qualquer hora e o aviso diz "está fechada agora. Abre às HHhMM" mesmo à tarde
  (o servidor não olha a `is_online`). Confirmar com o Danilo se é de propósito.
- **Restos do travão da loja fechada (não bloqueiam; o servidor apanha no fim):** a marca
  `_vendorFechada` é uma fotografia tirada à porta e não é gravada com o carrinho; o "+" do
  ecrã do carrinho (`increaseQuantity`) não a vê; a regra "fechada" vive em três sítios
  (`restaurants_screen`, `stores_screen`, `ReorderService.lojaFechada`) e a dos mercados não
  tem a excepção das Festas; na ficha o botão continua com aspecto activo (os cartões ficam
  cinzentos).
- **Restos do "Pedir de novo" (da segunda passagem do revisor):** no separador da loja o
  `applyTo` ainda recebe `restaurantStore: null` para não-parceiras, por isso o
  `vendorRestaurantId` fica vazio e a taxa de pedido pequeno própria da loja não carrega antes
  do orçamento do servidor; na lista de pedidos, sem rede, a lista de lojas fica vazia e a
  mensagem é "Esta loja já não está disponível" (devia dizer que não há ligação); não há teste
  que monte os dois ecrãs (precisam de `OrderStore` e `AuthStore`).
- **Autoteste, sugestão do revisor:** a captura `zz-loja-fechada-sem-carrinho` não conta como
  falha suave (o `tool/ci/autoteste_emulador.sh` só conta nomes com "falha"). Se um defeito
  deixar a marca de fechada presa, o teste fica verde e salta o pagamento sem ninguém ver.

## 6. Restos pequenos (ver `pronto/LEIA.md` §2, §3 e §5)

- `pricing_service.dart`: só arrumação do valor de reserva (2,50 → 0,99).
- Festas: o orçamento conta o saco (`festas_money_patch` por aplicar desde 25/08).
- "Deixar à porta" + dinheiro: guarda no servidor para pedidos forjados.
- Rascunhos de pagamento: tirar o botão de excluir ou dar-lhe função própria.
- Sinal com segredo: exigir `is_online`.
- Carrinho abandonado: decidir se o aviso respeita "só quem aceitou promoções" antes de ligar.
- `_notify_partner_status_change` chama o `notify-partner` com a chave pública → 403.
- `log_admin_action` aceita qualquer utilizador autenticado.
- Apagar os dois ecrãs mortos do parceiro (`restaurant_dashboard_screen.dart`,
  `partner_reservations_screen.dart`) e fechar as 2 linhas antigas de `cortex_red_proposals`.
- O push `carrinho_abandonado` devia abrir o carrinho ao tocar.
- Continente tem uma categoria chamada "Undefined".

## 7. Só se prova no aparelho

- Estafeta com a app em segundo plano: o sinal continua a bater (com segredo; e com o caminho
  antigo se o segredo falhar) — ver `drivers.last_heartbeat_at` e
  `driver_heartbeat_segredos.usado_em`.
- Cliente: "Deixar à porta" com cartão e MB Way ponta a ponta; o estafeta vê o aviso e a foto
  fica gravada.

## 8. Handoff para o Cérebro

Entregue ao `bibliotecario-cerebro` a 05/10 às 12h50: os seis blocos de baixo ficaram gravados
(quatro lições novas em `permanente/procedural/licoes/` e as entradas #25 e #26 de
`permanente/episodica/bugs-resolvidos.md`). O bloco 2 não entrou em `zonas-protegidas.md`
(página vermelha, só muda com o sim do Danilo): ficou como lição própria. A entrada #26 diz
"por commitar e por publicar": **reentregar com o commit e o versionCode quando a correcção da
loja fechada sair.** Avisos dele: `bugs-resolvidos.md` está com 21 KB (a próxima entrada obriga a
parti-lo) e `permanente/semantica/loops.md` está com 29,7 KB, acima do limite, desde 13/07.

```
HANDOFF → bibliotecario-cerebro
tipo: licao
escopo: projeto
tema-alvo: permanente/procedural/licoes/licao-skip-ci-no-commit-de-cima.md
conteudo: A marca [skip ci] no commit de CIMA de um push salta o build do push inteiro,
  mesmo que os commits de baixo tragam código. A 05/10/2026 o commit do relatório ia
  com a marca por cima do commit de código 5efd2d96; foi corrigido antes de empurrar.
  Só se põe a marca quando TODOS os commits do push são só-documentos.
```

```
HANDOFF → bibliotecario-cerebro
tipo: facto
escopo: projeto
tema-alvo: permanente/semantica/zonas-protegidas.md
conteudo: O "autorizo tudo" do Danilo é a ordem, não a chave. A 05/10/2026, com essa
  ordem dada na conversa, a Trava do PC continuou a proibir editar e publicar o
  dispatch-engine e editar pricing_service.dart (já tinha sido assim a 08/09), e o
  git push para produção foi recusado pelo classificador do Claude Code (como a 04/10)
  até o Danilo escrever "Empurra". O que se faz: tudo o que não está trancado, o resto
  pronto em .claude/.ai/missoes/<ronda>/pronto/ com prova, e a palavra pedida uma vez.
```

```
HANDOFF → bibliotecario-cerebro
tipo: bug
escopo: projeto
tema-alvo: permanente/episodica/bugs-resolvidos.md
conteudo: (ABERTO) "Parceiro chama estafeta" — post_order_to_ledger e
  apply_order_financial_split lançam o pedido como pedido normal de parceiro em dinheiro;
  as regras 2.4.1 dizem que o estafeta paga o total à loja. 10 € de balcão: loja +12,57 a
  mais, estafeta −10. Interruptor dispatch_parceiro_chama_estafeta_ligado=false desde
  05/10/2026 (migração 20261005061548). Zero pedidos existiam.
```

```
HANDOFF → bibliotecario-cerebro
tipo: licao
escopo: projeto
tema-alvo: permanente/procedural/licoes/licao-apagar-sem-politica-devolve-204.md
conteudo: Um DELETE pelo PostgREST numa tabela com RLS e sem política de apagar devolve
  204 e apaga ZERO linhas, sem erro. O painel "apagava" rascunhos de pagamento há meses
  sem apagar nenhum (payment_drafts só tem política de leitura; medido a 05/10/2026).
  Pedir sempre de volta o que saiu (.select('id')) antes de dizer "apagado" ou registar
  na auditoria.
```

```
HANDOFF → bibliotecario-cerebro
tipo: licao
escopo: projeto
tema-alvo: permanente/procedural/licoes/licao-autoteste-android-relogio-utc.md
conteudo: O emulador do autoteste do CI anda em UTC e a app decide "loja aberta" pelo
  relógio do aparelho. De verão, entre as 08h e as 10h de Lisboa a Auchan (abre às 09h00)
  está fechada no emulador e o teste falha em "não apareceu: botao-ver-carrinho". Medido
  a 05/10/2026: corrida #495 falhou às 07:15 e às 08:16 UTC, a #497 passou às 09:30 UTC
  sem mudar código. A prova está no autoteste.log do artefacto ([arnes] sao HH:MM no
  simulador; CartStore.addItem: BLOQUEADO), não no registo do job.
```

```
HANDOFF → bibliotecario-cerebro
tipo: bug
escopo: projeto
tema-alvo: permanente/episodica/bugs-resolvidos.md
conteudo: (CORRIGIDO NO RAMO LOCAL ficha-loja-fechada-05-10, POR PUBLICAR a 05/10/2026)
  Com a loja fechada, a ficha do produto (product_detail_screen.dart) dizia "adicionado ao
  carrinho" e fechava-se sem adicionar: CartStore.addItem recusa em silêncio quando
  _vendorFechada. O mesmo no "+" de store_products_screen (_QtyButton) e no "Pedir de
  novo" (ReorderService.applyTo reconfigura a sessão sem a marca de fechada). Regra
  1.27 do PADRAO: o travão ao meter no carrinho tem de se ver em TODOS os botões de
  adicionar, não só nos cartões.
```
