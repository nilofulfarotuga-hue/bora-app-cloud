---
id: tvde-roundtrip-preco-dinamico-2026-08-01
tipo: relatorio
data: 2026-08-01
agente: claude-opus
estado: concluido
---

# Relatório: pacote ida-e-volta TVDE deixa de ser €8 fixo (2026-08-01)

## Objectivo
O backend já tinha sido aberto via MCP antes desta sessão: nova RPC
`tvde_quote_roundtrip(p_distance_km)` devolve
`{one_way_cents, full_cents, discount_pct, price_cents, saving_cents}`,
`tvde_create_roundtrip_credit_cash` grava o `paid_cents` real e
`tvde_finish_ride` acerta por esse `paid_cents`.

**Faltava o app** — e era o ponto crítico: o Flutter mostrava €8 fixo
(`platform_settings.tvde_roundtrip_price_cents`) enquanto o servidor já cobrava
o valor certo. Cliente via um número, motorista recolhia outro.

## Alterações aplicadas (11 ficheiros, só Flutter)

### 1. `lib/stores/tvde_store.dart`
- **NOVO** `quoteRoundtrip(double distanceKm)` — chama a RPC `tvde_quote_roundtrip`.
  Tolera resposta `Map` ou `List` (composto do Postgres).
- **NOVO** `getRoundtripPaidCents(String creditId)` — lê `paid_cents` de
  `tvde_roundtrip_credits` pelo id do vale.
- Comentários que citavam `tvde_roundtrip_price_cents` / "€8" actualizados.

### 2. `lib/screens/client/tvde/tvde_request_ride_screen.dart` — CLIENTE
- `_roundtripPriceCents` deixa de nascer a `800`; nasce a `0` (= "sem cotação ainda").
- **NOVO** `_roundtripSavingCents` + `_fetchRoundtripQuote(km)`, disparado no fim de
  `_recalcEstimate()` — ou seja, assim que a distância de rota real é conhecida.
- Ambos voltam a `0` quando o destino é limpo (2 sítios) — nunca fica um preço
  de um destino anterior no ecrã.
- `_RoundtripToggle`: mostra `Ida + volta por €X · poupas €Y` (a poupança a
  verde). Sem cotação → o switch fica **desactivado** com
  *"Escolhe o destino para ver o preço do pacote."* — não dá para comprar às cegas.
- Botão: `Garantir ida e volta · €X` (sem preço → só `Garantir ida e volta`).
- Folha de pagamento: mensagem passa a
  *"Ida + volta com desconto. Poupas €Y face a duas corridas separadas."*

### 3. `lib/widgets/tvde/tvde_roundtrip_driver_notice.dart` — MOTORISTA
- `TvdeRoundtripPrice.load(store)` (lia o setting) → **`loadForRide(store, ride)`**,
  que lê o `paid_cents` do vale ligado à corrida (`ride.roundtripCreditId`).
- Removido o cache estático `_cached`/`_inflight`: era uma leitura **por sessão**,
  e agora o preço é **por corrida** — um cache global mostraria o valor do pacote
  anterior. `fallbackCents` (800) mantém-se só para corrida sem vale.

### 4. `lib/widgets/tvde/tvde_pay_badge.dart` — MOTORISTA ("COBRAR EM DINHEIRO")
- Passa a usar `loadForRide`. O badge e o aviso continuam a ler a **mesma fonte**
  (o memo de sessão "os dois têm de mostrar o mesmo número" mantém-se válido —
  a fonte é que mudou de setting para `paid_cents` do vale).

### 5. Restantes consumidores do preço do pacote (arrastados pela mudança de API)
| Ficheiro | Mudança |
|---|---|
| `screens/driver/tvde/tvde_ride_active_screen.dart` | lembrete de cobrança usa `loadForRide(store, finished)` |
| `screens/client/tvde/tvde_ride_tracking_screen.dart` | usa o `activeRide` para ler o vale |
| `screens/client/tvde/tvde_rate_screen.dart` | usa `widget.ride` |
| `screens/client/tvde/tvde_rides_history_screen.dart` | `_RideTile` passou a **StatefulWidget** e lê o `paid_cents` do **seu** vale |

> Nota sobre o histórico: um único `_packageCents` para a lista toda mostraria o
> mesmo valor em pacotes de preços diferentes. Como o preço agora varia com a
> distância, cada linha tem de ler o seu vale. Foi por isso que o tile mudou.

### 6. `lib/models/tvde_fare_view.dart`
- Só comentários: `packageCents` passa a documentar-se como `paid_cents` do vale.
  **A lógica não mudou** — continua `base = isReturnLeg ? 0 : packageCents`.

### 7. `lib/screens/admin/admin_dashboard_screen.dart`
- Subtítulo do cartão "Ida e volta": `Pacotes €8 · …` → `Pacotes ida + volta · …`.

## Motorista da volta (item 3 do pedido) — CONFIRMADO, sem alteração
Pedido: *"só confirmar que o ecrã mostra o valor que vem do `driver_earn_cents`."*

Confirmado por leitura: **todos** os ecrãs de ganhos do motorista lêem
`ride.driverEarnCents`, que vem directamente de `driver_earn_cents`
(`lib/models/tvde_ride.dart:122`). Nenhum valor hardcoded:
`tvde_offer_screen`, `tvde_ride_active_screen`, `tvde_driver_rate_screen`,
`tvde_driver_earnings_screen` e o próprio aviso do pacote.
Na volta o aviso diz *"Recebes €X desta corrida. A volta já está paga — não
cobres nada ao cliente."* — €X = `driver_earn_cents` do servidor.

## Item 4 (admin) — APLICADO após aprovação explícita do Danilo

Pediste: *"acrescentar o campo `tvde_roundtrip_discount_pct` nas configurações do
TVDE, com nota 'desconto % aplicado sobre ida+volta'."*

**Ficheiro:** `lib/screens/admin/admin_platform_settings_screen.dart` —
`tvde_roundtrip_discount_pct` entrou na whitelist `_isEditable`, ao lado de
`tvde_max_stops` e `tvde_stop_timer_seconds`.

**Porque parei primeiro e porque avancei depois.** Numa primeira passagem
travei isto e sinalizei como 🔴: a chave é a % de desconto do pacote, logo mexe
no que o cliente paga, e o próprio ficheiro diz que as chaves de dinheiro
*"ficam blindadas"*. O Danilo respondeu (2026-08-01), e a distinção que fez é a
que fica registada no código:

> *"É o dono a mexer no próprio preço pelo painel dele, que é exactamente a
> regra do projecto (autoridade total no admin) — não é um agente a mexer em
> dinheiro sozinho."*

Ou seja: o gate 🔴 protege contra **o agente** alterar dinheiro por iniciativa
própria, não contra **o dono** usar o painel que existe para isso. Continuam
blindadas as chaves em cêntimos (`tvde_stop_fee_cents`, `tvde_stop_driver_cents`).

**Nota descritiva:** já escrita na coluna `description` de `platform_settings`
pelo Danilo via MCP — não foi preciso SQL nenhum deste lado. O ecrã já a
renderiza sozinho (`_Setting.description`, lido de `j['description']`).

## Verificação

| Check | Resultado |
|---|---|
| `flutter analyze` (11 ficheiros tocados) | **0 erros, 0 warnings** · 17 info |
| `flutter analyze` (3 ficheiros do 2.º lote) | **0 erros, 0 warnings** · 11 info |
| `flutter test` (5 ficheiros TVDE) | **45/45 passaram** (`00:15 +45: All tests passed!`) |
| `flutter analyze` (admin whitelist, 2.º commit) | **`No issues found!` (ran in 20.2s)** |
| `flutter test` TVDE (re-corrido após a whitelist) | **45/45** (`00:19 +45: All tests passed!`) |
| `grep tvde_roundtrip_price_cents lib/` | **0 ocorrências** — setting eliminado do app |
| `grep "€8" lib/` | só em **comentários**; nenhum valor funcional |
| versionCode | NÃO incrementado (o CI trata) |

Todos os `info` são lints de estilo pré-existentes (`prefer_const_constructors`,
`use_build_context_synchronously`) — nenhum introduzido pela lógica nova.

## O que NÃO foi tocado (por design)
- SQL / migrations / Edge Functions / Stripe / RLS — nada.
- `dispatch_engine`, `pricing_service.dart`, `finalizePurchase`, `bora_tokens` — nada.
- Fotos de produtos, preços, comissões — nada.
- `TvdeFareView` — lógica intacta; só documentação.

## Git

| Campo | Valor |
|---|---|
| Branch | `autonomous-night-2026-04-29` |
| Commit | `63aa33ea1fa036550a1c8ed34217fe3087e01fda` |
| Push | HTTPS ✅ (`294be17..63aa33e`) — SSH falhou (`Permission denied (publickey)`), como esperado nesta máquina |
| GitHub API | Confirmado ✅ — author `Danilo (Hermes autonomous)`, date `2026-08-01T19:37:09Z`, 12 ficheiros |
| `git add` | Por caminho explícito (12 ficheiros) — nunca `-A` |
| `git pull --rebase --autostash` | Rebased (1/1) + autostash aplicado |
| Commits empurrados | **Apenas 1** (`git log 294be17..63aa33e` = 1 linha) — sem boleia de outro executor |

Output real do push:
```
To https://github.com/nilofulfarotuga-hue/bora-app-cloud.git
   294be17..63aa33e  HEAD -> autonomous-night-2026-04-29
```

> O push dispara `build_android.yml` (Play alpha) e `build_web_deploy.yml`.
> Só depois do build instalado é que o cliente deixa de ver €8 fixo — até lá
> a divergência app↔servidor mantém-se no APK antigo.

## Bugs encontrados fora do scope
Nenhum.
