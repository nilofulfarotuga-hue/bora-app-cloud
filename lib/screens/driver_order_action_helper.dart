import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/order_model.dart';
import '../stores/order_store.dart';
import '../utils/safe_image_picker.dart';

class DriverOrderAction {
  const DriverOrderAction({
    required this.label,
    required this.successMessage,
    required this.execute,
  });

  final String label;
  final String successMessage;
  final Future<bool> Function() execute;
}

DriverOrderAction? resolveDriverOrderAction(
    OrderStore store, OrderModel order) {
  switch (order.status) {
    case OrderStatus.driverAccepted:
      // For non-partner store/restaurant pickups the driver must first
      // finalize the purchase (enter the real amount paid) before confirming
      // pickup. Hide the button until isPurchaseFinalized == true — the
      // _FinalizePurchaseButton is shown in its place during driverAccepted.
      final needsPurchaseFinalize = !order.isPartnerStore &&
          (order.serviceType == OrderServiceType.storeShopping ||
              order.serviceType == OrderServiceType.restaurant);
      if (needsPurchaseFinalize && !order.isPurchaseFinalized) {
        return null;
      }
      // FAVOR-ESTAFETA (27/09): favor com compra — primeiro "Tratar do favor"
      // (compra + talão); só depois aparece "Recolher pedido".
      if (order.serviceType == OrderServiceType.errand &&
          order.errandHasPurchase &&
          !order.isPurchaseFinalized) {
        return null;
      }
      return DriverOrderAction(
        label: "Recolher pedido",
        successMessage: "Pedido recolhido",
        execute: () => store.pickUpOrder(order),
      );
    case OrderStatus.pickedUp:
      return DriverOrderAction(
        label: "Iniciar entrega",
        successMessage: "Entrega iniciada",
        execute: () => store.startDelivery(order),
      );
    case OrderStatus.onTheWay:
      return DriverOrderAction(
        label: "Concluir entrega",
        successMessage: "Pedido entregue",
        execute: () => store.finishOrder(order),
      );
    default:
      return null;
  }
}

/// [ronda 04/10 · app-estafeta #7] Prova de entrega com foto ("deixar à
/// porta", padrão Uber Eats/Glovo). Partilhada pelo ecrã do estafeta e pelo
/// mapa da entrega — os dois têm botão de concluir.
///
/// A regra vive no servidor (`estafeta_entrega_precisa_foto`): foto exigida se
/// o cliente pediu "deixar à porta" OU se o admin ligou
/// `platform_settings.foto_entrega_obrigatoria`. A foto sobe pela Edge Function
/// `upload-order-photo` e grava-se com `estafeta_registar_foto_entrega`
/// (`orders.foto_entrega_url` + `foto_entrega_em`).
class ProvaDeEntrega {
  ProvaDeEntrega._();

  static final Map<String, Future<Map<String, dynamic>?>> _cache = {};

  /// Fotos já tiradas mas por enviar (falha de rede): a tentativa seguinte
  /// usa esta em vez de pedir outra.
  static final Map<String, XFile> _porEnviar = {};

  static Future<Map<String, dynamic>?> info(String orderId) =>
      _cache[orderId] ??= _ler(orderId);

  static Future<Map<String, dynamic>?> _ler(String orderId) async {
    try {
      final r = await Supabase.instance.client
          .rpc('estafeta_entrega_precisa_foto', params: {'p_order_id': orderId})
          .timeout(const Duration(seconds: 6));
      if (r is Map && r['ok'] == true) return Map<String, dynamic>.from(r);
    } catch (e) {
      debugPrint('[prova-entrega] estafeta_entrega_precisa_foto: $e');
    }
    unawaited(Future<void>.delayed(
        const Duration(seconds: 1), () => _cache.remove(orderId)));
    return null;
  }

  /// Antes de fechar a entrega. Devolve false se o estafeta cancelou ou o
  /// envio falhou (a foto fica guardada para a próxima tentativa). Sem
  /// resposta do servidor sobre a regra, não bloqueia a entrega.
  static Future<bool> garantirFoto(
      BuildContext context, OrderModel order) async {
    final dados = await info(order.id);
    if (!context.mounted) return false;
    if (dados == null ||
        dados['exigida'] != true ||
        dados['ja_tem_foto'] == true) {
      return true;
    }
    final messenger = ScaffoldMessenger.of(context);
    var foto = _porEnviar[order.id];
    if (foto == null) {
      final querTirar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.photo_camera_outlined, size: 40),
          title: const Text('Foto da entrega'),
          content: Text(dados['deixar_a_porta'] == true
              ? 'O cliente pediu para deixar à porta. Tira uma foto da '
                  'encomenda no sítio onde a deixaste.'
              : 'Tira uma foto da encomenda entregue para ficar como prova.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.photo_camera),
              label: const Text('Tirar foto'),
            ),
          ],
        ),
      );
      if (querTirar != true || !context.mounted) return false;
      try {
        foto = await SafeImagePicker.pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.rear,
          imageQuality: 75,
          maxWidth: 1600,
        );
      } catch (e) {
        debugPrint('[prova-entrega] câmara: $e');
        foto = null;
      }
      if (foto == null) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Sem foto não é possível concluir esta entrega.')));
        return false;
      }
      _porEnviar[order.id] = foto;
    }
    try {
      final bytes = await foto.readAsBytes();
      final up = await Supabase.instance.client.functions.invoke(
        'upload-order-photo',
        body: {
          'fileBase64': base64Encode(bytes),
          'fileName':
              'entrega_${order.id}_${DateTime.now().millisecondsSinceEpoch}.jpg',
        },
      ).timeout(const Duration(seconds: 40));
      final data = up.data;
      final url = (data is Map && data['success'] == true)
          ? data['url'] as String?
          : null;
      if (url == null) throw Exception('upload sem url: $data');
      final r = await Supabase.instance.client.rpc(
        'estafeta_registar_foto_entrega',
        params: {'p_order_id': order.id, 'p_foto_url': url},
      ).timeout(const Duration(seconds: 10));
      if (r is! Map || r['ok'] != true) throw Exception('registo: $r');
      _porEnviar.remove(order.id);
      _cache[order.id] = Future.value({...dados, 'ja_tem_foto': true});
      return true;
    } catch (e) {
      debugPrint('[prova-entrega] envio: $e');
      messenger.showSnackBar(const SnackBar(
        content: Text('Não foi possível enviar a foto. Verifica a ligação '
            'e carrega outra vez — a foto já tirada fica guardada.'),
        duration: Duration(seconds: 5),
      ));
      return false;
    }
  }
}
