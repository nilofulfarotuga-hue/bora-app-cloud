"""N2 (21/10/2026): palavras de ENCOMENDA na Edge notify-tvde-client, por cima da v7 DO AR.

Uso: python -I aplicar_encomendas_sobre_v7.py <index_v7_do_ar.ts> <saida.ts>
Cada troca tem de aparecer exactamente as vezes esperadas; senao aborta e nao escreve nada.
Passageiros: frases iguais (statusMessage intacta para encomenda=false).
Encomendas: as mesmas frases do gatilho fn_notify_tvde_client_on_status + as duas de reserva
('agendada' e 'reserva_confirmar', mandadas pelo varrimento das reservas so com o estado).
"""
import io
import sys

ent, sai = sys.argv[1], sys.argv[2]
s = io.open(ent, encoding='utf-8', newline='').read()

ENC = '''function statusMessageEncomenda(status: string, driverName: string): { title: string; body: string } | null {
  const d = driverName ? driverName : 'O teu estafeta'
  switch (status) {
    case 'motorista_atribuido':
    case 'motorista_a_caminho':
      return { title: '\U0001F4E6 Estafeta a caminho da recolha', body: `${d} vem buscar a tua encomenda.` }
    case 'motorista_chegou':
      return { title: '\U0001F4CD O estafeta chegou à recolha', body: `${d} está no local de recolha.` }
    case 'em_andamento':
      return { title: '\U0001F4E6 Encomenda recolhida', body: 'A tua encomenda vai a caminho da entrega. O preço é o que viste ao pedir.' }
    case 'finalizada':
      return { title: '✅ Encomenda entregue', body: 'A entrega foi concluída. Avalia a entrega na app.' }
    case 'sem_motorista':
      return { title: '\U0001F615 Sem estafetas disponíveis', body: 'Não encontrámos estafeta a tempo e o pedido foi cancelado. Se pagaste na app, o valor é devolvido. Podes tentar de novo.' }
    case 'cancelada_motorista':
      return { title: 'Entrega cancelada', body: 'O estafeta cancelou a entrega. Pedimos desculpa — tenta de novo.' }
    case 'agendada':
      return { title: 'Reserva marcada', body: 'A tua encomenda ficou marcada. Avisamos-te assim que houver estafeta.' }
    case 'reserva_confirmar':
      return { title: 'Ainda queres a tua entrega?', body: 'A tua reserva é daqui a pouco. Abre a app para confirmar ou cancelar.' }
    default:
      return null
  }
}

function json('''

TROCAS = [
    ("// textos alinhados com o preco fixo e com o fim da procura (sem_motorista).\n",
     "// textos alinhados com o preco fixo e com o fim da procura (sem_motorista).\n"
     "//\n"
     "// v8 (2026-10-21, encomendas no motor do Bora Motorista): le tvde_rides.ride_kind e,\n"
     "// numa ENCOMENDA, as frases sao de entrega (iguais as do gatilho\n"
     "// fn_notify_tvde_client_on_status), incluindo as duas de reserva ('agendada' e\n"
     "// 'reserva_confirmar'). Passageiros: frases de sempre. Nada mais mudou.\n", 1),
    ("    .select('client_id, driver_id, status')\n",
     "    .select('client_id, driver_id, status, ride_kind')\n", 1),
    ("    : statusMessage(status, driverName)\n",
     "    : statusMessage(status, driverName, ride.ride_kind === 'encomendas')\n", 1),
    ("function statusMessage(status: string, driverName: string): { title: string; body: string } | null {\n",
     "function statusMessage(status: string, driverName: string, encomenda = false): { title: string; body: string } | null {\n"
     "  if (encomenda) return statusMessageEncomenda(status, driverName)\n", 1),
    ("function json(", ENC, 1),
]

for antes, depois, n in TROCAS:
    c = s.count(antes)
    if c != n:
        sys.exit(f'ABORTA: ancora aparece {c} vezes (esperava {n}): {antes[:70]!r}')
    s = s.replace(antes, depois)

io.open(sai, 'w', encoding='utf-8', newline='').write(s)
print('ok', len(TROCAS), 'trocas')
