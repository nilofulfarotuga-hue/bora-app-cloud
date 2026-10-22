import '../l10n/bora_lang.dart';
import '../l10n/tr.dart';
import 'ride_kind_textos.dart';

/// Tipo de pedido no motor do Bora Motorista (TVDE) — `tvde_rides.ride_kind`.
///
/// 21/10/2026 (fechar-pendencias A1, "um motor só"): as ENCOMENDAS correm no
/// mesmo motor das corridas de passageiros — mesmo preço, mesmo despacho,
/// mesmos pagamentos, reservas e cancelamento. **Só mudam as palavras**, e as
/// palavras vivem num mapa único ([kTextosEncomendas]), nunca em ecrãs copiados.
enum RideKind { passageiros, encomendas }

extension RideKindDb on RideKind {
  /// Valor gravado em `tvde_rides.ride_kind` e mandado em `p_ride_kind`.
  String get db => this == RideKind.encomendas ? 'encomendas' : 'passageiros';

  bool get isEncomenda => this == RideKind.encomendas;
}

/// Lê o valor da base. Tudo o que não for exactamente 'encomendas' (null,
/// coluna ainda não existente numa resposta antiga, texto estranho) é
/// passageiros — que é o que todas as corridas eram antes de 21/10.
RideKind rideKindFromDb(Object? v) =>
    v?.toString() == 'encomendas' ? RideKind.encomendas : RideKind.passageiros;

/// Palavras que NUNCA podem aparecer num ecrã de encomenda (PT) — o teste
/// `test/ride_kind_textos_test.dart` usa esta mesma regra.
final RegExp kPalavrasDePassageiro =
    RegExp(r'corrida|motorista|viagem|passageir|boleia|condutor', caseSensitive: false);

/// O mesmo em inglês.
final RegExp kPalavrasDePassageiroEn = RegExp(
    r'\b(ride|rides|driver|drivers|trip|trips|passenger|passengers|journey)\b',
    caseSensitive: false);

/// A camada de etiquetas. A chave é SEMPRE o texto de passageiros que já
/// existia (assim o ecrã de passageiros fica byte a byte igual e o inglês dele
/// continua a vir de `kStringsEn`); numa encomenda troca-se pela versão do mapa.
extension RideKindTexto on String {
  /// Ecrãs do motorista e do painel (só português).
  String rk(RideKind k) =>
      k == RideKind.encomendas ? (kTextosEncomendas[this]?.$1 ?? this) : this;

  /// App do cliente (PT/EN). Passageiros = exactamente o `.tr` de sempre.
  String trK(RideKind k) {
    if (k != RideKind.encomendas) return tr;
    final e = kTextosEncomendas[this];
    if (e == null) return tr;
    return BoraLang.isEnglish ? e.$2 : e.$1;
  }

  /// Igual a [trK] com marcadores `{0}`, `{1}`… (como `trArgs`).
  String trArgsK(RideKind k, List<Object?> args) {
    var out = trK(k);
    for (var i = 0; i < args.length; i++) {
      out = out.replaceAll('{$i}', '${args[i]}');
    }
    return out;
  }

  /// [rk] com marcadores (ecrãs só em português).
  String rkArgs(RideKind k, List<Object?> args) {
    var out = rk(k);
    for (var i = 0; i < args.length; i++) {
      out = out.replaceAll('{$i}', '${args[i]}');
    }
    return out;
  }
}
