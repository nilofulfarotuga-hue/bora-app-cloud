import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Origem de um pedido: feito na app ou pelo robô de WhatsApp.
///
/// Os pedidos do robô de WhatsApp ficam em `public.order_origem` (order_id,
/// origem 'app'|'whatsapp', client_phone). Aqui só se LÊ essa tabela: leitura
/// só para admin e para o parceiro dono da loja do pedido (RLS); a escrita é
/// só da chave de serviço. Se a leitura falhar (tabela ainda sem existir, sem
/// permissão, sem rede) os ecrãs ficam IGUAIS ao que eram — sem erro visível.
const String kOrigemApp = 'app';
const String kOrigemWhatsApp = 'whatsapp';

/// Valores do filtro "Origem" do painel admin.
const String kFiltroOrigemTodas = 'all';

/// Uma linha de `order_origem`.
@immutable
class PedidoOrigem {
  const PedidoOrigem({required this.origem, this.clientPhone});

  final String origem;
  final String? clientPhone;

  bool get ehWhatsApp => origem == kOrigemWhatsApp;
}

/// true quando a origem é o robô de WhatsApp. `null` e 'app' → false.
bool origemEhWhatsApp(String? origem) => origem == kOrigemWhatsApp;

/// "WhatsApp" ou "App" (sem linha em order_origem = "App").
String rotuloOrigem(String? origem) =>
    origemEhWhatsApp(origem) ? 'WhatsApp' : 'App';

/// Telefone do cliente a mostrar: o do pedido se vier preenchido; senão o
/// guardado em order_origem. `null` quando nenhum dos dois existe.
String? telefoneDoCliente({String? doPedido, String? daOrigem}) {
  final p = (doPedido ?? '').trim();
  if (p.isNotEmpty) return p;
  final o = (daOrigem ?? '').trim();
  return o.isNotEmpty ? o : null;
}

/// Filtro "Origem: Todas | App | WhatsApp" da lista de pedidos do admin.
/// [origens] == null (leitura falhou) ou filtro "todas" → lista como está.
/// Pedido sem linha em order_origem conta como "App".
List<Map<String, dynamic>> filtrarPedidosPorOrigem(
  List<Map<String, dynamic>> pedidos,
  Map<String, PedidoOrigem>? origens,
  String filtro,
) {
  if (origens == null) return pedidos;
  if (filtro != kOrigemApp && filtro != kOrigemWhatsApp) return pedidos;
  final queroWhatsApp = filtro == kOrigemWhatsApp;
  return pedidos.where((p) {
    final zap = origens[p['id']?.toString() ?? '']?.ehWhatsApp ?? false;
    return zap == queroWhatsApp;
  }).toList();
}

/// Ids por pedido. O URL leva os ids todos, por isso vai em lotes.
const int _kTamanhoLote = 50;

/// Lê em lote a origem dos pedidos [ids]. Devolve só as linhas que existem
/// (pedido sem linha = feito na app). Devolve `null` se a leitura falhar
/// (tabela inexistente, sem permissão, sem rede): quem chama deixa o ecrã
/// como estava.
Future<Map<String, PedidoOrigem>?> carregarOrigensPedidos(
    Iterable<String> ids) async {
  final lista = ids.where((e) => e.isNotEmpty).toSet().toList();
  if (lista.isEmpty) return <String, PedidoOrigem>{};
  try {
    final out = <String, PedidoOrigem>{};
    for (var i = 0; i < lista.length; i += _kTamanhoLote) {
      final lote = lista.sublist(i, math.min(i + _kTamanhoLote, lista.length));
      final rows = await Supabase.instance.client
          .from('order_origem')
          .select('order_id,origem,client_phone')
          .inFilter('order_id', lote)
          .timeout(const Duration(seconds: 8));
      for (final r in rows) {
        final id = r['order_id']?.toString();
        final origem = r['origem']?.toString();
        if (id == null || id.isEmpty || origem == null) continue;
        out[id] = PedidoOrigem(
          origem: origem,
          clientPhone: r['client_phone']?.toString(),
        );
      }
    }
    return out;
  } catch (e) {
    debugPrint('[order_origem] leitura falhou (ecrã fica como estava): $e');
    return null;
  }
}
