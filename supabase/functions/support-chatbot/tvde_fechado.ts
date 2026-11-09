// M10 09/11/2026 (item 2.11, ordem do Danilo de 04/11): com o Bora Motorista fechado
// (platform_settings.tvde_app_visivel=false) o robô não oferece corridas de carro. As ferramentas
// das reservas de corrida saem da lista e a parte das corridas sai das instruções; o histórico fica
// intocado (quem perguntar por uma corrida antiga é passado à equipa). Quando reabrir, volta tudo.
export const FERRAMENTAS_TVDE = [
  'agent_get_my_tvde_reservations',
  'tvde_reservation_reschedule',
  'tvde_reservation_dest_quote',
  'tvde_reservation_change_dest',
];
export const TVDE_FECHADO_AVISO =
  'BORA MOTORISTA (corridas de carro) está FECHADO: não ofereces nem explicas corridas. Se alguém perguntar por uma corrida antiga ou marcada, dizes que a equipa vai ver e acabas com [HANDOFF_HUMAN].';

export function semBoraMotorista(texto: string): string {
  let out = texto;
  const ini = out.indexOf('RESERVAS DE CORRIDA (TVDE');
  if (ini >= 0) {
    const ultima = out.indexOf('- Cancelar a corrida marcada', ini);
    const fim = ultima >= 0 ? out.indexOf('\n', ultima) : -1;
    if (fim > ini) out = out.slice(0, ini) + TVDE_FECHADO_AVISO + out.slice(fim);
  }
  return out
    .replace(', reservas de mesa e corridas marcadas (TVDE)', ' e reservas de mesa')
    .replace(' Corridas de carro → agent_get_my_tvde_reservations.', '')
    .replace(' Corridas de carro: agent_get_my_tvde_reservations.', '');
}
