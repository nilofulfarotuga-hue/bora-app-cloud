/// O QUE FALTA A CADA PRESTADOR — limpeza e lavagem (missão
/// documentos-todos-papeis-22-10). Mesma ideia do estafeta
/// ([documentosEmFaltaEstafeta]): uma regra pura, testada, usada pelo painel e
/// pela app do prestador, para nunca dizerem coisas diferentes.
///
/// Os documentos destes papéis vivem em `docs` (jsonb) como caminho solto no
/// balde privado (`cleaner-documents` / `washer-documents`); a foto de perfil
/// é um URL público (`avatars`); os dados legais (D3) estão em colunas.
library;

import 'driver_documentos.dart' show DocEmFalta;

String? _t(Object? v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

Map<String, dynamic> docsDe(Map<String, dynamic> linha) {
  final d = linha['docs'];
  return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
}

/// Caminho de um documento dentro de `docs` (só texto conta — `materials_ok`
/// é sim/não e `materials_list` é lista; o painel da limpeza rebentava ao
/// tratar tudo como texto).
String? docCaminho(Map<String, dynamic> linha, String chave) {
  final v = docsDe(linha)[chave];
  return v is String ? _t(v) : null;
}

/// Dados legais (DSA art. 30 + DAC7), os mesmos para todos os papéis.
List<DocEmFalta> _legaisEmFalta(Map<String, dynamic> l) => [
      if (_t(l['legal_name']) == null)
        const DocEmFalta(chave: 'legal_name', rotulo: 'Nome legal'),
      if (_t(l['nif']) == null) const DocEmFalta(chave: 'nif', rotulo: 'NIF'),
      if (_t(l['address']) == null)
        const DocEmFalta(chave: 'address', rotulo: 'Morada'),
      if (_t(l['birth_date']) == null)
        const DocEmFalta(chave: 'birth_date', rotulo: 'Data de nascimento'),
      if (_t(l['iban']) == null) const DocEmFalta(chave: 'iban', rotulo: 'IBAN'),
      if (_t(l['dsa_self_certified_at']) == null)
        const DocEmFalta(
            chave: 'dsa', rotulo: 'Declaração (autocertificação DSA)'),
    ];

/// Profissional de limpeza: foto de perfil, documento de identificação,
/// materiais confirmados, dados legais e (se contar) o comprovativo.
List<DocEmFalta> documentosEmFaltaLimpeza(
  Map<String, dynamic> c, {
  bool atividadeEmFalta = false,
}) =>
    [
      if (_t(c['photo_url']) == null)
        const DocEmFalta(
            chave: 'photo', rotulo: 'Foto de perfil', kindFoto: 'photo'),
      if (docCaminho(c, 'id_doc') == null)
        const DocEmFalta(
            chave: 'id_doc',
            rotulo: 'Documento de identificação',
            kindFoto: 'id_doc'),
      if (docsDe(c)['materials_ok'] != true)
        const DocEmFalta(
            chave: 'materials', rotulo: 'Confirmação dos materiais'),
      ..._legaisEmFalta(c),
      if (atividadeEmFalta)
        const DocEmFalta(
            chave: 'atividade', rotulo: 'Comprovativo de atividade'),
    ];

/// Lavador: foto de perfil, documento de identificação, carta de condução
/// (leva o carro do cliente), materiais, dados legais e o comprovativo.
List<DocEmFalta> documentosEmFaltaLavagem(
  Map<String, dynamic> w, {
  bool atividadeEmFalta = false,
}) =>
    [
      if (_t(w['photo_url']) == null)
        const DocEmFalta(
            chave: 'photo', rotulo: 'Foto de perfil', kindFoto: 'photo'),
      if (docCaminho(w, 'id_doc') == null)
        const DocEmFalta(
            chave: 'id_doc',
            rotulo: 'Documento de identificação',
            kindFoto: 'id_doc'),
      if (docCaminho(w, 'driving_license') == null)
        const DocEmFalta(
            chave: 'driving_license',
            rotulo: 'Carta de condução',
            kindFoto: 'driving_license'),
      if (docsDe(w)['materials_ok'] != true)
        const DocEmFalta(
            chave: 'materials', rotulo: 'Confirmação dos materiais'),
      ..._legaisEmFalta(w),
      if (atividadeEmFalta)
        const DocEmFalta(
            chave: 'atividade', rotulo: 'Comprovativo de atividade'),
    ];
