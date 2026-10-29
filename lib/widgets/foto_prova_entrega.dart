import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../l10n/tr.dart';
import '../models/order_model.dart';
import '../services/interruptores_app.dart';
import 'private_bucket_image.dart';

/// A hora da foto em texto ("Tirada às 14:32"), em hora de Lisboa do aparelho.
/// `null` quando não há hora.
String? textoHoraDaFoto(DateTime? quando) {
  if (quando == null) return null;
  final l = quando.toLocal();
  final h = l.hour.toString().padLeft(2, '0');
  final m = l.minute.toString().padLeft(2, '0');
  return 'Tirada às {0}'.trArgs(['$h:$m']);
}

/// Foto de prova da entrega, visível ao cliente (adendo 4 · item 2,
/// 29/10/2026). Até aqui só o admin a via.
///
/// A foto vive no balde privado `order-photos`; a política
/// `order_photos_select_entrega_cliente` deixa o cliente dono do pedido
/// assiná-la. Aparece assim que o estafeta a regista (antes de fechar a
/// entrega). Sem foto, ou com o interruptor `feature_foto_entrega_cliente`
/// desligado no painel, não desenha nada.
class FotoProvaEntregaCliente extends StatefulWidget {
  const FotoProvaEntregaCliente({
    super.key,
    required this.orderId,
    required this.status,
    this.margem = const EdgeInsets.only(bottom: Spacing.md),
  });

  final String orderId;

  /// Muda-se o estado, volta-se a procurar (a foto chega pouco antes de
  /// "entregue").
  final OrderStatus status;
  final EdgeInsets margem;

  @override
  State<FotoProvaEntregaCliente> createState() =>
      _FotoProvaEntregaClienteState();
}

class _FotoProvaEntregaClienteState extends State<FotoProvaEntregaCliente> {
  String? _url;
  DateTime? _quando;
  bool _ligado = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void didUpdateWidget(covariant FotoProvaEntregaCliente old) {
    super.didUpdateWidget(old);
    if (old.orderId != widget.orderId || old.status != widget.status) {
      _carregar();
    }
  }

  Future<void> _carregar() async {
    try {
      final ligado = await InterruptoresApp.instance
          .ligado(InterruptoresApp.fotoEntregaCliente);
      if (!ligado) {
        if (mounted && _ligado) setState(() => _ligado = false);
        return;
      }
      final linha = await Supabase.instance.client
          .from('orders')
          .select('foto_entrega_url, foto_entrega_em')
          .eq('id', widget.orderId)
          .maybeSingle();
      if (!mounted) return;
      final url = (linha?['foto_entrega_url'] as String?)?.trim();
      setState(() {
        _ligado = true;
        _url = (url == null || url.isEmpty) ? null : url;
        _quando = DateTime.tryParse('${linha?['foto_entrega_em'] ?? ''}');
      });
    } catch (e) {
      debugPrint('[FotoProvaEntrega] ${widget.orderId}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    if (!_ligado || url == null) return const SizedBox.shrink();
    final hora = textoHoraDaFoto(_quando);
    return Padding(
      padding: widget.margem,
      child: Container(
        key: const Key('foto_prova_entrega'),
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.photo_camera_outlined,
                    size: 22, color: AppColors.primary),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    'Foto da entrega'.tr,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            if (hora != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  hora,
                  style: const TextStyle(
                      fontSize: 16, color: AppColors.textSecondary),
                ),
              ),
            const SizedBox(height: Spacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.md),
              child: PrivateBucketImage(
                urlOrPath: url,
                height: 200,
                width: double.infinity,
                tituloAmpliada: 'Foto da entrega'.tr,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
