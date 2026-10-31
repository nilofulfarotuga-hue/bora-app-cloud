import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/euros.dart';

// Ajustes ao peso dos produtos ao quilo dos mercados NÃO-parceiros
// (31/10/2026).
//
// O cliente pede "4 bananas"; o estafeta pesa e escreve o valor da balança;
// a RPC `estafeta_ajustar_peso` grava uma linha por (pedido, produto) em
// `public.order_weight_adjustments` e avisa o cliente (sino
// `order_weight_adjusted` + push do notify-client). A RLS deixa o cliente
// ler as linhas dos seus pedidos e o estafeta as do pedido que leva.
//
// Este ficheiro só LÊ. Quem escreve é a RPC no servidor (dinheiro: a app
// nunca calcula nem grava o novo preço).

/// `in_app_notifications.kind` e `data.type` do push (notify-client) do aviso
/// "Preço ajustado ao peso". O push leva também `orderId`.
const String kTipoAjustePeso = 'order_weight_adjusted';

/// Uma linha de `public.order_weight_adjustments`. Modelo puro: [fromMap]
/// não toca no Supabase, para se poder testar sem rede.
@immutable
class AjustePeso {
  const AjustePeso({
    required this.id,
    required this.orderId,
    required this.productId,
    this.itemName,
    this.qty = 1,
    required this.estBaseCents,
    required this.realBaseCents,
    required this.estClientCents,
    required this.newClientCents,
    required this.deltaClientCents,
    this.driverUserId,
    this.paymentMethod,
    this.settledVia,
    this.settledAt,
    this.notifiedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String orderId;
  final String productId;

  /// Nome do artigo como estava no pedido (pode faltar).
  final String? itemName;
  final int qty;

  /// Preço de caixa (sem margem) estimado e o real da balança, em cêntimos.
  final int estBaseCents;
  final int realBaseCents;

  /// O que o cliente pagava pela linha (estimado) e o que passa a pagar, em
  /// cêntimos. É isto que o cliente vê: "1,12 € → 1,40 €".
  final int estClientCents;
  final int newClientCents;

  /// [newClientCents] − [estClientCents] (positivo = paga mais).
  final int deltaClientCents;

  final String? driverUserId;
  final String? paymentMethod;
  final String? settledVia;
  final DateTime? settledAt;
  final DateTime? notifiedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Tolerante: números como int, double ou texto; datas ISO ou null; chaves
  /// em falta dão o valor neutro (0 / null). Nunca lança por um campo mau.
  factory AjustePeso.fromMap(Map<String, dynamic> m) {
    final est = _int(m['est_client_cents']);
    final novo = _int(m['new_client_cents']);
    return AjustePeso(
      id: _txt(m['id']) ?? '',
      orderId: _txt(m['order_id']) ?? '',
      productId: _txt(m['product_id']) ?? '',
      itemName: _txt(m['item_name']),
      qty: m['qty'] == null ? 1 : _int(m['qty']),
      estBaseCents: _int(m['est_base_cents']),
      realBaseCents: _int(m['real_base_cents']),
      estClientCents: est,
      newClientCents: novo,
      // A coluna é NOT NULL no servidor; se faltar no mapa, faz-se a conta.
      deltaClientCents: m['delta_client_cents'] == null
          ? novo - est
          : _int(m['delta_client_cents']),
      driverUserId: _txt(m['driver_user_id']),
      paymentMethod: _txt(m['payment_method']),
      settledVia: _txt(m['settled_via']),
      settledAt: _data(m['settled_at']),
      notifiedAt: _data(m['notified_at']),
      createdAt: _data(m['created_at']),
      updatedAt: _data(m['updated_at']),
    );
  }

  /// O valor mudou mesmo (o estafeta pode ter voltado ao previsto).
  bool get mudou => newClientCents != estClientCents;

  /// Já foi acertado (cobrado/devolvido) pelo servidor.
  bool get acertado => settledAt != null;

  /// "1,12 €" — o que estava previsto para a linha.
  String get antesTexto => eurCents(estClientCents);

  /// "1,40 €" — o que a linha passa a custar.
  String get depoisTexto => eurCents(newClientCents);

  /// "1,12 € → 1,40 €".
  String get deAteTexto => textoDeAteCents(estClientCents, newClientCents);

  /// "+0,28 €" / "-0,10 €" / "0,00 €".
  String get diferencaTexto => textoDiferencaCents(deltaClientCents);

  static int _int(Object? v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.round();
    return num.tryParse(v.toString().trim())?.round() ?? 0;
  }

  static String? _txt(Object? v) {
    if (v == null) return null;
    final t = v.toString().trim();
    return t.isEmpty ? null : t;
  }

  static DateTime? _data(Object? v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }
}

/// "1,12 € → 1,40 €" a partir de cêntimos (vírgula decimal, símbolo depois).
String textoDeAteCents(int antesCents, int depoisCents) =>
    '${eurCents(antesCents)} → ${eurCents(depoisCents)}';

/// "+0,28 €" quando sobe, "-0,10 €" quando desce, "0,00 €" sem mudança.
String textoDiferencaCents(int deltaCents) =>
    deltaCents > 0 ? '+${eurCents(deltaCents)}' : eurCents(deltaCents);

/// Leitura de `order_weight_adjustments`.
class AjustesPesoService {
  AjustesPesoService({SupabaseClient? client}) : _client = client;

  static final AjustesPesoService instance = AjustesPesoService();

  final SupabaseClient? _client;
  SupabaseClient get _sb => _client ?? Supabase.instance.client;

  /// Colunas lidas (todas as da tabela).
  static const String colunas =
      'id,order_id,product_id,item_name,qty,est_base_cents,real_base_cents,'
      'est_client_cents,new_client_cents,delta_client_cents,driver_user_id,'
      'payment_method,settled_via,settled_at,notified_at,created_at,updated_at';

  /// Todas as linhas do pedido, da mais antiga para a mais recente. Lista
  /// vazia com [orderId] vazio. Erros de rede/RLS sobem a quem chama.
  Future<List<AjustePeso>> doPedido(String orderId) async {
    if (orderId.isEmpty) return const <AjustePeso>[];
    final rows = await _sb
        .from('order_weight_adjustments')
        .select(colunas)
        .eq('order_id', orderId)
        .order('created_at', ascending: true);
    return deLinhas(rows);
  }

  /// Converte o que vem do banco numa lista; ignora o que não for um mapa.
  static List<AjustePeso> deLinhas(Object? rows) {
    if (rows is! List) return const <AjustePeso>[];
    return rows
        .whereType<Map>()
        .map((m) => AjustePeso.fromMap(Map<String, dynamic>.from(m)))
        .toList(growable: false);
  }

  /// Soma das diferenças ao cliente, em cêntimos (positivo = paga mais).
  static int somaDiferencaCents(Iterable<AjustePeso> ajustes) =>
      ajustes.fold<int>(0, (s, a) => s + a.deltaClientCents);

  /// Só as linhas em que o valor mudou (as que o cliente tem de ver).
  static List<AjustePeso> soMudados(Iterable<AjustePeso> ajustes) =>
      ajustes.where((a) => a.mudou).toList(growable: false);

  /// A tabela não está no realtime: quando chega o push
  /// `order_weight_adjusted` com a app aberta, o `NotificationService` chama
  /// [avisarNovoAjuste] e os ecrãs abertos voltam a ler. O valor é um
  /// contador (sobe a cada aviso); [ultimoPedidoAvisado] diz de que pedido.
  static final ValueNotifier<int> avisos = ValueNotifier<int>(0);
  static String? ultimoPedidoAvisado;

  static void avisarNovoAjuste(String orderId) {
    ultimoPedidoAvisado = orderId;
    avisos.value = avisos.value + 1;
  }
}
