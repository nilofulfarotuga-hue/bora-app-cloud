// ============================================================
// DISPATCH ENGINE — DESATIVADO
// Toda a lógica de dispatch foi movida para o backend.
// Este ficheiro existe apenas para não quebrar imports existentes.
// Consultar: supabase/functions/dispatch-engine/index.ts
// ============================================================

import 'package:flutter/foundation.dart';

import '../models/order_model.dart';
import '../stores/driver_store.dart';
import '../stores/order_store.dart';

class DispatchEngine {
  // Singleton mantido para não quebrar injeção existente
  static final DispatchEngine _instance = DispatchEngine._internal();
  factory DispatchEngine({
    Duration offerTimeout = const Duration(seconds: 10),
    Duration recycleDelay = const Duration(seconds: 30),
  }) =>
      _instance;
  DispatchEngine._internal();

  // Todos os métodos estão desativados.
  // O Flutter não toma mais decisões de dispatch.

  /// Called by ProxyProvider2 in main.dart — no-op, backend dispatch active.
  void attach({
    required OrderStore orderStore,
    required DriverStore driverStore,
  }) {
    debugPrint('[DispatchEngine] Desativado. Backend controla o dispatch.');
  }

  void dispose() {
    // DISABLED
  }

  void triggerDispatch() {
    // DISABLED — dispatch agora é feito no backend
  }

  void notifyOrderAccepted(OrderModel order) {
    // DISABLED
  }

  void notifyOrderPickedUp(OrderModel order) {
    // DISABLED
  }

  void notifyOrderReleased(OrderModel order) {
    // DISABLED
  }
}
