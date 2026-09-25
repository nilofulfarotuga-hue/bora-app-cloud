# Prova LIVE — autocomplete Guarda (Bug #1) — 2026-07-10

Sonda direta à Google Places Autocomplete REST API (o MESMO endpoint que o
`place_autocomplete_service_io.dart` usa no Android real), com o viés da Guarda
(`location=40.5373,-7.2657&radius=25000&components=country:pt&language=pt-PT`).
Chave lida de `.dart_defines` (nunca impressa). NÃO é teste web nem mock.

## Resultado (status=OK nos 4 casos)

| Query (biased) | 1.º resultado devolvido |
|---|---|
| `Continente` | **Continente Bom Dia Guarda** ✅ |
| `Continente Guarda` | Continente Bom Dia Guarda ✅ |
| `Lavie` | **LA VIE Guarda** ✅ |
| `Lavie Guarda` | LA VIE Guarda (+ Bertrand La Vie, iServices La Vie, Pizza Hut La Vie…) ✅ |

## Leitura
- A API + viés + **remoção do `types=geocode`** (que antes só devolvia ruas) já
  faz o estabelecimento local da Guarda aparecer em 1.º para ambos os casos.
- Logo o bug que o Danilo viu no telemóvel (Continente de outra cidade / "Lavie"
  vazio) vem de um **APK instalado ANTERIOR ao fix** (commit `f90d9fa` + remoção
  de `types`). O código atual resolve; falta a app com o fix chegar ao device.

## Hardening aplicado nesta sessão (garantia, não probabilidade)
- Removido o gate frágil `semGuarda`: agora dispara-se **SEMPRE** a pesquisa
  explícita `"<query> Guarda"` e coloca-se à frente (dedup por place_id), em
  `_io` e `_web`. Antes, um item da Guarda ERRADO (uma rua homónima) na 1.ª
  passagem saltava o retry e o estabelecimento certo nunca surgia.
- Teste de regressão determinístico novo cobre exatamente esse caso.

## Falta (Lista Vermelha)
- **Build + install de um APK novo** no telemóvel do Danilo para o fix chegar ao
  device. Build de PRODUÇÃO = 🔴 → precisa de "vai". Um build/install DEBUG para
  prova visual é reversível mas não foi corrido neste loop headless.
