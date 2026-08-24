import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/cart_item.dart';
import '../models/driver_model.dart';
import '../models/order_model.dart';
import '../models/order_service_type.dart';
import 'cart_store.dart';
import 'driver_store.dart';

/// Encomenda simulada da preview Festas — vive SÓ em memória no browser.
///
/// Nada aqui toca o servidor: sem Stripe, sem INSERT em `orders`, sem
/// dispatch, sem notificações. A guarda de `coming_soon` do servidor fica
/// intacta porque a preview nem sequer tenta criar pedido real.
///
/// O estafeta simulado é injectado no [DriverStore] real
/// (demoUpsertDriver) para o mapa do tracking mexer sozinho. A encomenda
/// NUNCA entra no OrderStore (zona protegida): o OrderTrackingScreen cai em
/// `widget.order` quando o id não está no store, por isso basta reconstruir
/// o modelo a cada transição e o wrapper repassá-lo.
class FestasDemoStore extends ChangeNotifier {
  static const String idEstafeta = 'demo-estafeta-festas';

  /// Coordenadas da loja (restaurants.lat/lng da Sabores do Brasil).
  static const LatLng _loja = LatLng(40.5364, -7.2683);

  /// Destino de reserva quando o cliente não definiu morada (centro da Guarda).
  static const LatLng _destinoReserva = LatLng(40.5432, -7.2606);

  DriverStore? _drivers;
  Timer? _timer;

  OrderModel? pedido;
  bool lojaAberta = true;
  bool recolha = false;
  DateTime? quando;

  // Argumentos base do pedido — o OrderModel tem campos finais, por isso cada
  // transição reconstrói o modelo com o MESMO id.
  String? _id;
  double _total = 0;
  double _subtotal = 0;
  double _deliveryFee = 0;
  double _serviceFee = 0;
  double _distanceKm = 0;
  List<CartItem> _itens = const [];
  String _vendor = 'Sabores do Brasil';
  PaymentMethod _metodo = PaymentMethod.cash;
  String? _nota;
  LatLng _destino = _destinoReserva;
  String _rua = '';
  String _cidade = 'Guarda';

  bool get temPedido => pedido != null;

  /// Cria a encomenda simulada a partir do carrinho real. Chamado pelo
  /// intercepto do ecrã de pagamento quando `kFestasPreview` está ligado.
  void criarPedido({
    required CartStore cart,
    required DriverStore drivers,
    required double total,
    required PaymentMethod metodo,
    String? nota,
  }) {
    _drivers = drivers;
    _timer?.cancel();

    recolha = cart.isTakeaway;
    quando = cart.festasQuando;
    _id = null; // novo id
    _total = total;
    _subtotal = cart.subtotal;
    final b = cart.pricingBreakdown;
    _deliveryFee = recolha ? 0 : b.deliveryFee;
    _serviceFee = b.serviceFee;
    _distanceKm = b.distanceKm;
    _itens = cart.items;
    _vendor = cart.vendorName ?? 'Sabores do Brasil';
    _metodo = metodo;
    _nota = nota;
    _destino = cart.deliveryLocation ?? _destinoReserva;
    _rua = cart.dropoffStreet;
    _cidade = cart.dropoffCity.isEmpty ? 'Guarda' : cart.dropoffCity;

    _emitir(OrderStatus.created);
  }

  /// A Keli aceitou — o pedido entra em preparação.
  /// Aceita a encomenda. [prontoEmMinutos] segue a mecânica real do
  /// parceiro (partner_takeaway_accept + PreparingCountdownBanner): quando
  /// existe, o cliente vê "Pronto em ~X min" enquanto prepara.
  void aceitar({int? prontoEmMinutos}) {
    _prontoEmMinutos = prontoEmMinutos;
    _prontoEmAte = prontoEmMinutos == null
        ? null
        : DateTime.now().add(Duration(minutes: prontoEmMinutos));
    _emitir(OrderStatus.preparing);
  }

  int? _prontoEmMinutos;
  DateTime? _prontoEmAte;

  /// A Keli recusou.
  void recusar() {
    _timer?.cancel();
    _emitir(OrderStatus.rejected);
  }

  /// A Keli carregou em "Encomenda pronta".
  /// Recolha: fica pronta para levantar. Entrega: chama o estafeta simulado.
  void marcarPronta() {
    if (recolha) {
      _emitir(OrderStatus.readyForPickup);
      return;
    }
    _emitir(OrderStatus.callingDriver);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 3), () {
      _poeEstafeta(_loja);
      _emitir(OrderStatus.driverAccepted, estafeta: idEstafeta);
      _timer = Timer(const Duration(seconds: 4), () {
        _emitir(OrderStatus.pickedUp, estafeta: idEstafeta);
        _timer = Timer(const Duration(seconds: 2), _arrancarViagem);
      });
    });
  }

  /// Abre/fecha a loja (só na demonstração; nada escreve na base).
  void alternarLoja(bool aberta) {
    lojaAberta = aberta;
    notifyListeners();
  }

  /// Limpa tudo (novo percurso).
  void limpar() {
    _timer?.cancel();
    pedido = null;
    quando = null;
    recolha = false;
    notifyListeners();
  }

  // ── interno ────────────────────────────────────────────────────────────────

  void _arrancarViagem() {
    _emitir(OrderStatus.onTheWay, estafeta: idEstafeta);
    const passos = 24;
    var passo = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 900), (t) {
      passo++;
      final f = passo / passos;
      _poeEstafeta(LatLng(
        _loja.latitude + (_destino.latitude - _loja.latitude) * f,
        _loja.longitude + (_destino.longitude - _loja.longitude) * f,
      ));
      if (passo >= passos) {
        t.cancel();
        // Sem estafeta no estado final: evita o ecrã de avaliação pós-entrega
        // (que escreveria na base — e nada nesta preview escreve).
        _emitir(OrderStatus.delivered);
      }
    });
  }

  void _poeEstafeta(LatLng onde) {
    _drivers?.demoUpsertDriver(DriverModel(
      id: idEstafeta,
      name: 'Estafeta Bora',
      location: onde,
      vehicleType: VehicleType.motorcycle,
      licensePlate: 'AA-00-BB',
      isOnline: true,
    ));
  }

  void _emitir(OrderStatus status, {String? estafeta}) {
    final novo = OrderModel(
      id: _id,
      total: _total,
      serviceType: recolha ? OrderServiceType.takeaway : OrderServiceType.restaurant,
      subtotal: _subtotal,
      deliveryFee: _deliveryFee,
      serviceFee: _serviceFee,
      distanceKm: _distanceKm,
      items: _itens,
      vendorName: _vendor,
      // Sem restaurantId: o pós-entrega não abre avaliação contra a loja real.
      isPartnerStore: true,
      orderType: recolha ? OrderType.takeaway : OrderType.partnerRestaurant,
      paymentMethod: _metodo,
      customerName: 'Cliente da demonstração',
      customerNotes: _nota,
      pickupLocation: _loja,
      pickupStreet: 'Sabores do Brasil · Guarda',
      destination: recolha ? null : _destino,
      dropoffStreet: _rua,
      dropoffCity: _cidade,
      status: status,
      assignedDriverId: estafeta,
      takeawayPickupCode: recolha ? 'FESTA' : null,
      takeawayPrepMinutes: _prontoEmMinutos,
      takeawayReadyAt: status == OrderStatus.preparing && _prontoEmAte != null
          ? _prontoEmAte
          : (recolha && status == OrderStatus.readyForPickup ? quando : null),
    );
    _id = novo.id;
    pedido = novo;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
