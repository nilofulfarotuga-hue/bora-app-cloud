# notify-tvde-driver — título "📦 Nova encomenda!" (PROPOSTA, não publicada)

21/10/2026 · fechar-pendencias A1. **Não publiquei esta Edge Function** e não mexi no ficheiro do
repositório, de propósito:

- No ar está a **v22** (`updated_at` 12/10/2026). O ficheiro do repo
  (`supabase/functions/notify-tvde-driver/index.ts`, último commit 14fb9994 de 16/10) está
  **à frente** do ar: leva a troca de chave da missão `chave-nova-16-10` (`keys.ts`/`secretKey()`),
  que é de outra missão (Bloco G). Publicar o ficheiro do repo levaria essa troca "à boleia".
- É a função que toca o telemóvel do motorista em TODAS as ofertas do Bora Motorista. Um erro de
  sintaxe aqui cala as ofertas de passageiros. Sem o "sim" do revisor não a publico.

Sem esta mudança, numa encomenda o aviso do sistema (o que aparece com o ecrã bloqueado) diz
"🚗 Nova corrida!" — o resto já diz encomenda: o cartão de oferta dentro da app ("Nova encomenda —
agora", com o ganho em número grande), os avisos ao cliente e o ecrã do estafeta.

## A mudança (2 sítios, só texto; aplicar POR CIMA da v22 lida com `get_edge_function`)

1. Na leitura da corrida da oferta (`lerCorridaOferta`), acrescentar `ride_kind` ao `select`:

```ts
.select('origin_label, dest_label, est_fare_cents, est_distance_km, driver_earn_cents, agreed_driver_earn_cents, agreed_fare_cents, payment_method, offer_expires_at, current_offer_driver_id, status, ride_kind')
```

2. No caminho original da OFERTA: um título por tipo, usado nos DOIS sítios onde hoje está
   `'🚗 Nova corrida!'` (bloco `data.title` e `apns.payload.aps.alert.title`):

```ts
let tituloOferta = '🚗 Nova corrida!'           // junto de: let originLabel = 'Recolha', ...
// dentro do `if (ride) { ... }` que já existe:
if (ride.ride_kind === 'encomendas') tituloOferta = '📦 Nova encomenda!'
// e nos dois sítios:
title: tituloOferta,
payload: { aps: { alert: { title: tituloOferta, body: headsUpBody }, ... } },
```

Passageiros: `ride_kind` vem 'passageiros' (ou nada, numa corrida antiga) → o título fica
exactamente '🚗 Nova corrida!'. O corpo ("Ganhas €x · origem -> destino") não muda — o número
grande continua a ser o ganho do estafeta (skill ganho-motorista-numero-grande).

## Como provar depois de publicar

1. `get_edge_function notify-tvde-driver` → a versão nova tem `ride_kind` no select e
   `tituloOferta` nos 2 sítios; o resto igual à v22.
2. Uma oferta de passageiros real a seguir: `tvde_ride_events`/log do push com
   `title: '🚗 Nova corrida!'` e `ok:true`.
3. Encomenda demo só com motoristas reais offline (ou de madrugada), estafeta demo com token:
   push com `title: '📦 Nova encomenda!'`.
