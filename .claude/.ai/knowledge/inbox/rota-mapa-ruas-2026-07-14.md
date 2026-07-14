---
data: 2026-07-14
tarefa: BUG rota do mapa em linha reta (TVDE + limpeza + delivery)
estado: corrigido (delivery) / confirmado ok (TVDE) / n/a (limpeza) — commit local, push bloqueado (build produção)
---

# Investigação: rota do mapa "quase em linha reta" (Danilo testou ao vivo)

## Resumo

O relato era sobre o mapa TVDE ("tela Corrida"), mas a investigação mostrou que o
código TVDE **já estava correto** (rota real via Google Directions). O bug real —
com o exato sintoma descrito (linha reta cortando praças/jardins) — estava no
**delivery** (motorista + cliente), que partilha o mesmo stack de mapa
(`google_maps_flutter`) que o TVDE tenta imitar. Foi aí que corrigi.

## O que já estava certo (TVDE) — só confirmado, nada a corrigir

- `lib/screens/driver/tvde/tvde_ride_active_screen.dart` (motorista, AppBar "Corrida")
- `lib/screens/client/tvde/tvde_ride_tracking_screen.dart` (cliente, "A tua corrida")
- `lib/screens/client/tvde/tvde_request_ride_screen.dart` (estimativa de preço)

Todos usam `DirectionsService` (`lib/services/directions_service.dart` →
Google Directions API real, `directions_service_io.dart` no mobile,
`directions_service_web.dart` na web). Quando a chamada falha, o código
**não desenha nada** (mantém o `Set<Polyline>` vazio) — nunca cai para uma
linha reta. Ou seja, o pior caso no TVDE é "sem linha", nunca "linha errada".

## O bug real (delivery) — CORRIGIDO

### 1. `lib/screens/driver_map_screen.dart` (mapa do estafeta)

Em `_updateRouteMulti`, quando o Directions API falhava **no primeiro carregamento**
(`isFirstLoad`), o código fazia:

```dart
_routePoints = [origin, ...stops.map((s) => s.location)];
```

Isto desenhava uma linha **reta e SÓLIDA**, com a mesma cor/largura da rota real
(`width: 6`, sem `patterns`), e ficava presa assim até o Directions responder com
sucesso — o motorista via uma "rota" indistinguível da real, cortando por cima de
tudo. Ironicamente o ficheiro já tinha um fallback tracejado correto (linha ~745,
estilo Uber/Glovo) para quando `_routePoints` está vazio — mas esse código morto
nunca era alcançado porque a linha reta sólida enchia `_routePoints` primeiro.

**Fix:** removida a atribuição da linha reta sólida. Agora, quando o Directions
falha no primeiro load, `_routePoints` fica vazio e o fallback tracejado (que já
existia) assume — visualmente distinto de uma rua real, nunca disfarçado de rota.

### 2. `lib/screens/order_tracking_screen.dart` (mapa do cliente — pedido em curso)

Em `_updateRoute`, TODA falha do Directions (não só a primeira) substituía
`_routePoints` por `[origin, destination]` — uma linha reta **sólida** (`width: 5`,
sem `patterns`), inclusive sobrescrevendo uma rota real boa anterior sempre que a
chave (origem/destino) mudava e o pedido seguinte falhava.

**Fix:**
- Falha no Directions → já não sobrescreve com linha reta; limpa `_routePoints`
  (preserva o alvo atual, nunca aponta para um destino desatualizado).
- O fallback de renderização (usado quando `_routePoints` está vazio) passou a ser
  **tracejado** (`PatternItem.dash(20)/gap(10)`, igual ao padrão já usado no mapa
  do estafeta) em vez de sólido.

## Limpeza — sem mapa, nada para corrigir

- `lib/screens/client/cleaning/cleaning_tracking_screen.dart` (cliente): é só uma
  timeline de estados (agendada → confirmada → a caminho → em curso → concluída).
  **Não tem `GoogleMap` nenhum.**
- `lib/screens/cleaner/*.dart` (profissional): nenhum ecrã do cleaner tem
  `GoogleMap`. Não existe rota desenhada em lado nenhum do fluxo de limpeza.

Não há bug de "linha reta" na limpeza porque não há mapa/rota nesse fluxo hoje.
Se no futuro o Danilo quiser mapa de navegação para a profissional, é feature nova
(reusar `DirectionsService`), não um bug a corrigir agora.

## Validação

- `flutter analyze lib/screens/driver_map_screen.dart lib/screens/order_tracking_screen.dart`
  → 0 erros; só avisos/infos pré-existentes sem relação com a mudança (baseline).
- Mudança cirúrgica: só as duas atribuições de linha reta + 1 pattern de traço.
  Nenhuma lógica de preço/dispatch/pagamento tocada.

## Push

Este branch (`autonomous-night-2026-04-29`) dispara `build_android.yml` em cada
`git push` (build de produção + publish no Google Play, track `alpha`) — Lista
Vermelha. Commit feito localmente; push **não** foi executado, aguarda "vai" do
Danilo (mesmo padrão do chat-guiado PARTE 1).
