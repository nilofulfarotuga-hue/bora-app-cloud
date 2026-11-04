// lib/widgets/checkin/checkin_mes_sheet.dart
//
// Vista do MÊS dos marcos do check-in (Bloco D, 21/10/2026): abre pela seta do
// cartão "Check-in diário". Mostra o texto do Danilo, em que dia da sequência
// está o cliente, os 4 marcos (7, 10, 15, 30) com o que se ganha e quantos dias
// faltam, e o botão para "Os meus prémios". Tudo vem do servidor.
import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../l10n/tr.dart';
import '../../services/checkin_premios_service.dart';

Future<void> mostrarCheckinMes(
  BuildContext context,
  CheckinPremiosEstado estado, {
  VoidCallback? abrirPremios,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (ctx) => CheckinMesSheet(
      estado: estado,
      abrirPremios: abrirPremios == null
          ? null
          : () {
              Navigator.of(ctx).pop();
              abrirPremios();
            },
    ),
  );
}

class CheckinMesSheet extends StatelessWidget {
  const CheckinMesSheet({super.key, required this.estado, this.abrirPremios});

  final CheckinPremiosEstado estado;
  final VoidCallback? abrirPremios;

  @override
  Widget build(BuildContext context) {
    final e = estado;
    final porUsar = e.porUsar.length;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: SingleChildScrollView(
          key: const Key('checkin_mes_sheet'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Os prémios do mês'.tr,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                e.texto.isNotEmpty
                    ? e.texto.tr
                    : 'Faz o check-in todos os dias. Aos 10 dias seguidos ganhas 2 salgados da Keli (pagas só a entrega e as taxas). Aos 15, um açaí do Goola. Aos 30, escolhes 2 horas de limpeza ou uma lavagem exterior do carro.'
                        .tr,
                style: const TextStyle(fontSize: 13.5, height: 1.35, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              _Progresso(estado: e),
              const SizedBox(height: 12),
              // 04/11/2026: calendário com TODOS os prémios do mês.
              CalendarioPremios(estado: e),
              const SizedBox(height: 12),
              for (final m in e.marcos) ...[
                _MarcoLinha(marco: m, diaMarco: e.diaMarco),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 4),
              Text(
                'Se falhares um dia, a sequência volta ao dia 1. Depois do dia {0} recomeça no dia 1.'
                    .trArgs([e.cicloDias]),
                style: const TextStyle(fontSize: 12, color: AppColors.textSubtle, height: 1.3),
              ),
              if (abrirPremios != null) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const Key('btn_os_meus_premios'),
                  onPressed: abrirPremios,
                  icon: const Icon(Icons.card_giftcard, size: 18),
                  label: Text(porUsar > 0
                      ? 'Os meus prémios ({0})'.trArgs([porUsar])
                      : 'Os meus prémios'.tr),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Calendário do ciclo (04/11/2026, escada de prémios): um quadrado por dia.
/// Dia com prémio: foto e nome curto. Dia sem prémio novo: os tokens do dia.
/// Por baixo, que o prémio conquistado fica guardado e, se for o caso, quando
/// é o próximo prémio (um a cada 30 dias).
class CalendarioPremios extends StatelessWidget {
  const CalendarioPremios({super.key, required this.estado});

  final CheckinPremiosEstado estado;

  @override
  Widget build(BuildContext context) {
    final e = estado;
    final total = e.cicloDias <= 0 ? 30 : e.cicloDias;
    final porDia = <int, CheckinMarco>{
      for (final m in e.marcos)
        if (m.dia >= 1 && m.dia <= total) m.dia: m,
    };
    final bloqueado = e.escada?.premioBloqueado() ?? false;
    return Column(
      key: const Key('checkin_calendario'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: total,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 0.78,
          ),
          itemBuilder: (_, i) {
            final dia = i + 1;
            return _DiaCalendario(
              dia: dia,
              marco: porDia[dia],
              tokens: e.tokensDoDia(dia),
              feito: e.diasSeguidos > 0 && dia <= e.diaMarco,
              hoje: dia == e.diaDeHoje,
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Nos dias sem prémio novo ganhas os tokens do dia. O prémio que já conquistaste fica guardado.'.tr,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3),
        ),
        if (bloqueado) ...[
          const SizedBox(height: 6),
          Text(
            'Próximo prémio disponível a {0}.'.trArgs([diaMes(e.escada!.proximoPremioEm)]),
            key: const Key('checkin_proximo_premio_em'),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
          ),
        ],
      ],
    );
  }
}

class _DiaCalendario extends StatelessWidget {
  const _DiaCalendario({
    required this.dia,
    required this.marco,
    required this.tokens,
    required this.feito,
    required this.hoje,
  });

  final int dia;
  final CheckinMarco? marco;
  final int tokens;
  final bool feito;
  final bool hoje;

  bool get _temPremio => marco != null && marco!.tipo != 'tokens';

  @override
  Widget build(BuildContext context) {
    final m = marco;
    final fundo = feito
        ? const Color(0xFFDCFCE7)
        : _temPremio
            ? const Color(0xFFFFF7ED)
            : const Color(0xFFF9FAFB);
    final borda = hoje
        ? AppColors.primary
        : _temPremio
            ? AppColors.accent
            : const Color(0xFFE5E7EB);
    final Widget meio;
    if (_temPremio) {
      final foto = m!.fotoUrl;
      meio = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: foto == null
            ? Icon(m.tipo == 'servico' ? Icons.cleaning_services_outlined : Icons.card_giftcard,
                size: 26, color: AppColors.accent)
            : Image.network(
                foto,
                width: 34,
                height: 34,
                fit: BoxFit.cover,
                cacheWidth: 120,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.card_giftcard, size: 26, color: AppColors.accent),
              ),
      );
    } else {
      meio = Text(
        tokens > 0 ? '+$tokens' : '·',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: (m?.tipo == 'tokens') ? AppColors.accent : AppColors.textSecondary,
        ),
      );
    }
    return Container(
      key: Key('checkin_cal_dia_$dia'),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borda, width: hoje ? 2 : 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$dia',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: feito ? AppColors.primaryDark : AppColors.textSubtle)),
          meio,
          Text(
            _temPremio ? _curto(m!.titulo.tr) : (tokens > 0 ? 'tokens'.tr : ''),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 8.5, height: 1.05, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  static String _curto(String t) {
    final s = t.replaceFirst(RegExp(r'^(um|uma|o|a|os|as)\s+', caseSensitive: false), '');
    return s.isEmpty ? t : '${s[0].toUpperCase()}${s.substring(1)}';
  }
}

class _Progresso extends StatelessWidget {
  const _Progresso({required this.estado});

  final CheckinPremiosEstado estado;

  @override
  Widget build(BuildContext context) {
    final e = estado;
    final total = e.cicloDias <= 0 ? 30 : e.cicloDias;
    final valor = (e.diaMarco / total).clamp(0.0, 1.0);
    final prox = e.proximo;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            e.diasSeguidos == 0
                ? 'Começa hoje a tua sequência.'.tr
                : 'Estás no dia {0} de {1}.'.trArgs([e.diaMarco, total]),
            key: const Key('checkin_mes_dia'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: valor,
              minHeight: 8,
              backgroundColor: const Color(0xFFDCFCE7),
              color: AppColors.primary,
            ),
          ),
          if (prox != null) ...[
            const SizedBox(height: 8),
            Text(
              prox.faltam <= 1
                  ? 'Falta 1 dia para ganhares {0}.'.trArgs([prox.titulo.tr])
                  : 'Faltam {0} dias para ganhares {1}.'.trArgs([prox.faltam, prox.titulo.tr]),
              key: const Key('checkin_mes_proximo'),
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _MarcoLinha extends StatelessWidget {
  const _MarcoLinha({required this.marco, required this.diaMarco});

  final CheckinMarco marco;
  final int diaMarco;

  IconData get _icone => switch (marco.tipo) {
        'tokens' => Icons.toll_rounded,
        'servico' => Icons.cleaning_services_outlined,
        _ => Icons.card_giftcard,
      };

  @override
  Widget build(BuildContext context) {
    final feito = marco.atingido;
    return Container(
      key: Key('checkin_marco_${marco.dia}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: feito ? const Color(0xFFDCFCE7) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: feito ? AppColors.primary : const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: feito ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: feito ? AppColors.primary : const Color(0xFFE5E7EB)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${marco.dia}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: feito ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                Text(
                  'dias'.tr,
                  style: TextStyle(fontSize: 9.5, color: feito ? Colors.white : AppColors.textSubtle),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_icone, size: 15, color: AppColors.primaryDark),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        marco.tipo == 'tokens' && marco.tokens != null
                            ? '{0} tokens'.trArgs([marco.tokens])
                            : marco.titulo.tr,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                if (marco.descricao.isNotEmpty)
                  Text(
                    marco.descricao.tr,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            feito
                ? 'Ganho'.tr
                : (marco.faltam == 1 ? 'Falta 1 dia'.tr : 'Faltam {0} dias'.trArgs([marco.faltam])),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: feito ? AppColors.primaryDark : AppColors.textSubtle,
            ),
          ),
        ],
      ),
    );
  }
}
