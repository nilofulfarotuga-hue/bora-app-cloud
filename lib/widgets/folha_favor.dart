// Abre a folha de execução do Favor (`ErrandExecutionSheet`) com o pedido
// SEMPRE atualizado e com folga para a barra de navegação do Android.
//
// Porque existe (08/10/2026, pedido real 74dd4ecc): a folha é zona protegida
// (contém `_finalizePurchase`) e não se lhe toca. Mas recebia uma fotografia
// do pedido tirada no momento em que abria — depois do talão (1,88 €) o
// cartão "3. Entrega" continuava a dizer "Cobrar ao cliente €12.00" (o valor
// estimado) enquanto a faixa laranja, que lê o pedido vivo, dizia €9.88. Só
// ao fechar no X e voltar a abrir é que acertava. Aqui, por fora e sem mudar
// um byte da folha:
//  1. o pedido que a folha recebe é o da `OrderStore` (o Realtime substitui-o
//     quando o servidor muda), e a cada mudança de estado relê-se do servidor
//     para o valor do talão chegar logo;
//  2. ao reabrir, a folha começa no passo gravado no servidor
//     (`orders.errand_passo`): a folha escolhe a fase só no arranque, pela
//     paragem em casa e pela compra, por isso o primeiro fotograma recebe uma
//     cópia ajustada a essa escolha e daí em diante o pedido verdadeiro;
//  3. os botões do fundo ("Confirmar recolha", "Confirmar compra", "Marcar
//     como entregue") deixam de ficar por baixo da barra de 3 botões.
// A conta do dinheiro e a chamada ao talão continuam a ser as da folha.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../models/order_model.dart';
import '../stores/order_store.dart';
import '../utils/favor_passos.dart';
import 'errand_execution_sheet_compat.dart';

class FolhaFavor {
  FolhaFavor._();

  static Future<void> abrir(BuildContext context, OrderModel order) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => FolhaFavorAoVivo(inicial: order),
    );
  }

  /// A cópia do pedido que faz a folha arrancar no passo certo. A folha
  /// decide a fase no arranque assim: paragem em casa → recolha; senão
  /// compra → talão; senão → entrega.
  static OrderModel paraArranque(OrderModel o) {
    final passo = passoAtual(o);
    if (passo == 0) return o;
    try {
      return OrderModel.fromSupabase({
        ...o.toSupabase(),
        'errand_home_stop': false,
        if (passo >= 2) 'errand_has_purchase': false,
        'errand_budget_status': o.errandBudgetStatus,
        'errand_request_photo_url': o.errandRequestPhotoUrl,
        'errand_passo': o.errandPasso,
      });
    } catch (e) {
      debugPrint('[folha-favor] cópia de arranque: $e');
      return o;
    }
  }
}

class FolhaFavorAoVivo extends StatefulWidget {
  const FolhaFavorAoVivo({super.key, required this.inicial});

  final OrderModel inicial;

  @override
  State<FolhaFavorAoVivo> createState() => _FolhaFavorAoVivoState();
}

class _FolhaFavorAoVivoState extends State<FolhaFavorAoVivo> {
  late final OrderModel _arranque = FolhaFavor.paraArranque(widget.inicial);
  bool _jaArrancou = false;
  String? _assinatura;
  Timer? _releitura;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _jaArrancou = true);
    });
  }

  @override
  void dispose() {
    _releitura?.cancel();
    super.dispose();
  }

  OrderModel _vivo(OrderStore store) {
    for (final o in store.orders) {
      if (o.id == widget.inicial.id) return o;
    }
    return widget.inicial;
  }

  /// Mudou o estado (recolha, talão, a caminho) → relê do servidor, para o
  /// `final_total` do talão chegar mesmo que o Realtime se atrase.
  void _talvezReler(OrderStore store, OrderModel vivo) {
    final assinatura =
        '${vivo.status.name}|${vivo.isPurchaseFinalized}|${vivo.finalTotal}';
    final antes = _assinatura;
    _assinatura = assinatura;
    if (antes == null || antes == assinatura) return;
    _releitura?.cancel();
    _releitura = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      unawaited(store.loadOrders());
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<OrderStore>();
    final vivo = _vivo(store);
    _talvezReler(store, vivo);
    final mq = MediaQuery.of(context);
    // Com o teclado aberto a folha já sobe por ele (a folha soma o
    // viewInsets); a barra do sistema fica por baixo do teclado.
    final folga = mq.viewPadding.bottom - mq.viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: folga > 0 ? folga : 0),
      child: ErrandExecutionSheet(order: _jaArrancou ? vivo : _arranque),
    );
  }
}
