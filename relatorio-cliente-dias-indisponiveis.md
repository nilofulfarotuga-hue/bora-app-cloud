# Relatório — Dias indisponíveis marcados no passo "Escolher dia" (cliente)

**Data:** 2026-07-19 · **Branch:** `autonomous-night-2026-04-29`
**Squad (CEO-AI):** cliente + flutter-ui · **Não toca dinheiro** (Lista Vermelha).

## Objetivo
No passo "Escolher dia", mostrar JÁ no cartão do dia quando o profissional escolhido **não
trabalha** (folga/fora do padrão), em vez de o cliente só descobrir depois de tocar e ver
"Sem horários disponíveis neste dia".

## Como funciona agora
1. **Ao escolher o profissional** (passo anterior), carrego **UMA vez** a disponibilidade dele
   (fetch único, não por cartão):
   - **padrão semanal** → `staff_availability` (que `day_of_week` têm `is_working=true`);
   - **exceções** no intervalo visível → `staff_availability_exceptions` (folgas/dias extra).
   Guardo em memória (`Map<staffId, Set<dow>>` e `Map<staffId, {data: is_working}>`).
2. **Cálculo por dia** (`_dayAvailable`) — a MESMA lógica do `get_available_slots`, replicada só
   para efeito **visual** (a verdade final continua a ser a função no servidor):
   - se existe **exceção** para a data → usa o `is_working` da exceção (prioridade);
   - senão → usa o `is_working` do **dia-da-semana** no padrão semanal;
   - sem nenhuma linha → **NÃO disponível**.
3. **"Qualquer profissional disponível"** (`_kAnyStaffId`): um dia conta como disponível se
   **pelo menos um** profissional trabalha nesse dia (carrego a disponibilidade de todos).
4. **`_DayCell`** ganhou um estado "indisponível": fundo cinza (`surface` + borda), número
   esbatido e rótulo **"Indisponível"**; o **toque fica desativado** (`onTap: null`) — o cliente
   não entra num dia vazio. Dias de trabalho ficam com a aparência normal de sempre.
5. **Loading discreto**: enquanto carrega, uma linha "A verificar disponibilidade…" no topo; os
   dias só ganham o estado cinza depois de os dados chegarem.

## Decisões / salvaguardas
- **Fail-safe:** `_availReady` só fica `true` após um fetch bem-sucedido. Em **erro ou durante o
  loading**, TODOS os dias ficam disponíveis (comportamento atual) — nunca bloqueio a marcação
  por causa de uma falha de leitura.
- **RLS confirmada via MCP:** `staff_availability.sa_select` e
  `staff_availability_exceptions.sae_select` têm `qual = true` (leitura pública) → o cliente lê
  estas tabelas diretamente, sem RPC. (Se estivessem fechadas, um read vazio marcaria tudo como
  indisponível — por isso confirmei antes.)
- **Agenda cheia NÃO é marcada** (por design, ver pedido): só marco indisponíveis os dias em que o
  profissional **não trabalha**. Marcar "cheio" obrigaria a chamar `get_available_slots` para cada
  dia do ano (pesado). Dias de trabalho ficam normais; se por acaso estiverem cheios, o cliente
  ainda vê o já-existente **"Sem horários disponíveis neste dia"** no passo seguinte. Aceitável.
- **DST:** o `day_of_week` é calculado com `day.weekday % 7` (Dom→0…Sáb→6), a bater com a DB.

## Qualidade
- `flutter analyze` nos ficheiros tocados: **No issues found!**
- PT-PT, design system. Não mexi em pagamento, `get_available_slots`, nem noutros passos.
- Reutilizei o padrão dos métodos vizinhos da store (try/catch + mensagens PT-PT).

## Ficheiros tocados
- `lib/stores/services_store.dart` — `fetchWeeklyWorkingDays()` + `fetchExceptionsRange()`.
- `lib/screens/client/services/booking_flow_screen.dart` — `_loadAvailability()`, `_dayAvailable()`,
  loader discreto, `_DayCell` com estado "Indisponível" + toque desativado.
- `relatorio-cliente-dias-indisponiveis.md` — este relatório.

## O que ficou para depois
- **Marcar dias cheios (agenda lotada)** como indisponíveis: **deferido** de propósito (custo de
  1 chamada `get_available_slots`/dia). Fica a mensagem no passo seguinte, como hoje.
