import 'package:flutter/material.dart';

import '../../config/app_colors.dart';

/// Contador de horas de serviço TVDE nas últimas 24 h — informativo
/// (Lei 45/2018 art. 13.º, na versão da Lei 59/2026: máximo de 10 h em
/// qualquer período de 24 h, somando todas as plataformas).
///
/// Recebe os números por parâmetro (sem Supabase) para ser testável. Quem o
/// usa lê `tvde_minha_conformidade` e passa-o por [TvdeHorasServicoCard.fromConformidade].
///
/// Não controla nada: só mostra. O travão, se o interruptor
/// `tvde_work_limit_enforce` estiver ligado, é o servidor.
class TvdeHorasServicoCard extends StatelessWidget {
  const TvdeHorasServicoCard({
    super.key,
    required this.horasTotal,
    required this.limite,
    this.horasOutras = 0,
    this.limiteEfetivo = false,
  });

  /// Lê a resposta de `tvde_minha_conformidade`.
  factory TvdeHorasServicoCard.fromConformidade(Map<String, dynamic> m,
      {Key? key}) {
    num n(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);
    return TvdeHorasServicoCard(
      key: key,
      horasTotal: n(m['horas_total_24h']),
      limite: m['limite_horas'] == null ? 10 : n(m['limite_horas']),
      horasOutras: n(m['horas_outras_plataformas']),
      limiteEfetivo: m['limite_efetivo'] == true,
    );
  }

  /// Horas nas últimas 24 h, todas as plataformas (Bora + declaradas).
  final num horasTotal;
  final num limite;

  /// Horas declaradas pelo motorista noutras plataformas.
  final num horasOutras;

  /// O servidor já aplica o limite (interruptor ligado).
  final bool limiteEfetivo;

  /// "10" para inteiros, "7,5" com uma casa decimal para o resto.
  static String formatarHoras(num h) {
    if (h == h.roundToDouble()) return h.round().toString();
    return h.toStringAsFixed(1).replaceAll('.', ',');
  }

  bool get atingiuLimite => limiteEfetivo && limite > 0 && horasTotal >= limite;

  @override
  Widget build(BuildContext context) {
    final frac = limite > 0 ? (horasTotal / limite).clamp(0.0, 1.0).toDouble() : 0.0;
    final perto = limite > 0 && horasTotal >= limite * 0.8;
    final cor = atingiuLimite
        ? AppColors.error
        : (perto ? const Color(0xFFD97706) : AppColors.primary);
    return Column(
      key: const Key('tvde_horas_servico_card'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.schedule, size: 16, color: cor),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'Horas de serviço nas últimas 24 h: '
                '${formatarHoras(horasTotal)} h de ${formatarHoras(limite)} h',
                style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: frac,
            minHeight: 5,
            backgroundColor: AppColors.divider,
            valueColor: AlwaysStoppedAnimation<Color>(cor),
          ),
        ),
        if (horasOutras > 0) ...[
          const SizedBox(height: 2),
          Text(
            'Noutras plataformas: ${formatarHoras(horasOutras)} h (declarado)',
            style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
        ],
        if (atingiuLimite) ...[
          const SizedBox(height: 4),
          Text(
            'Atingiste o limite legal de ${formatarHoras(limite)} horas',
            key: const Key('tvde_horas_limite_atingido'),
            style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.error,
                fontWeight: FontWeight.w700),
          ),
        ],
      ],
    );
  }
}
