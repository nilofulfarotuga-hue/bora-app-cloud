/// Porque é que o pagamento MB WAY não arrancou, dito ao cliente em português
/// de Portugal.
///
/// Missão fechar-app-15-11 (Bloco 5). Em 14 dias houve 4 pedidos cancelados
/// por `payment_failed`, todos MB WAY, e o cliente só via "Não foi possível
/// iniciar o pagamento MBWay", sem saber porquê, já sem carrinho e de volta
/// ao início. O servidor (`create-mbway-payment-intent`) responde com um
/// código HTTP e um texto curto em inglês; aqui traduz-se isso numa frase que
/// diz o que fazer a seguir. Só texto: não decide valores nem pagamentos.
library;

/// Frase comum a todas as falhas: o carrinho não se perdeu.
const String mbwayCarrinhoContinua =
    'O teu carrinho continua aqui: tenta outra vez ou escolhe outro meio de pagamento.';

/// O cliente não confirmou na app MB WAY (cancelou, recusou, não tinha saldo
/// ou passou o tempo).
const String mbwayNaoConfirmado =
    'O pagamento MB WAY não foi confirmado: foi cancelado, recusado na app '
    'MB WAY ou passou o tempo. $mbwayCarrinhoContinua';

/// Traduz a resposta do servidor numa frase para o cliente.
///
/// [status] é o código HTTP (null quando nem houve resposta, p. ex. sem rede)
/// e [erro] o texto que o servidor devolveu em `error` (ou a exceção).
String mensagemErroMbway({int? status, String? erro}) {
  final e = (erro ?? '').toLowerCase();
  final String motivo;
  if (status == null &&
      (e.contains('socket') ||
          e.contains('network') ||
          e.contains('timeout') ||
          e.contains('failed host lookup') ||
          e.contains('connection'))) {
    motivo = 'Não há ligação à internet para pedir o pagamento MB WAY.';
  } else if (status == 401 || e.contains('unauthorized') || e.contains('missing_token')) {
    motivo = 'A tua sessão terminou. Entra outra vez na tua conta para pagar com MB WAY.';
  } else if (e.contains('amount too small')) {
    motivo = 'O MB WAY só aceita pagamentos a partir de 0,50 €.';
  } else if (status == 409 || e.contains('already processed')) {
    motivo = 'Este pedido já tinha sido tratado, por isso o MB WAY não foi pedido outra vez.';
  } else if (e.contains('phone') ||
      e.contains('billing_details') ||
      e.contains('mb_way') && e.contains('invalid')) {
    motivo = 'Esse número de telemóvel não foi aceite pelo MB WAY. '
        'Confirma se é o número que tens na app MB WAY.';
  } else if (status == 404 || e.contains('order not found')) {
    motivo = 'Não encontrámos o pedido para pedir o pagamento MB WAY.';
  } else if (status != null && status >= 500) {
    motivo = 'O MB WAY não aceitou o pedido de pagamento neste momento.';
  } else {
    motivo = 'Não foi possível pedir o pagamento MB WAY.';
  }
  return '$motivo $mbwayCarrinhoContinua';
}
