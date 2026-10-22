/// DOCUMENTOS DO ESTAFETA — uma regra só para o painel e para a app
/// (missão cadastro-estafeta-fotos-22-10).
///
/// O ecrã de aprovação do admin e o ecrã "Conta em análise" do estafeta
/// perguntam a mesma coisa: "o que falta a esta candidatura?". A resposta vive
/// aqui, numa função pura e testada (`test/driver_documentos_test.dart`), para
/// os dois nunca dizerem coisas diferentes.
///
/// Também aqui: o tipo real de uma foto pelos primeiros bytes (o nome engana —
/// `.jpg` dava `image/jpg`, que o bucket recusou durante meses) e o nome do
/// veículo em português.
library;

import 'dart:typed_data';

/// Um item que falta na candidatura.
class DocEmFalta {
  const DocEmFalta({
    required this.chave,
    required this.rotulo,
    this.kindFoto,
  });

  /// Identificador estável (`selfie`, `document`, `document_number`,
  /// `vehicle`, `license_plate`, `iban`, `atividade`).
  final String chave;

  /// O que se mostra ("Foto do documento").
  final String rotulo;

  /// Quando é uma foto: o `kind` que a Edge `upload-driver-document` aceita.
  final String? kindFoto;

  bool get eFoto => kindFoto != null;

  @override
  String toString() => rotulo;
}

String? _texto(Object? v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

/// Bicicleta não tem matrícula nem foto de veículo obrigatória.
bool _semMatricula(String? vehicleType) => (vehicleType ?? '') == 'bicycle';

/// O que falta, pela ordem em que o cadastro o pede.
///
/// [driver] é a linha de `drivers` (as colunas que existirem).
/// [atividadeEmFalta] = o comprovativo de atividade conta para a aprovação
/// desta pessoa e ainda não foi enviado (`provider_atividade.obrigatoria` e
/// `documento_path` vazio).
List<DocEmFalta> documentosEmFaltaEstafeta(
  Map<String, dynamic> driver, {
  bool atividadeEmFalta = false,
}) {
  final falta = <DocEmFalta>[];
  // A selfie fica em registration_selfie_url até à aprovação; o aprovar copia
  // para photo_url. Qualquer uma das duas serve.
  if (_texto(driver['photo_url']) == null &&
      _texto(driver['registration_selfie_url']) == null) {
    falta.add(const DocEmFalta(
        chave: 'selfie', rotulo: 'Foto pessoal (selfie)', kindFoto: 'selfie'));
  }
  if (_texto(driver['document_photo_url']) == null) {
    falta.add(const DocEmFalta(
        chave: 'document', rotulo: 'Foto do documento', kindFoto: 'document'));
  }
  if (_texto(driver['document_number']) == null) {
    falta.add(const DocEmFalta(
        chave: 'document_number', rotulo: 'Número do documento'));
  }
  if (atividadeEmFalta) {
    falta.add(const DocEmFalta(
        chave: 'atividade', rotulo: 'Comprovativo de atividade'));
  }
  final vt = driver['vehicle_type']?.toString();
  if (!_semMatricula(vt)) {
    if (_texto(driver['vehicle_photo_url']) == null) {
      falta.add(const DocEmFalta(
          chave: 'vehicle', rotulo: 'Foto do veículo', kindFoto: 'vehicle'));
    }
    if (_texto(driver['license_plate']) == null) {
      falta.add(const DocEmFalta(chave: 'license_plate', rotulo: 'Matrícula'));
    }
  }
  if (_texto(driver['iban']) == null) {
    falta.add(const DocEmFalta(chave: 'iban', rotulo: 'IBAN'));
  }
  return falta;
}

/// O parâmetro de `driver_register_or_update` que grava cada item (o RPC só
/// preenche o que vier — COALESCE — e mantém o resto). null = não se envia
/// por aqui (IBAN pelo Suporte; comprovativo pelo ecrã próprio).
String? parametroDoRegisto(String chave) => switch (chave) {
      'selfie' => 'p_registration_selfie_url',
      'document' => 'p_document_photo_url',
      'vehicle' => 'p_vehicle_photo_url',
      'vehicle_doc' => 'p_vehicle_doc_url',
      'document_number' => 'p_document_number',
      'license_plate' => 'p_license_plate',
      _ => null,
    };

/// "a, b e c" — para avisos e mensagens.
String juntarComE(List<String> itens) {
  if (itens.isEmpty) return '';
  if (itens.length == 1) return itens.first;
  return '${itens.sublist(0, itens.length - 1).join(', ')} e ${itens.last}';
}

/// Nome do veículo como se diz em português (a coluna guarda o valor técnico).
String veiculoEmPortugues(String? vehicleType) => switch (vehicleType) {
      'motorcycle' => 'Mota',
      'bicycle' => 'Bicicleta',
      'car' => 'Carro',
      'carro_passageiros' || 'carPassengers' => 'Carro de passageiros',
      null || '' => '—',
      _ => vehicleType,
    };

/// Modo de trabalho (`drivers.work_mode`: 'everything' | 'rides_only').
String modoDeTrabalhoEmPortugues(String? workMode) => switch (workMode) {
      'everything' => 'Tudo (entregas e corridas)',
      'rides_only' => 'Só corridas de passageiros',
      null || '' => '—',
      _ => workMode,
    };

/// Idade completa em anos numa data [hoje] (para o painel).
int? idadeEmAnos(DateTime? nascimento, DateTime hoje) {
  if (nascimento == null) return null;
  var anos = hoje.year - nascimento.year;
  if (hoje.month < nascimento.month ||
      (hoje.month == nascimento.month && hoje.day < nascimento.day)) {
    anos--;
  }
  return anos < 0 ? null : anos;
}

// ── Tipo real da foto ───────────────────────────────────────────────────────

enum TipoFoto { jpeg, png, webp, heic, desconhecido }

/// O tipo pelos primeiros bytes — nunca pelo nome do ficheiro (o iPhone chama
/// `.jpg` a fotos HEIC e o Android devolve caminhos sem extensão).
TipoFoto tipoDaFoto(Uint8List b) {
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return TipoFoto.jpeg;
  }
  if (b.length >= 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47 &&
      b[4] == 0x0D &&
      b[5] == 0x0A &&
      b[6] == 0x1A &&
      b[7] == 0x0A) {
    return TipoFoto.png;
  }
  if (b.length >= 12 &&
      b[0] == 0x52 && // R
      b[1] == 0x49 && // I
      b[2] == 0x46 && // F
      b[3] == 0x46 && // F
      b[8] == 0x57 && // W
      b[9] == 0x45 && // E
      b[10] == 0x42 && // B
      b[11] == 0x50) {
    // P
    return TipoFoto.webp;
  }
  if (b.length >= 12 &&
      b[4] == 0x66 &&
      b[5] == 0x74 &&
      b[6] == 0x79 &&
      b[7] == 0x70) {
    final marca = String.fromCharCodes(b.sublist(8, 12));
    if (const {'heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1', 'heim', 'heis', 'avif'}
        .contains(marca)) {
      return TipoFoto.heic;
    }
  }
  return TipoFoto.desconhecido;
}

/// O `contentType` que o bucket `driver-documents` aceita para cada tipo
/// (null = tem de ser convertida para JPEG antes de ir).
String? mimeDaFoto(TipoFoto t) => switch (t) {
      TipoFoto.jpeg => 'image/jpeg',
      TipoFoto.png => 'image/png',
      TipoFoto.webp => 'image/webp',
      TipoFoto.heic || TipoFoto.desconhecido => null,
    };

/// Normaliza um `contentType` vindo de um nome de ficheiro (`image/jpg`,
/// `image/JPG`, `jpeg`…) para o nome oficial. Igual ao que a Edge faz.
String normalizarMime(String? mime) {
  final m = (mime ?? '').trim().toLowerCase();
  if (m.isEmpty) return 'image/jpeg';
  if (m == 'image/jpg' || m == 'jpg' || m == 'jpeg' || m == 'image/pjpeg') {
    return 'image/jpeg';
  }
  if (m == 'png') return 'image/png';
  if (m == 'webp') return 'image/webp';
  return m;
}
