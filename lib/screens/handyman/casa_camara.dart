import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/tr.dart';
import '../../utils/safe_image_picker.dart';

/// Quanto se espera pela câmara/galeria antes de desistir (PADRAO_BORA 1.26:
/// nenhuma espera por hardware ou permissão fica sem limite).
const Duration kCasaCamaraLimite = Duration(minutes: 3);

/// A câmara foi recusada pelo sistema (permissão negada)?
bool casaCamaraRecusada(Object e) =>
    e is PlatformException &&
    (e.code == 'camera_access_denied' ||
        e.code == 'photo_access_denied' ||
        e.code.contains('denied'));

/// Tira (ou escolhe) uma foto com limite de tempo e, se o sistema recusar a
/// câmara, explica em português o que fazer. null = nada escolhido.
Future<XFile?> casaTirarFoto(
  BuildContext context, {
  ImageSource fonte = ImageSource.camera,
  double maxWidth = 1600,
  int imageQuality = 82,
}) async {
  try {
    return await SafeImagePicker.pickImage(
      source: fonte,
      maxWidth: maxWidth,
      imageQuality: imageQuality,
    ).timeout(kCasaCamaraLimite);
  } on TimeoutException {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('A câmara não respondeu. Fecha-a e tenta outra vez.'.tr)));
    }
    return null;
  } catch (e) {
    debugPrint('[CASA] câmara/galeria falhou: $e');
    if (!context.mounted) return null;
    if (casaCamaraRecusada(e)) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Sem acesso à câmara'.tr),
          content: Text(
              'O telemóvel não deixou o Bora usar a câmara. Abre as Definições do telemóvel, vai a Apps, Bora, Permissões, e ativa a Câmara (e as Fotos). Depois tenta outra vez.'.tr),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Percebi'.tr),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Não foi possível abrir a câmara. Tenta outra vez.'.tr)));
    }
    return null;
  }
}

/// Pergunta se é câmara ou galeria (para documentos; as fotos do trabalho são
/// só de câmara).
Future<ImageSource?> casaEscolherFonte(BuildContext context) =>
    showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text('Tirar foto'.tr),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('Escolher da galeria'.tr),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
