// lib/screens/admin/admin_stuck_orders_screen.dart
//
// [Estafeta web 2026-09-16 · BLOCO 5.7] Painel admin (PT-BR): "Pedidos parados".
// Pedidos em callingDriver há mais de dispatch_preassign_release_seconds
// (3 min por defeito), INCLUINDO os que têm entregador atribuído sem aceitar
// (o caso do Ney a 16/09), e pedidos ainda não prontos com entregador
// reservado. Em cada um: "Escolher estafeta" e "Mandar para todos".
// Leitura: RPC admin_stuck_orders. Escrita: só pelos caminhos oficiais.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/admin/escolher_estafeta_sheet.dart';
import 'admin_order_detail_screen.dart';

class AdminStuckOrdersScreen extends StatefulWidget {
  const AdminStuckOrdersScreen({super.key});

  @override
  State<AdminStuckOrdersScreen> createState() => _AdminStuckOrdersScreenState();
}

class _AdminStuckOrdersScreenState extends State<AdminStuckOrdersScreen> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _erro;
  Timer? _auto;

  @override
  void initState() {
    super.initState();
    _load();
    // Lista viva: um pedido parado é emergência, não se espera pelo refresh.
    _auto = Timer.periodic(const Duration(seconds: 20), (_) => _load(silencioso: true));
  }

  @override
  void dispose() {
    _auto?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silencioso = false}) async {
    if (!silencioso) setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client.rpc('admin_stuck_orders');
      final rows = (res is List)
          ? res.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _erro = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _loading = false;
      });
    }
  }

  String _espera(int? s) {
    if (s == null) return '—';
    if (s < 60) return '$s s';
    final m = s ~/ 60;
    if (m < 60) return '$m min';
    return '${m ~/ 60} h ${m % 60} min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos parados'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: () => _load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Não foi possível carregar: $_erro',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.error)),
                  ),
                )
              : _rows.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline, size: 48, color: Colors.green),
                            SizedBox(height: 12),
                            Text('Nenhum pedido parado agora.',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                            SizedBox(height: 4),
                            Text(
                              'Aparecem aqui os pedidos a chamar entregador há mais de 3 minutos '
                              '(mesmo com entregador atribuído) e os reservados à espera de ficar prontos.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _StuckCard(
                          r: _rows[i],
                          espera: _espera((_rows[i]['espera_s'] as num?)?.toInt()),
                          onChanged: () => _load(silencioso: true),
                        ),
                      ),
                    ),
    );
  }
}

class _StuckCard extends StatelessWidget {
  const _StuckCard({required this.r, required this.espera, required this.onChanged});
  final Map<String, dynamic> r;
  final String espera;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final id = (r['id'] ?? '').toString();
    final ref = id.replaceAll('-', '').substring(0, id.length >= 6 ? 6 : id.length).toUpperCase();
    final status = (r['status'] ?? '').toString();
    final atribuido = r['assigned_driver_name'] ?? r['assigned_driver_id'];
    final reservado = r['preassigned_driver_name'] ?? r['preassigned_driver_id'];
    final oferta = r['offer_driver_name'] ?? r['current_driver_offer_id'];
    final temAlguem = atribuido != null || reservado != null;
    final grave = status == 'callingDriver' && atribuido != null;
    final teste = r['is_test_order'] == true;
    final preco = (r['price'] as num?)?.toDouble();

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: grave ? const Color(0xFFFCA5A5) : const Color(0xFFE5E7EB)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AdminOrderDetailScreen(orderId: id)),
        ).then((_) => onChanged()),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '#$ref · ${r['vendor_name'] ?? 'Loja'}${teste ? ' · TESTE' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: grave ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('há $espera',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: grave ? const Color(0xFF991B1B) : const Color(0xFF92400E))),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${r['motivo'] ?? status}'
                '${preco != null ? ' · €${preco.toStringAsFixed(2)}' : ''}'
                '${r['customer_name'] != null ? ' · ${r['customer_name']}' : ''}',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              if (atribuido != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Atribuído a: $atribuido',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF991B1B), fontWeight: FontWeight.w600)),
                ),
              if (reservado != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Reservado para: $reservado', style: const TextStyle(fontSize: 13)),
                ),
              if (oferta != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Oferta em curso: $oferta', style: const TextStyle(fontSize: 13)),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                      onPressed: () async {
                        final ok = await escolherEstafetaParaPedido(context, orderId: id, status: status);
                        if (ok) onChanged();
                      },
                      icon: const Icon(Icons.person_search, size: 18),
                      label: const Text('Escolher estafeta'),
                    ),
                  ),
                  if (temAlguem) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final ok = await mandarPedidoParaTodos(context, orderId: id);
                          if (ok) onChanged();
                        },
                        icon: const Icon(Icons.campaign_outlined, size: 18),
                        label: const Text('Mandar para todos'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
