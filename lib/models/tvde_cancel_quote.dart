// [17/10/2026 · missão cancelamento-tardio] Cotação do cancelamento que o
// SERVIDOR dá antes de o cliente confirmar (`tvde_cancel_quote`).
//
// Porquê: o diálogo de cancelar calculava a pré-visualização sozinho — a
// janela grátis contada desde o PEDIDO (`createdAt`) e o valor pelo
// `TvdeFareView` —, enquanto o servidor conta desde o motorista ACEITAR e
// decide pelo tipo de corrida (normal = corrida inteira; plano, pacote,
// marcada, balcão, fila, preço combinado = taxa fixa). A app podia prometer
// um valor e cobrar outro. Agora o diálogo mostra só o que o servidor diz.
// A cotação nunca traz o que o motorista recebe, e aqui também não entra.

import '../l10n/tr.dart';

/// Regras que o servidor devolve em `regra`.
const Set<String> kRegrasDeCancelamento = {
  'sem_custo',
  'dentro_da_graca',
  'corrida_inteira',
  'taxa_fixa',
};

class TvdeCancelQuote {
  const TvdeCancelQuote({
    this.ok = true,
    required this.terminal,
    this.status,
    this.regra = '',
    this.feeCents = 0,
    this.fareCents = 0,
    this.comoCobra,
    this.graceSeconds = 0,
    this.secondsSinceAccept = 0,
    this.secondsLeftFree = 0,
    this.hadDriver = false,
    this.acceptedAt,
  });

  final bool ok;
  final bool terminal;

  /// Só nas respostas terminais: o estado em que a corrida já está.
  final String? status;

  /// `sem_custo` | `dentro_da_graca` | `corrida_inteira` | `taxa_fixa`
  /// ('' nas respostas terminais).
  final String regra;
  final int feeCents;
  final int fareCents;

  /// `pagamento_retido` | `carteira` | null.
  final String? comoCobra;
  final int graceSeconds;
  final int secondsSinceAccept;
  final int secondsLeftFree;
  final bool hadDriver;
  final DateTime? acceptedAt;

  /// Lê a resposta da RPC. Devolve `null` em tudo o que não for uma cotação
  /// válida: `ok:false` (ride_not_found / not_authorized / quote_failed),
  /// resposta vazia, tipos trocados ou uma regra que esta versão da app não
  /// conhece — nesses casos o ecrã mostra o aviso neutro, sem números.
  static TvdeCancelQuote? fromJson(Object? raw) {
    Object? r = raw;
    if (r is List) r = r.isEmpty ? null : r.first;
    if (r is! Map) return null;
    final m = Map<String, dynamic>.from(r);
    if (m['ok'] != true) return null;
    final terminal = m['terminal'] == true;
    final regra = m['regra']?.toString() ?? '';
    if (!terminal && !kRegrasDeCancelamento.contains(regra)) return null;
    final status = m['status']?.toString();
    if (terminal && (status == null || status.isEmpty)) return null;
    return TvdeCancelQuote(
      terminal: terminal,
      status: status,
      regra: regra,
      feeCents: _int(m['fee_cents']),
      fareCents: _int(m['fare_cents']),
      comoCobra: m['como_cobra']?.toString(),
      graceSeconds: _int(m['grace_seconds']),
      secondsSinceAccept: _int(m['seconds_since_accept']),
      secondsLeftFree: _int(m['seconds_left_free']),
      hadDriver: m['had_driver'] == true,
      acceptedAt: m['accepted_at'] == null
          ? null
          : DateTime.tryParse(m['accepted_at'].toString()),
    );
  }

  /// A corrida já acabou ou já foi cancelada (noutro aparelho, pelo motorista,
  /// pelo cron). `sem_motorista` NÃO conta: aí cancelar continua possível e
  /// sem custo — o RPC aceita.
  bool get jaTerminou => terminal && status != 'sem_motorista';

  /// A taxa que o diálogo mostra (e que o cliente aceita ao confirmar).
  int get taxaAMostrar => terminal ? 0 : feeCents;
}

int _int(Object? v) {
  if (v is num) return v.toInt();
  if (v is String) return num.tryParse(v)?.toInt() ?? 0;
  return 0;
}

/// [17/10] A taxa que o servidor REALMENTE cobrou, lida da linha que
/// `tvde_cancel_ride` devolve (`cancel_fee_cents`). 0 se ilegível.
int taxaCobradaDoCancelamento(Object? res) {
  Object? r = res;
  if (r is List) r = r.isEmpty ? null : r.first;
  if (r is! Map) return 0;
  final v = _int(r['cancel_fee_cents']);
  return v < 0 ? 0 : v;
}

/// Euros à portuguesa, sem o símbolo: 375 → "3,75".
String eurosPt(int cents) =>
    (cents / 100).toStringAsFixed(2).replaceAll('.', ',');

/// Contador mm:ss: 75 → "01:15".
String mmSs(int segundos) {
  final s = segundos < 0 ? 0 : segundos;
  final mm = (s ~/ 60).toString().padLeft(2, '0');
  final ss = (s % 60).toString().padLeft(2, '0');
  return '$mm:$ss';
}

/// O que o diálogo de cancelar diz. Decidido SÓ pela cotação do servidor
/// (função pura; testes em `test/tvde_cancel_quote_test.dart`).
class TextoCancelamento {
  const TextoCancelamento({
    required this.principal,
    required this.confirmar,
    required this.taxaCents,
    this.caixaCusto,
    this.detalhe,
    this.contador = false,
    this.semCotacao = false,
  });

  /// Frase principal do diálogo.
  final String principal;

  /// Caixa vermelha com o custo (só na corrida inteira).
  final String? caixaCusto;

  /// Linha pequena por baixo (como se cobra / o que acontece depois).
  final String? detalhe;

  /// Texto do botão de confirmar.
  final String confirmar;

  /// A taxa que o cliente vê e aceita ao confirmar. -1 = aviso neutro (sem
  /// cotação, nenhum número mostrado).
  final int taxaCents;

  /// Dentro da janela grátis: o diálogo mostra um contador vivo.
  final bool contador;

  /// Sem cotação do servidor: aviso neutro.
  final bool semCotacao;
}

/// [q] null = a cotação falhou (rede, prazo, `ok:false`). [minutosDaJanela]
/// só se usa no aviso neutro. [segundosRestantes] é o contador vivo da janela
/// grátis (por omissão, o que o servidor disse).
TextoCancelamento textoDoCancelamento(
  TvdeCancelQuote? q, {
  required int minutosDaJanela,
  int? segundosRestantes,
}) {
  if (q == null) {
    return TextoCancelamento(
      principal:
          'Não foi possível confirmar agora o custo do cancelamento. Se o motorista já aceitou há mais de {0} min, cancelar custa o valor da corrida. Queres cancelar na mesma?'
              .trArgs([minutosDaJanela]),
      confirmar: 'Cancelar na mesma'.tr,
      taxaCents: -1,
      semCotacao: true,
    );
  }
  final taxa = q.taxaAMostrar;
  final confirmar = taxa == 0
      ? 'Sim, cancelar'.tr
      : 'Cancelar e pagar {0} €'.trArgs([eurosPt(taxa)]);
  // Terminal `sem_motorista` (o único terminal que chega ao diálogo) é o
  // mesmo que nenhum motorista ter aceitado.
  if (q.terminal) {
    return TextoCancelamento(
      principal: 'Ainda nenhum motorista aceitou. Cancelas sem custo.'.tr,
      confirmar: confirmar,
      taxaCents: 0,
    );
  }
  switch (q.regra) {
    case 'dentro_da_graca':
      final restam = segundosRestantes ?? q.secondsLeftFree;
      return TextoCancelamento(
        principal:
            'Cancelamento grátis durante mais {0} (conta desde que o motorista aceitou).'
                .trArgs([mmSs(restam)]),
        detalhe: q.fareCents > 0
            ? 'Passado esse tempo, cancelar passa a ter custo (até {0} €, o valor da corrida).'
                .trArgs([eurosPt(q.fareCents)])
            : null,
        confirmar: confirmar,
        taxaCents: taxa,
        contador: true,
      );
    case 'corrida_inteira':
      final minutos = (q.graceSeconds / 60).round();
      return TextoCancelamento(
        caixaCusto: 'Custo de cancelamento: {0} €'.trArgs([eurosPt(taxa)]),
        principal:
            'O motorista já aceitou há mais de {0} min. Cancelar agora custa o valor total da corrida.'
                .trArgs([minutos]),
        detalhe: switch (q.comoCobra) {
          'pagamento_retido' =>
            'Esta corrida já está paga: o valor pago fica retido.'.tr,
          'carteira' =>
            'O valor é debitado da tua carteira Bora (se não tiveres saldo, fica como dívida).'
                .tr,
          _ => null,
        },
        confirmar: confirmar,
        taxaCents: taxa,
      );
    case 'taxa_fixa':
      return TextoCancelamento(
        principal: 'Cancelar agora tem uma taxa de {0} €.'
            .trArgs([eurosPt(taxa)]),
        confirmar: confirmar,
        taxaCents: taxa,
      );
    case 'sem_custo':
    default:
      return TextoCancelamento(
        principal: q.hadDriver
            ? 'Cancelamento sem custo.'.tr
            : 'Ainda nenhum motorista aceitou. Cancelas sem custo.'.tr,
        confirmar: confirmar,
        taxaCents: taxa,
      );
  }
}

/// SnackBar depois de cancelar: o que foi mesmo cobrado.
String textoDepoisDeCancelar(int taxaCobradaCents) => taxaCobradaCents > 0
    ? 'Corrida cancelada. Foram cobrados {0} €.'
        .trArgs([eurosPt(taxaCobradaCents)])
    : 'Corrida cancelada. Sem custo.'.tr;

/// SnackBar quando a corrida já tinha terminado antes de o cliente cancelar.
String textoJaTerminou(TvdeCancelQuote q) => q.status == 'finalizada'
    ? 'A corrida já tinha terminado.'.tr
    : 'A corrida já estava cancelada.'.tr;
