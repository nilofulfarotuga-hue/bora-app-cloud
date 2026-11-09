/// A MINHA CONTA DO ESTAFETA / MOTORISTA — o semáforo de tudo o que a conta
/// precisa (missão m2-estafeta-conta-fila-2026-11-08).
///
/// Pedido do Danilo a 08/11/2026: o estafeta vê o que está a dever, a vermelho;
/// toca, tira a foto (ou escreve) e fica verde. E os cartões do NIF e do recibo
/// verde saem do ecrã da oferta: vivem aqui, num sítio só.
///
/// A fonte é o servidor (`driver_minha_conta_estado`), que o painel admin usa
/// também. Esta função pura é a MESMA regra, escrita em Dart, para a app não
/// ficar às escuras enquanto a função não está no servidor (ou sem rede para
/// ela): os testes em `test/minha_conta_test.dart` fixam as regras e o SQL da
/// proposta `docs/propostas/m2-estafeta-2026-11-08/01_*.sql` segue-as linha a
/// linha.
library;

/// Vermelho, amarelo ou verde.
enum EstadoItemConta { falta, emAnalise, ok }

EstadoItemConta estadoItemDeTexto(String? s) => switch (s) {
      'ok' => EstadoItemConta.ok,
      'analise' || 'em_analise' => EstadoItemConta.emAnalise,
      _ => EstadoItemConta.falta,
    };

String estadoItemParaTexto(EstadoItemConta e) => switch (e) {
      EstadoItemConta.ok => 'ok',
      EstadoItemConta.emAnalise => 'analise',
      EstadoItemConta.falta => 'falta',
    };

/// Uma linha do semáforo.
class ItemConta {
  const ItemConta({
    required this.chave,
    required this.rotulo,
    required this.rotuloCurto,
    required this.estado,
    this.detalhe,
    this.bloqueiaOnline = false,
    this.opcional = false,
    this.kindFoto,
  });

  /// Identificador estável: `aprovacao`, `selfie`, `document`,
  /// `document_number`, `vehicle`, `license_plate`, `morada`, `nascimento`,
  /// `iban`, `fiscal`, `atividade`, `recibo`, `stripe`, `divida`.
  final String chave;

  /// O que se mostra no ecrã ("Foto do documento de identificação").
  final String rotulo;

  /// O que cabe na barra fina do mapa ("documento").
  final String rotuloCurto;

  final EstadoItemConta estado;

  /// Uma frase extra (motivo do robô, prazo, valor).
  final String? detalhe;

  /// Sem isto o servidor não deixa ficar online.
  final bool bloqueiaOnline;

  /// Não entra na barra "Falta:" nem na folha do Online (ex.: Stripe).
  final bool opcional;

  /// Quando se resolve com uma foto: o `kind` da Edge `upload-driver-document`.
  final String? kindFoto;

  bool get emFalta => estado == EstadoItemConta.falta;
  bool get eFoto => kindFoto != null;

  factory ItemConta.fromJson(Map<String, dynamic> j) => ItemConta(
        chave: (j['chave'] ?? '').toString(),
        rotulo: (j['rotulo'] ?? '').toString(),
        rotuloCurto: (j['rotulo_curto'] ?? j['rotulo'] ?? '').toString(),
        estado: estadoItemDeTexto(j['estado']?.toString()),
        detalhe: _texto(j['detalhe']),
        bloqueiaOnline: j['bloqueia'] == true,
        opcional: j['opcional'] == true,
        kindFoto: _texto(j['kind_foto']),
      );

  Map<String, dynamic> toJson() => {
        'chave': chave,
        'rotulo': rotulo,
        'rotulo_curto': rotuloCurto,
        'estado': estadoItemParaTexto(estado),
        'detalhe': detalhe,
        'bloqueia': bloqueiaOnline,
        'opcional': opcional,
        'kind_foto': kindFoto,
      };

  @override
  String toString() => '$chave:${estadoItemParaTexto(estado)}';
}

/// O estado da conta inteira.
class EstadoMinhaConta {
  const EstadoMinhaConta({
    required this.itens,
    this.dividaCents = 0,
    this.doServidor = false,
  });

  final List<ItemConta> itens;
  final int dividaCents;

  /// true = veio de `driver_minha_conta_estado`; false = montado na app.
  final bool doServidor;

  /// O que falta e conta (sem os opcionais), pela ordem do ecrã.
  List<ItemConta> get emFalta =>
      itens.where((i) => i.emFalta && !i.opcional).toList();

  /// O que impede de ficar online.
  List<ItemConta> get bloqueantes =>
      itens.where((i) => i.emFalta && i.bloqueiaOnline).toList();

  bool get tudoEmOrdem => emFalta.isEmpty;

  ItemConta? item(String chave) {
    for (final i in itens) {
      if (i.chave == chave) return i;
    }
    return null;
  }

  /// "Falta: NIF, IBAN e dívida 1,47 €" — a barra fina do mapa ocioso.
  /// null quando não falta nada.
  String? get resumoBarra {
    final f = emFalta;
    if (f.isEmpty) return null;
    return 'Falta: ${juntarComVirgulas(f.map((i) => i.rotuloCurto).toList())}';
  }

  factory EstadoMinhaConta.fromJson(Object? res) {
    if (res is! Map || res['ok'] != true) {
      return const EstadoMinhaConta(itens: <ItemConta>[]);
    }
    final lista = res['itens'] is List ? res['itens'] as List : const [];
    return EstadoMinhaConta(
      itens: [
        for (final e in lista)
          if (e is Map) ItemConta.fromJson(Map<String, dynamic>.from(e)),
      ],
      dividaCents: (res['divida_cents'] as num?)?.toInt() ?? 0,
      doServidor: true,
    );
  }
}

String? _texto(Object? v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

/// "a, b e c".
String juntarComVirgulas(List<String> itens) {
  if (itens.isEmpty) return '';
  if (itens.length == 1) return itens.first;
  return '${itens.sublist(0, itens.length - 1).join(', ')} e ${itens.last}';
}

/// 147 → "1,47 €".
String euros(int cents) {
  final v = (cents.abs() / 100).toStringAsFixed(2).replaceAll('.', ',');
  return '$v €';
}

const List<String> _meses = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', //
  'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];

/// Mês anterior a [hoje] ("outubro").
String mesAnteriorPorExtenso(DateTime hoje) {
  final m = DateTime(hoje.year, hoje.month - 1, 1).month;
  return _meses[m - 1];
}

/// Uma decisão do robô dos documentos sobre um campo
/// (`provider_documentos_estado`).
class DecisaoRobo {
  const DecisaoRobo(this.decisao, [this.motivo]);

  /// 'ok' | 'errado' | 'duvida'.
  final String decisao;
  final String? motivo;
}

ItemConta _foto({
  required String chave,
  required String rotulo,
  required String curto,
  required String kind,
  required bool tem,
  DecisaoRobo? robo,
  bool bloqueia = false,
}) {
  var estado = tem ? EstadoItemConta.ok : EstadoItemConta.falta;
  String? detalhe;
  if (tem && robo != null) {
    if (robo.decisao == 'errado') {
      estado = EstadoItemConta.falta;
      detalhe = robo.motivo ??
          'Não ficou legível ou não é o documento certo. Envia uma foto nova.';
    } else if (robo.decisao == 'duvida') {
      estado = EstadoItemConta.emAnalise;
      detalhe = 'Recebido — estamos a confirmar.';
    }
  }
  return ItemConta(
    chave: chave,
    rotulo: rotulo,
    rotuloCurto: curto,
    estado: estado,
    detalhe: detalhe,
    kindFoto: kind,
    bloqueiaOnline: bloqueia && estado == EstadoItemConta.falta,
  );
}

ItemConta _campo({
  required String chave,
  required String rotulo,
  required String curto,
  required bool tem,
}) =>
    ItemConta(
      chave: chave,
      rotulo: rotulo,
      rotuloCurto: curto,
      estado: tem ? EstadoItemConta.ok : EstadoItemConta.falta,
    );

/// Monta o semáforo a partir do que a app consegue ler sozinha.
///
/// [driver] = linha de `drivers`. [fiscal] = `driver_fiscal_status_get`.
/// [atividadeStatus] = 'por_enviar' | 'em_analise' | 'aprovada' | 'recusada'
/// (null = o comprovativo não se aplica a esta conta). [recibo] = a linha do
/// estafeta em `driver_monthly_invoice_summary` do mês passado (null = ainda
/// não há recibo a passar). [dividaCents] = semanas fechadas por pagar à Bora.
/// [robo] = decisões do robô por campo (`drivers.registration_selfie_url`…).
EstadoMinhaConta montarMinhaConta({
  required Map<String, dynamic> driver,
  Map<String, dynamic>? fiscal,
  String? atividadeStatus,
  bool atividadeTemDocumento = false,
  Map<String, dynamic>? recibo,
  int dividaCents = 0,
  Map<String, DecisaoRobo> robo = const {},
  DateTime? hoje,
}) {
  final agora = hoje ?? DateTime.now();
  final itens = <ItemConta>[];
  final aprovacao = (driver['approval_status'] ?? '').toString();
  final vt = (driver['vehicle_type'] ?? '').toString();
  final tvde = vt == 'carro_passageiros' || vt == 'carPassengers';

  // 1. Aprovação — só aparece enquanto não está aprovada.
  if (aprovacao != 'approved') {
    itens.add(ItemConta(
      chave: 'aprovacao',
      rotulo: 'Aprovação da conta',
      rotuloCurto: 'aprovação',
      estado: aprovacao == 'rejected'
          ? EstadoItemConta.falta
          : EstadoItemConta.emAnalise,
      detalhe: aprovacao == 'rejected'
          ? 'A candidatura não foi aprovada. Fala connosco no Suporte.'
          : 'A nossa equipa está a ver a tua candidatura.',
      bloqueiaOnline: true,
    ));
  }

  // 2. Selfie e documento de identificação (foto + número).
  itens.add(_foto(
    chave: 'selfie',
    rotulo: 'Foto pessoal (selfie)',
    curto: 'selfie',
    kind: 'selfie',
    tem: _texto(driver['photo_url']) != null ||
        _texto(driver['registration_selfie_url']) != null,
    robo: robo['drivers.registration_selfie_url'],
  ));
  itens.add(_foto(
    chave: 'document',
    rotulo: 'Foto do documento de identificação',
    curto: 'documento',
    kind: 'document',
    tem: _texto(driver['document_photo_url']) != null,
    robo: robo['drivers.document_photo_url'],
  ));
  itens.add(_campo(
    chave: 'document_number',
    rotulo: 'Número do documento',
    curto: 'n.º do documento',
    tem: _texto(driver['document_number']) != null,
  ));

  // 3. Veículo — bicicleta não tem; no TVDE vive na Conformidade TVDE.
  if (vt != 'bicycle' && !tvde) {
    itens.add(_foto(
      chave: 'vehicle',
      rotulo: 'Foto do veículo',
      curto: 'foto do veículo',
      kind: 'vehicle',
      tem: _texto(driver['vehicle_photo_url']) != null,
      robo: robo['drivers.vehicle_photo_url'],
    ));
    itens.add(_campo(
      chave: 'license_plate',
      rotulo: 'Matrícula',
      curto: 'matrícula',
      tem: _texto(driver['license_plate']) != null,
    ));
  }

  // 4. Morada, data de nascimento e IBAN.
  itens.add(_campo(
    chave: 'morada',
    rotulo: 'Morada',
    curto: 'morada',
    tem: _texto(driver['address']) != null,
  ));
  itens.add(_campo(
    chave: 'nascimento',
    rotulo: 'Data de nascimento',
    curto: 'data de nascimento',
    tem: _texto(driver['birth_date']) != null,
  ));
  itens.add(_campo(
    chave: 'iban',
    rotulo: 'IBAN (para receberes)',
    curto: 'IBAN',
    tem: _texto(driver['iban']) != null,
  ));

  // 5. NIF + atividade aberta nas Finanças.
  if (fiscal != null) {
    final ok = fiscal['completo'] == true;
    final bloqueado = fiscal['bloqueado'] == true;
    itens.add(ItemConta(
      chave: 'fiscal',
      rotulo: 'NIF e atividade aberta nas Finanças',
      rotuloCurto: 'NIF',
      estado: ok ? EstadoItemConta.ok : EstadoItemConta.falta,
      detalhe: ok
          ? null
          : bloqueado
              ? 'Sem isto não podes ficar online.'
              : 'Tens até ${fiscal['prazo']} para confirmar.',
      bloqueiaOnline: !ok && bloqueado,
    ));
  }

  // 6. Comprovativo de atividade (Finanças).
  if (atividadeStatus != null) {
    final EstadoItemConta e;
    String? det;
    switch (atividadeStatus) {
      case 'aprovada':
        e = EstadoItemConta.ok;
      case 'em_analise' when atividadeTemDocumento:
        e = EstadoItemConta.emAnalise;
        det = 'Recebido — estamos a confirmar.';
      case 'recusada':
        e = EstadoItemConta.falta;
        det = 'O comprovativo não foi aceite. Envia outro.';
      default:
        e = EstadoItemConta.falta;
    }
    itens.add(ItemConta(
      chave: 'atividade',
      rotulo: 'Comprovativo de atividade (Finanças)',
      rotuloCurto: 'comprovativo de atividade',
      estado: e,
      detalhe: det,
    ));
  }

  // 7. Recibo verde do mês passado.
  if (recibo != null) {
    final passado = recibo['recibo_passado'] == true;
    final mes = mesAnteriorPorExtenso(agora);
    itens.add(ItemConta(
      chave: 'recibo',
      rotulo: 'Recibo verde de $mes',
      rotuloCurto: 'recibo verde',
      estado: passado ? EstadoItemConta.ok : EstadoItemConta.falta,
      detalhe: passado ? null : 'Passa o recibo e marca aqui que já passaste.',
    ));
  }

  // 8. Pagamentos por cartão (Stripe) — opcional, nunca bloqueia.
  final stripe = (driver['stripe_account_status'] ?? 'none').toString();
  itens.add(ItemConta(
    chave: 'stripe',
    rotulo: 'Receber pagamentos por cartão (Stripe)',
    rotuloCurto: 'Stripe',
    estado: switch (stripe) {
      'enabled' => EstadoItemConta.ok,
      'pending' => EstadoItemConta.emAnalise,
      _ => EstadoItemConta.falta,
    },
    detalhe: stripe == 'enabled' ? null : 'Opcional.',
    opcional: true,
  ));

  // 9. Dívida à Bora (semanas fechadas por pagar).
  final bloqueadoPorDivida = driver['blocked_for_debt'] == true;
  final debtCol = (driver['debt_cents'] as num?)?.toInt() ?? 0;
  final divida = dividaCents > debtCol ? dividaCents : debtCol;
  itens.add(ItemConta(
    chave: 'divida',
    rotulo: divida > 0 ? 'Deves à Bora ${euros(divida)}' : 'Sem dívidas à Bora',
    rotuloCurto: 'dívida ${euros(divida)}',
    estado: divida > 0 ? EstadoItemConta.falta : EstadoItemConta.ok,
    detalhe: divida > 0 ? 'Paga por MB Way e carrega em "Já paguei".' : null,
    bloqueiaOnline: divida > 0 && bloqueadoPorDivida,
  ));

  return EstadoMinhaConta(itens: itens, dividaCents: divida);
}

// ── IBAN ────────────────────────────────────────────────────────────────────

/// Tira espaços e põe em maiúsculas ("pt50 0002…" → "PT500002…").
String limparIban(String s) => s.replaceAll(RegExp(r'\s'), '').toUpperCase();

/// IBAN português válido: "PT" + 23 dígitos e o controlo mod-97 certo
/// (o servidor só confirma o formato; o controlo apanha um dígito trocado).
bool ibanPtValido(String bruto) {
  final s = limparIban(bruto);
  if (!RegExp(r'^PT\d{23}$').hasMatch(s)) return false;
  final rearranjado = s.substring(4) + s.substring(0, 4);
  final numerico = StringBuffer();
  for (final c in rearranjado.codeUnits) {
    if (c >= 48 && c <= 57) {
      numerico.writeCharCode(c);
    } else {
      numerico.write(c - 55); // A=10 … Z=35
    }
  }
  var resto = 0;
  for (final c in numerico.toString().codeUnits) {
    resto = (resto * 10 + (c - 48)) % 97;
  }
  return resto == 1;
}

// ── Fila de espera do candidato ─────────────────────────────────────────────

/// Em que ponto está um candidato (missão m2, bloco 2). A aprovação final é
/// sempre do Danilo, no painel.
enum FaseCandidato { documentosPendentes, emVerificacao, filaDeEspera, aprovado, recusado }

String faseCandidatoParaTexto(FaseCandidato f) => switch (f) {
      FaseCandidato.documentosPendentes => 'documentos_pendentes',
      FaseCandidato.emVerificacao => 'em_verificacao',
      FaseCandidato.filaDeEspera => 'fila_de_espera',
      FaseCandidato.aprovado => 'aprovado',
      FaseCandidato.recusado => 'recusado',
    };

FaseCandidato faseCandidatoDeTexto(String? s) => switch (s) {
      'em_verificacao' => FaseCandidato.emVerificacao,
      'fila_de_espera' => FaseCandidato.filaDeEspera,
      'aprovado' => FaseCandidato.aprovado,
      'recusado' => FaseCandidato.recusado,
      _ => FaseCandidato.documentosPendentes,
    };

/// A regra: aprovado/recusado mandam; pendente com algo em falta (ou um
/// documento que o robô recusou) → documentos pendentes; tudo entregue mas o
/// robô (a agir) ainda não deu tudo por bom → em verificação; tudo entregue e
/// conferido (ou robô desligado) → fila de espera.
FaseCandidato faseDoCandidato({
  required String? approvalStatus,
  required int emFalta,
  required bool roboAgir,
  required bool roboTudoOk,
  bool roboRecusouAlgum = false,
}) {
  if (approvalStatus == 'approved') return FaseCandidato.aprovado;
  if (approvalStatus == 'rejected') return FaseCandidato.recusado;
  if (emFalta > 0 || roboRecusouAlgum) return FaseCandidato.documentosPendentes;
  if (roboAgir && !roboTudoOk) return FaseCandidato.emVerificacao;
  return FaseCandidato.filaDeEspera;
}

/// Os textos fixos que o candidato recebe (push, WhatsApp e dentro da app).
/// PT-PT, duas frases. Regra do Danilo (27/10): nunca "pouca procura" nem
/// "não há pedidos".
class TextosFila {
  TextosFila._();

  static const String tudoEntregue =
      'Está tudo em ordem com os teus documentos. Neste momento já temos '
      'estafetas suficientes para os pedidos atuais; ficas na fila e '
      'avisamos-te assim que a procura subir.';

  static String emFalta(List<String> itens) =>
      'A tua inscrição ainda não está completa: falta enviar '
      '${juntarComVirgulas(itens)}. Envia aqui na app; assim que estiver tudo, '
      'passas para a fila de ativação.';

  static String recusado(String documento, {bool ilegivel = true}) =>
      'O $documento ${ilegivel ? 'não ficou legível' : 'não é o documento certo'}. '
      'Envia uma foto nova, com boa luz e o documento inteiro.';

  /// Para os testes: nenhuma destas frases pode dizer isto.
  static const List<String> proibidas = ['pouca procura', 'não há pedidos'];
}
