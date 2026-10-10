import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../models/order_model.dart';
import '../services/destino_pendente.dart';
import '../stores/order_store.dart';
import '../utils/contact_validators.dart';
import '../widgets/bora/bora.dart';
import 'complete_profile_screen.dart';
import 'client_reservations_screen.dart';
import 'client_home_screen.dart';
import 'deep_link_store_screen.dart';
import 'order_tracking_screen.dart';
import 'orders_screen.dart';
import 'profile_screen.dart';

/// Host dos 4 tabs do cliente: Início · Entrega · Reserva · Perfil.
///
/// Cada tab tem a sua própria `BoraAppBar` — este widget só gere o
/// `IndexedStack` e a `BoraBottomNavV2`. Eventos globais (e.g. pedido aceite
/// por estafeta → push tracking) são observados aqui porque sobrevivem às
/// trocas de tab.
class ClientMainScreen extends StatefulWidget {
  const ClientMainScreen({super.key});

  /// Separador pedido por um ecrã empilhado por cima da home (ex.: "Ver nas
  /// minhas reservas" no fim de uma marcação). Consome-se e volta a nulo.
  static final ValueNotifier<BoraNavTab?> separadorPedido =
      ValueNotifier<BoraNavTab?>(null);

  /// Fecha tudo o que está por cima da home e mostra o separador [tab].
  static void abrirSeparador(BuildContext context, BoraNavTab tab) {
    separadorPedido.value = tab;
    if (tab == BoraNavTab.reservation) ClientReservationsScreen.pedirRecarga();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  State<ClientMainScreen> createState() => _ClientMainScreenState();
}

class _ClientMainScreenState extends State<ClientMainScreen> {
  BoraNavTab _currentTab = BoraNavTab.home;

  void _aplicarSeparadorPedido() {
    final tab = ClientMainScreen.separadorPedido.value;
    if (tab == null) return;
    ClientMainScreen.separadorPedido.value = null;
    if (!mounted) return;
    setState(() => _currentTab = tab);
  }

  @override
  void dispose() {
    ClientMainScreen.separadorPedido.removeListener(_aplicarSeparadorPedido);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Pedido feito antes de este ecrã existir: aplica-se já, sem setState.
    final pedido = ClientMainScreen.separadorPedido.value;
    if (pedido != null) {
      _currentTab = pedido;
      ClientMainScreen.separadorPedido.value = null;
    }
    ClientMainScreen.separadorPedido.addListener(_aplicarSeparadorPedido);
    // Quem chegou de fora a uma ficha (site, QR, WhatsApp) e teve de se
    // registar para marcar: o registo termina com popUntil(isFirst), portanto
    // a ficha desapareceu da pilha. Volta-se a ela aqui, mal a home aparece —
    // senão a pessoa acabava na home genérica, que é o beco que se quer evitar.
    WidgetsBinding.instance.addPostFrameCallback((_) => _abrirDestinoPendente());
    // Contacto em falta: pede-se UMA vez por arranque, e com saída ("Agora
    // não"). O bloqueio a sério é no checkout — ver garantirContactoDoCliente.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _pedirContactoUmaVez());
  }

  /// Só pergunta uma vez por arranque da app: um aviso que reaparece a cada
  /// separador deixa de ser aviso e passa a ser praga.
  static bool _contactoJaPerguntadoNesteArranque = false;

  Future<void> _pedirContactoUmaVez() async {
    if (_contactoJaPerguntadoNesteArranque || !mounted) return;
    final client = context.read<AuthStore>().currentClient;
    if (client == null) return;
    if (contactoDoClienteCompleto(
        nome: client.name, telemovel: client.phone)) {
      return;
    }
    _contactoJaPerguntadoNesteArranque = true;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => const CompleteProfileScreen(),
      ),
    );
  }

  Future<void> _abrirDestinoPendente() async {
    final destino = await DestinoPendente.consumir();
    if (destino == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            DeepLinkStoreScreen(tipo: destino.tipo, id: destino.id),
      ),
    );
  }

  /// Orders we have already pushed a tracking screen for.
  /// Prevents re-navigation on every rebuild after the user presses back.
  final Set<String> _navigatedOrderIds = {};


  OrderModel? _findActiveOrder(List<OrderModel> orders) {
    for (final o in orders) {
      // BUG 6 — incluir cancelled na exclusão (cliente não deve abrir
      // detail de pedido cancelado automaticamente).
      if (o.status.index >= OrderStatus.driverAccepted.index &&
          o.status != OrderStatus.delivered &&
          o.status != OrderStatus.rejected &&
          o.status != OrderStatus.cancelled) {
        return o;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrderStore>().orders;
    final activeOrder = _findActiveOrder(orders);
    if (activeOrder != null && !_navigatedOrderIds.contains(activeOrder.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_navigatedOrderIds.contains(activeOrder.id)) return;
        _navigatedOrderIds.add(activeOrder.id);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OrderTrackingScreen(order: activeOrder),
          ),
        );
      });
    }

    return Scaffold(
      body: IndexedStack(index: _currentTab.index, children: [
        const ClientHomeScreen(),
        const OrdersScreen(),
        // Recarrega de cada vez que a pessoa abre o separador.
        ClientReservationsScreen(
            ativo: _currentTab == BoraNavTab.reservation),
        const ProfileScreen(),
      ]),
      bottomNavigationBar: BoraBottomNavV2(
        current: _currentTab,
        onTabChanged: (tab) => setState(() => _currentTab = tab),
      ),
    );
  }
}
