"""Aplica as palavras de ENCOMENDA à Edge notify-tvde-driver **por cima da v22 do ar**.

Uso (no dia de ligar `tvde_encomendas_enabled`):
  1. ler a versão do ar com `get_edge_function notify-tvde-driver` e gravá-la em v22_no_ar.ts
     (tem de dar o mesmo md5 que o v22_no_ar.ts deste pasta: d6d28e6a776c40a23810daceac478baa;
     se não der, o ar mudou — parar e rever);
  2. python aplicar_encomendas_sobre_v22.py v22_no_ar.ts index.ts
  3. rever `diff v22_no_ar.ts index.ts` (só as linhas abaixo) e publicar index.ts SEM o _shared/keys.ts
     do repo (a troca de chave é do Bloco G e não vai junto).

Cada troca tem de aparecer exactamente o número de vezes esperado; senão aborta e não escreve nada.
Passageiros: o texto enviado fica igual (ride_kind 'passageiros' ou ausente → frase de sempre).
"""
import io
import sys

ent, sai = sys.argv[1], sys.argv[2]
s = io.open(ent, encoding='utf-8', newline='').read()

TROCAS = [
    # 1. ler o tipo onde a frase depende dele
    ("    .select('origin_label, dest_label, est_fare_cents, est_distance_km, driver_earn_cents, agreed_driver_earn_cents, agreed_fare_cents, payment_method, offer_expires_at, current_offer_driver_id, status')",
     "    .select('origin_label, dest_label, est_fare_cents, est_distance_km, driver_earn_cents, agreed_driver_earn_cents, agreed_fare_cents, payment_method, offer_expires_at, current_offer_driver_id, status, ride_kind')", 1),
    ("        .select('origin_label, dest_label')\n        .eq('id', rideId).maybeSingle()\n      if (ride) {\n        originLabel = ride.origin_label ?? originLabel\n        destLabel   = ride.dest_label ?? destLabel\n      }",
     "        .select('origin_label, dest_label, ride_kind')\n        .eq('id', rideId).maybeSingle()\n      if (ride) {\n        originLabel = ride.origin_label ?? originLabel\n        destLabel   = ride.dest_label ?? destLabel\n        encomendaCancelada = ride.ride_kind === 'encomendas'\n      }", 1),
    ("  if (kind === 'ride_cancelled') {\n    let originLabel = 'Recolha', destLabel = 'Destino'\n",
     "  if (kind === 'ride_cancelled') {\n    let originLabel = 'Recolha', destLabel = 'Destino'\n    let encomendaCancelada = false // [A1 21/10] encomenda: 'entrega', não 'corrida'\n", 1),
    ("          title: 'Corrida cancelada',\n          body:  `A corrida ${originLabel} -> ${destLabel} foi cancelada. Nao precisas de ir.`,",
     "          title: encomendaCancelada ? 'Entrega cancelada' : 'Corrida cancelada',\n          body:  encomendaCancelada\n            ? `A entrega ${originLabel} -> ${destLabel} foi cancelada. Nao precisas de ir.`\n            : `A corrida ${originLabel} -> ${destLabel} foi cancelada. Nao precisas de ir.`,", 1),
    ("          payload: { aps: { alert: { title: 'Corrida cancelada', body: `A corrida ${originLabel} -> ${destLabel} foi cancelada. Nao precisas de ir.` }, sound: 'default', 'content-available': 1, 'interruption-level': 'time-sensitive' } },",
     "          payload: { aps: { alert: { title: encomendaCancelada ? 'Entrega cancelada' : 'Corrida cancelada', body: encomendaCancelada ? `A entrega ${originLabel} -> ${destLabel} foi cancelada. Nao precisas de ir.` : `A corrida ${originLabel} -> ${destLabel} foi cancelada. Nao precisas de ir.` }, sound: 'default', 'content-available': 1, 'interruption-level': 'time-sensitive' } },", 1),
    # 2. fila / atribuída / passada a outro
    ("        .select('origin_label, dest_label, est_fare_cents, driver_earn_cents, payment_method')\n",
     "        .select('origin_label, dest_label, est_fare_cents, driver_earn_cents, payment_method, ride_kind')\n", 1),
    ("    let originLabel = 'Recolha', destLabel = 'Destino', earnEur = '0.00', fareEur = '0.00'\n    let mostraCobranca = false\n",
     "    let originLabel = 'Recolha', destLabel = 'Destino', earnEur = '0.00', fareEur = '0.00'\n    let mostraCobranca = false\n    let encomenda = false // [A1 21/10]\n", 1),
    ("        mostraCobranca = (ride.payment_method ?? 'cash') === 'cash' && cents > 0\n      }",
     "        mostraCobranca = (ride.payment_method ?? 'cash') === 'cash' && cents > 0\n        encomenda = ride.ride_kind === 'encomendas'\n      }", 1),
    ("        title = '🚗 Corrida em fila — depois desta'\n",
     "        title = encomenda ? '📦 Encomenda em fila — depois desta' : '🚗 Corrida em fila — depois desta'\n", 1),
    ("        body  = `${rota} • ${ganhaFrase}. Fica em fila e abre sozinha quando terminares a corrida actual.`\n",
     "        body  = encomenda\n          ? `${rota} • ${ganhaFrase}. Fica em fila e abre sozinha quando terminares a actual.`\n          : `${rota} • ${ganhaFrase}. Fica em fila e abre sozinha quando terminares a corrida actual.`\n", 1),
    ("        title = '🚗 Ficaste com uma corrida'\n",
     "        title = encomenda ? '📦 Ficaste com uma encomenda' : '🚗 Ficaste com uma corrida'\n", 1),
    ("        title = 'Corrida passada a outro motorista'\n        body  = `A corrida ${rota} foi passada a outro motorista. Não precisas de ir.`\n",
     "        title = encomenda ? 'Encomenda passada a outro estafeta' : 'Corrida passada a outro motorista'\n        body  = encomenda\n          ? `A encomenda ${rota} foi passada a outro estafeta. Não precisas de ir.`\n          : `A corrida ${rota} foi passada a outro motorista. Não precisas de ir.`\n", 1),
    # 3. reservas
    ("        .select('origin_label, dest_label, est_fare_cents, scheduled_at, reservation_offer_expires_at, driver_earn_cents, payment_method')\n",
     "        .select('origin_label, dest_label, est_fare_cents, scheduled_at, reservation_offer_expires_at, driver_earn_cents, payment_method, ride_kind')\n", 1),
    ("    let earnEur = '0.00', mostraCobranca = false\n    try {\n      const { data: ride } = await supabase\n        .from('tvde_rides')\n        .select('origin_label, dest_label, est_fare_cents, scheduled_at,",
     "    let earnEur = '0.00', mostraCobranca = false\n    let encomenda = false // [A1 21/10]\n    try {\n      const { data: ride } = await supabase\n        .from('tvde_rides')\n        .select('origin_label, dest_label, est_fare_cents, scheduled_at,", 1),
    ("        mostraCobranca = isCash && Number.isFinite(cents) && cents > 0\n      }",
     "        mostraCobranca = isCash && Number.isFinite(cents) && cents > 0\n        encomenda = ride.ride_kind === 'encomendas'\n      }", 1),
    ("        title = '📅 Reserva para aceitar'\n",
     "        title = encomenda ? '📦 Encomenda marcada para aceitar' : '📅 Reserva para aceitar'\n", 1),
    ("        title = '📅 Ficaste com uma reserva'\n",
     "        title = encomenda ? '📦 Ficaste com uma encomenda marcada' : '📅 Ficaste com uma reserva'\n", 1),
    ("        body  = `Às ${hora} • ${rota} • ${ganhaFrase}. Carrega \"A caminho\" — se não confirmares, a reserva passa a outro motorista.`\n",
     "        body  = `Às ${hora} • ${rota} • ${ganhaFrase}. Carrega \"A caminho\" — se não confirmares, a reserva passa a outro ${encomenda ? 'estafeta' : 'motorista'}.`\n", 1),
    ("        title = 'Reserva passou a outro motorista'\n        body  = `Não confirmaste a tempo a reserva das ${hora}. Foi entregue a outro motorista.`\n",
     "        title = encomenda ? 'Reserva passou a outro estafeta' : 'Reserva passou a outro motorista'\n        body  = `Não confirmaste a tempo a reserva das ${hora}. Foi entregue a outro ${encomenda ? 'estafeta' : 'motorista'}.`\n", 1),
    ("        title = 'Reserva passou a outro motorista'\n        body  = `O cliente mudou a hora para ${ptShort(scheduledAt)} às ${hora} e já tens outra reserva perto — passou a outro motorista.`\n",
     "        title = encomenda ? 'Reserva passou a outro estafeta' : 'Reserva passou a outro motorista'\n        body  = `O cliente mudou a hora para ${ptShort(scheduledAt)} às ${hora} e já tens outra reserva perto — passou a outro ${encomenda ? 'estafeta' : 'motorista'}.`\n", 1),
    # 4. a OFERTA na hora
    ("  let earnEur = '0.00', mostraCobranca = false, offerExpiresAt: string | null = null\n",
     "  let earnEur = '0.00', mostraCobranca = false, offerExpiresAt: string | null = null\n  // [A1 21/10] Encomenda no motor do Bora Motorista: o aviso diz encomenda.\n  let tituloOferta = '🚗 Nova corrida!', rideKind = 'passageiros'\n", 1),
    ("      offerExpiresAt = ride.offer_expires_at ?? null\n    }",
     "      offerExpiresAt = ride.offer_expires_at ?? null\n      if (ride.ride_kind === 'encomendas') { tituloOferta = '📦 Nova encomenda!'; rideKind = 'encomendas' }\n    }", 1),
    ("        title:      '🚗 Nova corrida!',\n",
     "        title:      tituloOferta,\n        rideKind,\n", 1),
    ("        payload: { aps: { alert: { title: '🚗 Nova corrida!', body: headsUpBody },",
     "        payload: { aps: { alert: { title: tituloOferta, body: headsUpBody },", 1),
]

for i, (de, para, n) in enumerate(TROCAS, 1):
    c = s.count(de)
    if c != n:
        sys.exit(f'troca {i}: apareceu {c} vez(es), esperava {n} — NADA foi escrito')
    s = s.replace(de, para)

cab = ("// v23 (2026-10-21, fechar-pendencias A1): ENCOMENDAS no motor do Bora Motorista —\n"
       "// le tvde_rides.ride_kind e, numa encomenda, os textos dizem encomenda/entrega/estafeta\n"
       "// (oferta, fila, atribuida, cancelada, reservas). Passageiros: textos iguais. Nada mais mudou.\n")
s = s.replace("// TVDE — Bora Motorista. Envia push FCM a um motorista de passageiros.\n",
              "// TVDE — Bora Motorista. Envia push FCM a um motorista de passageiros.\n" + cab, 1)
io.open(sai, 'w', encoding='utf-8', newline='').write(s)
print('ok', len(TROCAS), 'trocas')
