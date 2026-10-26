/// O QUE FALTA A CADA PRESTADOR — limpeza e lavagem (missão
/// documentos-todos-papeis-22-10). Mesma ideia do estafeta
/// ([documentosEmFaltaEstafeta]): uma regra pura, testada, usada pelo painel e
/// pela app do prestador, para nunca dizerem coisas diferentes.
///
/// Os documentos destes papéis vivem em `docs` (jsonb) como caminho solto no
/// balde privado (`cleaner-documents` / `washer-documents`); a foto de perfil
/// é um URL público (`avatars`); os dados legais (D3) estão em colunas.
library;

import 'driver_documentos.dart' show DocEmFalta, juntarComE;

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

// ── Reenvio pela app do prestador (missão docs-reenvio-26-10) ────────────────
// O Danilo, 22/10: cada prestador PENDENTE vê o que falta e envia ali mesmo,
// sem refazer o cadastro — como o estafeta. A lista é a mesma do painel (as
// funções acima); aqui só se decide COMO cada item se envia.

/// [papel] é 'cleaner' (limpeza) ou 'washer' (lavagem), como em
/// `provider_update_legal_fields`.
List<DocEmFalta> documentosEmFaltaPrestador(
  String papel,
  Map<String, dynamic> linha, {
  bool atividadeEmFalta = false,
}) =>
    papel == 'washer'
        ? documentosEmFaltaLavagem(linha, atividadeEmFalta: atividadeEmFalta)
        : documentosEmFaltaLimpeza(linha, atividadeEmFalta: atividadeEmFalta);

/// Os seis dados legais (DSA + DAC7). Gravam-se juntos, pelo mesmo formulário
/// e a mesma RPC do cadastro (`provider_update_legal_fields`).
const Set<String> kChavesDadosLegais = {
  'legal_name',
  'nif',
  'address',
  'birth_date',
  'iban',
  'dsa',
};

/// Chave da linha única que junta os dados legais em falta.
const String kChaveDadosFiscais = 'dados_fiscais';

/// Como o prestador envia cada item pela app.
enum ComoEnviar {
  /// Tirar/escolher foto e gravar (foto de perfil; documentos da lavagem).
  foto,

  /// Confirmar a lista de materiais (lavagem).
  materiais,

  /// Formulário dos dados legais e fiscais do cadastro.
  dadosFiscais,

  /// Ecrã do comprovativo de atividade.
  comprovativo,

  /// Não há caminho na app: fala com o Suporte.
  suporte,
}

/// Decide o botão de cada item.
///
/// Limpeza: o documento de identificação e os materiais vivem em
/// `cleaners.docs`, que só a RPC do cadastro (`cleaner_apply`) escreve — e
/// ela recusa candidaturas pendentes; a tabela não deixa o próprio escrever.
/// Esses dois vão pelo Suporte até haver uma RPC própria.
/// Lavagem: a linha é do próprio (`washers_update_own`), por isso os
/// documentos e os materiais gravam-se aqui.
ComoEnviar comoEnviarPrestador(String papel, String chave) {
  if (chave == kChaveDadosFiscais || kChavesDadosLegais.contains(chave)) {
    return ComoEnviar.dadosFiscais;
  }
  if (chave == 'atividade') return ComoEnviar.comprovativo;
  if (chave == 'photo') return ComoEnviar.foto;
  if (papel == 'washer') {
    if (chave == 'id_doc' || chave == 'driving_license') return ComoEnviar.foto;
    if (chave == 'materials') return ComoEnviar.materiais;
  }
  return ComoEnviar.suporte;
}

/// "NIF" fica "NIF"; "Foto de perfil" fica "foto de perfil" (para
/// "Falta: foto de perfil").
String minusculaInicial(String s) {
  if (s.length < 2) return s.toLowerCase();
  final segunda = s[1];
  if (segunda.toUpperCase() == segunda) return s; // sigla (NIF, IBAN)
  return s[0].toLowerCase() + s.substring(1);
}

/// Junta os dados legais em falta numa linha só, no sítio do primeiro
/// ("Dados fiscais (NIF, IBAN e morada)") — um formulário, um botão.
List<DocEmFalta> agruparDadosLegais(List<DocEmFalta> falta) {
  final legais =
      falta.where((d) => kChavesDadosLegais.contains(d.chave)).toList();
  if (legais.isEmpty) return falta;
  final linha = DocEmFalta(
    chave: kChaveDadosFiscais,
    rotulo: 'Dados fiscais '
        '(${juntarComE(legais.map((d) => minusculaInicial(d.rotulo)).toList())})',
  );
  final out = <DocEmFalta>[];
  var juntou = false;
  for (final d in falta) {
    if (!kChavesDadosLegais.contains(d.chave)) {
      out.add(d);
    } else if (!juntou) {
      out.add(linha);
      juntou = true;
    }
  }
  return out;
}

/// `docs` com os [novos] valores, sem perder os documentos que já lá estão.
Map<String, dynamic> docsCom(
        Map<String, dynamic> linha, Map<String, dynamic> novos) =>
    {...docsDe(linha), ...novos};

/// Motorista TVDE: os impedimentos que o servidor calcula
/// (`tvde_minha_conformidade.motivos` — a mesma conta do painel,
/// `admin_tvde_motoristas_conformidade`), como itens em falta.
List<DocEmFalta> motivosTvdeEmFalta(Object? conformidade) {
  final motivos = conformidade is Map ? conformidade['motivos'] : null;
  if (motivos is! List) return const [];
  final out = <DocEmFalta>[];
  for (final m in motivos.whereType<Map>()) {
    final rotulo = _t(m['rotulo']) ?? _t(m['codigo']);
    if (rotulo == null) continue;
    out.add(DocEmFalta(chave: _t(m['codigo']) ?? rotulo, rotulo: rotulo));
  }
  return out;
}
