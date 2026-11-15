/// Porque é que o pagamento MB WAY não arrancou, dito ao cliente em português
/// de Portugal (e em inglês, pelo `.tr`, quando a app está em inglês).
///
/// Missão fechar-app-15-11 (Bloco 5). Em 14 dias houve 4 pedidos cancelados
/// por `payment_failed`, todos MB WAY, e o cliente só via "Não foi possível
/// iniciar o pagamento MBWay", sem saber porquê, já sem carrinho e de volta
/// ao início. O servidor (`create-mbway-payment-intent`) responde com um
/// código HTTP e um texto curto em inglês; aqui traduz-se isso numa frase que
/// diz o que fazer a seguir. Só texto: não decide valores nem pagamentos.
///
/// Revisão 15/11 (achados 6 e 17): cada frase é um texto inteiro com `.tr`
/// (a chave do dicionário é a frase), sempre "MB WAY", e o pedido antigo que
/// pode continuar na app do banco é lembrado ao cliente.
library;

import '../l10n/tr.dart';

/// O que vem a seguir a qualquer falha em que o pedido de pagamento pode ter
/// chegado à app MB WAY: o carrinho não se perdeu, e o pedido antigo, se ainda
/// lá estiver, recusa-se lá (o cancelamento da Bora não o tira da app do
/// banco — ver docs/propostas/fechar-app-15-11/mbway-cancelar-pagamento.md).
String get mbwayCarrinhoContinua =>
    'O teu carrinho continua aqui: tenta outra vez ou escolhe outro meio de pagamento. Se o pedido antigo ainda aparecer na app MB WAY, recusa-o lá.'
        .tr;

/// MB WAY desligado no painel (`503 mbway_disabled`): tentar outra vez não
/// adianta, por isso só se diz para escolher outro meio.
String get mbwayDesligado =>
    'O MB WAY não está disponível de momento. O teu carrinho continua aqui: escolhe outro meio de pagamento.'
        .tr;

/// O cliente não confirmou na app MB WAY (cancelou, recusou, não tinha saldo
/// ou passou o tempo).
String get mbwayNaoConfirmado {
  final motivo =
      'O pagamento MB WAY não foi confirmado: foi cancelado, recusado na app MB WAY ou passou o tempo.'
          .tr;
  return '$motivo $mbwayCarrinhoContinua';
}

/// A frase é a do MB WAY desligado? (aí não vale a pena "Tentar outra vez").
bool eMbwayDesligado(String frase) => frase == mbwayDesligado;

/// Traduz a resposta do servidor numa frase para o cliente.
///
/// [status] é o código HTTP (null quando nem houve resposta, p. ex. sem rede)
/// e [erro] o texto que o servidor devolveu em `error` (ou a exceção).
String mensagemErroMbway({int? status, String? erro}) {
  final e = (erro ?? '').toLowerCase();
  if (status == 503 || e.contains('mbway_disabled')) return mbwayDesligado;
  final String motivo;
  if (status == null &&
      (e.contains('socket') ||
          e.contains('network') ||
          e.contains('timeout') ||
          e.contains('failed host lookup') ||
          e.contains('connection'))) {
    motivo = 'Não há ligação à internet para pedir o pagamento MB WAY.'.tr;
  } else if (status == 401 || e.contains('unauthorized') || e.contains('missing_token')) {
    motivo = 'A tua sessão terminou. Entra outra vez na tua conta para pagar com MB WAY.'.tr;
  } else if (e.contains('amount too small')) {
    motivo = 'O MB WAY só aceita pagamentos a partir de 0,50 €.'.tr;
  } else if (status == 409 || e.contains('already processed')) {
    motivo = 'Este pedido já não estava à espera de pagamento, por isso o MB WAY não foi pedido outra vez.'.tr;
  } else if (e.contains('phone') ||
      e.contains('billing_details') ||
      e.contains('mb_way') && e.contains('invalid')) {
    motivo = 'Esse número de telemóvel não foi aceite pelo MB WAY. Confirma se é o número que tens na app MB WAY.'.tr;
  } else if (status == 404 || e.contains('order not found')) {
    motivo = 'Não encontrámos o pedido para pedir o pagamento MB WAY.'.tr;
  } else if (status != null && status >= 500) {
    motivo = 'O MB WAY não aceitou o pedido de pagamento neste momento.'.tr;
  } else {
    motivo = 'Não foi possível pedir o pagamento MB WAY.'.tr;
  }
  return '$motivo $mbwayCarrinhoContinua';
}
