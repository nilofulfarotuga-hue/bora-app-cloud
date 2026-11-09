/// Missão m2 · bloco 5 (pedido do Danilo 08/11/2026, caso Jyosmi): quando a
/// oferta de um pedido AGENDADO toca antes de o pedido estar pronto, o cartão
/// diz em grande "Pedido agendado — fica pronto às 19:15", para o estafeta
/// não correr para a loja (que pode até estar fechada) e esperar à porta.
library;

/// Margem: se fica pronto daqui a menos de 2 minutos, já não é "agendado".
const Duration margemAgendado = Duration(minutes: 2);

/// A hora em que o pedido fica pronto: o que a loja prometeu
/// (`ready_at_promised`) ou, sem isso, a hora marcada (`scheduled_for`).
DateTime? horaProntoDoPedido(DateTime? scheduledFor, DateTime? readyAtPromised) =>
    readyAtPromised ?? scheduledFor;

/// "Pedido agendado — fica pronto às 19:15", ou null quando não se aplica.
String? textoPedidoAgendado({
  required DateTime? scheduledFor,
  required DateTime? readyAtPromised,
  required DateTime agora,
}) {
  final pronto = horaProntoDoPedido(scheduledFor, readyAtPromised);
  if (scheduledFor == null || pronto == null) return null;
  final local = pronto.toLocal();
  if (!local.isAfter(agora.add(margemAgendado))) return null;
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  final mesmoDia = local.year == agora.year &&
      local.month == agora.month &&
      local.day == agora.day;
  final dia = mesmoDia ? '' : ' de ${local.day}/${local.month}';
  return 'Pedido agendado — fica pronto às $hh:$mm$dia';
}
