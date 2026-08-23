import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../models/order_model.dart';
import '../stores/festas_demo_store.dart';
import 'festas_painel_loja_screen.dart';
import 'order_tracking_screen.dart';

/// Acompanhamento da encomenda simulada da preview Festas.
///
/// Reutiliza o [OrderTrackingScreen] REAL do delivery — timeline, mapa,
/// marcadores, PIN — por cima só entram a faixa de demonstração e o comutador
/// para o painel da loja. A cada transição de estado o FestasDemoStore emite
/// um OrderModel novo e este wrapper repassa-o ao ecrã de tracking.
class FestasDemoPedidoScreen extends StatelessWidget {
  const FestasDemoPedidoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final demo = context.watch<FestasDemoStore>();
    final pedido = demo.pedido;

    if (pedido == null) {
      // Percurso reiniciado — volta à raiz.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    if (pedido.status == OrderStatus.rejected) {
      return _Recusado(demo: demo);
    }

    return Stack(
      children: [
        OrderTrackingScreen(order: pedido),
        // Faixa de demonstração + comutador — discretos, no topo.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(60, 4, 60, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Material(
                      color: const Color(0xE6111111),
                      borderRadius: BorderRadius.circular(999),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const FestasPainelLojaScreen()),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 13, vertical: 7),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Flexible(
                                child: Text(
                                  'Demonstração — nada foi cobrado',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Painel da loja',
                                style: TextStyle(
                                    color: AppColors.accent,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Recusado extends StatelessWidget {
  const _Recusado({required this.demo});

  final FestasDemoStore demo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('😔', style: TextStyle(fontSize: 52)),
                const SizedBox(height: 14),
                const Text(
                  'A loja recusou este pedido',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Não foi cobrado nada. Podes tentar outra data '
                  'ou falar com a loja.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 14, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      demo.limpar();
                      Navigator.of(context)
                          .popUntil((route) => route.isFirst);
                    },
                    child: const Text('Voltar ao início'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
