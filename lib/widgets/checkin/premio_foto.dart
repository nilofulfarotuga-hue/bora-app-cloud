// lib/widgets/checkin/premio_foto.dart
//
// Foto REAL de um prémio do check-in (Bloco G, 10/11/2026): a foto do produto do
// catálogo; o prémio da loja usa a foto da loja. Só se mostra (recorte redondo
// ou de cantos redondos) — a foto nunca se altera. Sem foto, ou se não abrir, um
// ícone na cor do Bora (presente; limpeza/lavagem para o serviço).
import 'package:flutter/material.dart';

import '../../config/app_colors.dart';

class PremioFoto extends StatelessWidget {
  const PremioFoto({
    super.key,
    required this.url,
    this.tipo = 'produto',
    this.tamanho = 40,
    this.redonda = true,
  });

  final String? url;

  /// 'produto' | 'servico' | 'desconto' | 'tokens'.
  final String tipo;
  final double tamanho;

  /// Círculo (caminho, barra) ou cantos redondos (festa em grande).
  final bool redonda;

  IconData get _icone => switch (tipo) {
        'servico' => Icons.cleaning_services_outlined,
        'desconto' => Icons.local_offer_outlined,
        'tokens' => Icons.star_rounded,
        _ => Icons.card_giftcard,
      };

  @override
  Widget build(BuildContext context) {
    final sem = Container(
      width: tamanho,
      height: tamanho,
      color: const Color(0xFFF0FDF4),
      alignment: Alignment.center,
      child: Icon(_icone, size: tamanho * 0.5, color: AppColors.primaryDark),
    );
    final u = url;
    final foto = (u == null || u.trim().isEmpty)
        ? sem
        : Image.network(
            u,
            width: tamanho,
            height: tamanho,
            fit: BoxFit.cover,
            cacheWidth: (tamanho * 3).round(),
            errorBuilder: (_, __, ___) => sem,
          );
    return redonda
        ? ClipOval(child: SizedBox(width: tamanho, height: tamanho, child: foto))
        : ClipRRect(
            borderRadius: BorderRadius.circular(tamanho * 0.12),
            child: SizedBox(width: tamanho, height: tamanho, child: foto),
          );
  }
}
