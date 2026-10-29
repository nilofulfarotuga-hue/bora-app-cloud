import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../l10n/tr.dart';
import '../models/order_model.dart';
import '../screens/order_tracking_screen.dart';
import '../services/interruptores_app.dart';
import '../services/notification_service.dart';
import '../services/order_eta_service.dart';
import '../stores/order_store.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Lógica pura (testada sem Flutter): que pedido mostrar, o que dizer, em
// quantos minutos. Adendo 4 · item 1 (29/10/2026).
// ─────────────────────────────────────────────────────────────────────────────

/// O pedido ainda está em curso (não acabou, não foi recusado nem cancelado)?
bool pedidoEmCurso(OrderModel o) =>
    o.status != OrderStatus.delivered &&
    o.status != OrderStatus.rejected &&
    o.status != OrderStatus.cancelled;

/// O pedido a mostrar na barra: o mais recente ainda em curso, entre os
/// pedidos DESTE cliente ([pedidosDoCliente] já vem filtrado por
/// `OrderStore.ordersForCurrentClient`: um estafeta ou um parceiro nunca vê a
/// barra de um pedido que não é seu).
OrderModel? escolherPedidoAtivo(List<OrderModel> pedidosDoCliente) {
  OrderModel? melhor;
  for (final o in pedidosDoCliente) {
    if (!pedidoEmCurso(o)) continue;
    if (melhor == null || o.createdAt.isAfter(melhor.createdAt)) melhor = o;
  }
  return melhor;
}

/// O estado em palavras de pessoa (PT-PT). Curto: cabe numa linha.
String tituloDoEstado(OrderModel o) {
  final compras = o.serviceType == OrderServiceType.storeShopping;
  switch (o.status) {
    case OrderStatus.created:
      return compras ? 'Pedido recebido' : 'Pedido enviado à loja';
    case OrderStatus.preparing:
      return compras ? 'A preparar o teu pedido' : 'A loja está a preparar';
    case OrderStatus.readyForPickup:
      return 'Pronto para levantares';
    case OrderStatus.callingDriver:
      return 'À procura de estafeta';
    case OrderStatus.driverAccepted:
      return compras ? 'O estafeta vai às compras' : 'Estafeta a caminho da loja';
    case OrderStatus.pickedUp:
      return 'O estafeta já tem o teu pedido';
    case OrderStatus.onTheWay:
      return 'O estafeta vai a caminho';
    case OrderStatus.delivered:
      return 'Pedido entregue';
    case OrderStatus.rejected:
      return 'Pedido recusado';
    case OrderStatus.cancelled:
      return 'Pedido cancelado';
  }
}

/// Em que fases a espera da loja ainda conta para o tempo estimado, e por isso
/// o tempo já passado nessa fase desconta-se. Nas fases com estafeta a
/// distância viva (posição do estafeta) é que manda: não se desconta nada.
bool _descontaTempoDaFase(OrderStatus s) =>
    s == OrderStatus.preparing || s == OrderStatus.callingDriver;

/// Tempo estimado em texto, SEMPRE recalculado.
///
/// * Base: `OrderEtaService` (tempo de preparação da loja, quando existe, mais
///   minutos de entrega pela distância; nunca um "5-20 min" fixo).
/// * [naFase]: há quanto tempo o pedido está neste estado. Enquanto a loja
///   prepara, o que já passou desconta-se (e nunca se baixa de 5 minutos).
/// * Compras em loja não parceira ficam com o intervalo honesto do serviço.
/// * "Ir buscar": a hora a que fica pronto, se a loja a disse.
///
/// `null` quando não há como estimar (sem coordenadas): a barra mostra só o
/// estado, sem inventar um número.
String? etaDoPedido(OrderModel o, {Duration naFase = Duration.zero, LatLng? driverPos}) {
  if (!pedidoEmCurso(o)) return null;
  if (o.serviceType == OrderServiceType.takeaway) {
    final pronto = o.takeawayReadyAt?.toLocal();
    if (pronto == null) return null;
    final h = pronto.hour.toString().padLeft(2, '0');
    final m = pronto.minute.toString().padLeft(2, '0');
    return 'Pronto às {0}'.trArgs(['$h:$m']);
  }
  if (o.serviceType == OrderServiceType.storeShopping &&
      o.status.index <= OrderStatus.driverAccepted.index) {
    return OrderEtaService.label(o, driverPos: driverPos);
  }
  final base = OrderEtaService.minutesRemaining(o, driverPos: driverPos);
  if (base == null) return null;
  var minutos = base;
  // C6: com "fica pronto às HH:MM" o `base` já vem descontado do que passou
  // (conta desde agora até à hora prometida): não se desconta duas vezes.
  if (_descontaTempoDaFase(o.status) && o.readyAtPromised == null) {
    minutos = base - naFase.inMinutes;
  }
  if (minutos < 5) minutos = 5;
  // Arredonda para cima de 5 em 5, como o resto da app.
  minutos = ((minutos / 5).ceil()) * 5;
  return 'Chega em ~{0} min'.trArgs([minutos]);
}

/// Estado partilhado: o pedido que o ecrã de acompanhamento já está a mostrar
/// (a barra esconde-se aí, para não duplicar) e se há uma barra global montada
/// à volta do Navigator (o separador deixa então de desenhar a sua).
class BarraPedidoAtivoEstado {
  BarraPedidoAtivoEstado._();

  static final ValueNotifier<String?> pedidoAVer = ValueNotifier<String?>(null);
  static final ValueNotifier<int> hospedeiros = ValueNotifier<int>(0);

  /// A barra está mesmo a desenhar-se agora? O [BarraPedidoAtivoHost] usa-o
  /// para só tirar a margem de baixo ao ecrã quando a barra a está a pôr.
  static final ValueNotifier<bool> visivel = ValueNotifier<bool>(false);
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets
// ─────────────────────────────────────────────────────────────────────────────

/// A barra em si: verde (#16A34A), texto branco de 16 px, toca-se para abrir o
/// acompanhamento. Só aparece com o interruptor `feature_barra_pedido_ativo`
/// ligado no painel admin e quando há um pedido meu em curso.
class BarraPedidoAtivo extends StatefulWidget {
  const BarraPedidoAtivo(
      {super.key,
      this.meuId,
      this.aoTocar,
      this.margemInferior = false,
      this.escondida = false});

  /// Teclado aberto: a barra sai da frente (sem mudar a forma da árvore).
  final bool escondida;

  /// Dentro do [BarraPedidoAtivoHost]: a barra põe ela a margem de baixo do
  /// telemóvel (o ecrã de cima fica sem ela).
  final bool margemInferior;

  /// Para testes: quem sou. Por defeito, o utilizador da sessão (AuthStore).
  final String? meuId;

  /// Para testes: o que fazer ao tocar. Por defeito, abre o acompanhamento.
  final void Function(OrderModel pedido)? aoTocar;

  @override
  State<BarraPedidoAtivo> createState() => _BarraPedidoAtivoState();
}

class _BarraPedidoAtivoState extends State<BarraPedidoAtivo> {
  bool _ligado = true;
  Timer? _relogio;

  /// Desde quando o pedido está neste estado (visto por esta app). Muda quando
  /// o estado muda — é aí que o tempo estimado se recalcula do zero.
  final Map<String, ({OrderStatus estado, DateTime desde})> _fase = {};

  @override
  void initState() {
    super.initState();
    InterruptoresApp.instance
        .ligado(InterruptoresApp.barraPedidoAtivo)
        .then((v) {
      if (mounted && v != _ligado) setState(() => _ligado = v);
    });
    // Um minuto de cada vez chega: o tempo estimado anda em múltiplos de 5.
    _relogio = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _relogio?.cancel();
    super.dispose();
  }

  Duration _naFase(OrderModel o) {
    final agora = DateTime.now();
    final visto = _fase[o.id];
    if (visto == null || visto.estado != o.status) {
      _fase[o.id] = (estado: o.status, desde: agora);
      return Duration.zero;
    }
    return agora.difference(visto.desde);
  }

  void _abrir(OrderModel o) {
    final cb = widget.aoTocar;
    if (cb != null) {
      cb(o);
      return;
    }
    NotificationService.navigatorKey.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => OrderTrackingScreen(order: o)),
    );
  }

  bool _publicado = false;

  void _publicar(bool v) {
    if (v == _publicado) return;
    _publicado = v;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (BarraPedidoAtivoEstado.visivel.value != v) {
        BarraPedidoAtivoEstado.visivel.value = v;
      }
    });
  }

  @override
  void deactivate() {
    if (_publicado) {
      _publicado = false;
      scheduleMicrotask(() => BarraPedidoAtivoEstado.visivel.value = false);
    }
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ligado || widget.escondida) {
      _publicar(false);
      return const SizedBox.shrink();
    }
    final List<OrderModel> pedidos;
    try {
      final store = context.watch<OrderStore>();
      String? uid = widget.meuId;
      String? telefone;
      if (uid == null) {
        final auth = context.watch<AuthStore>();
        uid = auth.userId;
        telefone = auth.currentClient?.phone;
      }
      pedidos = store.ordersForCurrentClient(phone: telefone, userId: uid);
    } on ProviderNotFoundException {
      // Ecrãs de arranque, antes de existir o armazém de pedidos.
      _publicar(false);
      return const SizedBox.shrink();
    }
    final o = escolherPedidoAtivo(pedidos);
    if (o == null) {
      _publicar(false);
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<String?>(
      valueListenable: BarraPedidoAtivoEstado.pedidoAVer,
      builder: (context, aVer, _) {
        if (aVer == o.id) {
          _publicar(false);
          return const SizedBox.shrink();
        }
        _publicar(true);
        final eta = etaDoPedido(o, naFase: _naFase(o));
        return BarraPedidoAtivoVista(
          pedido: o,
          eta: eta,
          margemInferior: widget.margemInferior,
          aoTocar: () => _abrir(o),
        );
      },
    );
  }
}

/// O desenho da barra (sem lógica): título do estado, tempo estimado, toque.
class BarraPedidoAtivoVista extends StatelessWidget {
  const BarraPedidoAtivoVista({
    super.key,
    required this.pedido,
    required this.eta,
    required this.aoTocar,
    this.margemInferior = false,
  });

  final OrderModel pedido;
  final String? eta;
  final VoidCallback aoTocar;
  final bool margemInferior;

  @override
  Widget build(BuildContext context) {
    final titulo = tituloDoEstado(pedido).tr;
    return Semantics(
      button: true,
      label: [titulo, if (eta != null) eta!].join('. '),
      // Verde escuro do tema: texto branco sobre #16A34A só dá contraste 3,3:1
      // (AA pede 4,5:1); sobre o verde escuro dá 8:1.
      child: Material(
        color: AppColors.primaryDark,
        child: SafeArea(
          top: false,
          bottom: margemInferior,
          child: InkWell(
            key: const Key('barra_pedido_ativo'),
            onTap: aoTocar,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.delivery_dining,
                        color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            titulo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (eta != null)
                            Text(
                              eta!,
                              key: const Key('barra_pedido_ativo_eta'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A barra à volta do Navigator inteiro (um só sítio para todos os ecrãs).
///
/// Ligar em `MaterialApp.builder` (lib/main.dart), à volta do `child`:
/// `BarraPedidoAtivoHost(child: child ?? const SizedBox.shrink())`.
///
/// Põe a barra por baixo do ecrã, com a margem de baixo do telemóvel, e tira
/// essa margem ao ecrã de cima para não ficar espaço a mais. Com o teclado
/// aberto a barra esconde-se.
class BarraPedidoAtivoHost extends StatefulWidget {
  const BarraPedidoAtivoHost({super.key, required this.child});

  final Widget child;

  @override
  State<BarraPedidoAtivoHost> createState() => _BarraPedidoAtivoHostState();
}

class _BarraPedidoAtivoHostState extends State<BarraPedidoAtivoHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => BarraPedidoAtivoEstado.hospedeiros.value++);
  }

  @override
  void dispose() {
    final n = BarraPedidoAtivoEstado.hospedeiros.value;
    // O dispose pode correr com a árvore a desmontar: adia-se para não mexer
    // num notifier a meio do frame.
    scheduleMicrotask(() => BarraPedidoAtivoEstado.hospedeiros.value =
        n > 0 ? n - 1 : 0);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tecladoAberto = MediaQuery.of(context).viewInsets.bottom > 0;
    // A ARVORE TEM A MESMA FORMA SEMPRE (Column > Expanded > MediaQuery > ecra):
    // mudar a forma desmontava o Navigator e perdia a pilha de ecras.
    return Column(
      children: [
        Expanded(
          child: ValueListenableBuilder<bool>(
            valueListenable: BarraPedidoAtivoEstado.visivel,
            builder: (context, visivel, child) => MediaQuery.removePadding(
              context: context,
              removeBottom: visivel && !tecladoAberto,
              child: child!,
            ),
            child: widget.child,
          ),
        ),
        BarraPedidoAtivo(margemInferior: true, escondida: tecladoAberto),
      ],
    );
  }
}

/// A barra dentro do separador do cliente (sem Navigator global): desenha-se só
/// quando NÃO há um [BarraPedidoAtivoHost] montado à volta da app.
class BarraPedidoAtivoNoSeparador extends StatelessWidget {
  const BarraPedidoAtivoNoSeparador({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: BarraPedidoAtivoEstado.hospedeiros,
      builder: (context, n, _) =>
          n > 0 ? const SizedBox.shrink() : const BarraPedidoAtivo(),
    );
  }
}
