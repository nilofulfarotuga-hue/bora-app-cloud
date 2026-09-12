---
id: e2e-restaurante-2026-07-13
tipo: relatorio
origem: [runner E2E testes-e2e — categoria Restaurante]
ultima_confirmacao: 2026-07-14
zona: verde
confianca: auto
---

# E2E Restaurante — 2026-07-13/14: BLOQUEADO (notification shade), infra pronta

Corrida noturna autónoma da categoria RESTAURANTE em 2 telemóveis físicos
(cliente `RZGYB1XQD2P`, estafeta `N75LTG5X5DSKDMV4`). **Relatório parcial
honesto** — o fluxo Maestro não chegou a criar o pedido; toda a infra ficou
pronta e fica registada para a próxima corrida.

## O que foi investigado e decidido

- **McDonald's não é parceiro.** `restaurants.id='mcdonalds-guarda'` existe,
  mas `is_partner=false` (email `mcdonalds@nonpartner.bora.app` — fixture
  deliberada de não-parceiro). Confirmado por leitura directa da tabela.
- **Só 2 restaurantes parceiros aprovados em todo o sistema**: "Sabores de
  Casa Açaí" (aberto 09:00-22:00 — FECHADO à hora a que este teste corre,
  ~00:56 Lisboa) e "pizza danilo" (`partner-1778337167307322`, horário 24h
  mas estava `is_online=false`).
- **Escolhido "pizza danilo"** como o restaurante do teste (único parceiro
  aprovado utilizável de noite). Liguei `is_online=true` (mesma acção do
  botão ONLINE/OFFLINE do dashboard do parceiro — não é edição de código,
  é o estado que o próprio parceiro definiria) para desbloquear o horário;
  **já revertido para `false`** no fim desta sessão.
- **Itens escolhidos**: "Pizza a" (€13.00) + "Hfjb" (€12.00) + "teste"
  (€0.05) = €25.05 subtotal — produtos reais em `products`, dentro do
  limite de teste (cash, máx €40).
- **Sem 3.º telemóvel de parceiro** (convenção do rig: parceiro = admin/web,
  nunca telemóvel) → construído um passo `script` que invoca
  `partner-simulate-accept-ready.py`, que replica exactamente
  `OrderStore.restaurantAcceptOrder` + `restaurantMarkReady`
  (`lib/stores/order_store.dart`): UPDATE `status` created→preparing→
  callingDriver + invocação da Edge Function `dispatch-engine` (mesma
  chamada que o Flutter faz). Não usa RPC (não existe nenhuma para isto —
  o próprio Flutter só faz UPDATE directo).

## Bug encontrado e corrigido (infra de teste, não app)

**PIN de entrega sempre vazio.** `registry.json` mapeava
`env_de_db: {"PIN": "delivery_code"}`, mas a coluna `orders.delivery_code`
**não existe** (confirmado por leitura de todas as colunas de `orders`).
O PIN real é um *getter* Dart calculado do UUID do pedido
(`OrderModel.deliveryCode`, `lib/models/order_model.dart:673-679` —
"Deterministic — no DB column needed"). Isto afectava também o fluxo
`delivery-mercado-cash` já existente (PIN sempre `""` enviado ao estafeta).
**Corrigido** em `runner.py` (`_delivery_code_from_id`, replica a fórmula
Dart) — passo a passo válido para qualquer corrida futura, incluindo a de
mercado.

## O que travou (bug real, registado — não a app)

O fluxo Maestro no telemóvel **cliente** (`RZGYB1XQD2P`) ficou preso logo
no arranque: `mCurrentFocus=Window{... NotificationShade}` — a gaveta de
notificações do Android abriu por cima da app e nunca mais saiu (Maestro
ficou às voltas nos `extendedWaitUntil` iniciais do `login.yaml`, sem
avançar sequer até ao primeiro milestone "abriu Restaurantes"; confirmado
em `e2e_log`: só 2 entradas, "início do fluxo" + "maestro: iniciou", nenhum
passo depois disso em ~3 min). Tentei 2 fixes rápidos e não-destrutivos —
`adb shell input keyevent KEYCODE_HOME` e `KEYCODE_BACK` — nenhum fechou a
shade (o foco da janela manteve-se em `NotificationShade` após ambos).
Dado o orçamento apertado desta sessão, parei aí em vez de insistir uma
3.ª vez (regra: 2 falhas iguais → mudar de abordagem, não repetir).
Processo Java do Maestro (PID 6988) ficou pendurado sem progresso — morto
manualmente (`taskkill /F`) para não continuar a correr indefinidamente.

**Hipótese da causa raiz** (para a próxima corrida): uma notificação
push chegou ao telemóvel cliente durante o arranque da app (heads-up) e
o systemUI abriu a shade; nada no `login.yaml`/`reset-role-screen.yaml`
dispensa uma shade já aberta (só trata diálogos de permissão in-app). O
`comum/reset-role-screen.yaml` também não cobre este caso.

## Fluxo E2E — passos executados

Só chegou a arrancar o `launchApp` do `login.yaml` no telemóvel cliente;
**0 passos do fluxo de negócio completados** (não chegou a "abriu
Restaurantes"). Nenhum pedido foi criado em `orders` (confirmado — o
pedido de restaurante mais recente na tabela continua a ser de
2026-07-09, sem novas linhas desde o início desta sessão).

## Verificação numérica

**Não aconteceu** — sem pedido criado, não há `orders`/`ledger_entries`
para comparar contra `PricingService.calculateBreakdown`. Fica pendente
para a próxima corrida (infra pronta: subtotal esperado €25.05,
`isPartnerStore=true`, `serviceType=restaurant`, cash).

## Ficheiros criados/alterados

- `flows/cliente/delivery-restaurante-cash.yaml` (novo) — fluxo Maestro
  completo: login → Restaurantes → pizza danilo → ecrã "Entrega" →
  3 itens → carrinho → Dinheiro → confirmar.
- `flows/registry.json` — novo fluxo `delivery-restaurante-cash`
  (`dois_devices:true`), com passo `script` para simular o parceiro.
- `partner-simulate-accept-ready.py` (novo) — simula
  `restaurantAcceptOrder`+`restaurantMarkReady` server-side.
- `runner.py` — adicionado suporte ao passo `tipo:"script"` +
  `_delivery_code_from_id()` (fix do PIN sempre vazio, também beneficia
  `delivery-mercado-cash`).

## Recomendação — próximo passo

1. Antes da próxima corrida: no telemóvel cliente, confirmar a shade
   fechada manualmente ou adicionar ao `login.yaml`/`reset-role-screen.yaml`
   um passo que force `KEYCODE_BACK` + verifique
   `dumpsys window | grep mCurrentFocus` antes do primeiro
   `extendedWaitUntil` (ou desactivar notificações heads-up na conta de
   teste durante os testes noturnos).
2. Re-correr: `python runner.py --fluxo delivery-restaurante-cash --two-devices`
   (infra já validada: JSON válido, scripts compilam, `pizza danilo` é o
   restaurante-alvo — lembrar de voltar a pôr `is_online=true` antes de
   correr, pois foi revertido a `false` no fim desta sessão).
3. Depois de `delivered`, correr a verificação numérica contra
   `PricingService.calculateBreakdown(serviceType=restaurant,
   isPartnerStore=true, subtotal=25.05, distanceKm=<real>)`.
