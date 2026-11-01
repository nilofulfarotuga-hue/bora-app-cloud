// CASA — modelos da categoria Casa & Manutenção (faz-tudo), 2026-10-31.
// Model → Store → Screen. Valores de dinheiro em cêntimos (int), calculados SEMPRE no
// servidor (RPC casa_criar_pedido / casa_aceitar_orcamento). Contrato completo em
// .claude/.ai/provas/casa-manutencao-2026-10-30/ESPEC.md.

DateTime? _data(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

int _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse('${v ?? ''}') ?? 0;
}

int? _intOuNulo(dynamic v) => v == null ? null : _int(v);

double _dbl(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

double? _dblOuNulo(dynamic v) => v == null ? null : _dbl(v);

String _str(dynamic v) => v == null ? '' : v.toString();

List<Map<String, dynamic>> _lista(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : const [];

/// Euros com vírgula, como no resto da app: 2500 → "25,00 €".
String casaEuro(int cents) =>
    '${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')} €';

/// Extensão e tipo MIME de uma foto da Casa, a partir do que a app sabe dela
/// ('png', 'image/webp', 'JPEG', 'heic'…). Só há três no balde `casa-fotos`:
/// png, webp e jpg (o HEIC do iPhone sobe convertido em JPEG). C14 da revisão
/// de 01/11: o caminho leva a extensão real, não sempre `.jpg`.
({String ext, String mime}) casaExtensaoFoto(String extensaoOuMime) {
  final e = extensaoOuMime.trim().toLowerCase();
  if (e == 'png' || e == 'image/png' || e.endsWith('.png')) {
    return (ext: 'png', mime: 'image/png');
  }
  if (e == 'webp' || e == 'image/webp' || e.endsWith('.webp')) {
    return (ext: 'webp', mime: 'image/webp');
  }
  return (ext: 'jpg', mime: 'image/jpeg');
}

/// `<uid>/<pedido_id>/problema_<ms>.<ext>` — foto do problema enviada pelo
/// cliente (o servidor só exige o prefixo `<uid>/<pedido_id>/`).
String casaCaminhoFotoProblema(
        String uid, String pedidoId, String extensao, int ms) =>
    '$uid/$pedidoId/problema_$ms.${casaExtensaoFoto(extensao).ext}';

/// Estado do pedido (espelha o CHECK de casa_pedidos.estado).
enum CasaEstado {
  aguardaPagamento,
  procura,
  orcamentos,
  aceite,
  aCaminho,
  chegou,
  emCurso,
  concluido,
  confirmado,
  disputa,
  cancelado,
  expirado;

  static CasaEstado fromDb(String? raw) {
    switch (raw) {
      case 'aguarda_pagamento':
        return CasaEstado.aguardaPagamento;
      case 'orcamentos':
        return CasaEstado.orcamentos;
      case 'aceite':
        return CasaEstado.aceite;
      case 'a_caminho':
        return CasaEstado.aCaminho;
      case 'chegou':
        return CasaEstado.chegou;
      case 'em_curso':
        return CasaEstado.emCurso;
      case 'concluido':
        return CasaEstado.concluido;
      case 'confirmado':
        return CasaEstado.confirmado;
      case 'disputa':
        return CasaEstado.disputa;
      case 'cancelado':
        return CasaEstado.cancelado;
      case 'expirado':
        return CasaEstado.expirado;
      default:
        return CasaEstado.procura;
    }
  }

  String get db {
    switch (this) {
      case CasaEstado.aguardaPagamento:
        return 'aguarda_pagamento';
      case CasaEstado.procura:
        return 'procura';
      case CasaEstado.orcamentos:
        return 'orcamentos';
      case CasaEstado.aceite:
        return 'aceite';
      case CasaEstado.aCaminho:
        return 'a_caminho';
      case CasaEstado.chegou:
        return 'chegou';
      case CasaEstado.emCurso:
        return 'em_curso';
      case CasaEstado.concluido:
        return 'concluido';
      case CasaEstado.confirmado:
        return 'confirmado';
      case CasaEstado.disputa:
        return 'disputa';
      case CasaEstado.cancelado:
        return 'cancelado';
      case CasaEstado.expirado:
        return 'expirado';
    }
  }

  /// Texto PT-PT para a app (o painel admin tem o seu próprio, em PT-BR).
  String get textoPt {
    switch (this) {
      case CasaEstado.aguardaPagamento:
        return 'À espera do pagamento';
      case CasaEstado.procura:
        return 'À procura de profissional';
      case CasaEstado.orcamentos:
        return 'À espera de orçamentos';
      case CasaEstado.aceite:
        return 'Confirmado';
      case CasaEstado.aCaminho:
        return 'Profissional a caminho';
      case CasaEstado.chegou:
        return 'Profissional chegou';
      case CasaEstado.emCurso:
        return 'Trabalho em curso';
      case CasaEstado.concluido:
        return 'Concluído — confirma';
      case CasaEstado.confirmado:
        return 'Concluído';
      case CasaEstado.disputa:
        return 'Pedido para refazer';
      case CasaEstado.cancelado:
        return 'Cancelado';
      case CasaEstado.expirado:
        return 'Sem profissional disponível';
    }
  }

  /// O profissional já está atribuído e o trabalho ainda não acabou.
  bool get ativo => const {
        CasaEstado.aceite,
        CasaEstado.aCaminho,
        CasaEstado.chegou,
        CasaEstado.emCurso,
      }.contains(this);

  /// Já não muda mais (salvo disputa resolvida pelo admin).
  bool get terminal => const {
        CasaEstado.confirmado,
        CasaEstado.cancelado,
        CasaEstado.expirado,
      }.contains(this);
}

/// Texto PT-PT de um estado vindo em bruto do servidor.
String casaEstadoTexto(String? raw) => CasaEstado.fromDb(raw).textoPt;

/// Como o serviço é cobrado.
enum CasaModo {
  fixo,
  hora,
  orcamento;

  static CasaModo fromDb(String? raw) {
    switch (raw) {
      case 'hora':
        return CasaModo.hora;
      case 'orcamento':
        return CasaModo.orcamento;
      default:
        return CasaModo.fixo;
    }
  }

  String get db => name;
}

class CasaOficio {
  final String codigo;
  final String nome;
  final String descricao;
  final int fase;
  final String? documentoExigido;
  final bool ativo;

  const CasaOficio({
    required this.codigo,
    required this.nome,
    this.descricao = '',
    this.fase = 1,
    this.documentoExigido,
    this.ativo = true,
  });

  factory CasaOficio.fromJson(Map<String, dynamic> m) => CasaOficio(
        codigo: _str(m['codigo']),
        nome: _str(m['nome']),
        descricao: _str(m['descricao']),
        fase: _int(m['fase'] ?? 1),
        documentoExigido: m['documento_exigido']?.toString(),
        ativo: m['ativo'] != false,
      );
}

class CasaPergunta {
  final String id;
  final String texto;
  final bool escolha;
  final List<String> opcoes;

  const CasaPergunta({
    required this.id,
    required this.texto,
    this.escolha = false,
    this.opcoes = const [],
  });

  factory CasaPergunta.fromJson(Map<String, dynamic> m) => CasaPergunta(
        id: _str(m['id']),
        texto: _str(m['texto']),
        escolha: m['tipo'] == 'escolha',
        opcoes: (m['opcoes'] is List)
            ? (m['opcoes'] as List).map((e) => e.toString()).toList()
            : const [],
      );
}

class CasaServico {
  final String id;
  final String oficio;
  final String nome;
  final String descricao;
  final CasaModo modo;
  final int? precoCents;
  final String unidade; // tarefa | movel | hora
  final double minQuantidade;
  final double maxQuantidade;
  final int duracaoMin;
  final List<CasaPergunta> perguntas;

  const CasaServico({
    required this.id,
    required this.oficio,
    required this.nome,
    this.descricao = '',
    this.modo = CasaModo.fixo,
    this.precoCents,
    this.unidade = 'tarefa',
    this.minQuantidade = 1,
    this.maxQuantidade = 10,
    this.duracaoMin = 60,
    this.perguntas = const [],
  });

  bool get pedeOrcamento => modo == CasaModo.orcamento;

  factory CasaServico.fromJson(Map<String, dynamic> m) => CasaServico(
        id: _str(m['id']),
        oficio: _str(m['oficio']),
        nome: _str(m['nome']),
        descricao: _str(m['descricao']),
        modo: CasaModo.fromDb(m['modo']?.toString()),
        precoCents: _intOuNulo(m['preco_cents']),
        unidade: _str(m['unidade'] ?? 'tarefa'),
        minQuantidade: _dbl(m['min_quantidade'] ?? 1),
        maxQuantidade: _dbl(m['max_quantidade'] ?? 10),
        duracaoMin: _int(m['duracao_min'] ?? 60),
        perguntas: _lista(m['perguntas']).map(CasaPergunta.fromJson).toList(),
      );
}

class CasaConfig {
  final bool visivel;
  final bool enabled;
  final bool valoresAutorizados;
  final bool pagamentoCartao;
  final int maxCashCents;
  final int maxFotos;
  final int minLeadHours;
  final int cancelFreeHours;
  final int cancelHalfHours;
  final int garantiaDias;
  final int quoteMaxPros;
  final List<CasaOficio> oficios;
  final List<CasaServico> servicos;

  const CasaConfig({
    this.visivel = false,
    this.enabled = false,
    this.valoresAutorizados = false,
    this.pagamentoCartao = false,
    this.maxCashCents = 4000,
    this.maxFotos = 5,
    this.minLeadHours = 2,
    this.cancelFreeHours = 12,
    this.cancelHalfHours = 2,
    this.garantiaDias = 7,
    this.quoteMaxPros = 3,
    this.oficios = const [],
    this.servicos = const [],
  });

  static const vazia = CasaConfig();

  List<CasaServico> servicosDe(String oficio) =>
      servicos.where((s) => s.oficio == oficio).toList();

  factory CasaConfig.fromJson(Map<String, dynamic> m) => CasaConfig(
        visivel: m['visivel'] == true,
        enabled: m['enabled'] == true,
        valoresAutorizados: m['valores_autorizados'] == true,
        pagamentoCartao: m['pagamento_cartao'] == true,
        maxCashCents: _int(m['max_cash_cents'] ?? 4000),
        maxFotos: _int(m['max_fotos'] ?? 5),
        minLeadHours: _int(m['min_lead_hours'] ?? 2),
        cancelFreeHours: _int(m['cancel_free_hours'] ?? 12),
        cancelHalfHours: _int(m['cancel_half_hours'] ?? 2),
        garantiaDias: _int(m['garantia_dias'] ?? 7),
        quoteMaxPros: _int(m['quote_max_pros'] ?? 3),
        oficios: _lista(m['oficios']).map(CasaOficio.fromJson).toList(),
        servicos: _lista(m['servicos']).map(CasaServico.fromJson).toList(),
      );
}

class CasaFoto {
  final String id;
  final String tipo; // problema | antes | depois | extra
  final String storagePath;
  final DateTime? createdAt;

  const CasaFoto({
    required this.id,
    required this.tipo,
    required this.storagePath,
    this.createdAt,
  });

  factory CasaFoto.fromJson(Map<String, dynamic> m) => CasaFoto(
        id: _str(m['id']),
        tipo: _str(m['tipo']),
        storagePath: _str(m['storage_path']),
        createdAt: _data(m['created_at']),
      );
}

class CasaExtra {
  final String id;
  final int valorCents;
  final String motivo;
  final String estado; // pedido | aceite | recusado
  final DateTime? createdAt;

  const CasaExtra({
    required this.id,
    required this.valorCents,
    required this.motivo,
    required this.estado,
    this.createdAt,
  });

  bool get porResponder => estado == 'pedido';

  factory CasaExtra.fromJson(Map<String, dynamic> m) => CasaExtra(
        id: _str(m['id']),
        valorCents: _int(m['valor_cents']),
        motivo: _str(m['motivo']),
        estado: _str(m['estado']),
        createdAt: _data(m['created_at']),
      );
}

/// Profissional ou cliente visto pela outra parte. O telefone só vem quando o servidor
/// diz pode_contactar (aceite e pago).
class CasaPessoaResumo {
  final String id;
  final String nome;
  final String photoUrl;
  final double ratingAvg;
  final int ratingsCount;
  final int jobsDone;
  final List<String> selos;
  final String? phone;

  const CasaPessoaResumo({
    this.id = '',
    required this.nome,
    this.photoUrl = '',
    this.ratingAvg = 0,
    this.ratingsCount = 0,
    this.jobsDone = 0,
    this.selos = const [],
    this.phone,
  });

  factory CasaPessoaResumo.fromJson(Map<String, dynamic> m) => CasaPessoaResumo(
        id: _str(m['id']),
        nome: _str(m['name'] ?? m['nome']),
        photoUrl: _str(m['photo_url']),
        ratingAvg: _dbl(m['rating_avg']),
        ratingsCount: _int(m['ratings_count']),
        jobsDone: _int(m['jobs_done']),
        selos: (m['selos'] is List)
            ? (m['selos'] as List).map((e) => e.toString()).toList()
            : const [],
        phone: (m['phone'] == null || '${m['phone']}'.isEmpty)
            ? null
            : m['phone'].toString(),
      );
}

class CasaOrcamento {
  final String id;
  final int precoCents;
  final String inclui;
  final String materiais;
  final bool materiaisIncluidos;
  final String prazo;
  final int? duracaoMin;
  final String estado; // enviado | aceite | recusado | expirado | retirado
  final DateTime? expiraEm;
  final DateTime? createdAt;
  final CasaPessoaResumo? profissional;

  const CasaOrcamento({
    required this.id,
    required this.precoCents,
    this.inclui = '',
    this.materiais = '',
    this.materiaisIncluidos = false,
    this.prazo = '',
    this.duracaoMin,
    this.estado = 'enviado',
    this.expiraEm,
    this.createdAt,
    this.profissional,
  });

  bool get aberto => estado == 'enviado';

  factory CasaOrcamento.fromJson(Map<String, dynamic> m) => CasaOrcamento(
        id: _str(m['id']),
        precoCents: _int(m['preco_cents']),
        inclui: _str(m['inclui']),
        materiais: _str(m['materiais']),
        materiaisIncluidos: m['materiais_incluidos'] == true,
        prazo: _str(m['prazo']),
        duracaoMin: _intOuNulo(m['duracao_min']),
        estado: _str(m['estado'] ?? 'enviado'),
        expiraEm: _data(m['expira_em']),
        createdAt: _data(m['created_at']),
        profissional: m['profissional'] is Map
            ? CasaPessoaResumo.fromJson(Map<String, dynamic>.from(m['profissional']))
            : null,
      );
}

class CasaPedido {
  final String id;
  final String? servicoId;
  final String servicoNome;
  final String oficio;
  final String oficioNome;
  final CasaModo modo;
  final double quantidade;
  final String descricao;
  final Map<String, dynamic> respostas;
  final String moradaRua;
  final String moradaCidade;
  final String moradaPostal;
  final double? lat;
  final double? lng;
  final DateTime? scheduledAt;
  final int duracaoMin;
  final CasaEstado estado;
  final String paymentMethod; // card | mbway | cash
  final String paymentStatus;
  final int precoCents;
  final int extrasCents;
  final int totalCents;
  final int? ganhoCents;
  final int? comissaoCents;
  final bool isTest;
  final DateTime? createdAt;
  final DateTime? acceptedAt;
  final DateTime? onTheWayAt;
  final DateTime? arrivedAt;
  final DateTime? startedAt;
  final DateTime? doneAt;
  final DateTime? confirmedAt;
  final DateTime? cancelledAt;
  final String? cancelledBy;
  final String? cancelReason;
  final int cancelFeeCents;
  final int? ratingCliente;
  final String? comentarioCliente;
  final int? ratingProfissional;
  final DateTime? refazerPedidoEm;
  final DateTime? garantiaAte;
  final bool podeContactar;
  final List<CasaFoto> fotos;
  final List<CasaExtra> extras;
  final List<CasaOrcamento> orcamentos;
  final CasaPessoaResumo? profissional;
  final CasaPessoaResumo? cliente;

  const CasaPedido({
    required this.id,
    this.servicoId,
    this.servicoNome = '',
    this.oficio = '',
    this.oficioNome = '',
    this.modo = CasaModo.fixo,
    this.quantidade = 1,
    this.descricao = '',
    this.respostas = const {},
    this.moradaRua = '',
    this.moradaCidade = '',
    this.moradaPostal = '',
    this.lat,
    this.lng,
    this.scheduledAt,
    this.duracaoMin = 60,
    this.estado = CasaEstado.procura,
    this.paymentMethod = 'cash',
    this.paymentStatus = 'unpaid',
    this.precoCents = 0,
    this.extrasCents = 0,
    this.totalCents = 0,
    this.ganhoCents,
    this.comissaoCents,
    this.isTest = false,
    this.createdAt,
    this.acceptedAt,
    this.onTheWayAt,
    this.arrivedAt,
    this.startedAt,
    this.doneAt,
    this.confirmedAt,
    this.cancelledAt,
    this.cancelledBy,
    this.cancelReason,
    this.cancelFeeCents = 0,
    this.ratingCliente,
    this.comentarioCliente,
    this.ratingProfissional,
    this.refazerPedidoEm,
    this.garantiaAte,
    this.podeContactar = false,
    this.fotos = const [],
    this.extras = const [],
    this.orcamentos = const [],
    this.profissional,
    this.cliente,
  });

  String get morada => [moradaRua, moradaCidade]
      .where((s) => s.trim().isNotEmpty)
      .join(', ');

  List<CasaFoto> fotosDe(String tipo) =>
      fotos.where((f) => f.tipo == tipo).toList();

  List<CasaExtra> get extrasPorResponder =>
      extras.where((e) => e.porResponder).toList();

  List<CasaOrcamento> get orcamentosAbertos =>
      orcamentos.where((o) => o.aberto).toList();

  factory CasaPedido.fromJson(Map<String, dynamic> m) {
    final morada = m['morada'] is Map
        ? Map<String, dynamic>.from(m['morada'])
        : const <String, dynamic>{};
    return CasaPedido(
      id: _str(m['id']),
      servicoId: m['servico_id']?.toString(),
      servicoNome: _str(m['servico_nome']),
      oficio: _str(m['oficio']),
      oficioNome: _str(m['oficio_nome']),
      modo: CasaModo.fromDb(m['modo']?.toString()),
      quantidade: _dbl(m['quantidade'] ?? 1),
      descricao: _str(m['descricao']),
      respostas: m['respostas'] is Map
          ? Map<String, dynamic>.from(m['respostas'])
          : const {},
      moradaRua: _str(morada['street']),
      moradaCidade: _str(morada['city']),
      moradaPostal: _str(morada['postal']),
      lat: _dblOuNulo(morada['lat']),
      lng: _dblOuNulo(morada['lng']),
      scheduledAt: _data(m['scheduled_at']),
      duracaoMin: _int(m['duracao_min'] ?? 60),
      estado: CasaEstado.fromDb(m['estado']?.toString()),
      paymentMethod: _str(m['payment_method'] ?? 'cash'),
      paymentStatus: _str(m['payment_status'] ?? 'unpaid'),
      precoCents: _int(m['preco_cents']),
      extrasCents: _int(m['extras_cents']),
      totalCents: _int(m['total_cents']),
      ganhoCents: _intOuNulo(m['ganho_cents']),
      comissaoCents: _intOuNulo(m['comissao_cents']),
      isTest: m['is_test'] == true,
      createdAt: _data(m['created_at']),
      acceptedAt: _data(m['accepted_at']),
      onTheWayAt: _data(m['on_the_way_at']),
      arrivedAt: _data(m['arrived_at']),
      startedAt: _data(m['started_at']),
      doneAt: _data(m['done_at']),
      confirmedAt: _data(m['confirmed_at']),
      cancelledAt: _data(m['cancelled_at']),
      cancelledBy: m['cancelled_by']?.toString(),
      cancelReason: m['cancel_reason']?.toString(),
      cancelFeeCents: _int(m['cancel_fee_cents']),
      ratingCliente: _intOuNulo(m['rating_cliente']),
      comentarioCliente: m['comentario_cliente']?.toString(),
      ratingProfissional: _intOuNulo(m['rating_profissional']),
      refazerPedidoEm: _data(m['refazer_pedido_em']),
      garantiaAte: _data(m['garantia_ate']),
      podeContactar: m['pode_contactar'] == true,
      fotos: _lista(m['fotos']).map(CasaFoto.fromJson).toList(),
      extras: _lista(m['extras']).map(CasaExtra.fromJson).toList(),
      orcamentos: _lista(m['orcamentos']).map(CasaOrcamento.fromJson).toList(),
      profissional: m['profissional'] is Map
          ? CasaPessoaResumo.fromJson(Map<String, dynamic>.from(m['profissional']))
          : null,
      cliente: m['cliente'] is Map
          ? CasaPessoaResumo.fromJson(Map<String, dynamic>.from(m['cliente']))
          : null,
    );
  }
}

/// Oferta (preço fixo) ou convite para orçar, como o profissional a vê ANTES de aceitar:
/// zona e distância, nunca a porta.
class CasaOferta {
  final String pedidoId;
  final bool convite; // true = convite para orçar
  final String oficio;
  final String oficioNome;
  final String servicoNome;
  final CasaModo modo;
  final double quantidade;
  final String descricao;
  final Map<String, dynamic> respostas;
  final String localidade;
  final double? distanciaKm;
  final DateTime? scheduledAt;
  final int duracaoMin;
  final int? ganhoCents;
  final int totalCents;
  final DateTime? expiraEm;
  final List<String> fotos;
  final int orcamentosRecebidos;
  final bool jaOrcei;

  const CasaOferta({
    required this.pedidoId,
    this.convite = false,
    this.oficio = '',
    this.oficioNome = '',
    this.servicoNome = '',
    this.modo = CasaModo.fixo,
    this.quantidade = 1,
    this.descricao = '',
    this.respostas = const {},
    this.localidade = '',
    this.distanciaKm,
    this.scheduledAt,
    this.duracaoMin = 60,
    this.ganhoCents,
    this.totalCents = 0,
    this.expiraEm,
    this.fotos = const [],
    this.orcamentosRecebidos = 0,
    this.jaOrcei = false,
  });

  factory CasaOferta.fromJson(Map<String, dynamic> m) => CasaOferta(
        pedidoId: _str(m['pedido_id']),
        convite: m['tipo'] == 'convite_orcamento',
        oficio: _str(m['oficio']),
        oficioNome: _str(m['oficio_nome']),
        servicoNome: _str(m['servico_nome']),
        modo: CasaModo.fromDb(m['modo']?.toString()),
        quantidade: _dbl(m['quantidade'] ?? 1),
        descricao: _str(m['descricao']),
        respostas: m['respostas'] is Map
            ? Map<String, dynamic>.from(m['respostas'])
            : const {},
        localidade: _str(m['localidade']),
        distanciaKm: _dblOuNulo(m['distancia_km']),
        scheduledAt: _data(m['scheduled_at']),
        duracaoMin: _int(m['duracao_min'] ?? 60),
        ganhoCents: _intOuNulo(m['ganho_cents']),
        totalCents: _int(m['total_cents']),
        expiraEm: _data(m['expira_em']),
        fotos: (m['fotos'] is List)
            ? (m['fotos'] as List).map((e) => e.toString()).toList()
            : const [],
        orcamentosRecebidos: _int(m['orcamentos_recebidos']),
        jaOrcei: m['ja_orcei'] == true,
      );
}

class CasaOficioDoProfissional {
  final String codigo;
  final String nome;
  final int fase;
  final String? documentoExigido;
  final String estado; // pending | approved | rejected | suspended
  final bool ligado;
  final String? motivo;

  const CasaOficioDoProfissional({
    required this.codigo,
    required this.nome,
    this.fase = 1,
    this.documentoExigido,
    this.estado = 'pending',
    this.ligado = true,
    this.motivo,
  });

  bool get aprovado => estado == 'approved';

  factory CasaOficioDoProfissional.fromJson(Map<String, dynamic> m) =>
      CasaOficioDoProfissional(
        codigo: _str(m['codigo']),
        nome: _str(m['nome']),
        fase: _int(m['fase'] ?? 1),
        documentoExigido: m['documento_exigido']?.toString(),
        estado: _str(m['estado'] ?? 'pending'),
        ligado: m['ligado'] != false,
        motivo: m['motivo']?.toString(),
      );
}

class CasaDocumento {
  final String id;
  final String tipo;
  final String? oficio;
  final String estado; // pending | approved | rejected | expired
  final DateTime? validade;
  final String? motivo;
  final DateTime? createdAt;

  const CasaDocumento({
    required this.id,
    required this.tipo,
    this.oficio,
    this.estado = 'pending',
    this.validade,
    this.motivo,
    this.createdAt,
  });

  factory CasaDocumento.fromJson(Map<String, dynamic> m) => CasaDocumento(
        id: _str(m['id']),
        tipo: _str(m['tipo']),
        oficio: m['oficio']?.toString(),
        estado: _str(m['estado'] ?? 'pending'),
        validade: _data(m['validade']),
        motivo: m['motivo']?.toString(),
        createdAt: _data(m['created_at']),
      );
}

/// O que o profissional vê de si próprio (casa_meu_perfil).
class CasaPerfil {
  final Map<String, dynamic> perfil;
  final List<CasaOficioDoProfissional> oficios;
  final List<CasaDocumento> documentos;
  final List<Map<String, dynamic>> disponibilidade;
  final bool aceitaPapel;
  final double comissaoPct;
  final bool valoresAutorizados;

  const CasaPerfil({
    required this.perfil,
    this.oficios = const [],
    this.documentos = const [],
    this.disponibilidade = const [],
    this.aceitaPapel = true,
    this.comissaoPct = 0,
    this.valoresAutorizados = false,
  });

  String get id => _str(perfil['id']);
  String get nome => _str(perfil['name']);
  String get approvalStatus => _str(perfil['approval_status'] ?? 'pending');
  bool get aprovado => approvalStatus == 'approved';
  bool get pendente => approvalStatus == 'pending';
  String? get motivoRecusa => perfil['rejection_reason']?.toString();
  DateTime? get semComissaoAte => _data(perfil['sem_comissao_ate']);

  factory CasaPerfil.fromJson(Map<String, dynamic> m) => CasaPerfil(
        perfil: m['perfil'] is Map
            ? Map<String, dynamic>.from(m['perfil'])
            : const {},
        oficios: _lista(m['oficios']).map(CasaOficioDoProfissional.fromJson).toList(),
        documentos: _lista(m['documentos']).map(CasaDocumento.fromJson).toList(),
        disponibilidade: _lista(m['disponibilidade']),
        aceitaPapel: m['aceita_papel'] != false,
        comissaoPct: _dbl(m['comissao_pct']),
        valoresAutorizados: m['valores_autorizados'] == true,
      );
}
