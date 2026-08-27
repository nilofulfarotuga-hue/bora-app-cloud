import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cart_item.dart';
import '../models/order_model.dart';
import '../config/business_rules.dart' show BRTokens;
import '../services/maps_service.dart';
import '../services/pricing_service.dart';
import '../services/small_order_fee.dart';
import 'order_store.dart';

class CartStore extends ChangeNotifier {
  static const _kPrefsKey = 'bora_cart_v1';

  final List<CartItem> _items = [];

  OrderServiceType _serviceType = OrderServiceType.restaurant;
  bool _isPartnerStore = true;
  String? _vendorName;

  /// A loja da sessão actual está em "Em breve" (`coming_soon = true`).
  ///
  /// Desde 2026-08-05 o cliente pode percorrer TUDO — abrir a loja, escolher
  /// produtos e opções, encher o carrinho e seguir para o checkout. A travagem
  /// acontece só no ecrã de pagamento (ver `vendorBlocksAddToCart`).
  /// Defesa em profundidade: o servidor rejeita na mesma com
  /// `STORE_COMING_SOON` e o trigger `trg_payment_draft_coming_soon` garante
  /// que ninguém é cobrado.
  bool _vendorComingSoon = false;

  /// Texto do banner "Em breve" da loja da sessão (já com fallback aplicado
  /// pelo chamador — ver `RestaurantModel.comingSoonLabel`).
  String _vendorComingSoonText = 'Em breve';

  /// Loja da sessão pertence à categoria Festas (2026-08-25). Liga o passo do
  /// calendário no checkout (quando o carrinho tem item de encomenda) e a
  /// isenção do saco (regra do Danilo: festas não cobra saco).
  bool _vendorIsFestas = false;

  /// Id da loja da sessao actual. So serve para ir buscar o override da
  /// TAXA DE PEDIDO PEQUENO (uma loja pode ter minimo/taxa proprios).
  String? _vendorRestaurantId;

  /// Loja da sessao fora de horario. A verdade vem de `is_partner_open` no
  /// servidor (que ja conhece feriados e override do admin); aqui e so o
  /// espelho para o cliente, gravado quando a loja e aberta.
  bool _vendorFechada = false;
  String _vendorAvisoFechada = '';

  /// Data/hora escolhida para a encomenda de festa (mínimo: dia seguinte).
  /// NULL = pedido imediato ("Na hora"). Enviada ao servidor no checkout.
  DateTime? _festasQuando;
  String? _pickupStreet;
  String? _pickupCity;
  String? _pickupPostalCode;
  String _dropoffStreet = "";
  String _dropoffCity = "";
  String _dropoffPostalCode = "";
  double _distanceKm = PricingService.defaultDistanceKm;
  LatLng? _pickupLocation;
  LatLng? _deliveryLocation;
  bool _apartmentDelivery = false;
  bool _requiresCar = false;

  /// Wallet (saldo livre Bora) cents the user toggled to apply at checkout.
  /// Transient — never persisted. Cleared after [finishOrder] succeeds. Read by
  /// PaymentMethodScreen so Stripe is pre-auth at remaining (= total - wallet),
  /// and by [finishOrder] so OrderStore.createOrder triggers wallet_debit_for_order.
  int _walletAppliedCents = 0;
  int get walletAppliedCents => _walletAppliedCents;
  void setWalletApplied(int cents) {
    final clamped = cents < 0 ? 0 : cents;
    if (clamped == _walletAppliedCents) return;
    _walletAppliedCents = clamped;
    notifyListeners();
  }

  CartStore() {
    _loadCart();
  }

  // ── Persistence ──────────────────────────────────────────────────────────

  Future<void> _saveCart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode({
        'items': _items.map((i) => i.toJson()).toList(),
        'serviceType': _serviceType.name,
        'isPartnerStore': _isPartnerStore,
        'vendorName': _vendorName,
        'vendorComingSoon': _vendorComingSoon,
        'vendorComingSoonText': _vendorComingSoonText,
        'vendorIsFestas': _vendorIsFestas,
        'festasQuando': _festasQuando?.toIso8601String(),
        'pickupStreet': _pickupStreet,
        'pickupCity': _pickupCity,
        'pickupPostalCode': _pickupPostalCode,
        'dropoffStreet': _dropoffStreet,
        'dropoffCity': _dropoffCity,
        'dropoffPostalCode': _dropoffPostalCode,
        'pickupLat': _pickupLocation?.latitude,
        'pickupLng': _pickupLocation?.longitude,
        'deliveryLat': _deliveryLocation?.latitude,
        'deliveryLng': _deliveryLocation?.longitude,
        'distanceKm': _distanceKm,
        'apartmentDelivery': _apartmentDelivery,
      });
      await prefs.setString(_kPrefsKey, data);
    } catch (e) {
      debugPrint('CartStore._saveCart error: $e');
    }
  }

  Future<void> _loadCart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPrefsKey);
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final itemsJson = map['items'] as List<dynamic>? ?? [];
      _items.clear();
      for (final j in itemsJson) {
        _items.add(CartItem.fromJson(j as Map<String, dynamic>));
      }
      _serviceType = OrderServiceType.values.firstWhere(
        (e) => e.name == map['serviceType'],
        orElse: () => OrderServiceType.restaurant,
      );
      _isPartnerStore = map['isPartnerStore'] as bool? ?? true;
      _vendorName = map['vendorName'] as String?;
      _vendorComingSoon = map['vendorComingSoon'] as bool? ?? false;
      _vendorComingSoonText =
          map['vendorComingSoonText'] as String? ?? 'Em breve';
      _vendorIsFestas = map['vendorIsFestas'] as bool? ?? false;
      _festasQuando = map['festasQuando'] != null
          ? DateTime.tryParse(map['festasQuando'] as String)
          : null;
      _pickupStreet = map['pickupStreet'] as String?;
      _pickupCity = map['pickupCity'] as String?;
      _pickupPostalCode = map['pickupPostalCode'] as String?;
      _dropoffStreet = map['dropoffStreet'] as String? ?? '';
      _dropoffCity = map['dropoffCity'] as String? ?? '';
      _dropoffPostalCode = map['dropoffPostalCode'] as String? ?? '';
      final pickupLat = map['pickupLat'] as double?;
      final pickupLng = map['pickupLng'] as double?;
      if (pickupLat != null && pickupLng != null) {
        _pickupLocation = LatLng(pickupLat, pickupLng);
      }
      final deliveryLat = map['deliveryLat'] as double?;
      final deliveryLng = map['deliveryLng'] as double?;
      if (deliveryLat != null && deliveryLng != null) {
        _deliveryLocation = LatLng(deliveryLat, deliveryLng);
      }
      _distanceKm = (map['distanceKm'] as num?)?.toDouble() ??
          PricingService.defaultDistanceKm;
      _apartmentDelivery = map['apartmentDelivery'] as bool? ?? false;
      notifyListeners();
    } catch (e) {
      debugPrint('CartStore._loadCart error: $e');
    }
  }

  // ── Getters ───────────────────────────────────────────────────────────────

  List<CartItem> get items => List.unmodifiable(_items);

  int get totalItems => _items.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal =>
      _items.fold(0, (sum, item) => sum + item.price * item.quantity);

  double get total => subtotal;

  OrderServiceType get serviceType => _serviceType;

  bool get isPartnerStore => _isPartnerStore;

  bool get apartmentDelivery => _apartmentDelivery;

  double get distanceKm => _distanceKm;

  LatLng? get pickupLocation => _pickupLocation;

  LatLng? get deliveryLocation => _deliveryLocation;

  String? get vendorName => _vendorName;

  /// True quando a loja da sessão actual está em "Em breve" — a UI mostra o
  /// botão de adicionar/finalizar desactivado e [addItem] é ignorado.
  bool get vendorComingSoon => _vendorComingSoon;

  /// Loja da sessão é da categoria Festas (encomendas com aviso prévio).
  bool get vendorIsFestas => _vendorIsFestas;

  /// Data/hora da encomenda de festa (NULL = imediato).
  DateTime? get festasQuando => _festasQuando;

  void definirFestasQuando(DateTime? quando) {
    _festasQuando = quando;
    _saveCart();
    notifyListeners();
  }

  /// Se o estado "Em breve" deve travar o cliente ANTES do pagamento.
  ///
  /// Passou a `false` em 2026-08-05: a loja em "Em breve" deixa o cliente
  /// escolher produtos, opções e chegar ao checkout. O único sítio onde ele é
  /// travado é o ecrã de pagamento — ver `payment_method_screen.dart`.
  /// Os selos e o banner "Em breve" continuam a usar `vendorComingSoon`.
  bool get vendorBlocksAddToCart => false;

  /// Texto do banner "Em breve" da loja da sessão actual.
  String get vendorComingSoonText => _vendorComingSoonText;

  String? get pickupStreet => _pickupStreet;
  String? get pickupCity => _pickupCity;
  String? get pickupPostalCode => _pickupPostalCode;
  String get dropoffStreet => _dropoffStreet;
  String get dropoffCity => _dropoffCity;
  String get dropoffPostalCode => _dropoffPostalCode;

  // ── FIX: Expose whether the cart has a valid pickup location so that
  // UI screens can disable checkout when coordinates are missing.
  bool get hasValidPickupLocation => _pickupLocation != null;

  // ── TAXA DE PEDIDO PEQUENO (2026-08-27) ──────────────────────────────────
  // Fica FORA do OrderPricingBreakdown de proposito: `pricing_service.dart` e
  // zona protegida e nenhuma formula dele foi tocada. Os ecras somam esta
  // parcela ao total, e o servidor cobra-a pela sua propria conta (funcao
  // `small_order_fee_calc`, a mesma regra) — nao vai no payload do pedido.

  /// Definicoes em vigor para a loja desta sessao (override dela ou o global).
  /// A loja desta sessao esta fora de horario?
  ///
  /// Ao contrario do "Em breve", isto BLOQUEIA mesmo o adicionar ao carrinho:
  /// a loja ja trabalha connosco, so nao esta a servir agora. Navegar,
  /// espreitar o menu e ver precos continua tudo livre.
  bool get lojaFechada => _vendorFechada;

  /// Mensagem unica do bloqueio (PT-PT), com a hora a que abre.
  String get avisoLojaFechada => _vendorAvisoFechada;

  SmallOrderFeeConfig get smallOrderFeeConfig =>
      SmallOrderFeeService.para(_vendorRestaurantId);

  /// Taxa a cobrar por este carrinho, em euros. 0 quando nao se aplica.
  ///
  /// **O SERVIDOR MANDA.** Quando ha um quote fresco (`quote_order_pricing`,
  /// cache de 30 s), devolve-se o `small_order_fee` que ele calculou — e o
  /// mesmo numero que entra no `customer_total`, no `charge_total` e no
  /// `payment_buffer_total`, ou seja, e exactamente o que vai ser cobrado.
  ///
  /// O calculo local so entra quando ainda NAO ha quote: no carrinho, antes
  /// de haver morada de recolha e de entrega, a RPC nem pode ser chamada.
  /// Nesse caso e um espelho da mesma regra (`small_order_fee_calc`), com os
  /// valores lidos de `platform_settings` — nunca do codigo.
  double get smallOrderFee {
    final doServidor = (_quoteCache?['small_order_fee'] as num?)?.toDouble();
    if (doServidor != null) return doServidor;
    return smallOrderFeeConfig.taxaPara(_serviceType, subtotal);
  }

  /// `true` quando o valor acima veio do servidor, `false` quando e a
  /// estimativa local. So serve para diagnostico/testes.
  bool get smallOrderFeeVeioDoServidor =>
      _quoteCache?['small_order_fee'] != null;

  /// Quanto falta gastar para deixar de pagar a taxa. 0 quando ja nao paga.
  double get faltaParaMinimo =>
      smallOrderFeeConfig.faltaPara(_serviceType, subtotal);

  OrderPricingBreakdown get pricingBreakdown {
    final base = PricingService.calculateBreakdown(
      serviceType: _serviceType,
      subtotal: subtotal,
      distanceKm: _distanceKm,
      isPartnerStore: _isPartnerStore,
      apartmentDelivery: _apartmentDelivery,
    );
    // Festas (2026-08-25, regra do Danilo): a loja de festas não cobra saco.
    // Ajuste aqui, fora do PricingService (ficheiro protegido); o servidor
    // aplica a mesma isenção (migration festas_money_patch). customerTotal é
    // derivado do bagFee, por isso a cópia corrige o total sozinha.
    if (!_vendorIsFestas || base.bagFee <= 0) return base;
    return OrderPricingBreakdown(
      distanceKm: base.distanceKm,
      subtotal: base.subtotal,
      deliveryFee: base.deliveryFee,
      serviceFee: base.serviceFee,
      platformCommission: base.platformCommission,
      driverEarnings: base.driverEarnings,
      apartmentSurcharge: base.apartmentSurcharge,
      apartmentDelivery: base.apartmentDelivery,
      bagFee: 0,
      partnerMarkupHidden: base.partnerMarkupHidden,
      isPartnerSelfDispatch: base.isPartnerSelfDispatch,
    );
  }

  // BUG F (sessão exec 2026-05-12) — server-authoritative pricing quote.
  // Flutter pricingBreakdown usa distância local que pode diferir do server
  // (server recalcula com rota real). Esta função chama RPC quote_order_pricing
  // server-side para obter total authoritative ANTES do checkout final.
  //
  // Cache 30s para evitar quota spam. Returns null em erro (fallback caller
  // usa pricingBreakdown local + disclaimer "Total estimado").
  Map<String, dynamic>? _quoteCache;
  DateTime? _quoteCacheTime;

  Future<Map<String, dynamic>?> quoteOrderPricing({
    int walletAppliedCents = 0,
  }) async {
    // Cache hit (30s freshness)
    final now = DateTime.now();
    if (_quoteCache != null &&
        _quoteCacheTime != null &&
        now.difference(_quoteCacheTime!).inSeconds < 30) {
      return _quoteCache;
    }

    if (_pickupLocation == null || _deliveryLocation == null) return null;

    final cartInput = <String, dynamic>{
      'service_type': _serviceType.name,
      'is_partner_store': _isPartnerStore,
      'items': _items.map((i) => i.toJson()).toList(),
      'distance_km': _distanceKm,
      'apartment_delivery': _apartmentDelivery,
      'pickup_lat': _pickupLocation!.latitude,
      'pickup_lng': _pickupLocation!.longitude,
      'destination_lat': _deliveryLocation!.latitude,
      'destination_lng': _deliveryLocation!.longitude,
      'wallet_applied_cents': walletAppliedCents,
      'include_debt': true, // BUG #1 frontend (2026-05-12): server inclui dívida wallet em charge_total + retorna debt_settle_cents
      'payment_method': 'card', // any non-cash, RPC ignora para quote
    };

    try {
      final result = await Supabase.instance.client
          .rpc('quote_order_pricing', params: {'p_input': cartInput});
      if (result is Map) {
        _quoteCache = Map<String, dynamic>.from(result);
        _quoteCacheTime = now;
        return _quoteCache;
      }
    } catch (e) {
      debugPrint('[CartStore] quote_order_pricing failed: $e');
    }
    return null;
  }

  // Cache invalidation hook — chamar a partir de setters quando cart muda.
  // Não exposto agora (30s freshness é aceitável para o use case checkout).
  // Quando necessário invalidar manualmente: _quoteCache=null; _quoteCacheTime=null;

  // BR §14.9 — Takeaway agora é derivado de _serviceType (single source of
  // truth). Coluna `is_takeaway` foi APAGADA no servidor. O getter público
  // mantém compatibilidade com call sites existentes que verificam
  // cartStore.isTakeaway (cart_screen.dart, order_store.dart).
  bool get isTakeaway => _serviceType == OrderServiceType.takeaway;

  /// R5 — true quando o cliente escolheu modalidade via RestaurantOptionsScreen.
  /// O switch "Entrega ⇄ Ir buscar" em cart_screen.dart fica escondido para
  /// evitar UX ambíguo. Cliente que quer trocar volta atrás ao ecrã de opções.
  /// Reset em clearCart().
  bool _serviceTypeLockedByOptions = false;
  bool get serviceTypeLockedByOptions => _serviceTypeLockedByOptions;

  /// Setter usado por RestaurantOptionsScreen ("Entrega" vs "Ir buscar").
  /// Alterna entre restaurant e takeaway sem mexer nos restantes campos do
  /// contexto. Caller deve garantir que o cart está vazio se a troca muda
  /// vendor/loja — isto apenas troca a modalidade. Activa o lock R5.
  void setServiceTypeFromOption(OrderServiceType type) {
    _serviceTypeLockedByOptions = true;
    if (_serviceType == type) {
      notifyListeners();
      return;
    }
    _serviceType = type;
    // Curbside só faz sentido em takeaway — limpar ao sair.
    if (type != OrderServiceType.takeaway) {
      _isCurbside = false;
      _curbsideInfo = null;
    }
    notifyListeners();
  }

  // BR §14.9b/D6 — Curbside (cliente espera no carro). Imutável pós-paid
  // (UI-only guard em cart_screen e order_tracking_screen). Não usar para
  // takeaway-disabled restaurants.
  bool _isCurbside = false;
  bool get isCurbside => _isCurbside;
  void setCurbside(bool v) {
    _isCurbside = v;
    notifyListeners();
  }

  String? _curbsideInfo;
  String? get curbsideInfo => _curbsideInfo;
  void setCurbsideInfo(String? v) {
    final trimmed = v?.trim();
    _curbsideInfo = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    notifyListeners();
  }

  // Client gratuity at checkout (BR §4.5). Split 80/20 handled post-delivery.
  int _tipCents = 0;
  int get tipCents => _tipCents;
  double get tipEur => _tipCents / 100.0;
  void setTipCents(int v) {
    _tipCents = v < 0 ? 0 : v;
    notifyListeners();
  }

  // Optional photos for sendPackage / carryGroceries (BR §7.5/7.6).
  String? _packagePhotoUrl;
  String? _groceriesPhotoUrl;
  String? get packagePhotoUrl => _packagePhotoUrl;
  String? get groceriesPhotoUrl => _groceriesPhotoUrl;
  void setPackagePhotoUrl(String? url) {
    _packagePhotoUrl = url;
    notifyListeners();
  }

  void setGroceriesPhotoUrl(String? url) {
    _groceriesPhotoUrl = url;
    notifyListeners();
  }

  // FAVORES (errand) — foto opcional "do que comprar" (8.1). Reutiliza o bucket
  // privado de fotos de pedido. Limpa em finishOrder/clearCart.
  String? _errandRequestPhotoUrl;
  String? get errandRequestPhotoUrl => _errandRequestPhotoUrl;
  void setErrandRequestPhotoUrl(String? url) {
    _errandRequestPhotoUrl = url;
    notifyListeners();
  }

  /// FAVORES (errand) — configura a sessão do carrinho para um favor.
  /// Limpa items (favores não têm produtos, só descrição) e guarda os dados
  /// do wizard. O quote vem de quote_order_pricing — não recalcula aqui.
  void configureErrandSession({
    required String description,
    required String location,
    required LatLng locationCoords,
    required LatLng dropoff,
    LatLng? home,
    String? homeStopAddress,
    String? homeStopReason,
    int? homeStopCashCents,
    bool returnLeg = false,
    required String speed, // 'normal' | 'express'
    required bool hasPurchase,
    required int estimatedCents,
    required Map<String, dynamic> quote,
    required double distanceKm,
    String? dropoffStreet,
    String? dropoffCity,
    String? requestPhotoUrl,
  }) {
    if (_items.isNotEmpty) {
      _items.clear();
      _saveCart();
    }
    _serviceType = OrderServiceType.errand;
    _isPartnerStore = false;
    _requiresCar = false;
    _vendorName = null;
    _pickupLocation = home; // null se não houver paragem-casa
    _deliveryLocation = dropoff;
    // O servidor (e o finishOrder) exigem uma morada de entrega — o wizard
    // captura-a via autocomplete de rua.
    if (dropoffStreet != null && dropoffStreet.trim().isNotEmpty) {
      _dropoffStreet = dropoffStreet.trim();
    }
    if (dropoffCity != null && dropoffCity.trim().isNotEmpty) {
      _dropoffCity = dropoffCity.trim();
    }
    _apartmentDelivery = false;
    _errandRequestPhotoUrl = requestPhotoUrl;
    _errandSession = ErrandSession(
      description: description,
      location: location,
      locationCoords: locationCoords,
      home: home,
      homeStopAddress: homeStopAddress,
      homeStopReason: homeStopReason,
      homeStopCashCents: homeStopCashCents,
      returnLeg: returnLeg,
      speed: speed,
      hasPurchase: hasPurchase,
      estimatedCents: estimatedCents,
      quote: quote,
    );
    // Distância real (multi-segmento casa→favor→entrega) calculada no wizard
    // — é a mesma que o servidor cobra; evita ERRAND_DISTANCE_TOO_LOW.
    _distanceKm =
        distanceKm > 0 ? distanceKm : PricingService.defaultDistanceKm;
    notifyListeners();
  }

  ErrandSession? _errandSession;
  ErrandSession? get errandSession => _errandSession;

  void configureSession({
    required OrderServiceType serviceType,
    bool isPartnerStore = true,
    bool requiresCar = false,
    bool vendorComingSoon = false,
    bool vendorIsFestas = false,
    String vendorComingSoonText = 'Em breve',
    String? vendorName,
    String? vendorRestaurantId,
    bool vendorFechada = false,
    String vendorAvisoFechada = '',
    String? pickupStreet,
    String? pickupCity,
    String? pickupPostalCode,
    double? distanceKm,
    LatLng? pickupLocation,
    LatLng? deliveryLocation,
    String? dropoffStreet,
    String? dropoffCity,
    String? dropoffPostalCode,
  }) {
    final isSameContext = _serviceType == serviceType &&
        _vendorName == vendorName &&
        _isPartnerStore == isPartnerStore;

    if (_items.isNotEmpty && !isSameContext) {
      _items.clear();
      _saveCart();
    }

    _serviceType = serviceType;
    _isPartnerStore = isPartnerStore;
    _requiresCar = requiresCar;
    _vendorComingSoon = vendorComingSoon;
    _vendorComingSoonText = vendorComingSoonText;
    _vendorIsFestas = vendorIsFestas;
    _vendorRestaurantId = vendorRestaurantId;
    _vendorFechada = vendorFechada;
    _vendorAvisoFechada = vendorAvisoFechada;
    // Minimo/taxa proprios desta loja, se os tiver. Falhar aqui nunca trava o
    // carrinho: sem leitura, fica o valor global (ou taxa nenhuma).
    if (vendorRestaurantId != null) {
      SmallOrderFeeService.carregarLoja(vendorRestaurantId)
          .then((_) => notifyListeners());
    }
    if (!isSameContext) _festasQuando = null;
    _vendorName = vendorName;
    _pickupStreet = pickupStreet;
    _pickupCity = pickupCity;
    _pickupPostalCode = pickupPostalCode;
    if (dropoffStreet != null) _dropoffStreet = dropoffStreet;
    if (dropoffCity != null) _dropoffCity = dropoffCity;
    if (dropoffPostalCode != null) _dropoffPostalCode = dropoffPostalCode;
    _pickupLocation = pickupLocation;
    if (deliveryLocation != null) {
      _deliveryLocation = deliveryLocation;
    }

    _apartmentDelivery = false;

    // ── FIX: Log when pickup is null so developers can trace the issue
    // immediately in the console instead of discovering it at order time.
    if (_pickupLocation == null) {
      debugPrint(
        'CartStore.configureSession: WARNING — pickupLocation is null '
        'for vendor "$vendorName". Distance will use default fallback.',
      );
    }

    if (distanceKm != null) {
      _distanceKm = distanceKm;
    } else {
      _recalculateDistance();
    }

    notifyListeners();
  }

  void updateDeliveryAddress({
    required String street,
    required String city,
    required String postalCode,
    LatLng? location,
  }) {
    _dropoffStreet = street;
    _dropoffCity = city;
    _dropoffPostalCode = postalCode;
    if (location != null) {
      _deliveryLocation = location;
    }
    _recalculateDistance();
    notifyListeners();
  }

  void setApartmentDelivery(bool value) {
    if (_apartmentDelivery == value) return;
    _apartmentDelivery = value;
    notifyListeners();
  }

  void _recalculateDistance() {
    if (_pickupLocation != null && _deliveryLocation != null) {
      final distance = const Distance().as(
        LengthUnit.Kilometer,
        _pickupLocation!,
        _deliveryLocation!,
      );
      if (distance.isFinite && distance > 0) {
        _distanceKm = distance;
      } else {
        _distanceKm = PricingService.defaultDistanceKm;
      }
      return;
    }
    _distanceKm = PricingService.defaultDistanceKm;
  }

  /// M-E (2026-06-10) — o resumo TEM de mostrar a MESMA distância que o
  /// servidor cobra. createOrder/startCardPaymentDraft resolvem a distância
  /// com a rota Google (MapsService.getDistanceKm) antes do create_order;
  /// o fallback haversine de _recalculateDistance é linha reta e subestima
  /// sempre → "Total €6.00 no resumo, €6.79 no Stripe" (carry/send).
  /// Chamar ao entrar em qualquer ecrã de resumo (PaymentMethodScreen,
  /// painel do CartScreen). Sem rota (offline/erro) mantém o haversine.
  Future<void> refreshRouteDistance() async {
    final pickup = _pickupLocation;
    final destination = _deliveryLocation;
    if (pickup == null || destination == null) return;
    try {
      final routeKm = await MapsService.getDistanceKm(pickup, destination);
      if (routeKm != null &&
          routeKm.isFinite &&
          routeKm > 0 &&
          (routeKm - _distanceKm).abs() > 0.01) {
        _distanceKm = routeKm;
        _quoteCache = null; // total mudou — quote server cacheado ficou stale
        _quoteCacheTime = null;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[CartStore] refreshRouteDistance error: $e');
    }
  }

  void addItem(CartItem item) {
    // B1 (2026-06-11): a conclusão de 2026-05-21 ("preços na DB já incluem o
    // markup") estava ERRADA — provado pelo pedido real 80ba3a2e (Continente
    // cnt-4603911: DB €1,55 = preço BASE do site; backend cobrou 1,55×1,15).
    // O markup de exibição não-parceiro é aplicado nos CALL SITES que criam o
    // CartItem via PricingService.applyMarkup (price = exibido/cobrado;
    // basePrice = puro de catálogo). addItem usa o preço tal como vem — itens
    // de reorder/persistência já vêm finais e não podem ser re-marcados.
    // "EM BREVE" NAO TRAVA AQUI (corrigido 2026-08-27).
    //
    // Estava a devolver sem adicionar, o que contradizia o
    // `vendorBlocksAddToCart` (false = a UI deixa passar) e o comportamento
    // que se queria desde 2026-08-05: na loja em "Em breve" o cliente percorre
    // tudo — produtos, opcoes, carrinho — e so e travado no ecra de pagamento.
    // Com o travao aqui, o botao de adicionar nao fazia NADA e nao dizia
    // porque. O servidor continua a recusar (STORE_COMING_SOON), que e onde a
    // trava tem de estar.

    // LOJA FECHADA (2026-08-27): esta SIM trava o carrinho. A diferenca e que
    // a loja ja trabalha connosco, so nao esta a servir a esta hora — deixar
    // encher o carrinho para depois recusar seria pior. Navegar e ver precos
    // continua livre; e so o adicionar que para. Quem chama mostra
    // `avisoLojaFechada` (a UI usa showLojaFechadaSnackBar).
    if (_vendorFechada) {
      debugPrint(
        'CartStore.addItem: BLOQUEADO — "$_vendorName" está fechada.',
      );
      return;
    }

    final cartItem = item;

    final index = _items.indexWhere((i) => i.lineKey == cartItem.lineKey);

    if (index >= 0) {
      _items[index].quantity++;
    } else {
      _items.add(cartItem);
    }

    notifyListeners();
    _saveCart();
  }

  void removeItem(CartItem item) {
    _items.removeWhere((i) => i.lineKey == item.lineKey);
    notifyListeners();
    _saveCart();
  }

  void increaseQuantity(CartItem item) {
    final index = _items.indexWhere((i) => i.lineKey == item.lineKey);
    if (index >= 0) {
      _items[index].quantity++;
      notifyListeners();
      _saveCart();
    }
  }

  void decreaseQuantity(CartItem item) {
    final index = _items.indexWhere((i) => i.lineKey == item.lineKey);
    if (index >= 0) {
      if (_items[index].quantity <= 1) {
        _items.removeAt(index);
      } else {
        _items[index].quantity--;
      }
      notifyListeners();
      _saveCart();
    }
  }

  void clearCart() {
    // BUG #6 (2026-05-13) — reset completo. Antes só limpava _items e
    // _apartmentDelivery; tip/wallet/takeaway/photoUrls ficavam stale ao
    // trocar de loja e davam erro "não foi possível finalizar".
    _items.clear();
    _apartmentDelivery = false;
    _tipCents = 0;
    _walletAppliedCents = 0;
    // D4 — takeaway agora é derivado de _serviceType. Reset = default restaurant.
    _serviceType = OrderServiceType.restaurant;
    _isCurbside = false;
    _curbsideInfo = null;
    _serviceTypeLockedByOptions = false;
    _packagePhotoUrl = null;
    _groceriesPhotoUrl = null;
    _errandSession = null;
    _errandRequestPhotoUrl = null;
    // Festas — a data agendada morre com o carrinho (nunca vaza para a
    // compra seguinte).
    _festasQuando = null;
    notifyListeners();
    _saveCart();
  }

  /// BUG 1 / Fase 2 (2026-04-30) — Card payment-first flow.
  ///
  /// Builds the cart payload from this store's current state and invokes
  /// the new `create-payment-intent` Edge Fn (mode B). Returns
  /// `{clientSecret, paymentIntentId, draftId, amountCents}` on success
  /// or `null` on validation/RPC error.
  ///
  /// **Does NOT clear the cart.** Caller must call [clearCart] only after
  /// the Stripe charge is confirmed AND the order appears via realtime
  /// (use [OrderStore.waitForOrderFromDraft]).
  Future<Map<String, dynamic>?> startCardPaymentDraft(
    OrderStore orderStore, {
    String? clientPhone,
    String? customerName,
    String? savedPmId,
  }) async {
    final isShoppingOrder = _serviceType == OrderServiceType.restaurant ||
        _serviceType == OrderServiceType.storeShopping;
    if (isShoppingOrder && _items.isEmpty) return null;
    final isErrand = _serviceType == OrderServiceType.errand;
    // FAVORES — paragem em casa é opcional → pickup pode ser null; a morada de
    // entrega é capturada via autocomplete (coords obrigatórias, street opcional).
    if (!isErrand && _pickupLocation == null) {
      debugPrint('CartStore.startCardPaymentDraft: BLOCKED — pickupLocation null');
      return null;
    }
    // Recolha (takeaway): o cliente vai buscar à loja — nunca se lhe exige
    // morada. O destino do pedido passa a ser a própria loja (pickup).
    if (!isTakeaway &&
        (_deliveryLocation == null || (!isErrand && _dropoffStreet.isEmpty))) {
      debugPrint('CartStore.startCardPaymentDraft: BLOCKED — delivery missing');
      return null;
    }

    final breakdown = pricingBreakdown;

    return orderStore.startCardPaymentDraft(
      serviceType: _serviceType,
      itemsSubtotal: breakdown.subtotal,
      // Em recolha o destino é a própria loja (pickup validado acima).
      destination: isTakeaway ? _pickupLocation! : _deliveryLocation!,
      items: _items
          .map(
            (item) => CartItem(
              productId: item.productId,
              name: item.name,
              price: item.price,
              quantity: item.quantity,
              basePrice: item.basePrice,
              selectedOptions: item.selectedOptions,
            ),
          )
          .toList(),
      pickupLocation: _pickupLocation,
      distanceKm: breakdown.distanceKm,
      isPartnerStore: _isPartnerStore,
      requiresCar: _requiresCar,
      vendorName: _vendorName,
      pickupAddress: _pickupStreet ?? _vendorName,
      pickupStreet: _pickupStreet,
      pickupCity: _pickupCity,
      pickupPostalCode: _pickupPostalCode,
      dropoffAddress:
          [_dropoffStreet, _dropoffCity].where((s) => s.isNotEmpty).join(', '),
      dropoffStreet: _dropoffStreet,
      dropoffCity: _dropoffCity,
      dropoffPostalCode: _dropoffPostalCode,
      clientPhone: clientPhone,
      customerName: customerName,
      apartmentDelivery: _apartmentDelivery,
      walletAppliedCents: _walletAppliedCents,
      // FAVORES (errand)
      errandDescription: _errandSession?.description,
      errandLocation: _errandSession?.location,
      errandLocationLat: _errandSession?.locationCoords.latitude,
      errandLocationLng: _errandSession?.locationCoords.longitude,
      errandHomeStop: _errandSession?.hasHomeStop ?? false,
      errandHomeStopReason: _errandSession?.homeStopReason,
      errandSpeed: _errandSession?.speed,
      errandHasPurchase: _errandSession?.hasPurchase ?? false,
      errandEstimatedPurchaseCents: _errandSession?.estimatedCents ?? 0,
      errandRequestPhotoUrl: _errandRequestPhotoUrl,
      savedPmId: savedPmId,
    );
  }

  Future<bool> finishOrder(
    OrderStore orderStore, {
    required PaymentMethod paymentMethod,
    PaymentStatus paymentStatus = PaymentStatus.pending,
    String? paymentIntentId,
    String? notes,
    String? clientPhone,
    String? customerName,
    // Tokens applied as a discount at checkout. Stored for future consumption
    // phase (FIFO) — not yet deducted from bora_tokens table.
    int tokensUsed = 0,
  }) async {
    // Items are required for shopping-type orders; logistics orders (carry
    // groceries, send package) have no cart items by design.
    final isShoppingOrder = _serviceType == OrderServiceType.restaurant ||
        _serviceType == OrderServiceType.storeShopping;
    if (isShoppingOrder && _items.isEmpty) return false;
    // FAVORES — paragem em casa opcional (pickup pode ser null); a entrega é
    // capturada via autocomplete (não exige _dropoffStreet pré-preenchido).
    final isErrand = _serviceType == OrderServiceType.errand;

    // ── FIX: Block order creation when pickup coordinates are missing.
    // Previously, null pickupLocation silently passed through, causing:
    //   - MapsService skipped (no origin to calculate from)
    //   - distance stuck at default ~1.0 km
    //   - driver map showing two pins at the same location
    //   - incorrect pricing
    // Now we fail explicitly so the UI can show a clear error.
    if (!isErrand && _pickupLocation == null) {
      debugPrint(
        'CartStore.finishOrder: BLOCKED — pickupLocation is null for '
        'vendor "$_vendorName". Cannot create order without pickup coords.',
      );
      return false;
    }

    if (!isTakeaway && _deliveryLocation == null) {
      debugPrint(
        'CartStore.finishOrder: BLOCKED — deliveryLocation is null. '
        'User must define a delivery address before placing an order.',
      );
      return false;
    }

    if (!isErrand && !isTakeaway && _dropoffStreet.isEmpty) {
      debugPrint('CartStore.finishOrder: BLOCKED — dropoffStreet is empty.');
      return false;
    }

    final breakdown = pricingBreakdown;

    final success = await orderStore.createOrder(
      serviceType: _serviceType,
      itemsSubtotal: breakdown.subtotal,
      // Em recolha o destino é a própria loja (pickup validado acima).
      destination: isTakeaway ? _pickupLocation! : _deliveryLocation!,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
      paymentIntentId: paymentIntentId,
      items: _items
          .map(
            (item) => CartItem(
              productId: item.productId,
              name: item.name,
              price: item.price,
              quantity: item.quantity,
              basePrice: item.basePrice,
              selectedOptions: item.selectedOptions,
            ),
          )
          .toList(),
      pickupLocation: _pickupLocation,
      distanceKm: breakdown.distanceKm,
      isPartnerStore: _isPartnerStore,
      requiresCar: _requiresCar,
      vendorName: _vendorName,
      pickupAddress: _pickupStreet ?? _vendorName,
      pickupStreet: _pickupStreet,
      pickupCity: _pickupCity,
      pickupPostalCode: _pickupPostalCode,
      dropoffAddress:
          [_dropoffStreet, _dropoffCity].where((s) => s.isNotEmpty).join(', '),
      dropoffStreet: _dropoffStreet,
      dropoffCity: _dropoffCity,
      dropoffPostalCode: _dropoffPostalCode,
      customerNotes: notes,
      clientPhone: clientPhone,
      customerName: customerName,
      apartmentDelivery: _apartmentDelivery,
      tokenDiscountEur: tokensUsed * BRTokens.TOKEN_VALUE_EUR,
      packagePhotoUrl: _packagePhotoUrl,
      groceriesPhotoUrl: _groceriesPhotoUrl,
      // D4 — takeaway propaga via serviceType: OrderServiceType.takeaway.
      // Curbside vai como params separados (cliente input pré-paid).
      takeawayIsCurbside: _isCurbside,
      takeawayCurbsideInfo: _curbsideInfo,
      tipCents: _tipCents,
      walletAppliedCents: _walletAppliedCents,
      // FAVORES (errand)
      errandDescription: _errandSession?.description,
      errandLocation: _errandSession?.location,
      errandLocationLat: _errandSession?.locationCoords.latitude,
      errandLocationLng: _errandSession?.locationCoords.longitude,
      errandHomeStop: _errandSession?.hasHomeStop ?? false,
      errandHomeStopReason: _errandSession?.homeStopReason,
      errandSpeed: _errandSession?.speed,
      errandHasPurchase: _errandSession?.hasPurchase ?? false,
      errandEstimatedPurchaseCents: _errandSession?.estimatedCents ?? 0,
      errandRequestPhotoUrl: _errandRequestPhotoUrl,
    );

    if (!success) return false;
    // 8.1 — persistir a foto do favor SEM tocar create_order (RPC dedicada).
    final reqPhoto = _errandRequestPhotoUrl;
    final newOrderId = orderStore.lastCreatedOrderId;
    if (reqPhoto != null && newOrderId != null) {
      try {
        await Supabase.instance.client.rpc(
          'client_set_errand_request_photo',
          params: {'p_order_id': newOrderId, 'p_url': reqPhoto},
        );
      } catch (e) {
        debugPrint('CartStore.finishOrder: set errand photo failed (non-fatal): $e');
      }
    }
    // Festas (2026-08-25) — gravar a data da encomenda SEM tocar create_order
    // (RPC dedicada, mesmo desenho da foto do favor). O servidor valida:
    // dono do pedido, loja categoria festas, status created, mínimo dia
    // seguinte, e só uma vez.
    final quandoFesta = _festasQuando;
    if (_vendorIsFestas && quandoFesta != null && newOrderId != null) {
      try {
        await Supabase.instance.client.rpc(
          'festas_set_schedule',
          params: {
            'p_order_id': newOrderId,
            'p_scheduled_for': quandoFesta.toUtc().toIso8601String(),
          },
        );
      } catch (e) {
        // Não-fatal: a data segue também nas observações do pedido.
        debugPrint('CartStore.finishOrder: festas_set_schedule falhou: $e');
      }
    }
    _festasQuando = null;
    _packagePhotoUrl = null;
    _groceriesPhotoUrl = null;
    _errandSession = null;
    _errandRequestPhotoUrl = null;
    // serviceType + curbside resetados em clearCart() abaixo.
    _tipCents = 0;
    _walletAppliedCents = 0;
    clearCart();
    return true;
  }
}

/// FAVORES (errand) — payload persistido entre o wizard cliente e o
/// `OrderStore.createOrder`. Não atravessa serialização Supabase directamente
/// (os campos vão um a um no toSupabase do OrderModel).
class ErrandSession {
  ErrandSession({
    required this.description,
    required this.location,
    required this.locationCoords,
    this.home,
    this.homeStopAddress,
    this.homeStopReason,
    this.homeStopCashCents,
    this.returnLeg = false,
    required this.speed,
    required this.hasPurchase,
    required this.estimatedCents,
    required this.quote,
  });

  final String description;
  final String location;
  final LatLng locationCoords;
  final LatLng? home;
  // Parte 3 (rodada 2) — morada textual da paragem em casa (antes descartada),
  // dinheiro a pegar em casa (motivo dinheiro) e se há perna de volta no fim.
  final String? homeStopAddress;
  final String? homeStopReason;
  final int? homeStopCashCents;
  final bool returnLeg;
  final String speed; // 'normal' | 'express'
  final bool hasPurchase;
  final int estimatedCents;
  final Map<String, dynamic> quote;

  bool get hasHomeStop => home != null;
}
