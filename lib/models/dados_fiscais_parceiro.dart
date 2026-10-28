import '../utils/conformidade_mensagem.dart';

/// O que `parceiro_dados_fiscais(p_restaurant_id)` devolve (DAC7, Lei n.º
/// 36/2023). Missão boom-burger-2026-10-27, F3. Lido pelo dono da loja (sem
/// argumento, ou com o id da sua loja) e pelo admin (qualquer loja).
class DadosFiscaisParceiro {
  const DadosFiscaisParceiro({
    required this.restaurantId,
    required this.loja,
    this.legalName,
    this.nif,
    this.address,
    this.iban,
    this.birthDate,
    this.autocertificadoEm,
    this.autocertVersao,
    this.empresa = false,
    this.emFalta = const [],
  });

  final String restaurantId;
  final String loja;
  final String? legalName;
  final String? nif;
  final String? address;
  final String? iban;
  final DateTime? birthDate;

  /// `dsa_self_certified_at` (quando a loja confirmou a declaração).
  final DateTime? autocertificadoEm;

  /// `dsa_self_cert_version` (versão do texto da declaração).
  final String? autocertVersao;

  /// NIF de pessoa coletiva (começa por 5, 6, 7 ou 9): não se pede data de
  /// nascimento.
  final bool empresa;

  /// Códigos do que falta para a loja poder abrir ao público (ver
  /// [kCodigosEmFalta]).
  final List<String> emFalta;

  bool get completo => emFalta.isEmpty;

  /// Rótulos do que falta ("Nome legal", "NIF", ...).
  List<String> get rotulosEmFalta => emFalta.map(rotuloEmFalta).toList();

  static String? _texto(Object? v) {
    final t = v?.toString().trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  static DateTime? _data(Object? v) {
    final t = _texto(v);
    return t == null ? null : DateTime.tryParse(t);
  }

  factory DadosFiscaisParceiro.fromJson(Map<String, dynamic> j) =>
      DadosFiscaisParceiro(
        restaurantId: j['restaurant_id']?.toString() ?? '',
        loja: _texto(j['loja']) ?? '—',
        legalName: _texto(j['legal_name']),
        nif: _texto(j['nif']),
        address: _texto(j['address']),
        iban: _texto(j['iban']),
        birthDate: _data(j['birth_date']),
        autocertificadoEm: _data(j['dsa_self_certified_at']),
        autocertVersao: _texto(j['dsa_self_cert_version']),
        empresa: j['empresa'] == true,
        emFalta: codigosEmFalta(j['em_falta']),
      );
}
