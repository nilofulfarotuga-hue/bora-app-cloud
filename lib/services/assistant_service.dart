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

import '../l10n/tr.dart';

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

/// Comparação com o carrinho de outra app (Glovo, Uber Eats…), lida de um
/// print. Missão app-fechar 01/11/2026. Todos os números vêm do servidor
/// (`client-assistant` v10, `montarComparacao`): a diferença é calculada lá,
/// em código, nunca aqui nem pelo modelo.
class AssistantComparacao {
  const AssistantComparacao({
    required this.app,
    required this.totalOutraAppCents,
    required this.totalBoraCents,
    required this.lojaBora,
    required this.restaurantId,
    required this.coberturaPct,
    required this.emFalta,
    required this.diferencaCents,
    required this.boraMaisBarato,
    required this.nota,
    this.linhas = const [],
    this.vencedor,
  });

  /// Nome da outra app ("Glovo", "Uber Eats") ou "outra app".
  final String app;

  /// Total que estava escrito no print da outra app.
  final int totalOutraAppCents;

  /// Total da loja mais barata do Bora, com entrega e taxas incluídas.
  final int totalBoraCents;
  final String lojaBora;
  final String? restaurantId;
  final double coberturaPct;

  /// Artigos que a loja do Bora não tem.
  final List<String> emFalta;

  /// total da outra app − total do Bora (positivo = o Bora é mais barato).
  final int diferencaCents;
  final bool boraMaisBarato;
  final String? nota;

  /// Amigo Bora (08/11/2026): artigo a artigo, o preço na outra app (o que o
  /// cliente mostrou/escreveu) e no Bora. Vazio nos servidores antigos.
  final List<AssistantLinhaComparada> linhas;

  /// bora | outra | empate | sem_total (null nos servidores antigos).
  final String? vencedor;

  /// O cliente mostrou/escreveu o total da outra app (sem ele só há linhas).
  bool get temTotalOutra => totalOutraAppCents > 0;

  /// Igual nos dois lados (diferença zero).
  bool get igual => temTotalOutra && diferencaCents == 0;

  factory AssistantComparacao.fromJson(Map<String, dynamic> j) {
    final falta = j['em_falta'];
    final app = _str(j['app']).trim();
    return AssistantComparacao(
      linhas: _lista(j['linhas']).map(AssistantLinhaComparada.fromJson).toList(),
      vencedor: j['vencedor']?.toString(),
      app: app.isEmpty ? 'outra app' : app,
      totalOutraAppCents: _int(j['total_outra_app_cents']),
      totalBoraCents: _int(j['total_bora_cents']),
      lojaBora: _str(j['loja_bora']),
      restaurantId: j['restaurant_id']?.toString(),
      coberturaPct: _num(j['cobertura_pct'], 100),
      emFalta: falta is List
          ? falta
              .where((e) => e != null && e.toString().trim().isNotEmpty)
              .map((e) => e.toString())
              .toList(growable: false)
          : const [],
      diferencaCents: _int(j['diferenca_cents']),
      boraMaisBarato: _bool(j['bora_mais_barato']),
      nota: j['nota']?.toString(),
    );
  }
}

/// Uma linha da comparação com outra app (calculada no servidor, nunca aqui).
class AssistantLinhaComparada {
  const AssistantLinhaComparada({
    required this.artigo,
    required this.quantidade,
    this.outraCents,
    this.boraCents,
    this.boraNome,
    this.diferencaCents,
  });

  final String artigo;
  final int quantidade;
  final int? outraCents;
  final int? boraCents;
  final String? boraNome;

  /// outra − Bora (positivo = o Bora é mais barato nesta linha).
  final int? diferencaCents;

  static int? _intOuNulo(Object? v) => v == null ? null : _int(v);

  factory AssistantLinhaComparada.fromJson(Map<String, dynamic> j) =>
      AssistantLinhaComparada(
        artigo: _str(j['artigo']),
        quantidade: _int(j['quantidade'], 1),
        outraCents: _intOuNulo(j['outra_cents']),
        boraCents: _intOuNulo(j['bora_cents']),
        boraNome: j['bora_nome']?.toString(),
        diferencaCents: _intOuNulo(j['diferenca_cents']),
      );
}

/// A "deixa" do Amigo Bora: uma linha útil no fim de uma conversa livre
/// (promoção, parceiro novo, tokens a expirar, check-in). Escrita pelo
/// servidor; tocar conta como clique no painel.
class AssistantDeixa {
  const AssistantDeixa({
    required this.id,
    required this.tipo,
    required this.texto,
    required this.acaoTipo,
    this.acaoDestino,
  });

  final String id;
  final String tipo;
  final String texto;
  final String acaoTipo;
  final String? acaoDestino;

  factory AssistantDeixa.fromJson(Map<String, dynamic> j) {
    final a = j['acao'];
    final acao = a is Map ? Map<String, dynamic>.from(a) : const <String, dynamic>{};
    return AssistantDeixa(
      id: _str(j['id']),
      tipo: _str(j['tipo']),
      texto: _str(j['texto']),
      acaoTipo: _str(acao['tipo']),
      acaoDestino: acao['destino']?.toString(),
    );
  }
}

/// Uma foto a mandar ao assistente (já reduzida e em base64).
class AssistantFotoEnvio {
  const AssistantFotoEnvio({required this.base64, this.mime = 'image/jpeg'});
  final String base64;
  final String mime;
}

/// Tipo da imagem pelos primeiros bytes. O Claude recusa uma foto PNG
/// anunciada como JPEG, e na web (ou com fotos pequenas) a app manda os bytes
/// tal como vieram do seletor.
String mimeDaImagem(List<int> b) {
  bool comeca(List<int> assinatura, [int desde = 0]) {
    if (b.length < desde + assinatura.length) return false;
    for (var i = 0; i < assinatura.length; i++) {
      if (b[desde + i] != assinatura[i]) return false;
    }
    return true;
  }

  if (comeca(const [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (comeca(const [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  if (comeca(const [0x52, 0x49, 0x46, 0x46]) &&
      comeca(const [0x57, 0x45, 0x42, 0x50], 8)) {
    return 'image/webp';
  }
  return 'image/jpeg';
}

/// Máximo de fotos por mensagem na app (o servidor aceita até 6, com 16 M de
/// caracteres no total; 4 fotos de ~1,2 MB ficam bem abaixo disso).
const int kAssistantMaxFotos = 4;

/// Corpo do pedido à Edge Function `client-assistant` (função pura, testada
/// sem rede).
///
/// Uma foto vai pelos campos antigos `image_base64`/`image_mime` (funciona com
/// qualquer versão do servidor). Duas ou mais vão em `images: [{base64, mime}]`
/// (servidor v8+), e os campos antigos ficam vazios para a mesma foto não ser
/// lida duas vezes. Nunca manda mais de [kAssistantMaxFotos].
Map<String, dynamic> montarCorpoAssistente({
  required String? conversationId,
  String? message,
  String? imageBase64,
  String? imageMime,
  List<AssistantFotoEnvio> imagens = const [],
  required String platform,
  double? dropoffLat,
  double? dropoffLng,
  bool apartmentDelivery = false,
}) {
  final todas = <AssistantFotoEnvio>[
    if (imageBase64 != null && imageBase64.isNotEmpty)
      AssistantFotoEnvio(base64: imageBase64, mime: imageMime ?? 'image/jpeg'),
    ...imagens.where((f) => f.base64.isNotEmpty),
  ];
  final fotos = todas.length > kAssistantMaxFotos
      ? todas.sublist(0, kAssistantMaxFotos)
      : todas;
  final uma = fotos.length == 1 ? fotos.first : null;
  return {
    'conversation_id': conversationId,
    'message': message,
    'image_base64': uma?.base64,
    'image_mime': uma?.mime,
    if (fotos.length > 1)
      'images': [
        for (final f in fotos) {'base64': f.base64, 'mime': f.mime},
      ],
    'platform': platform,
    'dropoff_lat': dropoffLat,
    'dropoff_lng': dropoffLng,
    'apartment_delivery': apartmentDelivery,
  };
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
    this.comparacao,
    this.deixa,
    this.saudacao,
  });

  /// Amigo Bora: a linha útil do fim da conversa livre (ou null).
  final AssistantDeixa? deixa;

  /// Amigo Bora: 'habitual' | 'simples' quando é a saudação ao abrir.
  final String? saudacao;

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

  /// Comparação com o carrinho de outra app (null quando não houve print).
  final AssistantComparacao? comparacao;

  bool get temCartoes =>
      propostas.isNotEmpty ||
      divisao != null ||
      favores.isNotEmpty ||
      (listaExtraida?.isNotEmpty ?? false) ||
      acoes.isNotEmpty ||
      comparacao != null;

  factory AssistantReply.fromJson(Map<String, dynamic> j) {
    final div = j['divisao'];
    final fp = j['favor_preco'];
    final le = j['lista_extraida'];
    final cmp = j['comparacao'];
    final dx = j['deixa'];
    return AssistantReply(
      comparacao: cmp is Map
          ? AssistantComparacao.fromJson(Map<String, dynamic>.from(cmp))
          : null,
      deixa: dx is Map
          ? AssistantDeixa.fromJson(Map<String, dynamic>.from(dx))
          : null,
      saudacao: j['saudacao']?.toString(),
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

  /// Envia uma mensagem (texto e/ou uma ou várias fotos) e devolve a resposta
  /// estruturada. [imageBase64] continua a servir para uma foto só; [imagens]
  /// leva várias (até [kAssistantMaxFotos]) — ver [montarCorpoAssistente].
  static Future<AssistantReply> enviar({
    required String? conversationId,
    String? message,
    String? imageBase64,
    String? imageMime,
    List<AssistantFotoEnvio> imagens = const [],
    double? dropoffLat,
    double? dropoffLng,
    bool apartmentDelivery = false,
  }) async {
    try {
      final res = await _c.functions.invoke(
        'client-assistant',
        body: montarCorpoAssistente(
          conversationId: conversationId,
          message: message,
          imageBase64: imageBase64,
          imageMime: imageMime,
          imagens: imagens,
          platform: plataforma,
          dropoffLat: dropoffLat,
          dropoffLng: dropoffLng,
          apartmentDelivery: apartmentDelivery,
        ),
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

  // ── Amigo Bora (08/11/2026, missão m4) ────────────────────────────────

  /// Saudação ao abrir o Amigo: sem modelo e sem gastar a quota. Se agora
  /// bate com um hábito do cliente, vem com o último pedido dessa loja num
  /// carrinho proposto e o botão "Sim, repete". Nunca lança: null = sem
  /// saudação (a app mostra o ecrã vazio de sempre).
  static Future<AssistantReply?> abrir({
    double? dropoffLat,
    double? dropoffLng,
    bool apartmentDelivery = false,
  }) async {
    try {
      final res = await _c.functions.invoke('client-assistant', body: {
        'abrir': true,
        'platform': plataforma,
        'dropoff_lat': dropoffLat,
        'dropoff_lng': dropoffLng,
        'apartment_delivery': apartmentDelivery,
      });
      final data = res.data;
      if (data is! Map || data['ok'] != true) return null;
      final r = AssistantReply.fromJson(Map<String, dynamic>.from(data));
      return r.texto.trim().isEmpty ? null : r;
    } catch (e) {
      debugPrint('[AssistantService] abrir: $e');
      return null;
    }
  }

  /// Conta o toque na deixa (painel: "deixas clicadas"). Fire-and-forget.
  static Future<void> deixaClicada(String id) async {
    if (id.isEmpty) return;
    try {
      await _c.rpc('assistant_amigo_deixa_clicada', params: {'p_id': id});
    } catch (e) {
      debugPrint('[AssistantService] deixaClicada: $e');
    }
  }

  /// O resumo que o Amigo guarda do cliente (RLS: só o próprio).
  static Future<Map<String, dynamic>?> perfilAmigo() async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final r = await _c
          .from('assistant_client_profile')
          .select('perfil, lembrar, esquecido_em, atualizado_em')
          .eq('user_id', uid)
          .maybeSingle();
      return r == null ? null : Map<String, dynamic>.from(r);
    } catch (e) {
      debugPrint('[AssistantService] perfilAmigo: $e');
      return null;
    }
  }

  /// "Esquecer tudo" (RGPD): apaga as preferências, limpa o resumo e o Amigo
  /// só volta a aprender com o que acontecer daqui para a frente.
  static Future<bool> esquecerTudo() async {
    try {
      final r = await _c.rpc('assistant_amigo_esquecer');
      return r is Map && r['ok'] == true;
    } catch (e) {
      debugPrint('[AssistantService] esquecerTudo: $e');
      // Servidor sem a migração do Amigo: apaga pelo menos as preferências.
      await apagarMemoriaToda();
      return true;
    }
  }

  /// Deixar (ou não) o Amigo lembrar-se do cliente.
  static Future<bool> lembrar(bool sim) async {
    try {
      final r = await _c.rpc('assistant_amigo_lembrar', params: {'p_lembrar': sim});
      return r is Map && r['ok'] == true;
    } catch (e) {
      debugPrint('[AssistantService] lembrar: $e');
      return false;
    }
  }
}

/// Resumo do perfil do Amigo em frases curtas para o cliente ler (puro,
/// testado). Nunca mostra valores: só o que o Amigo usa para ajudar.
List<String> frasesDoPerfilAmigo(Map<String, dynamic>? perfil) {
  if (perfil == null || perfil.isEmpty) return const [];
  final out = <String>[];
  final nome = perfil['nome_tratamento']?.toString().trim() ?? '';
  if (nome.isNotEmpty) out.add('Chamo-te {0}.'.trArgs([nome]));
  for (final h in _lista(perfil['habitos']).take(3)) {
    final dia = switch ((h['dia'] as num?)?.toInt()) {
      1 => 'à segunda'.tr,
      2 => 'à terça'.tr,
      3 => 'à quarta'.tr,
      4 => 'à quinta'.tr,
      5 => 'à sexta'.tr,
      6 => 'ao sábado'.tr,
      7 => 'ao domingo'.tr,
      _ => '',
    };
    final periodo = switch (h['periodo']?.toString()) {
      'manha' => 'de manhã'.tr,
      'almoco' => 'ao almoço'.tr,
      'tarde' => 'à tarde'.tr,
      _ => 'à noite'.tr,
    };
    final loja = h['loja']?.toString() ?? '';
    if (dia.isNotEmpty && loja.isNotEmpty) {
      out.add('Costumas pedir no {0} {1} {2}.'.trArgs([loja, dia, periodo]));
    }
  }
  final lojas = _lista(perfil['lojas_favoritas'])
      .map((l) => l['nome']?.toString() ?? '')
      .where((n) => n.isNotEmpty)
      .take(3)
      .toList();
  if (lojas.isNotEmpty) out.add('Lojas favoritas: {0}.'.trArgs([lojas.join(', ')]));
  final rec = _lista(perfil['recorrentes'])
      .map((r) => r['nome']?.toString() ?? '')
      .where((n) => n.isNotEmpty)
      .take(5)
      .toList();
  if (rec.isNotEmpty) out.add('Pedes muitas vezes: {0}.'.trArgs([rec.join(', ')]));
  final restr = (perfil['restricoes'] is List ? perfil['restricoes'] as List : const [])
      .map((e) => e.toString())
      .where((e) => e.trim().isNotEmpty)
      .toList();
  if (restr.isNotEmpty) out.add('Disseste-me: {0}.'.trArgs([restr.join(', ')]));
  final gostos = (perfil['gostos'] is List ? perfil['gostos'] as List : const [])
      .map((e) => e.toString())
      .where((e) => e.trim().isNotEmpty)
      .toList();
  if (gostos.isNotEmpty) out.add('Gostas de: {0}.'.trArgs([gostos.join(', ')]));
  return out;
}

/// Interruptor `platform_settings.assistant_enabled`.
///
/// Lido uma vez por sessão (com sessão iniciada — a tabela só é legível por
/// autenticados). Enquanto não se sabe, fica **ligado**: a Edge Function
/// devolve 503 se estiver desligado, por isso o pior caso é um toque a mais.
class AssistantFlags {
  AssistantFlags._();

  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  /// Amigo Bora (08/11/2026): `assistant_personality_enabled`. Enquanto não
  /// se sabe (ou sem a migração) fica DESLIGADO: o nome e o cartão de
  /// boas-vindas só aparecem com o servidor pronto.
  static final ValueNotifier<bool> personalidade = ValueNotifier<bool>(false);

  /// `assistant_amigo_welcome_text` (editável no painel); vazio = texto da app.
  static final ValueNotifier<String> boasVindasAmigo = ValueNotifier<String>('');

  static bool _carregado = false;
  static Future<void>? _emCurso;

  static Future<void> carregar({bool forcar = false}) {
    if (_carregado && !forcar) return Future.value();
    return _emCurso ??= _ler().whenComplete(() => _emCurso = null);
  }

  static Future<void> _ler() async {
    try {
      final linhas = await Supabase.instance.client
          .from('platform_settings')
          .select('key, value')
          .inFilter('key', [
        'assistant_enabled',
        'assistant_personality_enabled',
        'assistant_amigo_welcome_text',
      ]);
      aplicar({
        for (final l in (linhas as List).whereType<Map>())
          l['key'].toString(): l['value'],
      });
    } catch (e) {
      debugPrint('[AssistantFlags] carregar: $e');
    }
  }

  /// Aplica as definições lidas (puro; usado também nos testes).
  @visibleForTesting
  static void aplicar(Map<String, dynamic> valores) {
    // Sem linhas = ainda sem sessão (RLS), não "desligado".
    if (!valores.containsKey('assistant_enabled')) return;
    final v = valores['assistant_enabled'];
    enabled.value = v is bool ? v : (v?.toString() != 'false');
    personalidade.value = valores['assistant_personality_enabled'] == true;
    final w = valores['assistant_amigo_welcome_text'];
    boasVindasAmigo.value = w is String ? w.trim() : '';
    _carregado = true;
  }

  /// Só para testes.
  @visibleForTesting
  static void reset() {
    _carregado = false;
    enabled.value = true;
    personalidade.value = false;
    boasVindasAmigo.value = '';
  }
}
