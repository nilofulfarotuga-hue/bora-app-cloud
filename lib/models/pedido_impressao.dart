// Pedido de impressão ou de personalizado (missão a3-guarda-16-11, parte 2).
// Espelho da tabela public.pedidos_impressao (migração 20261117100100_impressao.sql).

enum ImpressaoEstado { enviado, orcamentado, aceite, pronto, entregue, recusado, cancelado, expirado }

ImpressaoEstado impressaoEstadoDe(String? s) {
  switch (s) {
    case 'orcamentado':
      return ImpressaoEstado.orcamentado;
    case 'aceite':
      return ImpressaoEstado.aceite;
    case 'pronto':
      return ImpressaoEstado.pronto;
    case 'entregue':
      return ImpressaoEstado.entregue;
    case 'recusado':
      return ImpressaoEstado.recusado;
    case 'cancelado':
      return ImpressaoEstado.cancelado;
    case 'expirado':
      return ImpressaoEstado.expirado;
    default:
      return ImpressaoEstado.enviado;
  }
}

/// Texto do estado para o cliente e para a loja (PT-PT).
String impressaoEstadoTexto(ImpressaoEstado e, {bool personalizado = false}) {
  switch (e) {
    case ImpressaoEstado.enviado:
      return personalizado ? 'À espera do preço da loja' : 'Enviado à loja';
    case ImpressaoEstado.orcamentado:
      return 'Preço recebido — falta confirmar';
    case ImpressaoEstado.aceite:
      return 'Em preparação';
    case ImpressaoEstado.pronto:
      return 'Pronto';
    case ImpressaoEstado.entregue:
      return 'Entregue';
    case ImpressaoEstado.recusado:
      return 'Recusado pela loja';
    case ImpressaoEstado.cancelado:
      return 'Cancelado';
    case ImpressaoEstado.expirado:
      return 'Expirado';
  }
}

class ImpressaoFicheiro {
  final String path;
  final String nome;
  final int paginas;
  final String tipo; // pdf | jpg | png
  const ImpressaoFicheiro({required this.path, required this.nome, required this.paginas, required this.tipo});

  Map<String, dynamic> toMap() => {'path': path, 'nome': nome, 'paginas': paginas, 'tipo': tipo};

  factory ImpressaoFicheiro.fromMap(Map<String, dynamic> m) => ImpressaoFicheiro(
        path: (m['path'] ?? '').toString(),
        nome: (m['nome'] ?? '').toString(),
        paginas: (m['paginas'] as num?)?.toInt() ?? 1,
        tipo: (m['tipo'] ?? '').toString(),
      );
}

class PedidoImpressao {
  final String id;
  final DateTime createdAt;
  final String restaurantId;
  final String userId;
  final bool personalizado;
  final ImpressaoEstado estado;
  final List<ImpressaoFicheiro> ficheiros;
  final String? tamanho;
  final bool cor;
  final bool frenteVerso;
  final String? papel;
  final int copias;
  final String? intervalo;
  final int? paginas;
  final int? folhas;
  final String? acabamento;
  final String? productId;
  final String? textoPersonalizado;
  final String? fotoPath;
  final String modo; // levantar | entrega
  final String? morada;
  final String? nota;
  final int? artigoCents;
  final int? taxaServicoCents;
  final int? taxaEntregaCents;
  final int? totalCents;
  final bool precoProvisorio;
  final String? metodoPagamento;
  final bool isDemo;
  final String? codigoLevantamento;
  final String? motivoRecusa;

  const PedidoImpressao({
    required this.id,
    required this.createdAt,
    required this.restaurantId,
    required this.userId,
    required this.personalizado,
    required this.estado,
    required this.ficheiros,
    this.tamanho,
    this.cor = false,
    this.frenteVerso = false,
    this.papel,
    this.copias = 1,
    this.intervalo,
    this.paginas,
    this.folhas,
    this.acabamento,
    this.productId,
    this.textoPersonalizado,
    this.fotoPath,
    this.modo = 'levantar',
    this.morada,
    this.nota,
    this.artigoCents,
    this.taxaServicoCents,
    this.taxaEntregaCents,
    this.totalCents,
    this.precoProvisorio = false,
    this.metodoPagamento,
    this.isDemo = false,
    this.codigoLevantamento,
    this.motivoRecusa,
  });

  bool get entrega => modo == 'entrega';

  factory PedidoImpressao.fromMap(Map<String, dynamic> m) {
    final f = m['ficheiros'];
    return PedidoImpressao(
      id: m['id'].toString(),
      createdAt: DateTime.tryParse((m['created_at'] ?? '').toString())?.toLocal() ?? DateTime.now(),
      restaurantId: (m['restaurant_id'] ?? '').toString(),
      userId: (m['user_id'] ?? '').toString(),
      personalizado: m['tipo'] == 'personalizado',
      estado: impressaoEstadoDe(m['estado']?.toString()),
      ficheiros: f is List ? f.map((e) => ImpressaoFicheiro.fromMap(Map<String, dynamic>.from(e as Map))).toList() : const [],
      tamanho: m['tamanho']?.toString(),
      cor: m['cor'] == true,
      frenteVerso: m['frente_verso'] == true,
      papel: m['papel']?.toString(),
      copias: (m['copias'] as num?)?.toInt() ?? 1,
      intervalo: m['intervalo']?.toString(),
      paginas: (m['paginas'] as num?)?.toInt(),
      folhas: (m['folhas'] as num?)?.toInt(),
      acabamento: m['acabamento']?.toString(),
      productId: m['product_id']?.toString(),
      textoPersonalizado: m['texto_personalizado']?.toString(),
      fotoPath: m['foto_path']?.toString(),
      modo: (m['modo'] ?? 'levantar').toString(),
      morada: m['morada']?.toString(),
      nota: m['nota']?.toString(),
      artigoCents: (m['artigo_cents'] as num?)?.toInt(),
      taxaServicoCents: (m['taxa_servico_cents'] as num?)?.toInt(),
      taxaEntregaCents: (m['taxa_entrega_cents'] as num?)?.toInt(),
      totalCents: (m['total_cents'] as num?)?.toInt(),
      precoProvisorio: m['preco_provisorio'] == true,
      metodoPagamento: m['metodo_pagamento']?.toString(),
      isDemo: m['is_demo'] == true,
      codigoLevantamento: m['codigo_levantamento']?.toString(),
      motivoRecusa: m['motivo_recusa']?.toString(),
    );
  }

  /// Resumo curto das opções: "12 pág. · A4 · cores · frente e verso · 1 cópia".
  String get resumo {
    if (personalizado) return 'Personalizado · $copias un.';
    final partes = <String>[
      '${paginas ?? 0} pág.',
      tamanho ?? 'A4',
      cor ? 'cores' : 'preto e branco',
      frenteVerso ? 'frente e verso' : 'só frente',
      if (papel != null && papel != 'normal') papel == 'cartolina' ? 'cartolina' : 'papel fotográfico',
      if (acabamento != null && acabamento != 'nenhum') acabamentoTexto(acabamento!),
      '$copias ${copias == 1 ? 'cópia' : 'cópias'}',
    ];
    return partes.join(' · ');
  }
}

String acabamentoTexto(String a) {
  switch (a) {
    case 'agrafar':
      return 'agrafado';
    case 'argolas':
      return 'encadernado com argolas';
    case 'plastificar':
      return 'plastificado';
    default:
      return 'sem acabamento';
  }
}

String euros(int? cents) {
  if (cents == null) return '—';
  final v = (cents / 100).toStringAsFixed(2).replaceAll('.', ',');
  return '$v €';
}

/// Lê um intervalo "1-3, 5" e devolve as páginas (1-based) dentro de [total].
/// Vazio = todas. Inválido = null.
List<int>? paginasDoIntervalo(String texto, int total) {
  final t = texto.trim();
  if (t.isEmpty) return List<int>.generate(total, (i) => i + 1);
  final out = <int>{};
  for (final parte in t.split(RegExp(r'[,;]'))) {
    final p = parte.trim();
    if (p.isEmpty) continue;
    final m = RegExp(r'^(\d+)\s*-\s*(\d+)$').firstMatch(p);
    if (m != null) {
      final a = int.parse(m.group(1)!);
      final b = int.parse(m.group(2)!);
      if (a < 1 || b < a || b > total) return null;
      for (var i = a; i <= b; i++) {
        out.add(i);
      }
    } else {
      final n = int.tryParse(p);
      if (n == null || n < 1 || n > total) return null;
      out.add(n);
    }
  }
  if (out.isEmpty) return null;
  return out.toList()..sort();
}
