/// Telemóvel de QUALQUER país (28/11/2026, adendo do Danilo 10:10): "não tem
/// que ser só telefone em português; se forem pessoas que não têm telefone
/// português, nós podemos entrar em contacto pelo WhatsApp".
///
/// - O cliente escolhe o indicativo (Portugal +351 por defeito) e escreve o
///   número; a validação é a do país escolhido (biblioteca
///   `phone_numbers_parser`, os dados do libphonenumber da Google).
/// - Grava-se SEMPRE em formato internacional: `+351912345678`,
///   `+5511987654321`. Nada de regra fixa de 9 dígitos.
/// - Os números antigos guardados sem indicativo (`912345678`) continuam a
///   valer como Portugal.
///
/// Textos em PT-PT (app de cliente).
library;

import 'package:phone_numbers_parser/phone_numbers_parser.dart';

/// Um país do seletor de indicativo.
class PaisTelefone {
  const PaisTelefone(this.iso, this.nome, this.bandeira);

  final IsoCode iso;
  final String nome;
  final String bandeira;

  /// Indicativo sem o `+` (ex.: `351`), lido dos dados da biblioteca.
  String get indicativo => PhoneNumber(isoCode: iso, nsn: '').countryCode;
}

/// Portugal primeiro (o defeito), depois os países de onde vêm mais clientes
/// e visitantes da Guarda, e o resto da Europa e do mundo por ordem alfabética.
const List<PaisTelefone> kPaisesTelefone = [
  PaisTelefone(IsoCode.PT, 'Portugal', '🇵🇹'),
  PaisTelefone(IsoCode.BR, 'Brasil', '🇧🇷'),
  PaisTelefone(IsoCode.ES, 'Espanha', '🇪🇸'),
  PaisTelefone(IsoCode.FR, 'França', '🇫🇷'),
  PaisTelefone(IsoCode.GB, 'Reino Unido', '🇬🇧'),
  PaisTelefone(IsoCode.CH, 'Suíça', '🇨🇭'),
  PaisTelefone(IsoCode.DE, 'Alemanha', '🇩🇪'),
  PaisTelefone(IsoCode.LU, 'Luxemburgo', '🇱🇺'),
  PaisTelefone(IsoCode.CV, 'Cabo Verde', '🇨🇻'),
  PaisTelefone(IsoCode.AO, 'Angola', '🇦🇴'),
  PaisTelefone(IsoCode.MZ, 'Moçambique', '🇲🇿'),
  PaisTelefone(IsoCode.GW, 'Guiné-Bissau', '🇬🇼'),
  PaisTelefone(IsoCode.ST, 'São Tomé e Príncipe', '🇸🇹'),
  PaisTelefone(IsoCode.IN, 'Índia', '🇮🇳'),
  PaisTelefone(IsoCode.NP, 'Nepal', '🇳🇵'),
  PaisTelefone(IsoCode.BD, 'Bangladesh', '🇧🇩'),
  PaisTelefone(IsoCode.PK, 'Paquistão', '🇵🇰'),
  PaisTelefone(IsoCode.UA, 'Ucrânia', '🇺🇦'),
  PaisTelefone(IsoCode.RO, 'Roménia', '🇷🇴'),
  PaisTelefone(IsoCode.MD, 'Moldávia', '🇲🇩'),
  PaisTelefone(IsoCode.BE, 'Bélgica', '🇧🇪'),
  PaisTelefone(IsoCode.NL, 'Países Baixos', '🇳🇱'),
  PaisTelefone(IsoCode.IT, 'Itália', '🇮🇹'),
  PaisTelefone(IsoCode.IE, 'Irlanda', '🇮🇪'),
  PaisTelefone(IsoCode.AD, 'Andorra', '🇦🇩'),
  PaisTelefone(IsoCode.PL, 'Polónia', '🇵🇱'),
  PaisTelefone(IsoCode.BG, 'Bulgária', '🇧🇬'),
  PaisTelefone(IsoCode.AT, 'Áustria', '🇦🇹'),
  PaisTelefone(IsoCode.SE, 'Suécia', '🇸🇪'),
  PaisTelefone(IsoCode.NO, 'Noruega', '🇳🇴'),
  PaisTelefone(IsoCode.DK, 'Dinamarca', '🇩🇰'),
  PaisTelefone(IsoCode.US, 'Estados Unidos', '🇺🇸'),
  PaisTelefone(IsoCode.CA, 'Canadá', '🇨🇦'),
  PaisTelefone(IsoCode.VE, 'Venezuela', '🇻🇪'),
  PaisTelefone(IsoCode.CO, 'Colômbia', '🇨🇴'),
  PaisTelefone(IsoCode.AR, 'Argentina', '🇦🇷'),
  PaisTelefone(IsoCode.MA, 'Marrocos', '🇲🇦'),
  PaisTelefone(IsoCode.CN, 'China', '🇨🇳'),
  PaisTelefone(IsoCode.TL, 'Timor-Leste', '🇹🇱'),
];

/// O país por defeito do seletor.
const PaisTelefone kPaisTelefonePorDefeito =
    PaisTelefone(IsoCode.PT, 'Portugal', '🇵🇹');

String _limpo(String? v) =>
    (v ?? '').trim().replaceAll(RegExp(r'[\s\-().]'), '');

/// Lê o número tal como a pessoa o escreveu. Se começa por `+` ou `00`, o
/// indicativo vem no próprio número (a pessoa colou-o inteiro); senão, vale o
/// país escolhido no seletor. `null` quando não se percebe o número.
PhoneNumber? lerTelefone(String? numero, IsoCode pais) {
  var s = _limpo(numero);
  if (s.isEmpty) return null;
  if (s.startsWith('00')) s = '+${s.substring(2)}';
  if (s.startsWith('+')) {
    try {
      return PhoneNumber.parse(s);
    } catch (_) {
      return null;
    }
  }
  PhoneNumber? nacional;
  try {
    nacional = PhoneNumber.parse(s, destinationCountry: pais);
    if (nacional.isValid()) return nacional;
  } catch (_) {}
  // Com o país já escolhido, muita gente escreve o número sem o 0 nacional
  // (ex.: Reino Unido "7911 123456" em vez de "07911 123456"): tenta-se com o
  // indicativo à frente.
  try {
    final indicativo = PhoneNumber(isoCode: pais, nsn: '').countryCode;
    final comIndicativo = PhoneNumber.parse('+$indicativo$s');
    // O mesmo indicativo pode ser de vários países (+44: Reino Unido,
    // Guernsey, Jersey...): conta o indicativo, não a bandeira.
    if (comIndicativo.isValid() && comIndicativo.countryCode == indicativo) {
      return comIndicativo;
    }
  } catch (_) {}
  return nacional;
}

/// `null` quando o número é válido para o país; senão a mensagem a mostrar.
String? validarTelefone(String? numero, IsoCode pais) {
  if (_limpo(numero).isEmpty) return 'Indica o teu telemóvel.';
  final n = lerTelefone(numero, pais);
  if (n == null || !n.isValid()) {
    return 'Número inválido para o país escolhido. Confirma o indicativo e o número.';
  }
  return null;
}

/// O número em formato internacional (`+351912345678`), ou `null` se não for
/// válido para o país escolhido. É esta a forma que se grava.
String? telefoneInternacional(String? numero, IsoCode pais) {
  final n = lerTelefone(numero, pais);
  if (n == null || !n.isValid()) return null;
  return n.international;
}

/// Um telefone já guardado (com ou sem indicativo) é utilizável? Os antigos
/// sem indicativo leem-se como Portugal.
bool telefoneGuardadoValido(String? guardado) =>
    telefoneInternacional(guardado, IsoCode.PT) != null;

/// Para preencher o seletor e o campo a partir do que está guardado:
/// `+5511987654321` → Brasil + `11987654321`; `912345678` → Portugal.
({PaisTelefone pais, String nacional}) separarTelefone(String? guardado) {
  final n = lerTelefone(guardado, IsoCode.PT);
  if (n == null) {
    return (pais: kPaisTelefonePorDefeito, nacional: _limpo(guardado));
  }
  final pais = kPaisesTelefone.firstWhere(
    (p) => p.iso == n.isoCode,
    orElse: () => PaisTelefone(n.isoCode, n.isoCode.name, '🌍'),
  );
  return (pais: pais, nacional: n.nsn);
}

/// Número estrangeiro (não Portugal)? Para esses, o contacto é pelo WhatsApp.
bool telefoneEstrangeiro(String? guardado) {
  final n = lerTelefone(guardado, IsoCode.PT);
  return n != null && n.isoCode != IsoCode.PT;
}

/// Os dígitos para o `https://wa.me/<dígitos>` (sem `+`), ou `null`.
String? digitosWhatsApp(String? guardado) {
  final i = telefoneInternacional(guardado, IsoCode.PT);
  return i?.substring(1);
}
