# Investigação: distância (km) errada na lista de restaurantes — 2026-07-15

**Resultado: NÃO era bug de código.** O haversine já é real e calculado por
restaurante. O padrão "fixo" (0.0 km / 2.0 km) reportado é coincidência de
**dados de teste**, confirmada por query directa à BD — não código.

## 1) Onde é calculada a distância (resposta à pergunta do pedido)

- `lib/screens/restaurants_screen.dart` → widget `_MetaRow` (usado no
  `ListView.builder` da lista, uma instância por restaurante):
  ```dart
  final client = cart.deliveryLocation;         // morada activa do cliente
  final pickup = business.location;              // lat/lng do restaurante
  final distanceKm = OrderEtaService.distanceKmBetween(client, pickup);
  ...
  label: '${distanceKm.toStringAsFixed(1)} km',
  ```
- `OrderEtaService.distanceKmBetween` → `latlong2.Distance().as(LengthUnit.Kilometer, a, b)`,
  ou seja **haversine real**, chamado individualmente para cada `business` da
  lista. **Não existe valor fixo nem lógica por categoria** — confirmado por
  leitura de todo o ficheiro e de `distance_service.dart` (haversine manual,
  usado noutros ecrãs, também correcto).
- `client` (`cart.deliveryLocation`) é resolvido em `client_home_screen.dart`
  por esta ordem: morada default da BD (`client_addresses`) → morada "Casa"
  (`SessionStore`) → GPS (`LocationService.getCurrentLocation()`).
- `pickup` (`business.location`) vem directo de `restaurants.lat` /
  `restaurants.lng`, parseados sem fallback em `restaurant_store.dart`
  (`_restaurantFromRecord`), incluindo no handler de realtime UPDATE.

## 2) Prova — dados reais da BD (Supabase, 2026-07-15)

```sql
select id, name, lat, lng from restaurants where name in (...)
```

| Restaurante | lat | lng |
|---|---|---|
| Burger King | 40.534021 | -7.243637 |
| KFC | 40.551987 | -7.24888 |
| McDonald's | 40.542704 | -7.239618 |
| pizza danilo | 40.5402657 | -7.2673597 |
| pizzaria Paulista | 40.5402657 | -7.2673597 |
| Sabores de Casa Açaí | 40.5369 | -7.2681 |

Morada default (`client_addresses`, `is_default=true`) da única conta usada
no teste (`nilofulfarotuga@gmail.com`, user_id `c9fccf85-...`):

> Rua do Torreão 14, Guarda — **lat 40.5402657, lng -7.2673597**

Ou seja: a morada de entrega do cliente de teste é **exactamente** a mesma
coordenada de "pizza danilo" e "pizzaria Paulista" (mesmo pin GPS).

## 3) Recalculando o haversine real (fora da app, mesma fórmula) a partir desse ponto

| Restaurante | km real (haversine) | label que a app mostra |
|---|---|---|
| pizza danilo | 0.0000 | **0.0 km** ✅ (mesmo ponto — correcto) |
| pizzaria Paulista | 0.0000 | **0.0 km** ✅ (mesmo ponto — correcto) |
| Sabores de Casa Açaí | 0.3794 | **0.4 km** (perto, mas distinto) |
| KFC | 2.0339 | **2.0 km** |
| Burger King | 2.1216 | **2.1 km** |
| McDonald's | 2.3598 | **2.4 km** |

Os 6 valores são **distintos e matematicamente correctos** para as
coordenadas reais na BD. O que pareceu "fixo" ao olhar rápido:
- pizza danilo / pizzaria Paulista dão 0.0 km porque **partilham a mesma
  coordenada** entre si e com a morada default do testador (não é bug —
  distância entre dois pontos idênticos é mesmo zero).
- BK / KFC / McDonald's estão todos a ~2.0–2.4 km porque Guarda é uma cidade
  pequena e ficam a distâncias parecidas desse ponto — os valores (2.0 / 2.1
  / 2.4) já são diferentes, só parecem "o mesmo" a um olhar rápido sem ver
  a casa decimal.

## 4) Validação

- `flutter analyze` nos 5 ficheiros da cadeia (`restaurants_screen.dart`,
  `order_eta_service.dart`, `distance_service.dart`, `cart_store.dart`,
  `restaurant_store.dart`): **0 issues**.
- Haversine reproduzido fora da app (Node.js, mesma fórmula esférica) com as
  coordenadas reais da BD → bate certo com os valores que a app mostra.
- Revisão de todo o `restaurants_screen.dart`, `order_eta_service.dart`,
  `distance_service.dart`, `restaurant_store.dart` (parsing de lat/lng no
  fetch inicial e no realtime) — nenhum fallback fixo, nenhuma lógica por
  categoria/`isPartner` a decidir o texto de distância.

## 5) Acção tomada

**Nenhuma alteração de código** — o cálculo já estava correcto (real,
haversine, por restaurante). Não editei `restaurants.lat/lng` na BD: não
tenho forma de saber a morada real de "pizza danilo" / "pizzaria Paulista",
e corrigir coordenadas de negócio de parceiros é decisão do Danilo, não algo
para adivinhar em produção.

**Sugestão para o Danilo:** se "pizza danilo" e "pizzaria Paulista" não
ficam de facto no mesmo prédio que a tua morada de entrega de teste
(Rua do Torreão 14), confirma a morada real de cada uma e corrige o pin no
admin — foi provavelmente registado com "usar localização atual" a partir
do mesmo telemóvel/local usado para testar como cliente.

Sem commit/push — não houve alteração de código para subir.

---

distância km: não era bug — o cálculo já é real (haversine) e distinto por
restaurante; o padrão "fixo" reportado veio de dados de teste (2 restaurantes
registados no mesmo pin da morada default do testador), confirmado por SQL
directo à BD + flutter analyze limpo.
