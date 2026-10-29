// 28/10/2026 (missao-geral, Bloco 1, C3) — a "conta curta" do dinheiro.
//
// Caso real de 28/10: pedido de 14,35 € pago quase todo com saldo Bora e
// tokens. O estafeta via "RECEBER 14,35 €" e o cliente só devia 3,31 €. O
// valor a cobrar já vem certo do modelo (`totalToCollectCash`, servidor
// primeiro); isto só EXPLICA de onde vem, numa linha:
//
//   "Total 14,35 € · já pago com saldo/tokens 11,04 € · RECEBER 3,31 €"
//
// Só apresentação: nenhuma conta de preço muda aqui.
import '../models/order_model.dart';
import 'euros.dart';
import 'favor_passos.dart' show favorComDinheiroDeCasa;

/// Total do pedido sem a dívida anterior: o final do talão quando existe,
/// senão o preço da criação.
double _totalDoPedido(OrderModel o) => o.finalTotal ?? o.total;

/// A linha curta para o estafeta, ou null quando não há nada a explicar:
/// pagamento que não é dinheiro, nada pago antes com saldo/tokens/crédito de
/// menu, ou Favor em que o estafeta leva o dinheiro de casa (aí a conta é a
/// do troco, no cartão do Favor).
///
/// RECEBER é sempre [OrderModel.totalToCollectCash] — o mesmo número da faixa
/// laranja — que já inclui a dívida anterior; quando há dívida, ela aparece
/// na linha para a conta bater.
String? contaCurtaDinheiro(OrderModel o) {
  if (o.paymentMethod != PaymentMethod.cash) return null;
  if (favorComDinheiroDeCasa(o)) return null;
  final jaPago = o.jaPagoSemDinheiro;
  if (jaPago <= 0) return null;
  final partes = <String>[
    'Total ${eur(_totalDoPedido(o))}',
    'já pago com saldo/tokens ${eur(jaPago)}',
    if (o.debtCollectedCents > 0)
      'dívida anterior ${eur(o.debtCollectedCents / 100.0)}',
    'RECEBER ${eur(o.totalToCollectCash)}',
  ];
  return partes.join(' · ');
}

/// Para os ecrãs do cliente: quanto paga em dinheiro à porta e quanto já
/// pagou com saldo/tokens/crédito de menu. null quando não é dinheiro ou não
/// há nada pago antes (aí o "Total" já é o que paga).
({double emDinheiro, double jaPago})? dinheiroDoCliente(OrderModel o) {
  if (o.paymentMethod != PaymentMethod.cash) return null;
  // 29/10 (revisor): Favor com o dinheiro levado de casa é a conta do troco,
  // não um "paga em dinheiro" — como no contaCurtaDinheiro.
  if (favorComDinheiroDeCasa(o)) return null;
  final jaPago = o.jaPagoSemDinheiro;
  if (jaPago <= 0) return null;
  return (emDinheiro: o.totalToCollectCash, jaPago: jaPago);
}
