# Missão 23/09 — TVDE: oferta na hora · ida-e-volta com reserva · painel

## O que NÃO foi feito (primeiro, como manda o PADRAO §3.9)

1. **Prova no emulador (app em fundo + ecrã bloqueado → oferta e push < 3 s) — NÃO feita.**
   Este contentor cloud não tem Android SDK nem emulador (sem KVM). A prova do
   telemóvel fica para o próximo build (≥ o que o CI gerar deste push): Danilo online,
   app em fundo, ecrã bloqueado, pedir corrida de teste a dinheiro com a conta
   "Cliente E2E" → ver `offer_delay_s` e `push_delay_s` no painel (coluna nova).
2. **Bloco B servidor NÃO aplicado** — mexe em cobrança. Fica pronto como proposta:
   `supabase/migrations/PROPOSTA_20260923_tvde_ida_e_volta_com_reserva.sql` +
   `supabase/functions/tvde-payment/index.ts` (v11, sem deploy).
   ⚠️ **ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.**
   Com o "vai": aplicar a migração e publicar a tvde-payment v11 (comparar antes com
   a versão em produção). A migração liga no fim `tvde_roundtrip_reservation_enabled`,
   que é o que faz aparecer o botão na app — até lá o botão NÃO aparece e nada parte.
3. `tr_notify_tvde_driver_on_offer` não foi mexido: o atraso não estava lá (pg_net
   dispara no commit); estava na Edge Function, que foi encurtada.

## Bloco A — motorista sempre vivo

**Causa na raiz (telemóvel):** o GPS "online à espera" do TVDE corria sem serviço
em primeiro plano de localização (Android estrangula em fundo), com `distanceFilter: 50`
(parado = zero posições) e envio ao servidor travado a 45 s. As entregas tinham o
serviço mas também o filtro de 50 m.

- `lib/services/localizacao_online.dart` (novo): stream com serviço em primeiro plano
  tipo `location` ("Bora — estás online"), posição a cada 15 s MESMO PARADO, wake lock;
  iOS com localização em fundo, sem pausa automática. Usado no TVDE e nas entregas
  (item 5: o estafeta do delivery fica coberto pelo mesmo caminho).
- Ao ficar online, uma vez por instalação: explicação PT-PT + "Permitir sempre" +
  "Não otimizar" a bateria. Nunca bloqueia ficar online.
- `DriverLocationPingService`: 14 s (era 45 s).
- `BoraForegroundService`: tick 7,5 s, batimento a cada ~15 s (era 30 s); posição de
  reserva pela RPC autenticada `driver_update_location` quando a app principal morre
  (token de sessão guardado e renovado; sem RPC anónima nova).
- Item 3 (ecrã inteiro): já estava feito — canal `bora_orders_urgent_v3`, `fullScreenIntent`,
  categoria `call`, prioridade máxima, `FLAG_INSISTENT`. Não mexido.
- Item 4: `notify-tvde-driver` **v19 publicada** — token Google em cache e as leituras
  em paralelo. Antes: 1–8 s. Primeira oferta real depois do deploy (corrida `322aa6ef`,
  15:31:56): **push em 0,48 s**, motorista aceitou 3,5 s depois.
- Compatível com o trabalho da ronda-fecho A10 da mesma manhã (ping de posição no
  batimento de 30 s): os dois somam.

## Achado que muda a leitura do problema

Atraso pedido→1.ª oferta, últimos 3 dias (corridas na hora):

| Pagamento | corridas | média | máx |
|---|---|---|---|
| dinheiro | 7 | 4,8 s | 33 s (a `1e13a6ea`) |
| MB Way | 8 | 44,6 s | 70 s |
| cartão | 8 (6 canceladas sem oferta) | 65,9 s | 130 s |

Os "30–70 s" são quase todos **espera do pagamento**: com MB Way/cartão o despacho
só arranca quando o banco confirma (`dispatch_deferred`). O GPS velho explica o caso
de dinheiro (33 s). Decidir se se oferece ao motorista ANTES de o MB Way confirmar é
decisão de dinheiro/despacho (zona protegida) — fica como proposta, não feito.

**Cartão:** 6 de 8 corridas a cartão em 3 dias acabaram `payment_failed` /
`payment_abandoned` (`requires_payment_method` / `requires_action`). Reportado, fora
do âmbito (há a missão pagamento-cartão de 22/09).

**Reserva paga com a app fechada (bug existente, incluído na proposta):** o
stripe-webhook só marca `payment_status='succeeded'`; a reserva fica em
`aguarda_pagamento` e aos 15 min o sweep cancela-a com o dinheiro cobrado. A proposta
traz um trigger na base (`tr_tvde_reserva_paga_ativa`) que a activa — provado em
transação revertida: `aguarda_pagamento/pendente` → `a_procurar/succeeded`.

## Bloco B — ida-e-volta com reserva

App (já no código, escondido até ao "vai"): "Marcar para depois" no pacote → hora da
IDA → "E a volta?" ("Chamo quando terminar" predefinida / "Marcar hora da volta",
30 min–12 h) → dinheiro, cartão ou MB Way (pacote todo na marcação, sem tokens, sem
taxa de reserva). Agenda do motorista: "Ida · pacote" / "Volta · pacote".

Prova em transação revertida (9 casos, zero lixo confirmado por SELECT):
T1 dinheiro com volta marcada: ida `a_procurar`, ganho 375; volta `is_return_leg`,
tarifa 0, ganho 375; vale `reservado`, €8,00. · T2 ida feita → vale `usado`.
· T3 volta falha → vale `ativo` (12 h). · T4 cartão: as duas `aguarda_pagamento` →
depois do pagamento `a_procurar`; idempotente. · T5 cliente cancela a ida → vale
`anulado`, volta cancelada, reembolso pedido. · T6 "chamo quando terminar" → vale
`ativo` depois da ida. · T7 expirar não mata vale com volta marcada viva. · T8 volta
a 10 min → `return_too_soon`. · T9 `mark_paid` só service_role.

## Bloco C — painel admin (PT-BR)

- Migração `20260923170000_admin_tvde_atraso_oferta_e_pacote_reservas` **aplicada**
  (só leitura): `offer_delay_s` + `push_delay_s` em `admin_tvde_rides_list`; pacote,
  perna ligada e estado do vale em `admin_tvde_reservations_list`.
- Corridas: "Atraso da oferta: Xs · push +Ys" (vermelho acima de 10 s; cartão/MB Way
  marcado "inclui o pagamento online").
- /admin/tvde/reservas: bloco do pacote (IDA/VOLTA, volta marcada ou "cliente chama",
  vale). Cancelar/Trocar motorista por perna = os botões de cada cartão.
- Settings editáveis: `tvde_heartbeat_window_seconds`, `tvde_roundtrip_reservation_enabled`,
  `tvde_roundtrip_return_min_gap_minutes` (as de preço/ganho continuam blindadas).
