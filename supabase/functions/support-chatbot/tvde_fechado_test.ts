// M10 09/11/2026 (2.11): com o Bora Motorista fechado o robô não fala de corridas.
// Correr: deno test --no-lock --allow-read=. tvde_fechado_test.ts
import { FERRAMENTAS_TVDE, semBoraMotorista, TVDE_FECHADO_AVISO } from './tvde_fechado.ts';

function igual(a: unknown, b: unknown, msg: string) {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}: ${JSON.stringify(a)} != ${JSON.stringify(b)}`);
}
function verdade(c: boolean, msg: string) {
  if (!c) throw new Error(msg);
}

Deno.test('as âncoras que o corte procura existem no index.ts (se mudarem, o corte deixa de funcionar)', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  verdade(src.split("'RESERVAS DE CORRIDA (TVDE").length - 1 === 2, 'duas secções de reservas de corrida (Gemini e Claude)');
  verdade(src.split("'- Cancelar a corrida marcada").length - 1 === 2, 'a última linha de cada secção');
  verdade(src.includes(', reservas de mesa e corridas marcadas (TVDE)'), 'apresentação do Claude');
  verdade(src.includes(' Corridas de carro → agent_get_my_tvde_reservations.'), 'guia das ferramentas');
  verdade(src.includes(' Corridas de carro: agent_get_my_tvde_reservations.'), 'descrição de agent_get_my_bookings');
  for (const n of FERRAMENTAS_TVDE) verdade(src.includes(`name: '${n}'`), `ferramenta ${n} existe`);
});

Deno.test('corta a secção inteira, troca pelo aviso e tira as menções; o resto fica igual', () => {
  const texto = [
    'És o assistente de ajuda da Bora App, dentro da app: entregas, Favores, reservas de mesa e corridas marcadas (TVDE), na Guarda.',
    '- Marcações → agent_get_my_bookings. Corridas de carro → agent_get_my_tvde_reservations.',
    'RESERVAS DE MESA: pagas €3.',
    '',
    'RESERVAS DE CORRIDA (TVDE / "Bora Motorista": corrida marcada)',
    '- Mudar a HORA: tvde_reservation_reschedule.',
    '- Mudar o DESTINO: tvde_reservation_dest_quote.',
    '- Cancelar a corrida marcada: na app, em "As minhas reservas".',
    '',
    'FERRAMENTAS DE PROPOSTA',
  ].join('\n');
  const out = semBoraMotorista(texto);
  verdade(!/tvde_reservation|RESERVAS DE CORRIDA|corridas marcadas|agent_get_my_tvde/.test(out), 'sem corridas: ' + out);
  verdade(out.includes(TVDE_FECHADO_AVISO), 'leva o aviso de fechado');
  verdade(out.includes('RESERVAS DE MESA: pagas €3.'), 'reservas de mesa ficam');
  verdade(out.includes('FERRAMENTAS DE PROPOSTA'), 'o que vem depois fica');
  verdade(out.includes('entregas, Favores e reservas de mesa, na Guarda.'), 'apresentação sem TVDE: ' + out.split('\n')[0]);
});

Deno.test('texto sem corridas não muda', () => {
  const t = 'Reservas de mesa: €3.\nFavores: farmácia.';
  igual(semBoraMotorista(t), t, 'igual');
});
