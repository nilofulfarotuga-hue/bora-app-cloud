# F2 — P6 PIN server-side: alteração PROPOSTA ao order_store.dart (zona 🔴)

`lib/stores/order_store.dart` está na Lista Vermelha (a Trava bloqueia a minha
edição). O servidor JÁ está pronto e provado (RPC `driver_validate_delivery_pin`
aplicada, testes E2E passaram: errado→wrong_pin, certo→delivered, repete→
already_delivered, 5×→blocked). Falta só ligar a app — esta é a alteração exata.

## 1) Novo método em OrderStore (a seguir a `finishOrder`, ~linha 1642)

```dart
  /// P6 (2026-08-17) — Conclui a entrega VALIDANDO O PIN NO SERVIDOR.
  /// A app envia o código; a RPC `driver_validate_delivery_pin` decide (deriva
  /// o mesmo PIN do UUID, regista tentativas, bloqueia à 5.ª e só ela muda para
  /// delivered). O cliente NUNCA decide localmente.
  ///
  /// `order` é o pedido DESTA entrega (com stacking, validar contra o certo).
  Future<DeliveryPinResult> finishOrderWithPin(
      OrderModel order, String pin) async {
    Map<String, dynamic> data;
    try {
      final res = await supabase.rpc('driver_validate_delivery_pin',
          params: {'p_order_id': order.id, 'p_pin': pin});
      data = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    } catch (e) {
      // Falha de rede/servidor: NÃO fechar localmente. Tenta de novo.
      return const DeliveryPinResult(ok: false, error: 'network');
    }
    if (data['ok'] == true) {
      // Servidor já pôs delivered. Espelha o estado local (mesmo efeito do
      // finishOrder, mas sem re-emitir a transição — o servidor mandou).
      final idx = _orders.indexWhere((o) => o.id == order.id);
      if (idx != -1) {
        _orders[idx] = OrderModel.fromSupabase({
          ..._orders[idx].toSupabase(),
          'status': 'delivered',
          'delivered_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
      if (order.assignedDriverId != null) {
        _driverStore.releaseOrderForDriver(order.assignedDriverId!, order.id);
        _driverStore.stopTracking(order.id);
        _driverLocationService.stopTracking();
        order.pickupWarningIssued = false;
      }
      _lastDeliveredAt = DateTime.now();
      notifyListeners();
      return const DeliveryPinResult(ok: true);
    }
    return DeliveryPinResult(
      ok: false,
      error: data['error'] as String?,
      attemptsLeft: (data['attempts_left'] as num?)?.toInt(),
    );
  }
```

## 2) Classe de resultado (topo do ficheiro, junto às outras ou num novo)

```dart
/// Resultado da validação do PIN de entrega server-side (P6).
class DeliveryPinResult {
  const DeliveryPinResult({required this.ok, this.error, this.attemptsLeft});
  final bool ok;
  final String? error;        // wrong_pin | blocked | invalid_status | network | ...
  final int? attemptsLeft;    // preenchido em wrong_pin
}
```

## 3) Ligar os 2 diálogos de código (driver_map_screen.dart e driver_home_screen.dart)

Nos dois `_showDeliveryCodeDialog`, em vez de comparar `entered != order.deliveryCode`
localmente e depois `action.execute()`, passar a:

```dart
// dentro do onPressed do "Confirmar", após validar que tem 4 dígitos:
final r = await context.read<OrderStore>().finishOrderWithPin(order, entered);
if (r.ok) {
  Navigator.of(dialogContext).pop(true);   // fechado pelo servidor
} else if (r.error == 'wrong_pin') {
  setDialogState(() => errorText =
      'Código incorreto. Tentativas restantes: ${r.attemptsLeft ?? '-'}.');
  controller.clear();
} else if (r.error == 'blocked') {
  setDialogState(() => errorText =
      'Bloqueado após 5 tentativas. O suporte foi avisado.');
} else if (r.error == 'network') {
  setDialogState(() => errorText = 'Sem ligação ao servidor. Tenta de novo.');
} else {
  setDialogState(() => errorText = 'Não foi possível concluir (${r.error}).');
}
```

O `deliveryCode` (getter derivado) fica no modelo só para MOSTRAR ao cliente —
deixa de ser usado como fonte de verdade da entrega. A conta local morre.

## Porquê proposta e não aplicado
order_store.dart é zona protegida (dinheiro/estado de ordem). O servidor já está
provado; isto é só a costura de UI/estado. Aplica quando quiseres — nada aqui
cobra nem calcula dinheiro; é troca de "decidir local" por "obedecer ao servidor".
