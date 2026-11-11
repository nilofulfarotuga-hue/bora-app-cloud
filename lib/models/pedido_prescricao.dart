// Pedido de receita / pedido especial numa farmácia (missão farmacias-2026-11-11).
// Espelha a tabela public.pedidos_prescricao (ver .claude/.ai/missoes/farmacias-2026-11-11/CONTRATO.md).
// Os campos sensíveis (caminhos de fotos, códigos da receita) só chegam a quem a RLS deixa ver:
// o cliente dono, a farmácia do pedido e o admin.

enum PrescricaoTipo { receita, pedidoLivre }

enum PrescricaoEstado {
  enviado,
  aceite,
  aceiteParcial,
  recusado,
  expirado,
  cancelado,
  confirmado,
  entregue;

  static PrescricaoEstado fromDb(String? v) {
    switch (v) {
      case 'aceite':
        return PrescricaoEstado.aceite;
      case 'aceite_parcial':
        return PrescricaoEstado.aceiteParcial;
      case 'recusado':
        return PrescricaoEstado.recusado;
      case 'expirado':
        return PrescricaoEstado.expirado;
      case 'cancelado':
        return PrescricaoEstado.cancelado;
      case 'confirmado':
        return PrescricaoEstado.confirmado;
      case 'entregue':
        return PrescricaoEstado.entregue;
      case 'enviado':
      default:
        return PrescricaoEstado.enviado;
    }
  }

  String get db {
    switch (this) {
      case PrescricaoEstado.aceiteParcial:
        return 'aceite_parcial';
      default:
        return name;
    }
  }

  /// À espera da farmácia.
  bool get aEsperaDaFarmacia => this == PrescricaoEstado.enviado;

  /// A farmácia disse que tem (tudo ou parte) e falta o cliente confirmar.
  bool get aEsperaDoCliente =>
      this == PrescricaoEstado.aceite || this == PrescricaoEstado.aceiteParcial;

  /// Já não muda (salvo admin).
  bool get terminado =>
      this == PrescricaoEstado.recusado ||
      this == PrescricaoEstado.expirado ||
      this == PrescricaoEstado.cancelado ||
      this == PrescricaoEstado.entregue;
}

/// Motivos de recusa da farmácia (valores da coluna motivo_recusa).
class PrescricaoMotivo {
  static const semStock = 'sem_stock';
  static const receitaInvalida = 'receita_invalida';
  static const outro = 'outro';

  static String rotulo(String? m) {
    switch (m) {
      case semStock:
        return 'Sem stock';
      case receitaInvalida:
        return 'Receita inválida ou caducada';
      case outro:
        return 'Outro motivo';
      default:
        return '';
    }
  }
}

class PedidoPrescricao {
  final String id;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String restaurantId;
  final String userId;
  final PrescricaoTipo tipo;
  final PrescricaoEstado estado;

  // Cliente
  final String? receitaFotoPath;
  final String? receitaNumero;
  final String? receitaCodigoAcesso;
  final String? receitaCodigoOpcao;
  final String? descricao;
  final String? pedidoFotoPath;
  final String? morada;
  final double? lat;
  final double? lng;
  final String? nota;
  final String? assinaturaPath;
  final String? consentimentoVersao;
  final String? consentimentoTexto;
  final DateTime? consentimentoEm;

  // Farmácia
  final int? valorMedicamentosCents;
  final String? itensDisponiveis;
  final int? tempoPreparacaoMin;
  final String? motivoRecusa;
  final String? motivoTexto;
  final String? voltaATer;
  final DateTime? respondidoEm;
  final DateTime? expiraEm;

  // Confirmação
  final int? taxaServicoCents;
  final int? totalCents;
  final String? metodoPagamento;
  final bool? soDisponiveis;
  final DateTime? confirmadoEm;
  final String? codigoLevantamento;
  final String? codigoEntrega;
  final String? orderId;
  final bool isDemo;
  final DateTime? canceladoEm;
  final DateTime? entregueEm;
  final DateTime? dadosApagadosEm;

  const PedidoPrescricao({
    required this.id,
    required this.createdAt,
    required this.restaurantId,
    required this.userId,
    required this.tipo,
    required this.estado,
    this.updatedAt,
    this.receitaFotoPath,
    this.receitaNumero,
    this.receitaCodigoAcesso,
    this.receitaCodigoOpcao,
    this.descricao,
    this.pedidoFotoPath,
    this.morada,
    this.lat,
    this.lng,
    this.nota,
    this.assinaturaPath,
    this.consentimentoVersao,
    this.consentimentoTexto,
    this.consentimentoEm,
    this.valorMedicamentosCents,
    this.itensDisponiveis,
    this.tempoPreparacaoMin,
    this.motivoRecusa,
    this.motivoTexto,
    this.voltaATer,
    this.respondidoEm,
    this.expiraEm,
    this.taxaServicoCents,
    this.totalCents,
    this.metodoPagamento,
    this.soDisponiveis,
    this.confirmadoEm,
    this.codigoLevantamento,
    this.codigoEntrega,
    this.orderId,
    this.isDemo = false,
    this.canceladoEm,
    this.entregueEm,
    this.dadosApagadosEm,
  });

  static DateTime? _dt(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
  static int? _int(dynamic v) =>
      v == null ? null : (v is num ? v.toInt() : int.tryParse(v.toString()));
  static double? _dbl(dynamic v) =>
      v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));

  factory PedidoPrescricao.fromMap(Map<String, dynamic> m) {
    return PedidoPrescricao(
      id: m['id'].toString(),
      createdAt: _dt(m['created_at']) ?? DateTime.now(),
      updatedAt: _dt(m['updated_at']),
      restaurantId: (m['restaurant_id'] ?? '').toString(),
      userId: (m['user_id'] ?? '').toString(),
      tipo: m['tipo'] == 'pedido_livre' ? PrescricaoTipo.pedidoLivre : PrescricaoTipo.receita,
      estado: PrescricaoEstado.fromDb(m['estado'] as String?),
      receitaFotoPath: m['receita_foto_path'] as String?,
      receitaNumero: m['receita_numero'] as String?,
      receitaCodigoAcesso: m['receita_codigo_acesso'] as String?,
      receitaCodigoOpcao: m['receita_codigo_opcao'] as String?,
      descricao: m['descricao'] as String?,
      pedidoFotoPath: m['pedido_foto_path'] as String?,
      morada: m['morada'] as String?,
      lat: _dbl(m['lat']),
      lng: _dbl(m['lng']),
      nota: m['nota'] as String?,
      assinaturaPath: m['assinatura_path'] as String?,
      consentimentoVersao: m['consentimento_versao'] as String?,
      consentimentoTexto: m['consentimento_texto'] as String?,
      consentimentoEm: _dt(m['consentimento_em']),
      valorMedicamentosCents: _int(m['valor_medicamentos_cents']),
      itensDisponiveis: m['itens_disponiveis'] as String?,
      tempoPreparacaoMin: _int(m['tempo_preparacao_min']),
      motivoRecusa: m['motivo_recusa'] as String?,
      motivoTexto: m['motivo_texto'] as String?,
      voltaATer: m['volta_a_ter'] as String?,
      respondidoEm: _dt(m['respondido_em']),
      expiraEm: _dt(m['expira_em']),
      taxaServicoCents: _int(m['taxa_servico_cents']),
      totalCents: _int(m['total_cents']),
      metodoPagamento: m['metodo_pagamento'] as String?,
      soDisponiveis: m['so_disponiveis'] as bool?,
      confirmadoEm: _dt(m['confirmado_em']),
      codigoLevantamento: m['codigo_levantamento'] as String?,
      codigoEntrega: m['codigo_entrega'] as String?,
      orderId: m['order_id'] as String?,
      isDemo: m['is_demo'] == true,
      canceladoEm: _dt(m['cancelado_em']),
      entregueEm: _dt(m['entregue_em']),
      dadosApagadosEm: _dt(m['dados_apagados_em']),
    );
  }

  bool get eReceita => tipo == PrescricaoTipo.receita;

  /// Total que o cliente paga = medicamentos + taxa do serviço (o servidor manda o total
  /// depois de confirmar; antes disso soma-se o que a farmácia disse + a taxa das definições).
  int? totalPrevistoCents(int taxaServicoCentsDefinicao) {
    if (totalCents != null) return totalCents;
    if (valorMedicamentosCents == null) return null;
    return valorMedicamentosCents! + (taxaServicoCents ?? taxaServicoCentsDefinicao);
  }
}

/// Euros em PT-PT a partir de cêntimos: 1234 -> "12,34 €".
String eurosDeCents(int? cents) {
  if (cents == null) return '—';
  final neg = cents < 0;
  final v = cents.abs();
  final s = '${v ~/ 100},${(v % 100).toString().padLeft(2, '0')} €';
  return neg ? '-$s' : s;
}
