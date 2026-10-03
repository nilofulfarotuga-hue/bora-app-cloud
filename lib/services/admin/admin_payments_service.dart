import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/saved_card.dart';

/// Uma cobrança, venha ela de que vertical vier.
class AdminPaymentRow {
  const AdminPaymentRow({
    required this.vertical,
    required this.entityId,
    required this.userId,
    required this.paymentIntentId,
    required this.amountCents,
    required this.status,
    required this.paymentMethod,
    required this.createdAt,
  });

  final String vertical;
  final String entityId;
  final String? userId;
  final String? paymentIntentId;
  final int amountCents;
  final String? status;
  final String? paymentMethod;
  final DateTime? createdAt;

  factory AdminPaymentRow.fromMap(Map<String, dynamic> m) => AdminPaymentRow(
        vertical: (m['vertical'] as String?) ?? '?',
        entityId: (m['entity_id'] as String?) ?? '',
        userId: m['user_id'] as String?,
        paymentIntentId: m['payment_intent_id'] as String?,
        amountCents: (m['amount_cents'] as num?)?.toInt() ?? 0,
        status: m['status'] as String?,
        paymentMethod: m['payment_method'] as String?,
        createdAt: m['created_at'] != null
            ? DateTime.tryParse(m['created_at'].toString())
            : null,
      );

  /// Só faz sentido estornar o que foi mesmo cobrado no cartão.
  bool get podeEstornar =>
      (paymentIntentId ?? '').startsWith('pi_') && amountCents > 0;

  /// Painel é PT-BR, mas a moeda é euro — o Bora cobra em Portugal.
  String get valorFormatado => '€${(amountCents / 100).toStringAsFixed(2)}';

  static const Map<String, String> rotulosVertical = {
    'delivery': 'Delivery',
    'reserva': 'Reserva de mesa',
    'marcacao': 'Agendamento',
    'tvde': 'TVDE corrida',
    'tvde_plano': 'TVDE plano',
    'limpeza': 'Limpeza',
  };

  String get verticalRotulo => rotulosVertical[vertical] ?? vertical;
}

/// PaymentIntent parado à espera de autenticação 3DS.
class AdminStuckIntent {
  const AdminStuckIntent({
    required this.id,
    required this.status,
    required this.amountCents,
    required this.created,
    required this.metadata,
  });

  final String id;
  final String status;
  final int amountCents;
  final DateTime? created;
  final Map<String, dynamic> metadata;

  factory AdminStuckIntent.fromMap(Map<String, dynamic> m) => AdminStuckIntent(
        id: (m['id'] as String?) ?? '',
        status: (m['status'] as String?) ?? '',
        amountCents: (m['amount_cents'] as num?)?.toInt() ?? 0,
        created: m['created'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                ((m['created'] as num).toInt()) * 1000)
            : null,
        metadata: (m['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}

/// Erro já com mensagem PT-BR pronta para o painel.
class AdminPaymentsException implements Exception {
  const AdminPaymentsException(this.mensagem);
  final String mensagem;
  @override
  String toString() => mensagem;
}

/// Serviço da aba admin "Pagamentos/Cartões" (Carteira Única, Parte 6/6).
///
/// Duas fontes, porque os dados vivem em dois sítios:
///  - RPC `admin_list_payments` — histórico, que sai do nosso banco;
///  - Edge Fn `admin-payments`  — cartões, PaymentIntents travados e estorno,
///    que só a Stripe sabe.
class AdminPaymentsService {
  AdminPaymentsService({SupabaseClient? client}) : _override = client;

  static final AdminPaymentsService instance = AdminPaymentsService();

  final SupabaseClient? _override;
  SupabaseClient get _sb => _override ?? Supabase.instance.client;

  /// Histórico de cobranças de todas as verticais.
  Future<List<AdminPaymentRow>> listarPagamentos({
    String? vertical,
    String? busca,
    int limite = 200,
    int offset = 0,
  }) async {
    try {
      final res = await _sb.rpc('admin_list_payments', params: {
        'p_vertical': vertical,
        'p_search': busca,
        'p_limit': limite,
        'p_offset': offset,
      });
      if (res is! List) return const [];
      return res
          .map((e) => AdminPaymentRow.fromMap((e as Map).cast<String, dynamic>()))
          .toList();
    } on PostgrestException catch (e) {
      debugPrint('[AdminPaymentsService] listarPagamentos: ${e.message}');
      if (e.message.contains('admin only')) {
        throw const AdminPaymentsException(
            'Sua sessão não tem permissão de admin. Saia e entre novamente.');
      }
      if (e.code == 'PGRST202' || e.message.contains('does not exist')) {
        throw const AdminPaymentsException(
            'Falta aplicar a migration 20260721120000_admin_list_payments.sql '
            'no banco. O histórico fica vazio até lá.');
      }
      throw AdminPaymentsException('Não foi possível carregar: ${e.message}');
    }
  }

  /// Cartões guardados de UM cliente (marca + últimos 4, nunca o número).
  Future<List<SavedCard>> cartoesDoUsuario(String userId) async {
    final data = await _invoke({'action': 'list_cards', 'user_id': userId});
    final raw = (data['cards'] as List?) ?? const [];
    return raw
        .map((m) => SavedCard.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList();
  }

  /// PaymentIntents parados à espera de 3DS.
  Future<List<AdminStuckIntent>> intentsTravados({int limite = 100}) async {
    final data = await _invoke({'action': 'stuck_intents', 'limit': limite});
    final raw = (data['intents'] as List?) ?? const [];
    return raw
        .map((m) => AdminStuckIntent.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList();
  }

  /// Estorna. O valor real e as travas ficam na Edge Fn `refund`, que esta
  /// chamada apenas alcança — o app nunca fala com a Stripe diretamente.
  Future<String?> estornar({
    required String paymentIntentId,
    required int amountCents,
    String? userId,
    String? entityId,
    String? vertical,
    String? motivo,
  }) async {
    final data = await _invoke({
      'action': 'refund',
      'payment_intent_id': paymentIntentId,
      'amount_cents': amountCents,
      if (userId != null) 'user_id': userId,
      if (entityId != null) 'entity_id': entityId,
      if (vertical != null) 'vertical': vertical,
      if (motivo != null) 'reason': motivo,
    });
    return data['refund_id'] as String?;
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final res = await _sb.functions.invoke('admin-payments', body: body);
      final data = (res.data is Map)
          ? (res.data as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      if (res.status >= 400 || data['error'] != null) {
        throw AdminPaymentsException(_mensagem(res.status, data));
      }
      return data;
    } on AdminPaymentsException {
      rethrow;
    } catch (e) {
      debugPrint('[AdminPaymentsService] invoke falhou: $e');
      throw const AdminPaymentsException(
          'Não foi possível falar com o servidor. Verifique a conexão. '
          'Se o problema persistir, confirme se a Edge Function '
          '"admin-payments" já foi publicada.');
    }
  }

  String _mensagem(int status, Map<String, dynamic> data) {
    final code = data['error']?.toString() ?? '';
    switch (code) {
      case 'forbidden: admin only':
        return 'Sua sessão não tem permissão de admin.';
      case 'user_id_required':
        return 'Selecione um cliente primeiro.';
      case 'charge_missing':
        return 'Esse pagamento não tem cobrança concluída — não há o que estornar.';
      case 'refund_failed':
        return 'A Stripe recusou o estorno: ${data['details'] ?? 'motivo não informado'}';
      default:
        if (status == 404) {
          return 'Edge Function "admin-payments" ainda não foi publicada.';
        }
        return code.isEmpty ? 'Falha (erro $status).' : code;
    }
  }
}
