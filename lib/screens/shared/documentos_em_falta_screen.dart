/// "Faltam documentos" — o ecrã que abre quando a pessoa toca no aviso do
/// painel "Pedir documentos em falta" (18/11/2026, regra de 07/11: o pedido
/// fica visível nas pendências da pessoa, onde consegue enviar). App em PT-PT.
///
/// Mostra a mesma lista do ecrã de entrada de cada papel, com um botão por
/// item para enviar ali mesmo.
library;

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../widgets/estafeta_documentos_em_falta.dart';
import '../../widgets/prestador_documentos_em_falta.dart';

/// [papel] vem no `related_id` do aviso: driver, cleaner, washer ou handyman.
class DocumentosEmFaltaScreen extends StatelessWidget {
  const DocumentosEmFaltaScreen({super.key, required this.papel});

  final String papel;

  String get _titulo => switch (papel) {
        'cleaner' => 'Limpeza: documentos em falta',
        'washer' => 'Lavagem: documentos em falta',
        'handyman' => 'Casa: documentos em falta',
        _ => 'Estafeta: documentos em falta',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(_titulo)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'A equipa Bora pediu-te estes documentos. Envia cada um no botão '
            'ao lado; depois revemos e avisamos-te.',
            style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          switch (papel) {
            'cleaner' || 'washer' || 'handyman' =>
              PrestadorDocumentosEmFalta(papel: papel),
            _ => const EstafetaDocumentosEmFalta(),
          },
        ],
      ),
    );
  }
}

/// Kind do aviso em `in_app_notifications` e no push (`notify-admin-message`).
const String kKindDocumentosEmFalta = 'documentos_em_falta';

const _papeisComEcra = {'driver', 'cleaner', 'washer', 'handyman'};

/// Título que o painel põe no aviso (`pedirDocumentosEmFalta`).
const String kTituloAvisoDocumentos = 'Faltam documentos na tua candidatura';

/// O papel do ecrã a abrir para um aviso do sino, ou null se o aviso não é
/// um pedido de documentos. Os avisos novos trazem o papel em `related_id`;
/// os antigos (kind `admin_push`, antes de 18/11) tiram-no da frase.
String? papelDoAvisoDeDocumentos(Map<String, dynamic> n) {
  final kind = n['kind']?.toString();
  if (kind == kKindDocumentosEmFalta) {
    final p = n['related_id']?.toString() ?? '';
    return _papeisComEcra.contains(p) ? p : 'driver';
  }
  if (kind == 'admin_push' && n['title']?.toString() == kTituloAvisoDocumentos) {
    final corpo = n['body']?.toString() ?? '';
    if (corpo.contains('profissional de limpeza')) return 'cleaner';
    if (corpo.contains('lavador')) return 'washer';
    if (corpo.contains('profissional da Casa')) return 'handyman';
    return 'driver';
  }
  return null;
}
