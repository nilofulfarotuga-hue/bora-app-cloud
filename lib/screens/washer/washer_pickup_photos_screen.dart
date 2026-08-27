import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../models/carwash_models.dart';
import '../../services/carwash_upload_service.dart';
import '../../stores/washer_store.dart';
import '../../utils/safe_image_picker.dart';

/// LAVAGEM AUTO — as 4 fotos da recolha.
///
/// OBRIGATÓRIAS, e só para o LAVADOR (o cliente nunca é obrigado a nada).
/// O botão "Recolhi o carro" fica cinzento até as quatro estarem tiradas,
/// uma a uma, com o ecrã a pedir cada ângulo pelo nome.
///
/// SÓ CÂMARA, na hora — não se aceitam imagens da galeria. A garantia final
/// está no servidor: `carwash_mark_picked_up` valida os 4 ângulos outra vez.
class WasherPickupPhotosScreen extends StatefulWidget {
  const WasherPickupPhotosScreen({super.key, required this.booking});

  final CarwashBooking booking;

  @override
  State<WasherPickupPhotosScreen> createState() =>
      _WasherPickupPhotosScreenState();
}

class _WasherPickupPhotosScreenState extends State<WasherPickupPhotosScreen> {
  final Map<CarwashAngle, XFile> _locais = {};
  final Map<CarwashAngle, String> _paths = {};
  CarwashAngle? _aEnviar;
  bool _submitting = false;

  bool get _completo => CarwashAngle.values.every(_paths.containsKey);

  Future<void> _tirar(CarwashAngle angle) async {
    // Só câmara. Sem opção de galeria — é de propósito.
    final f = await SafeImagePicker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      imageQuality: 82,
    );
    if (f == null || !mounted) return;

    setState(() {
      _locais[angle] = f;
      _aEnviar = angle;
    });

    try {
      final path = await CarwashUploadService.upload(
        f,
        bookingId: widget.booking.id,
        kind: 'before',
        tag: angle.wire,
      );
      if (!mounted) return;
      setState(() => _paths[angle] = path);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locais.remove(angle);
        _paths.remove(angle);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível enviar a foto '
            '"${angle.label}". Tenta outra vez.')),
      );
    } finally {
      if (mounted) setState(() => _aEnviar = null);
    }
  }

  Future<void> _confirmarRecolha() async {
    if (!_completo || _submitting) return;
    setState(() => _submitting = true);
    final store = context.read<WasherStore>();
    final fotos = CarwashAngle.values
        .map((a) => CarwashPhoto(angle: a.wire, url: _paths[a]!))
        .toList();
    final ok = await store.markPickedUp(widget.booking.id, fotos);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(store.lastError ?? 'Não foi possível confirmar.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final feitas = _paths.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Fotos da recolha'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(Spacing.lg),
        child: SizedBox(
          height: 52,
          child: FilledButton(
            // Cinzento até as 4 estarem — e o servidor valida na mesma.
            onPressed: (_completo && !_submitting) ? _confirmarRecolha : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              disabledBackgroundColor: AppColors.divider,
            ),
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(
                    _completo
                        ? 'Recolhi o carro'
                        : 'Faltam ${4 - feitas} foto${4 - feitas == 1 ? '' : 's'}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: [
          Container(
            padding: const EdgeInsets.all(Spacing.lg),
            decoration: BoxDecoration(
              color: AppColors.primaryWash,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${widget.booking.plate} · ${widget.booking.carMakeModel}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: Spacing.xs),
                const Text(
                  'Tira as quatro fotos do carro antes de o levar. '
                  'Protege-te a ti e ao cliente.',
                  style: TextStyle(color: AppColors.textSecondary, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.lg),
          for (final a in CarwashAngle.values)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.md),
              child: _AnguloTile(
                angle: a,
                ficheiro: _locais[a],
                enviada: _paths.containsKey(a),
                aEnviar: _aEnviar == a,
                onTap: () => _tirar(a),
              ),
            ),
        ],
      ),
    );
  }
}

class _AnguloTile extends StatelessWidget {
  const _AnguloTile({
    required this.angle,
    required this.ficheiro,
    required this.enviada,
    required this.aEnviar,
    required this.onTap,
  });

  final CarwashAngle angle;
  final XFile? ficheiro;
  final bool enviada;
  final bool aEnviar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: aEnviar ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enviada ? AppColors.primary : AppColors.divider,
            width: enviada ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ficheiro == null
                  ? Container(
                      width: 72,
                      height: 72,
                      color: AppColors.surface2,
                      child: const Icon(Icons.photo_camera_outlined,
                          color: AppColors.textSubtle),
                    )
                  : Image.file(File(ficheiro!.path),
                      width: 72, height: 72, fit: BoxFit.cover),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(angle.label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                    aEnviar
                        ? 'A enviar...'
                        : enviada
                            ? 'Foto guardada'
                            : angle.hint,
                    style: TextStyle(
                      fontSize: 12,
                      color: enviada
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (aEnviar)
              const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                enviada ? Icons.check_circle : Icons.camera_alt,
                color: enviada ? AppColors.primary : AppColors.textSubtle,
              ),
          ],
        ),
      ),
    );
  }
}
