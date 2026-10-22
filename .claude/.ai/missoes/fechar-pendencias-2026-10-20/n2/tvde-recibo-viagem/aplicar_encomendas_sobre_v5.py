"""N2 (21/10/2026): palavras de ENCOMENDA no e-mail do recibo (Edge tvde-recibo-viagem), por cima da v5 DO AR.

Uso: python -I aplicar_encomendas_sobre_v5.py <index_v5_do_ar.ts> <saida.ts>
Cada troca tem de aparecer exactamente as vezes esperadas; senao aborta e nao escreve nada.
Os numeros continuam todos a vir de _tvde_recibo (SQL). Passageiros: e-mail igual byte a byte.
"""
import io
import sys

ent, sai = sys.argv[1], sys.argv[2]
s = io.open(ent, encoding='utf-8', newline='').read()

TROCAS = [
    ("// v3  2026-09-30 (Resumo da viagem, cálculo, código, duração)\n",
     "// v3  2026-09-30 (Resumo da viagem, cálculo, código, duração)\n"
     "// v6  2026-10-21 (encomendas no motor do Bora Motorista: numa ENCOMENDA o e-mail diz\n"
     "//      entrega/estafeta; os numeros nao mudam; passageiros igual byte a byte)\n", 1),
    ("  if (!resendKey) return fim(false, 'resend_sem_chave')\n",
     "  if (!resendKey) return fim(false, 'resend_sem_chave')\n"
     "\n"
     "  // v6: o tipo da corrida so escolhe as palavras (o recibo SQL ja traz o titulo certo).\n"
     "  const { data: tipo } = await admin.from('tvde_rides').select('ride_kind').eq('id', rideId).maybeSingle()\n"
     "  const encomenda = tipo?.ride_kind === 'encomendas'\n", 1),
    ("      subject: `Resumo da tua viagem Bora · ${dataPt(recibo.data)}`,\n      html: htmlRecibo(recibo),\n",
     "      subject: `Resumo da tua ${encomenda ? 'entrega' : 'viagem'} Bora · ${dataPt(recibo.data)}`,\n      html: htmlRecibo(recibo, encomenda),\n", 1),
    ("function htmlRecibo(r: any): string {\n",
     "function htmlRecibo(r: any, encomenda = false): string {\n", 1),
    ("    linhas.push(linha('Serviço de transporte (motorista)', euro(r.transporte_cents)))\n",
     "    linhas.push(linha(encomenda ? 'Serviço de entrega (estafeta)' : 'Serviço de transporte (motorista)', euro(r.transporte_cents)))\n", 1),
    ("  linhas.push(linha('Valor da viagem', euro(r.valor_viagem_cents), !r.descontos_cents))\n",
     "  linhas.push(linha(encomenda ? 'Valor da entrega' : 'Valor da viagem', euro(r.valor_viagem_cents), !r.descontos_cents))\n", 1),
    ("`<br>Código da viagem: ${esc(r.codigo_viagem)}`",
     "`<br>${encomenda ? 'Código da entrega' : 'Código da viagem'}: ${esc(r.codigo_viagem)}`", 1),
    ("<br>Motorista: ${esc(r.motorista ?? '—')}</p>",
     "<br>${encomenda ? 'Estafeta' : 'Motorista'}: ${esc(r.motorista ?? '—')}</p>", 1),
]

for antes, depois, n in TROCAS:
    c = s.count(antes)
    if c != n:
        sys.exit(f'ABORTA: ancora aparece {c} vezes (esperava {n}): {antes[:70]!r}')
    s = s.replace(antes, depois)

io.open(sai, 'w', encoding='utf-8', newline='').write(s)
print('ok', len(TROCAS), 'trocas')
