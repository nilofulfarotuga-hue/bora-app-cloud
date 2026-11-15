// Painel (PT-BR) — filas dos entregadores e rascunhos das compras (14/11/2026).
//
// Adenda 1 do Danilo: cada entregador faz um pedido de cada vez. O que ele
// aceitou por cima do pedido em andamento fica "em espera" (stand-by) e só
// aparece no app dele depois de entregar o atual. Ordem da espera: Favor
// URGENTE logo depois do atual, depois as entregas, o Favor normal no fim.
// Aqui vê-se a fila de cada entregador e, em cada pedido, o rascunho da compra
// (o que ele já marcou), para fechar pelo painel/MCP se o app falhar.
// Fonte: `admin_filas_estafetas` e `admin_rascunho_compra` (só admin).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../widgets/admin/admin_rascunho_compra_section.dart';

class AdminFilasEstafetasScreen extends StatefulWidget {
  const AdminFilasEstafetasScreen({super.key});

  @override
  State<AdminFilasEstafetasScreen> createState() =>
      _AdminFilasEstafetasScreenState();
}

class _AdminFilasEstafetasScreenState extends State<AdminFilasEstafetasScreen> {
  List<Map<String, dynamic>> _filas = const [];
  String? _erro;
  bool _aCarregar = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _aCarregar = true;
      _erro = null;
    });
    try {
      final res =
          await Supabase.instance.client.rpc('admin_filas_estafetas');
      if (!mounted) return;
      setState(() {
        _filas = [
          for (final f in (res as List? ?? const []))
            Map<String, dynamic>.from(f as Map)
        ];
        _aCarregar = false;
      });
    } catch (e) {
      if (!mounted) return;
      final texto = e.toString();
      setState(() {
        _aCarregar = false;
        _erro = texto.contains('PGRST202') || texto.contains('does not exist')
            ? 'A função admin_filas_estafetas ainda não foi publicada no '
                'servidor (migração 20261114190000).'
            : texto;
      });
    }
  }

  static String _tipo(Map<String, dynamic> p) {
    final st = p['service_type'] as String?;
    if (st == 'errand') {
      return p['errand_speed'] == 'express' ? 'Favor URGENTE' : 'Favor normal';
    }
    return switch (st) {
      'restaurant' => 'Restaurante',
      'storeShopping' => 'Compras no mercado',
      'carryGroceries' => 'Levar compras',
      'sendPackage' => 'Encomenda',
      _ => st ?? 'Pedido',
    };
  }

  void _abrirRascunho(String orderId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (_, sc) => SingleChildScrollView(
          controller: sc,
          padding: const EdgeInsets.all(12),
          child: AdminRascunhoCompraSection(
            orderId: orderId,
            esconderSemRascunho: false,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Filas dos entregadores'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              color: Colors.teal.shade50,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Cada entregador vê só o pedido em andamento (ATIVO). O que ele '
                  'aceitou por cima fica EM ESPERA (stand-by) e abre no app dele, '
                  'com aviso, quando entregar o atual. Ordem: Favor urgente logo '
                  'depois do atual, depois as entregas, o Favor normal no fim. '
                  'Toque num pedido para ver o rascunho da compra (o que ele já '
                  'marcou).',
                ),
              ),
            ),
            if (_aCarregar)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_erro != null)
              Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_erro!),
                ),
              )
            else if (_filas.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nenhum entregador com pedidos em andamento agora.'),
              )
            else
              for (final f in _filas) _cartaoEstafeta(f),
          ],
        ),
      ),
    );
  }

  Widget _cartaoEstafeta(Map<String, dynamic> f) {
    final fila = [
      for (final p in (f['fila'] as List? ?? const []))
        Map<String, dynamic>.from(p as Map)
    ];
    final espera = fila.where((p) => p['estado'] == 'em_espera').length;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.delivery_dining, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (f['estafeta'] as String?) ?? 'Entregador sem nome',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                if (espera > 0)
                  Chip(
                    label: Text('$espera em espera'),
                    backgroundColor: Colors.orange.shade100,
                  ),
              ],
            ),
            for (final p in fila)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                onTap: () => _abrirRascunho(p['order_id'] as String),
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: p['estado'] == 'ativo'
                      ? Colors.green.shade100
                      : Colors.orange.shade100,
                  child: Text('${p['posicao']}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                title: Text(
                  '${p['estado'] == 'ativo' ? 'ATIVO' : 'EM ESPERA'} · '
                  '${_tipo(p)} · ${p['loja'] ?? '—'}',
                ),
                subtitle: Text(
                  'Cliente: ${p['cliente'] ?? '—'} · status ${p['status']}'
                  '${p['rascunho_marcados'] != null ? ' · ${p['rascunho_marcados']} itens marcados' : ''}',
                ),
                trailing: const Icon(Icons.chevron_right),
              ),
          ],
        ),
      ),
    );
  }
}
