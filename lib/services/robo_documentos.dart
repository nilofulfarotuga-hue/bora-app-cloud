/// ROBÔ "FISCAL DE DOCUMENTOS" — as peças puras (missão final-app-2026-10-29,
/// adendo 3). Sem rede e sem Supabase, para o painel e as apps dizerem sempre
/// as mesmas coisas e para tudo ser testado (`test/robo_documentos_test.dart`).
///
/// O robô só OLHA: diz "ok", "errado" ou "dúvida" sobre cada documento. NUNCA
/// aprova nada — a aprovação é só do Danilo. Os vereditos vivem em
/// `documentos_verificacoes` (só o admin lê); o candidato vê os seus pelo RPC
/// `provider_documentos_estado`, e só quando o robô está a agir.
library;

/// Um veredito do robô sobre um ficheiro (uma linha de `documentos_verificacoes`).
class VereditoRobo {
  const VereditoRobo({
    required this.id,
    required this.campo,
    required this.decisao,
    this.acao = 'nenhuma',
    this.modo = 'sombra',
    this.tipoDetetado,
    this.tipoEsperado,
    this.confianca,
    this.motivoPt,
    this.nomeBate,
    this.nifBate,
    this.legivel,
    this.path,
    this.criadoEm,
    this.revertidoEm,
    this.userId,
    this.nome,
    this.papel,
  });

  factory VereditoRobo.fromMap(Map<String, dynamic> m) {
    String? t(Object? v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return VereditoRobo(
      id: (m['id'] as num?)?.toInt() ?? 0,
      campo: t(m['campo']) ?? '',
      decisao: t(m['decisao']) ?? 'duvida',
      acao: t(m['acao']) ?? 'nenhuma',
      modo: t(m['modo']) ?? 'sombra',
      tipoDetetado: t(m['tipo_detectado']),
      tipoEsperado: t(m['tipo_documento_esperado']),
      confianca: (m['confianca'] is num)
          ? (m['confianca'] as num).toDouble()
          : double.tryParse(m['confianca']?.toString() ?? ''),
      motivoPt: t(m['motivo_pt']),
      nomeBate: m['nome_bate'] as bool?,
      nifBate: m['nif_bate'] as bool?,
      legivel: m['legivel'] as bool?,
      path: t(m['path']),
      criadoEm: DateTime.tryParse(m['created_at']?.toString() ?? ''),
      revertidoEm: DateTime.tryParse(m['revertido_em']?.toString() ?? ''),
      userId: t(m['user_id']),
      nome: t(m['nome']),
      papel: t(m['papel']),
    );
  }

  final int id;

  /// `tabela.coluna` (ex.: `provider_atividade.documento_path`).
  final String campo;

  /// 'ok' | 'errado' | 'duvida'.
  final String decisao;

  /// 'nenhuma' | 'recusado' | 'pedido' — o que o robô fez a seguir (só com o robô a agir).
  final String acao;

  /// 'sombra' | 'ativo' | 'previa'.
  final String modo;
  final String? tipoDetetado;
  final String? tipoEsperado;
  final double? confianca;
  final String? motivoPt;
  final bool? nomeBate;
  final bool? nifBate;
  final bool? legivel;
  final String? path;
  final DateTime? criadoEm;
  final DateTime? revertidoEm;
  final String? userId;
  final String? nome;
  final String? papel;

  bool get ok => decisao == 'ok';
  bool get errado => decisao == 'errado';
  bool get duvida => decisao == 'duvida';
  bool get desfeito => revertidoEm != null;

  /// O robô já agiu sobre este (recusou ou pediu) e ninguém desfez.
  bool get agiu => acao != 'nenhuma' && !desfeito;
}

// ── Rótulos ─────────────────────────────────────────────────────────────────────

/// Nome do documento pelo campo da base (PT-BR/PT-PT neutro; serve o painel e a app).
String rotuloDoCampo(String campo) => switch (campo) {
      'provider_atividade.documento_path' => 'Comprovativo de atividade',
      'drivers.registration_selfie_url' => 'Selfie',
      'drivers.document_photo_url' => 'Documento de identificação',
      'drivers.vehicle_photo_url' => 'Foto do veículo',
      'drivers.vehicle_doc_url' => 'Documento do veículo',
      'cleaners.docs.id_doc' || 'washers.docs.id_doc' => 'Documento de identificação',
      'washers.docs.driving_license' => 'Carta de condução',
      _ => campo,
    };

/// "o que o ficheiro devia ser", com artigo, para frases como "não é …".
String _esperadoComArtigo(String campo) => switch (campo) {
      'provider_atividade.documento_path' => 'o comprovativo das Finanças',
      'drivers.registration_selfie_url' => 'uma selfie',
      'drivers.document_photo_url' ||
      'cleaners.docs.id_doc' ||
      'washers.docs.id_doc' =>
        'um documento de identificação',
      'drivers.vehicle_photo_url' => 'uma foto do veículo',
      'drivers.vehicle_doc_url' => 'o documento do veículo',
      'washers.docs.driving_license' => 'a carta de condução',
      _ => 'o documento pedido',
    };

/// "o que o robô viu", com artigo indefinido. null = não identificou (outro).
String? _detetadoComArtigo(String? tipo) => switch (tipo) {
      'comprovativo_atividade_AT' => 'o comprovativo de atividade das Finanças',
      'cartao_cidadao' => 'um cartão de cidadão',
      'titulo_residencia' => 'um título de residência',
      'passaporte' => 'um passaporte',
      'carta_conducao' => 'uma carta de condução',
      'documento_veiculo' => 'um documento de veículo',
      'foto_veiculo' => 'uma foto de um veículo',
      'selfie' => 'uma selfie',
      'fatura_ou_talao' => 'uma fatura ou um talão',
      _ => null,
    };

/// Frase curta do veredito para o PAINEL (PT-BR, termos técnicos entre parênteses).
/// Ex.: "Robô: parece um cartão de cidadão, não é o comprovativo das Finanças (97% de certeza)".
String textoDoVeredito(VereditoRobo v) {
  final pct = v.confianca == null ? '' : ' (${(v.confianca! * 100).round()}% de certeza)';
  final viu = _detetadoComArtigo(v.tipoDetetado);
  final esperado = _esperadoComArtigo(v.campo);
  if (v.errado) {
    if (v.legivel == false) {
      return 'Robô: não consegue ler este ficheiro$pct';
    }
    return viu == null
        ? 'Robô: não parece $esperado$pct'
        : 'Robô: parece $viu, não é $esperado$pct';
  }
  if (v.duvida) {
    final conf = <String>[
      if (v.nomeBate == false) 'o nome não bate com o da conta',
      if (v.nifBate == false) 'o NIF não bate com o da conta',
    ];
    if (conf.isNotEmpty) return 'Robô: dúvida — ${conf.join(' e ')}';
    return 'Robô: sem certeza${viu == null ? '' : ' (parece $viu)'} — confirma tu';
  }
  final extra = <String>[
    if (v.nomeBate == true) 'nome confere',
    if (v.nifBate == true) 'NIF confere',
  ];
  final viuTxt = viu == null ? '' : ' $viu';
  return 'Robô: parece$viuTxt'
      '${extra.isEmpty ? '' : ' — ${extra.join(' e ')}'}$pct';
}

// ── Escolha do veredito de cada ficheiro ─────────────────────────────────────────

/// O ficheiro mostrado é o que o robô analisou? (o caminho do veredito aparece
/// no URL ou no caminho do ficheiro, com ou sem %-codificação)
bool vereditoDoFicheiro(VereditoRobo v, String? urlOuCaminho) {
  final p = v.path;
  if (p == null || p.isEmpty) return true;
  final f = urlOuCaminho;
  if (f == null || f.isEmpty) return false;
  if (f.contains(p)) return true;
  try {
    return Uri.decodeFull(f).contains(Uri.decodeFull(p));
  } catch (_) {
    return false;
  }
}

/// O último veredito (não desfeito) de cada campo. [linhas] vêm do RPC
/// `admin_documentos_verificacoes` ou da tabela, por ordem qualquer.
Map<String, VereditoRobo> ultimoPorCampo(Iterable<Map<String, dynamic>> linhas) {
  final por = <String, VereditoRobo>{};
  for (final m in linhas) {
    final v = VereditoRobo.fromMap(m);
    if (v.campo.isEmpty || v.desfeito) continue;
    final ant = por[v.campo];
    if (ant == null || v.id > ant.id) por[v.campo] = v;
  }
  return por;
}

/// Os vereditos que a linha do painel (`_robo`) traz, por campo.
Map<String, VereditoRobo> vereditosDaLinha(Map<String, dynamic> linha) {
  final r = linha['_robo'];
  if (r is Map<String, VereditoRobo>) return r;
  if (r is Map) {
    return {
      for (final e in r.entries)
        if (e.value is VereditoRobo) e.key.toString(): e.value as VereditoRobo,
    };
  }
  return const {};
}

/// O veredito do campo se for o do ficheiro que se está a mostrar.
VereditoRobo? vereditoDe(Map<String, dynamic> linha, String campo, {String? ficheiro}) {
  final v = vereditosDaLinha(linha)[campo];
  if (v == null) return null;
  if (ficheiro != null && !vereditoDoFicheiro(v, ficheiro)) return null;
  return v;
}

// ── Aprovar: o que o robô tem a dizer ────────────────────────────────────────────

/// Frases a vermelho para pôr junto ao botão Aprovar (uma por documento errado).
List<String> avisosParaAprovar(Map<String, dynamic> linha) => [
      for (final v in vereditosDaLinha(linha).values)
        if (v.errado && !v.desfeito) '${rotuloDoCampo(v.campo)} — ${textoDoVeredito(v)}',
    ];

/// O servidor só deixa aprovar a candidatura nova depois do comprovativo de
/// atividade aprovado (gatilho `fn_atividade_antes_de_ativar`). Em vez de deixar
/// a chamada falhar com 400, o painel avisa antes. null = pode seguir.
String? bloqueioDaAtividade(Map<String, dynamic> linha) {
  final a = linha['_atividade'];
  if (a is! Map || a['obrigatoria'] != true) return null;
  if (a['atividade_status'] == 'aprovada') return null;
  final v = vereditoDe(linha, 'provider_atividade.documento_path');
  final visto = v == null ? '' : '\n${textoDoVeredito(v)}';
  final enviado = (a['documento_path']?.toString().trim().isNotEmpty ?? false);
  return enviado
      ? 'Falta aprovar o comprovativo de atividade desta pessoa (abre a ficha e toca em "Aprovar comprovativo").$visto'
      : 'Falta o comprovativo de atividade desta pessoa: ainda não o enviou.$visto';
}

/// Resumo de uma linha para as listas: "Robô: tudo certo" / "Robô: 1 errado".
({String texto, String nivel}) resumoDoRobo(Map<String, dynamic> linha) {
  final vs = vereditosDaLinha(linha).values.where((v) => !v.desfeito).toList();
  if (vs.isEmpty) return (texto: 'Robô: ainda não viu os documentos', nivel: 'nada');
  final errados = vs.where((v) => v.errado).length;
  final duvidas = vs.where((v) => v.duvida).length;
  if (errados > 0) {
    return (
      texto: 'Robô: $errados ${errados == 1 ? 'documento errado' : 'documentos errados'}',
      nivel: 'errado',
    );
  }
  if (duvidas > 0) {
    return (
      texto: 'Robô: $duvidas ${duvidas == 1 ? 'dúvida' : 'dúvidas'}',
      nivel: 'duvida',
    );
  }
  return (
    texto: vs.length == 1
        ? 'Robô: tudo certo no documento visto'
        : 'Robô: tudo certo nos ${vs.length} documentos vistos',
    nivel: 'ok',
  );
}

// ── A app do candidato (PT-PT, "tu") ─────────────────────────────────────────────

/// "Isto parece um cartão de cidadão, não o comprovativo das Finanças. Escolhe
/// outro ficheiro." — a frase da verificação na hora.
String mensagemDaPrevia({required String campo, String? tipoDetetado}) {
  final esperado = _esperadoComArtigo(campo);
  final viu = _detetadoComArtigo(tipoDetetado);
  return viu == null
      ? 'Isto não parece $esperado. Escolhe outro ficheiro.'
      : 'Isto parece $viu, não $esperado. Escolhe outro ficheiro.';
}

/// O que a app mostra por documento: estado + motivo do robô.
class DocumentoEstadoApp {
  const DocumentoEstadoApp({required this.campo, required this.decisao, this.motivoPt});

  factory DocumentoEstadoApp.fromMap(Map<String, dynamic> m) => DocumentoEstadoApp(
        campo: m['campo']?.toString() ?? '',
        decisao: m['decisao']?.toString() ?? 'duvida',
        motivoPt: (m['motivo_pt']?.toString().trim().isEmpty ?? true)
            ? null
            : m['motivo_pt'].toString().trim(),
      );

  final String campo;
  final String decisao;
  final String? motivoPt;

  String get rotulo => rotuloDoCampo(campo);

  /// Precisa de ser enviado de novo (o robô recusou ou pediu).
  bool get precisaDeNovo => decisao == 'errado';

  String get estado => switch (decisao) {
        'ok' => 'Recebido e parece certo',
        'errado' => 'Precisa de ser enviado de novo',
        _ => 'Em análise',
      };
}

/// O que o RPC `provider_documentos_estado` devolve. `ativo=false` = o robô não
/// está a agir: a app não mostra nada dele.
class EstadoDocumentosApp {
  const EstadoDocumentosApp({required this.ativo, this.itens = const []});

  factory EstadoDocumentosApp.fromJson(Map<String, dynamic> j) => EstadoDocumentosApp(
        ativo: j['ativo'] == true,
        itens: (j['itens'] is List)
            ? (j['itens'] as List)
                .whereType<Map>()
                .map((e) => DocumentoEstadoApp.fromMap(Map<String, dynamic>.from(e)))
                .toList()
            : const [],
      );

  final bool ativo;
  final List<DocumentoEstadoApp> itens;

  List<DocumentoEstadoApp> get aCorrigir => itens.where((i) => i.precisaDeNovo).toList();
}
