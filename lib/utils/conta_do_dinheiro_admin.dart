// 28/10/2026 (missao-geral, Bloco 1, C4) — painel admin (PT-BR): a conta do
// dinheiro de um pedido, linha a linha, a partir das colunas que o próprio
// pedido já traz. Só leitura: não muda nada em nenhum valor.
//
// O aviso vermelho usa a MESMA regra da vigia do servidor
// (`vigia_dinheiro_a_cobrar`, proposta C5): pedido a dinheiro com
// cash_total_due > (final_total ou price) − saldo − tokens − crédito de menu
// + 0,01. A dívida anterior fica fora da regra de propósito (o create_order
// também a deixa fora do cash_total_due; a app do entregador soma-a por cima).

class LinhaContaDinheiro {
  const LinhaContaDinheiro(this.rotulo, this.valor, {this.destaque = false});

  final String rotulo;
  final String valor;
  final bool destaque;
}

class ContaDoDinheiroAdmin {
  const ContaDoDinheiroAdmin({required this.linhas, this.aviso});

  final List<LinhaContaDinheiro> linhas;

  /// Texto do aviso vermelho, ou null quando a conta bate.
  final String? aviso;
}

double? _eurDe(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int _centsDe(dynamic v) {
  if (v is num) return v.round();
  if (v is String) return (double.tryParse(v) ?? 0).round();
  return 0;
}

String _fmt(double v) => '€${v.toStringAsFixed(2)}';

/// Monta as linhas da secção "Conta do dinheiro (linha a linha)".
/// [pedido] = a linha de `orders` que o ecrã carrega; [talaoLoja] = o
/// `talao_loja` do `admin_order_cash_breakdown` (null enquanto não chega ou
/// sem permissão).
ContaDoDinheiroAdmin contaDoDinheiroAdmin(
  Map<String, dynamic> pedido, {
  double? talaoLoja,
}) {
  final total =
      _eurDe(pedido['final_total']) ?? _eurDe(pedido['price']) ?? 0;
  final saldo = _centsDe(pedido['wallet_applied_cents']) / 100.0;
  final tokens = _centsDe(pedido['tokens_applied_value_cents']) / 100.0;
  final credito = _centsDe(pedido['menu_credit_applied_cents']) / 100.0;
  final divida = _centsDe(pedido['debt_collected_cents']) / 100.0;
  final cashDue = _eurDe(pedido['cash_total_due']);
  final isCash = pedido['payment_method'] == 'cash';

  final linhas = <LinhaContaDinheiro>[
    LinhaContaDinheiro('Total do pedido', _fmt(total), destaque: true),
    LinhaContaDinheiro('Saldo Bora usado', _fmt(saldo)),
    LinhaContaDinheiro('Tokens usados (valor em €)', _fmt(tokens)),
    LinhaContaDinheiro('Crédito de menu', _fmt(credito)),
    LinhaContaDinheiro('Dívida anterior', _fmt(divida)),
    LinhaContaDinheiro(
      'Dinheiro a cobrar na porta (valor gravado pelo servidor)',
      cashDue != null ? _fmt(cashDue) : '—',
      destaque: true,
    ),
    LinhaContaDinheiro(
      'Valor do talão da loja',
      talaoLoja != null && talaoLoja > 0 ? _fmt(talaoLoja) : '—',
    ),
  ];

  String? aviso;
  if (isCash && cashDue != null) {
    var devia = total - saldo - tokens - credito;
    if (devia < 0) devia = 0;
    devia = (devia * 100).roundToDouble() / 100;
    if (cashDue > devia + 0.01) {
      aviso = 'Atenção: o entregador vai cobrar ${_fmt(cashDue)} em dinheiro, '
          'mas o cliente só deve ${_fmt(devia)} '
          '(total − saldo − tokens − crédito de menu). '
          'O resto já foi pago com saldo/tokens — conferir antes do acerto.';
    }
  }
  return ContaDoDinheiroAdmin(linhas: linhas, aviso: aviso);
}
