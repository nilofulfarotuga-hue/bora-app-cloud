# Relatório — Janela de marcação do cliente (1 ano + agrupada por mês)

**Data:** 2026-07-19 · **Branch:** `autonomous-night-2026-04-29`
**Squad (CEO-AI):** cliente + flutter-ui · **Não toca dinheiro** (Lista Vermelha).

## Problema
No passo "Escolher dia" (`booking_flow_screen.dart`) o cliente só via **30 dias** e a grelha
**não mostrava o mês/ano** — só cartões soltos. Serviços de beleza marcam-se com 1-2 meses de
antecedência.

## O que mudou

### 1. Janela: 30 → 365 dias, **lida de `platform_settings`**
- **Li o limite de `platform_settings`** (não usei 365 fixo): novo método
  `ServicesStore.fetchMaxAdvanceDays()` chama a RPC `get_setting('appointment_max_advance_days')`,
  com **fallback seguro 365** se a leitura falhar/vier inválida. Padrão igual ao `get_setting` do
  `tvde_store`. Assim o Danilo ajusta a janela sem rebuild.
- A chave **já existia com valor 30**. Bumpei-a para **365** via MCP (`UPDATE platform_settings …
  value = to_jsonb(365)`). Isto é **obrigatório** e não é dinheiro: confirmei via MCP que a RPC
  `client_book_appointment` valida a data contra `appointment_max_advance_days` (sem outro tecto
  hardcoded) — se ficasse em 30, o servidor rejeitaria datas mais longe mesmo com a UI a mostrá-las.
- `booking_flow` lê o valor no `_loadCatalog` (junto com serviços+staff) e guarda em
  `_maxAdvanceDays` (default 365). A constante fixa `_kMaxAdvanceDays = 30` foi **removida**.

### 2. Grelha agrupada por MÊS, com cabeçalho "Mês Ano" PT-PT
- `_dayStep` reescrito como **`CustomScrollView`** com, por mês: um `SliverToBoxAdapter` de
  cabeçalho (ex.: **"Julho 2026"**, "Agosto 2026", … título do design system, `w800`, 17px) seguido
  de um `SliverGrid` de 4 colunas com os dias desse mês.
- Scroll fluido, contínuo, do mês atual (topo = hoje) até 1 ano à frente.
- **`_DayCell` reutilizado tal como está** (não redesenhado). Toque num dia mantém exatamente o
  comportamento antigo: `setState(_day=…)` + `_next()` + `_loadSlotsForDay(d)`.
- **Nomes de meses:** o array existente perto do `_formatDayLong` é **abreviado/minúsculas**
  (`jan`, `fev`…), impróprio para um cabeçalho "Julho 2026". Por isso adicionei um `static const
  _ptMonths` com os nomes **completos** (não é duplicação do abreviado — é dado diferente).
- **DST:** a iteração de dias usa aritmética de calendário (`DateTime(y, m, day+1)`), não
  `Duration(days:1)`, para uma janela de 365 dias não "escorregar" uma hora numa mudança de hora.

## Fluxo (mental)
1. Cliente entra na marcação → vê "Julho 2026" no topo e pode **scrollar até Julho 2027**.
2. Toca num dia distante (ex.: 10 de Outubro) → passo das horas chama `get_available_slots`
   (inalterado) → mostra slots, ou o já-existente **"Sem horários disponíveis neste dia"** se o dia
   for folga/sem disponibilidade. Não bloqueio o toque por isso.
3. Confirmar/pagar → `client_book_appointment` aceita a data (setting=365). ✅

## Qualidade
- `flutter analyze` nos ficheiros tocados: **No issues found!**
- PT-PT, design system (verde/laranja/Inter). Só o passo "Escolher dia" + leitura do limite.
- **Não** mexi em pagamento, `get_available_slots`, nem noutros passos.

## Ficheiros tocados
- `lib/stores/services_store.dart` — `fetchMaxAdvanceDays()`.
- `lib/screens/client/services/booking_flow_screen.dart` — janela dinâmica + `_dayStep` por mês
  + `_ptMonths` + `_MonthSection`; removida a constante fixa de 30.
- **DB (via MCP, não é git):** `platform_settings.appointment_max_advance_days` 30 → **365**.
- `relatorio-janela-marcacao-cliente.md` — este relatório.

## O que ficou para depois (declarado)
- **Botões rápidos "Este mês / Próximo mês" / seletor de mês** para saltar: **deferido** (opcional
  no pedido). O scroll contínuo com cabeçalhos por mês já resolve a orientação e a navegação; o
  salto rápido é um extra que fica para uma iteração seguinte para não aumentar o escopo/risco.
