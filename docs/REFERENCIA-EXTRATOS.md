# REFERÊNCIA — como o Uber e o Glovo mostram o extrato a quem trabalha

> Missão `contas-claras-2026-09-20` · Bloco 2 · lido a 20/09/2026 nas páginas públicas de
> ajuda, no navegador (help.uber.com, uber.com/blog, riderhub.glovoapp.com). Regra do Danilo:
> **copiar a clareza, não o desenho.** O que está aqui é o que eles mostram, por que ordem,
> e as palavras que usam. O que a Bora faz com isto está no fim (§3).

---

## 1. Uber Driver — "Earnings" e o extrato semanal

**Fontes:** `help.uber.com › Driving & Delivering › View your trip earnings and weekly statements`;
`… › Understanding how earnings are calculated`; `uber.com/blog › Track your earnings weekly`.

### 1.1 Onde a pessoa vê o dinheiro (na app)

1. Ícone **Earnings** no fundo do ecrã → o número grande da semana em curso.
2. **See details** → ganhos **por dia** da semana em curso.
3. A data no topo muda de semana.
4. **See earnings activity** → a lista de **cada corrida/entrega**, dia a dia.

Três níveis, sempre na mesma ordem: **total → por dia → por trabalho**. Um toque desce um nível.

### 1.2 O extrato semanal (chega segunda-feira, por email e no painel)

Ordem fixa das secções:

1. **Weekly summary** — duas linhas só: *Total earned* e *cashed out* (quanto ganhou e quanto
   já foi pago/levantado). É a capa. Antes de qualquer detalhe.
2. **Breakdowns** — de onde veio o total: *trips* (corridas), *promotions*, *tips* (gorjetas),
   *adjustments* (acertos de semanas anteriores — ex.: gorjeta que chegou dias depois).
3. **Transactions** — toda a actividade, linha a linha: *trip earnings*, *payouts* (pagamentos
   feitos à pessoa), *fees* (taxas).
4. Nos extratos novos, também: **how much customers paid** (quanto o cliente pagou) e **the
   weekly Uber service fee** (a parte do Uber).

Ciclo: **segunda 04:00 → segunda 03:59** seguinte. "Weekly statements provide your most
complete and finalized earnings details" — a semana fechada é a verdade final; o dia a dia é
provisório.

### 1.3 As palavras

- *Earnings* = corridas (com surge/boost) + promoções + gorjetas **menos** taxas do Uber.
- *Service fee* = "the difference between what a rider pays and what a driver earns on a trip"
  — mostram a diferença entre o que o cliente pagou e o que o motorista ganhou, com esse nome.
- *Adjustments* = acertos com sinal, sempre ligados à semana a que pertencem.
- *Cashed out* = o que já saiu para a pessoa.
- Cancelamentos e prémios de referência entram na mesma lista de *Earnings* — não há
  "outra conta".

---

## 2. Glovo (courier) — "Payments", "Wallet" e a factura

**Fonte:** `riderhub.glovoapp.com › Earnings & Payments` (Base earnings · Extra earnings ·
Cash management · Billing & Invoicing).

### 2.1 Cada entrega tem até 4 parcelas, com nome

1. **Delivery fee** — o valor que a pessoa vê **antes de aceitar** ("the fee you will receive
   and that you are made aware of before you accept an order").
2. **Promos** — chuva, feriados, picos. Aparecem com símbolo/multiplicador.
3. **Quests** — objectivos com prémio.
4. **Tips** — "100% of the tip's amount goes to your earnings".

A distância é sempre a de Google Maps entre onde estava ao aceitar → loja → cliente,
"although you are free to choose which path to take".

### 2.2 Dinheiro em mão — a **Wallet** (é o que a Bora não tem hoje)

Três casos de cash, todos anunciados no ecrã de aceitação:

- *Cash is needed at pick up only* — paga à loja; o valor é somado aos ganhos quando entrega.
- *Cash is needed at pick up and at drop off* — paga à loja e o cliente paga-lhe em dinheiro;
  o que recebeu **é descontado do próximo pagamento**.
- *Cash is needed at drop off only* — só recebe do cliente; descontado do próximo pagamento.

A Wallet mostra **o saldo e as linhas que o compõem**, com quatro palavras:

- **Current balance** — "sum of all transactions" (o saldo é a soma das linhas, ponto).
- **Payment** — o que a pessoa pagou na loja (a favor dela).
- **Collection** — o que recebeu do cliente na entrega (contra ela).
- **Cash-out** — o que ela depositou para baixar o saldo.
- **Payout** — o acerto automático diário que a app faz para baixar o saldo.

Quando o dinheiro em mão passa um tecto, a app lembra a pessoa de fazer *cash-out*.
Um saldo negativo na Wallet no fim do período **entra na factura e é subtraído** — não fica
uma dívida separada.

### 2.3 "Payments" na app e a factura

- Menu **Payments**: ganhos "for each completed delivery, organized per week then per day";
  extras (promo, gorjetas) visíveis; **"Click on the deliveries to see the details for each one"**.
- Período de facturação: 14 dias, segunda 00:00 → domingo 23:59.
- A factura, por esta ordem: *Personal data* · *Total performance offered* (ganhos com promos e
  quests, **sem gorjetas**, "this is not the amount that will be received via bank transfer")
  · *Total invoice* (depois de impostos) · *Total cash received, Cash collection, Sum of daily
  cash withdrawals* (os movimentos de dinheiro em mão do período) · *Adjustments* (com sinal:
  equipamento, restos da factura anterior) · **Total to receive** ("how much you will receive
  via bank transfer").

Repare-se: a factura diz duas vezes "isto **não** é o que vais receber" antes de chegar ao
número que é. Nunca deixam a pessoa confundir o bruto com o líquido.

---

## 3. O que a Bora copia (a clareza) e o que muda (o desenho)

| Princípio deles | Como fica na Bora (RPC `extrato_prestador`) |
|---|---|
| Três níveis: total → dia → trabalho, um toque desce | `resumo` (hoje / semana / semana passada) → `dias` → `trabalhos`, e cada trabalho abre as `parcelas` |
| Capa com duas linhas: ganhou / já recebeu | `resumo.semana.ganho_cents` e `acerto.ultimo` (quanto, quando, pago?) |
| Breakdown com nome: trips / promotions / tips / adjustments | por trabalho: base, km, extras (talão, sacos, paragens), tokens; por semana: `entregas`, `corridas`, `compensacoes`, `tokens` |
| "How much customers paid" + "service fee" | cada trabalho leva `cliente_pagou_cents` e `parte_bora_cents` — a diferença aparece com nome, não se esconde |
| Wallet de cash: saldo = soma das linhas; Payment / Collection / Payout | `dinheiro_em_mao`: uma linha por pedido a dinheiro (`recebeu_do_cliente`, `pagou_na_loja`, `fica_para_a_bora`), com o total a devolver — e é a soma das linhas, provada pelo vigia |
| "This is not the amount you will receive" antes do líquido | `deve_lhe_a_bora` e `deve_a_bora` separados, cada um com as suas linhas; o `saldo_sentido` só no fim |
| A semana fechada é a verdade final | o `acerto` vem de `driver_weekly_settlements` (a linha fechada), nunca recalculado na app |
| Um saldo negativo entra na factura e é subtraído | a dívida abatida aparece como linha no acerto, com o nome do que a originou |

O que **não** se copia: o desenho de ecrã, a Wallet como conta separada (na Bora o cash é
uma secção do mesmo extrato), e o ciclo de 14 dias (a Bora fecha à semana, segunda-feira,
como já está em `driver_settlement_week_bounds`).

**Regra dura (ordem do Danilo):** o Flutter não faz contas. Todos os números acima saem de
**uma** RPC do servidor; a app só os mostra. Valor que o servidor não souber → "—" com a razão.
