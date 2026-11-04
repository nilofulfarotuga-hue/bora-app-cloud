import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';

/// Aviso da loja no TOPO da página (04/11/2026, ordem do Danilo): o texto
/// "Sobre" da loja (`restaurants.about_text`), bem visível ao entrar. Ex.: a
/// Mercadona · Beleza e Higiene diz que por agora só tem perfumaria, cosmética
/// e higiene. Sem texto, sem rede ou com erro: não mostra nada.
class AvisoDaLoja extends StatefulWidget {
  const AvisoDaLoja({super.key, required this.restaurantId, this.ler});

  final String restaurantId;

  /// Só para testes: devolve o texto sem ir ao servidor.
  final Future<String?> Function(String restaurantId)? ler;

  static Future<String?> lerDoServidor(String restaurantId) async {
    final linha = await Supabase.instance.client
        .from('restaurants')
        .select('about_text')
        .eq('id', restaurantId)
        .maybeSingle();
    final t = (linha?['about_text'] ?? '').toString().trim();
    return t.isEmpty ? null : t;
  }

  @override
  State<AvisoDaLoja> createState() => _AvisoDaLojaState();
}

class _AvisoDaLojaState extends State<AvisoDaLoja> {
  String? _texto;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final t = await (widget.ler ?? AvisoDaLoja.lerDoServidor)(widget.restaurantId);
      if (mounted && t != null && t.trim().isNotEmpty) setState(() => _texto = t.trim());
    } catch (_) {
      // sem aviso: a loja abre como sempre
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _texto;
    if (t == null) return const SizedBox.shrink();
    return Padding(
      key: const Key('aviso_da_loja'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: AppColors.accent, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                t,
                style: const TextStyle(fontSize: 15, height: 1.35, color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
