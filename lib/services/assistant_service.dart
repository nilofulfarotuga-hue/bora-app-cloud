// BORA ASSISTENTE (07/10/2026) — o assistente de compras do cliente.
//
// Camada de dados do ecrã de conversa:
//   * modelos da resposta estruturada da Edge Function `client-assistant`;
//   * chamada à função (com o JWT do cliente), histórico e marcação de
//     propostas (RPC `assistant_mark_proposal`);
//   * interruptor `platform_settings.assistant_enabled` (lido uma vez);
//   * a proposta "pendente" guardada no aparelho até o pedido nascer.
//
// Nada aqui calcula preços: todos os valores vêm do servidor já fechados.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Chave de SharedPreferences com a conversa activa.
const String kAssistantConversationPrefsKey = 'bora_assistant.conversation_id';

/// Chave de SharedPreferences com a proposta que o cliente abriu no carrinho
/// e ainda não encomendou.
const String kAssistantPendingProposalPrefsKey = 'bora_assistant.pending_proposal';

double _num(dynamic v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

int _int(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

bool _bool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is String) return v == 'true';
  return fallback;
}

String _str(dynamic v, [String fallback = '']) =>
    v == null ? fallback : v.toString();

List<Map<String, dynamic>> _lista(dynamic v) {
  if (v is! List) return const [];
  return v
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList(growable: false);
}

/// Um artigo dentro de uma proposta de carrinho.
class AssistantItem {
  const AssistantItem({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.basePrice,
    required this.lineTotal,
    this.unit,
    this.photoUrl,
    this.confidence = 'alta',
    this.maior18 = false,
    this.query = '',
  });

  final String productId;
  final String name;
  final int quantity;

  /// Preço exibido por unidade (já com o markup do servidor se não-parceiro).
  final double unitPrice;

  /// Preço puro de catálogo (`products.price`). Null em dados antigos.
  final double? basePrice;
  final double lineTotal;
  final String? unit;
  final String? photoUrl;

  /// 'alta' ou 'parecido' (pede confirmação ao cliente).
  final String confidence;
  final bool maior18;
  final String query;

  bool get parecido => confidence == 'parecido';

  factory AssistantItem.fromJson(Map<String, dynamic> j) => AssistantItem(
        productId: _str(j['product_id']),
        name: _str(j['name']),
        quantity: _int(j['quantity'], 1).clamp(1, 999),
        unitPrice: _num(j['unit_price']),
        basePrice: j['base_price'] == null ? null : _num(j['base_price']),
        lineTotal: _num(j['line_total']),
        unit: j['unit']?.toString(),
        photoUrl: j['photo_url']?.toString(),
        confidence: _str(j['confidence'], 'alta'),
        maior18: _bool(j['maior_18']),
        query: _str(j['query']),
      );
}

/// Artigo pedido que a loja não tem.
class AssistantMissingItem {
  const AssistantMissingItem({required this.query, required this.quantity});
  final String query;
  final int quantity;

  factory AssistantMissingItem.fromJson(Map<String, dynamic> j) =>
      AssistantMissingItem(
        query: _str(j['query']),
        quantity: _int(j['quantity'], 1),
      );
}

/// Uma proposta de carrinho numa loja (ou uma das partes de uma divisão).
class AssistantProposal {
  const AssistantProposal({
    required this.proposalId,
    required this.restaurantId,
    required this.restaurantName,
    required this.isPartner,
    required this.serviceType,
    required this.open,
    required this.coveragePct,
    required this.rank,
    required this.kind,
    required this.items,
    required this.missingItems,
    required this.subtotal,
    required this.deliveryFee,
    required this.serviceFee,
    required this.smallOrderFee,
    required this.bagFee,
    required this.customerTotal,
    required this.savingsCents,
    required this.hasMaior18,
    required this.distanceKm,
  });

  final String proposalId;
  final String restaurantId;
  final String restaurantName;
  final bool isPartner;

  /// 'storeShopping' | 'restaurant'
  final String serviceType;
  final bool open;
  final double coveragePct;
  final int rank;
  final String kind;
  final List<AssistantItem> items;
  final List<AssistantMissingItem> missingItems;
  final double subtotal;
  final double deliveryFee;
  final double serviceFee;
  final double smallOrderFee;
  final double bagFee;
  final double customerTotal;
  final int savingsCents;
  final bool hasMaior18;
  final double distanceKm;

  factory AssistantProposal.fromJson(Map<String, dynamic> j) =>
      AssistantProposal(
        proposalId: _str(j['proposal_id'] ?? j['id']),
        restaurantId: _str(j['restaurant_id']),
        restaurantName: _str(j['restaurant_name']),
        isPartner: _bool(j['is_partner']),
        serviceType: _str(j['service_type'], 'storeShopping'),
        open: _bool(j['open'], true),
        coveragePct: _num(j['coverage_pct'], 100),
        rank: _int(j['rank'], 1),
        kind: _str(j['kind'], 'single'),
        items: _lista(j['items']).map(AssistantItem.fromJson).toList(),
        missingItems:
            _lista(j['missing_items']).map(AssistantMissingItem.fromJson).toList(),
        subtotal: _num(j['subtotal']),
        deliveryFee: _num(j['delivery_fee']),
        serviceFee: _num(j['service_fee']),
        smallOrderFee: _num(j['small_order_fee']),
        bagFee: _num(j['bag_fee']),
        customerTotal: _num(j['customer_total']),
        savingsCents: _int(j['savings_cents']),
        hasMaior18: _bool(j['has_maior_18']),
        distanceKm: _num(j['distance_km']),
      );

  /// Linha de `assistant_cart_proposals` (quando se abre pela URL
  /// `/assistente?proposta=<uuid>` ou se redesenha do histórico).
  factory AssistantProposal.fromRow(Map<String, dynamic> r) =>
      AssistantProposal.fromJson({
        ...r,
        'proposal_id': r['id'],
        'open': r['open'] ?? true,
      });
}

/// Sugestão de dividir a lista por 2 lojas.
class AssistantDivisao {
  const AssistantDivisao({
    required this.customerTotal,
    required this.savingsVsBestSingleCents,
    required this.splitGroup,
    required this.parts,
  });
  final double customerTotal;
  final int savingsVsBestSingleCents;
  final String? splitGroup;
  final List<AssistantProposal> parts;

  factory AssistantDivisao.fromJson(Map<String, dynamic> j) => AssistantDivisao(
        customerTotal: _num(j['customer_total']),
        savingsVsBestSingleCents: _int(j['savings_vs_best_single_cents']),
        splitGroup: j['split_group']?.toString(),
        parts: _lista(j['parts']).map(AssistantProposal.fromJson).toList(),
      );
}

/// Coisa que só se consegue por Favor (tabaco, fora do catálogo…).
class AssistantFavor {
  const AssistantFavor({
    required this.query,
    required this.quantity,
    required this.maior18,
  });
  final String query;
  final int quantity;
  final bool maior18;

  factory AssistantFavor.fromJson(Map<String, dynamic> j) => AssistantFavor(
        query: _str(j['query']),
        quantity: _int(j['quantity'], 1),
        maior18: _bool(j['maior_18']),
      );
}

class AssistantFavorPreco {
  const AssistantFavorPreco({
    required this.available,
    required this.normalFee,
    required this.expressFee,
    required this.normalSlaMinutes,
    required this.expressSlaMinutes,
    required this.maxAdvanceCents,
  });
  final bool available;
  final double normalFee;
  final double expressFee;
  final int normalSlaMinutes;
  final int expressSlaMinutes;
  final int maxAdvanceCents;

  factory AssistantFavorPreco.fromJson(Map<String, dynamic> j) =>
      AssistantFavorPreco(
        available: _bool(j['available'], true),
        normalFee: _num(j['normal_fee']),
        expressFee: _num(j['express_fee']),
        normalSlaMinutes: _int(j['normal_sla_minutes']),
        expressSlaMinutes: _int(j['express_sla_minutes']),
        maxAdvanceCents: _int(j['max_advance_cents']),
      );
}

/// Chip de acção que o assistente sugere.
class AssistantAcao {
  const AssistantAcao({required this.tipo, required this.rotulo, this.destino});
  final String tipo;
  final String rotulo;
  final String? destino;

  factory AssistantAcao.fromJson(Map<String, dynamic> j) => AssistantAcao(
        tipo: _str(j['tipo']),
        rotulo: _str(j['rotulo']),
        destino: j['destino']?.toString(),
      );
}

/// Resposta estruturada do assistente (a mesma forma vai para
/// `assistant_chat_messages.structured`, por isso serve para redesenhar).
class AssistantReply {
  const AssistantReply({
    required this.conversationId,
    required this.texto,
    required this.propostas,
    required this.divisao,
    required this.favores,
    required this.favorPreco,
    required this.listaExtraida,
    required this.acoes,
    required this.handoff,
    required this.ticketId,
    required this.messagesRemainingToday,
    required this.poupancaAcumuladaCents,
  });

  final String? conversationId;
  final String texto;
  final List<AssistantProposal> propostas;
  final AssistantDivisao? divisao;
  final List<AssistantFavor> favores;
  final AssistantFavorPreco? favorPreco;
  final List<AssistantMissingItem>? listaExtraida;
  final List<AssistantAcao> acoes;
  final bool handoff;
  final String? ticketId;
  final int? messagesRemainingToday;
  final int poupancaAcumuladaCents;

  bool get temCartoes =>
      propostas.isNotEmpty ||
      divisao != null ||
      favores.isNotEmpty ||
      (listaExtraida?.isNotEmpty ?? false) ||
      acoes.isNotEmpty;

  factory AssistantReply.fromJson(Map<String, dynamic> j) {
    final div = j['divisao'];
    final fp = j['favor_preco'];
    final le = j['lista_extraida'];
    return AssistantReply(
      conversationId: j['conversation_id']?.toString(),
      texto: _str(j['texto']),
      propostas: _lista(j['propostas']).map(AssistantProposal.fromJson).toList(),
      divisao: div is Map
          ? AssistantDivisao.fromJson(Map<String, dynamic>.from(div))
          : null,
      favores: _lista(j['favores']).map(AssistantFavor.fromJson).toList(),
      favorPreco: fp is Map
          ? AssistantFavorPreco.fromJson(Map<String, dynamic>.from(fp))
          : null,
      listaExtraida: le is List
          ? _lista(le).map(AssistantMissingItem.fromJson).toList()
          : null,
      acoes: _lista(j['acoes']).map(AssistantAcao.fromJson).toList(),
      handoff: _bool(j['handoff']),
      ticketId: j['ticket_id']?.toString(),
      messagesRemainingToday: j['messages_remaining_today'] == null
          ? null
          : _int(j['messages_remaining_today']),
      poupancaAcumuladaCents: _int(j['poupanca_acumulada_cents']),
    );
  }

  /// Só o texto (resposta sem estrutura, ex. mensagem antiga).
  factory AssistantReply.texto(String texto) => AssistantReply(
        conversationId: null,
        texto: texto,
        propostas: const [],
        divisao: null,
        favores: const [],
        favorPreco: null,
        listaExtraida: null,
        acoes: const [],
        handoff: false,
        ticketId: null,
        messagesRemainingToday: null,
        poupancaAcumuladaCents: 0,
      );
}

/// Erro do assistente com o texto que o servidor quer mostrar.
class AssistantException implements Exception {
  const AssistantException(this.codigo, this.texto, {this.status});
  final String codigo; // quota | disabled | auth | rede | servidor
  final String texto;
  final int? status;

  @override
  String toString() => 'AssistantException($codigo, $status): $texto';
}

/// Mensagem do histórico (`assistant_chat_messages`).
class AssistantHistoryMessage {
  const AssistantHistoryMessage({
    required this.role,
    required this.content,
    required this.imageUrl,
    required this.reply,
    required this.createdAt,
  });
  final String role; // user | assistant
  final String content;
  final String? imageUrl;
  final AssistantReply? reply;
  final DateTime? createdAt;
}

class AssistantService {
  AssistantService._();

  static SupabaseClient get _c => Supabase.instance.client;

  static String get plataforma {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
  }

  /// Envia uma mensagem (texto e/ou foto) e devolve a resposta estruturada.
  static Future<AssistantReply> enviar({
    required String? conversationId,
    String? message,
    String? imageBase64,
    String? imageMime,
    double? dropoffLat,
    double? dropoffLng,
    bool apartmentDelivery = false,
  }) async {
    try {
      final res = await _c.functions.invoke(
        'client-assistant',
        body: {
          'conversation_id': conversationId,
          'message': message,
          'image_base64': imageBase64,
          'image_mime': imageMime,
          'platform': plataforma,
          'dropoff_lat': dropoffLat,
          'dropoff_lng': dropoffLng,
          'apartment_delivery': apartmentDelivery,
        },
      );
      final data = res.data;
      if (data is! Map) {
        throw const AssistantException('servidor', 'Resposta vazia do servidor.');
      }
      final map = Map<String, dynamic>.from(data);
      if (map['ok'] == false || map['error'] != null) {
        throw AssistantException(
          _str(map['error'], 'servidor'),
          _str(map['texto'], 'Não consegui responder agora.'),
          status: res.status,
        );
      }
      return AssistantReply.fromJson(map);
    } on AssistantException {
      rethrow;
    } on FunctionException catch (e) {
      String texto = '';
      String codigo = 'servidor';
      final d = e.details;
      if (d is Map) {
        texto = _str(d['texto']);
        codigo = _str(d['error'], codigo);
      }
      if (e.status == 429) codigo = 'quota';
      if (e.status == 503) codigo = 'disabled';
      if (e.status == 401) codigo = 'auth';
      throw AssistantException(codigo, texto, status: e.status);
    } catch (e) {
      debugPrint('[AssistantService] enviar: $e');
      throw const AssistantException('rede', '');
    }
  }

  /// Histórico de uma conversa (RLS deixa o cliente ler só o seu).
  static Future<List<AssistantHistoryMessage>> historico(
      String conversationId) async {
    final rows = await _c
        .from('assistant_chat_messages')
        .select('role, content, image_url, structured, created_at')
        .eq('conversation_id', conversationId)
        .inFilter('role', ['user', 'assistant'])
        .order('created_at', ascending: true)
        .limit(200);
    return (rows as List).whereType<Map>().map((r) {
      final m = Map<String, dynamic>.from(r);
      final st = m['structured'];
      AssistantReply? reply;
      if (m['role'] == 'assistant') {
        reply = st is Map
            ? AssistantReply.fromJson(Map<String, dynamic>.from(st))
            : AssistantReply.texto(_str(m['content']));
      }
      return AssistantHistoryMessage(
        role: _str(m['role']),
        content: _str(m['content']),
        imageUrl: m['image_url']?.toString(),
        reply: reply,
        createdAt: DateTime.tryParse(_str(m['created_at'])),
      );
    }).toList();
  }

  /// Lê uma proposta pelo id (abrir pela URL `?proposta=`).
  static Future<AssistantProposal?> proposta(String id) async {
    final r = await _c
        .from('assistant_cart_proposals')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (r == null) return null;
    return AssistantProposal.fromRow(Map<String, dynamic>.from(r));
  }

  /// Marca a proposta como aberta no carrinho / encomendada.
  static Future<bool> marcarProposta(
    String proposalId,
    String status, {
    String? orderId,
  }) async {
    try {
      final r = await _c.rpc('assistant_mark_proposal', params: {
        'p_id': proposalId,
        'p_status': status,
        'p_order_id': orderId,
      });
      return r is Map && r['ok'] == true;
    } catch (e) {
      debugPrint('[AssistantService] marcarProposta($status): $e');
      return false;
    }
  }

  // ── Conversa activa no aparelho ───────────────────────────────────────

  static Future<String?> conversaGuardada() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getString(kAssistantConversationPrefsKey);
      return (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      return null;
    }
  }

  static Future<void> guardarConversa(String? id) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (id == null || id.isEmpty) {
        await p.remove(kAssistantConversationPrefsKey);
      } else {
        await p.setString(kAssistantConversationPrefsKey, id);
      }
    } catch (_) {}
  }

  // ── Proposta pendente (aberta no carrinho, à espera do pedido) ────────

  static Future<void> guardarPropostaPendente(String proposalId) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(kAssistantPendingProposalPrefsKey, proposalId);
    } catch (_) {}
  }

  /// Chamado quando um pedido nasce com sucesso (CartStore.finishOrder).
  /// Fire-and-forget: nunca trava o checkout, nunca lança.
  static Future<void> pedidoCriado(String? orderId) async {
    if (orderId == null || orderId.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      final id = p.getString(kAssistantPendingProposalPrefsKey);
      if (id == null || id.isEmpty) return;
      final ok = await marcarProposta(id, 'ordered', orderId: orderId);
      if (ok) await p.remove(kAssistantPendingProposalPrefsKey);
    } catch (e) {
      debugPrint('[AssistantService] pedidoCriado: $e');
    }
  }

  // ── Estatísticas e memória do cliente ─────────────────────────────────

  static Future<Map<String, dynamic>?> stats() async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return null;
    final r = await _c
        .from('assistant_client_stats')
        .select('savings_shown_cents, savings_realized_cents, proposals_count, orders_count')
        .eq('user_id', uid)
        .maybeSingle();
    return r == null ? null : Map<String, dynamic>.from(r);
  }

  static Future<List<Map<String, dynamic>>> memoria() async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return const [];
    final rows = await _c
        .from('assistant_client_memory')
        .select('id, kind, key, value, updated_at')
        .eq('user_id', uid)
        .order('updated_at', ascending: false);
    return (rows as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<void> apagarMemoria(String id) =>
      _c.from('assistant_client_memory').delete().eq('id', id);

  static Future<void> apagarMemoriaToda() async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return;
    await _c.from('assistant_client_memory').delete().eq('user_id', uid);
  }
}

/// Interruptor `platform_settings.assistant_enabled`.
///
/// Lido uma vez por sessão (com sessão iniciada — a tabela só é legível por
/// autenticados). Enquanto não se sabe, fica **ligado**: a Edge Function
/// devolve 503 se estiver desligado, por isso o pior caso é um toque a mais.
class AssistantFlags {
  AssistantFlags._();

  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);
  static bool _carregado = false;
  static Future<void>? _emCurso;

  static Future<void> carregar({bool forcar = false}) {
    if (_carregado && !forcar) return Future.value();
    return _emCurso ??= _ler().whenComplete(() => _emCurso = null);
  }

  static Future<void> _ler() async {
    try {
      final linha = await Supabase.instance.client
          .from('platform_settings')
          .select('value')
          .eq('key', 'assistant_enabled')
          .maybeSingle();
      // Linha vazia = ainda sem sessão (RLS), não "desligado".
      if (linha == null) return;
      final v = linha['value'];
      final on = v is bool ? v : (v?.toString() != 'false');
      enabled.value = on;
      _carregado = true;
    } catch (e) {
      debugPrint('[AssistantFlags] carregar: $e');
    }
  }

  /// Só para testes.
  @visibleForTesting
  static void reset() {
    _carregado = false;
    enabled.value = true;
  }
}
