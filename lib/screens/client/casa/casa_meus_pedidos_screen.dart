import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../l10n/tr.dart';
import '../../../models/casa_models.dart';
import '../../../stores/casa_store.dart';
import '../../../widgets/bora/bora.dart';
import '../../../widgets/bora/bora_empty_placeholder.dart';
import '../../../widgets/bora/lista_estado.dart';
import 'casa_pedido_screen.dart';
import 'casa_regras.dart';
import 'casa_widgets.dart';

/// CASA — "Os meus pedidos" (31/10/2026): os por resolver primeiro, depois o
/// histórico. Tocar abre o acompanhamento. Enquanto carrega mostra o esqueleto
/// e, se falhar, "Tentar outra vez" — nunca "ainda não tens pedidos" por engano.
class CasaMeusPedidosScreen extends StatefulWidget {
  const CasaMeusPedidosScreen({super.key});

  @override
  State<CasaMeusPedidosScreen> createState() => _CasaMeusPedidosScreenState();
}

class _CasaMeusPedidosScreenState extends State<CasaMeusPedidosScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CasaStore>().carregarMeusPedidos();
    });
  }

  void _abrir(CasaPedido p) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CasaPedidoScreen(pedido: p)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CasaStore>();
    final pedidos = store.meusPedidos;

    final Widget corpo;
    if (pedidos.isEmpty && !store.pedidosCarregados && !store.pedidosFalharam) {
      corpo = const ListaACarregar();
    } else if (pedidos.isEmpty && store.pedidosFalharam) {
      corpo = ListaComErro(onRetry: store.carregarMeusPedidos);
    } else if (pedidos.isEmpty) {
      corpo = BoraEmptyPlaceholder(
        icon: Icons.home_repair_service_outlined,
        title: 'Ainda não fizeste pedidos'.tr,
        message:
            'Quando pedires um trabalho para casa, acompanhas tudo aqui.'.tr,
      );
    } else {
      corpo = RefreshIndicator(
        onRefresh: store.carregarMeusPedidos,
        child: ListView.separated(
          padding: EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg,
              BoraBottomActionBar.folgaInferior(context)),
          itemCount: pedidos.length,
          separatorBuilder: (_, __) => const SizedBox(height: Spacing.md),
          itemBuilder: (_, i) => _LinhaPedido(
            pedido: pedidos[i],
            onTap: () => _abrir(pedidos[i]),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(title: 'Os meus pedidos'.tr),
      body: corpo,
    );
  }
}

class _LinhaPedido extends StatelessWidget {
  const _LinhaPedido({required this.pedido, required this.onTap});

  final CasaPedido pedido;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = pedido;
    final quando = p.scheduledAt ?? p.createdAt;
    final aberto = !p.estado.terminal;
    final precisaDeTi = p.estado == CasaEstado.concluido ||
        p.extrasPorResponder.isNotEmpty ||
        (p.estado == CasaEstado.orcamentos && p.orcamentosAbertos.isNotEmpty);
    return CasaCartao(
      onTap: onTap,
      padding: const EdgeInsets.all(Spacing.md),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: aberto ? AppColors.primaryWash : AppColors.surface2,
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Icon(
              casaIconeOficio(p.oficio),
              color: aberto ? AppColors.primary : AppColors.textSubtle,
            ),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.servicoNome.isEmpty ? p.oficioNome : p.servicoNome,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  casaEstadoTr(p.estado),
                  style: TextStyle(
                    color: aberto ? AppColors.primary : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (quando != null)
                  Text(
                    casaQuandoTexto(quando),
                    style: const TextStyle(
                        color: AppColors.textSubtle, fontSize: 12),
                  ),
                if (precisaDeTi)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      p.estado == CasaEstado.orcamentos
                          ? 'Tens orçamentos para ver'.tr
                          : 'Precisa da tua resposta'.tr,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (p.totalCents > 0)
            Padding(
              padding: const EdgeInsets.only(left: Spacing.sm),
              child: Text(
                casaEuro(p.totalCents),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          const Icon(Icons.chevron_right, color: AppColors.textSubtle),
        ],
      ),
    );
  }
}
