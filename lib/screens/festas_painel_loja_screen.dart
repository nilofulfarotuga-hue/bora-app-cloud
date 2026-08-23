import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../models/order_model.dart';
import '../stores/festas_demo_store.dart';
import '../stores/restaurant_store.dart';
import '../widgets/bora/bora_screen_app_bar.dart';

/// O painel da loja na preview Festas — a experiência da dona, sem login.
///
/// Recriação fiel do dia-a-dia do parceiro (a encomenda a entrar, Aceitar /
/// Recusar, Encomenda pronta, encomendas por data, os produtos com preços,
/// abrir/fechar a loja), alimentada pela encomenda simulada e pelos dados
/// reais da base em leitura. Nada aqui escreve no servidor.
class FestasPainelLojaScreen extends StatelessWidget {
  const FestasPainelLojaScreen({super.key});

  static const String _lojaId = 'sabores-brasil-guarda';

  @override
  Widget build(BuildContext context) {
    final demo = context.watch<FestasDemoStore>();
    final restaurantes = context.watch<RestaurantStore>();
    final pedido = demo.pedido;
    final produtos = restaurantes.partnerProductsForRestaurant(_lojaId,
        onlyAvailable: true);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Painel da loja',
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Ver como cliente',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.md, Spacing.lg, Spacing.xxl),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              border: Border.all(color: const Color(0xFFBFDBFE)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Ambiente de demonstração — nada foi cobrado.',
              style: TextStyle(
                  fontSize: 12, color: Color(0xFF1E40AF),
                  fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: Spacing.md),

          // ── A loja ────────────────────────────────────────────────────────
          _Cartao(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Sabores do Brasil',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                        demo.lojaAberta ? 'Loja aberta' : 'Loja fechada',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: demo.lojaAberta
                              ? const Color(0xFF15803D)
                              : const Color(0xFFB91C1C),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: demo.lojaAberta,
                  activeTrackColor: AppColors.primary,
                  onChanged: demo.alternarLoja,
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.md),

          // ── Encomendas ────────────────────────────────────────────────────
          const _Titulo('Encomendas'),
          if (pedido == null)
            const _Cartao(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: Text('As encomendas novas aparecem aqui.',
                      style: TextStyle(color: Color(0xFF6B7280))),
                ),
              ),
            )
          else
            _PedidoCartao(demo: demo, pedido: pedido),

          const SizedBox(height: Spacing.lg),

          // ── Por data de entrega ───────────────────────────────────────────
          const _Titulo('Por data de entrega'),
          _Cartao(
            child: pedido == null
                ? const Text('Sem encomendas marcadas.',
                    style: TextStyle(color: Color(0xFF6B7280), fontSize: 13))
                : Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEDD5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '${demo.quando?.day ?? '—'}',
                              style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFFC2410C)),
                            ),
                            Text(
                              _mesCurto(demo.quando),
                              style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFC2410C)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '1 encomenda · ${_horas(demo.quando)}',
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700),
                            ),
                            Text(
                              demo.recolha
                                  ? 'O cliente vem buscar'
                                  : 'Entrega por estafeta',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF6B7280)),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '€${pedido.total.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: Spacing.lg),

          // ── Os teus produtos ──────────────────────────────────────────────
          const _Titulo('Os teus produtos'),
          _Cartao(
            child: produtos.isEmpty
                ? const Text('Sem produtos.',
                    style: TextStyle(color: Color(0xFF6B7280), fontSize: 13))
                : Column(
                    children: [
                      for (final p in produtos)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13.5)),
                              ),
                              Text('€${p.price.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                      const SizedBox(height: 4),
                      const Text(
                        'No dia-a-dia mudas preços, fotos e descrições aqui.',
                        style:
                            TextStyle(fontSize: 11.5, color: Color(0xFF9CA3AF)),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static String _mesCurto(DateTime? d) {
    if (d == null) return '';
    const m = [
      'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
      'jul', 'ago', 'set', 'out', 'nov', 'dez',
    ];
    return m[d.month - 1];
  }

  static String _horas(DateTime? d) => d == null
      ? 'sem hora marcada'
      : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _PedidoCartao extends StatelessWidget {
  const _PedidoCartao({required this.demo, required this.pedido});

  final FestasDemoStore demo;
  final OrderModel pedido;

  ({String texto, Color fundo, Color cor}) get _estado {
    switch (pedido.status) {
      case OrderStatus.created:
        return (
          texto: 'Nova — à espera da tua confirmação',
          fundo: const Color(0xFFFFEDD5),
          cor: const Color(0xFFC2410C)
        );
      case OrderStatus.preparing:
        return (
          texto: 'Aceite — em preparação',
          fundo: const Color(0xFFDBEAFE),
          cor: const Color(0xFF1D4ED8)
        );
      case OrderStatus.readyForPickup:
        return (
          texto: 'Pronta — o cliente vem buscar',
          fundo: const Color(0xFFDCFCE7),
          cor: const Color(0xFF15803D)
        );
      case OrderStatus.callingDriver:
      case OrderStatus.driverAccepted:
        return (
          texto: 'Pronta — estafeta a caminho da loja',
          fundo: const Color(0xFFDCFCE7),
          cor: const Color(0xFF15803D)
        );
      case OrderStatus.pickedUp:
      case OrderStatus.onTheWay:
        return (
          texto: 'A caminho do cliente',
          fundo: const Color(0xFFDCFCE7),
          cor: const Color(0xFF15803D)
        );
      case OrderStatus.delivered:
        return (
          texto: 'Entregue',
          fundo: const Color(0xFFDCFCE7),
          cor: const Color(0xFF15803D)
        );
      case OrderStatus.rejected:
      case OrderStatus.cancelled:
        return (
          texto: 'Recusada',
          fundo: const Color(0xFFFEE2E2),
          cor: const Color(0xFFB91C1C)
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = _estado;
    return _Cartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  pedido.customerName ?? 'Cliente',
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w800),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: e.fundo,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(e.texto,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: e.cor)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${demo.recolha ? 'Recolha' : 'Entrega'} · '
            '${FestasPainelLojaScreen._horas(demo.quando)} · '
            'dia ${demo.quando?.day ?? '—'} de '
            '${FestasPainelLojaScreen._mesCurto(demo.quando)}',
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF6B7280)),
          ),
          const Divider(height: 20),
          for (final item in pedido.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${item.quantity}× ',
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w800)),
                      Expanded(
                        child: Text(item.name,
                            style: const TextStyle(fontSize: 13.5)),
                      ),
                    ],
                  ),
                  for (final op in item.selectedOptions)
                    Padding(
                      padding: const EdgeInsets.only(left: 22),
                      child: Text(
                        '${op.group}: ${op.items.join(', ')}',
                        style: const TextStyle(
                            fontSize: 11.5, color: Color(0xFF6B7280)),
                      ),
                    ),
                ],
              ),
            ),
          if ((pedido.customerNotes ?? '').isNotEmpty) ...[
            const SizedBox(height: 2),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F7F4),
                borderRadius: BorderRadius.circular(8),
                border: const Border(
                    left: BorderSide(color: Color(0xFFE7D8BE), width: 3)),
              ),
              child: Text(
                pedido.customerNotes!,
                style: const TextStyle(
                    fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('Total',
                  style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
              const Spacer(),
              Text('€${pedido.total.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 12),
          if (pedido.status == OrderStatus.created)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: demo.recusar,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB91C1C),
                      side: const BorderSide(color: Color(0xFFFECACA)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11)),
                    ),
                    child: const Text('Recusar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: demo.aceitar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11)),
                    ),
                    child: const Text('Aceitar',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            )
          else if (pedido.status == OrderStatus.preparing)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: demo.marcarPronta,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11)),
                ),
                child: const Text('Encomenda pronta',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
        ],
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(texto,
            style:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      );
}

class _Cartao extends StatelessWidget {
  const _Cartao({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Spacing.md),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      );
}
