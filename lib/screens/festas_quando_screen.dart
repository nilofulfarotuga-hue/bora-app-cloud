import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../models/restaurant_model.dart';
import '../widgets/bora/bora_screen_app_bar.dart';

/// Passo do checkout **só para lojas de festas**: escolher o dia e a hora da
/// encomenda.
///
/// Os dias que não cumprem o aviso prévio ([kFestasAvisoHoras]) aparecem
/// riscados — visíveis, com a razão à vista, para a pessoa perceber porquê.
/// Devolve o [DateTime] escolhido, ou `null` se voltar atrás.
class FestasQuandoScreen extends StatefulWidget {
  const FestasQuandoScreen({
    super.key,
    this.horaAbertura = 9,
    this.horaFecho = 20,
    this.inicial,
    this.encomendaGrande = false,
  });

  /// Encomenda grande (Cento no carrinho ou total >= €40): 3 dias de aviso.
  final bool encomendaGrande;

  /// Horário da loja (`business_hours`). O padrão é o da Sabores do Brasil.
  final int horaAbertura;
  final int horaFecho;
  final DateTime? inicial;

  @override
  State<FestasQuandoScreen> createState() => _FestasQuandoScreenState();
}

class _FestasQuandoScreenState extends State<FestasQuandoScreen> {
  late DateTime _mes;
  DateTime? _dia;
  int? _hora;

  /// A partir daqui a loja já consegue preparar a encomenda.
  late final DateTime _minimo;

  static const _nomesMes = [
    'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
    'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
  ];

  @override
  void initState() {
    super.initState();
    _minimo = DateTime.now().add(Duration(
        days: widget.encomendaGrande
            ? kFestasAvisoDiasGrande
            : kFestasAvisoDiasNormal));
    final agora = DateTime.now();
    _mes = DateTime(agora.year, agora.month);
    final ini = widget.inicial;
    if (ini != null) {
      _mes = DateTime(ini.year, ini.month);
      _dia = DateTime(ini.year, ini.month, ini.day);
      _hora = ini.hour;
    }
  }

  bool _cedoDemais(DateTime dia) {
    // O dia serve se a última hora de recolha desse dia já respeita o aviso.
    final fim = DateTime(dia.year, dia.month, dia.day, widget.horaFecho);
    return fim.isBefore(_minimo);
  }

  bool get _podeRecuar {
    final minMes = DateTime(_minimo.year, _minimo.month);
    return _mes.isAfter(minMes);
  }

  List<int> get _horasPossiveis {
    final d = _dia;
    final out = <int>[];
    for (var h = widget.horaAbertura; h <= widget.horaFecho; h++) {
      if (d != null) {
        final quando = DateTime(d.year, d.month, d.day, h);
        if (quando.isBefore(_minimo)) continue;
      }
      out.add(h);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final pronto = _dia != null && _hora != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Quando queres?'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.md, Spacing.lg, Spacing.xxl),
        children: [
          _Cartao(child: _calendario()),
          const SizedBox(height: Spacing.md),
          _Cartao(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Hora',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  'A loja está aberta das ${widget.horaAbertura}h '
                  'às ${widget.horaFecho}h.',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: Spacing.sm),
                if (_dia == null)
                  Text('Escolhe primeiro o dia.',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _horasPossiveis.map((h) {
                      final on = _hora == h;
                      return _Pastilha(
                        texto: '${h.toString().padLeft(2, '0')}:00',
                        activa: on,
                        onTap: () => setState(() => _hora = h),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.md),
          Container(
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              border: Border.all(color: const Color(0xFFFED7AA)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Os dias riscados não cumprem o aviso prévio. '
              'Encomendas grandes pedem $kFestasAvisoDiasGrande dias; '
              'as restantes, $kFestasAvisoDiasNormal dia.',
              style: const TextStyle(
                  fontSize: 12.5, color: Color(0xFF9A3412), height: 1.5),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.sm, Spacing.lg, Spacing.md),
        child: SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: pronto
                ? () => Navigator.pop(
                      context,
                      DateTime(_dia!.year, _dia!.month, _dia!.day, _hora!),
                    )
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Continuar',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ),
      ),
    );
  }

  Widget _calendario() {
    final primeiro = DateTime(_mes.year, _mes.month, 1);
    final desloca = (primeiro.weekday - 1) % 7; // semana começa à segunda
    final dias = DateTime(_mes.year, _mes.month + 1, 0).day;

    final celulas = <Widget>[];
    for (final d in const ['S', 'T', 'Q', 'Q', 'S', 'S', 'D']) {
      celulas.add(Center(
        child: Text(d,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary)),
      ));
    }
    for (var i = 0; i < desloca; i++) {
      celulas.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= dias; d++) {
      final dia = DateTime(_mes.year, _mes.month, d);
      final cedo = _cedoDemais(dia);
      final on = _dia != null &&
          _dia!.year == dia.year &&
          _dia!.month == dia.month &&
          _dia!.day == dia.day;
      celulas.add(_DiaCelula(
        numero: d,
        riscado: cedo,
        activo: on,
        onTap: cedo
            ? null
            : () => setState(() {
                  _dia = dia;
                  if (_hora != null &&
                      DateTime(dia.year, dia.month, dia.day, _hora!)
                          .isBefore(_minimo)) {
                    _hora = null;
                  }
                }),
      ));
    }

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              onPressed: _podeRecuar
                  ? () => setState(
                      () => _mes = DateTime(_mes.year, _mes.month - 1))
                  : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                '${_nomesMes[_mes.month - 1]} de ${_mes.year}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              onPressed: () => setState(
                  () => _mes = DateTime(_mes.year, _mes.month + 1)),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          children: celulas,
        ),
      ],
    );
  }
}

class _Cartao extends StatelessWidget {
  const _Cartao({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      );
}

class _DiaCelula extends StatelessWidget {
  const _DiaCelula({
    required this.numero,
    required this.riscado,
    required this.activo,
    this.onTap,
  });

  final int numero;
  final bool riscado;
  final bool activo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: activo
          ? AppColors.primary
          : (riscado ? const Color(0xFFF7F7F6) : AppColors.surface),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Center(
          child: Text(
            '$numero',
            style: TextStyle(
              fontSize: 13,
              fontWeight: riscado ? FontWeight.w500 : FontWeight.w700,
              color: activo
                  ? Colors.white
                  : (riscado
                      ? const Color(0xFFC7CDC9)
                      : AppColors.textPrimary),
              decoration:
                  riscado ? TextDecoration.lineThrough : TextDecoration.none,
              decorationColor: const Color(0xFFC7CDC9),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pastilha extends StatelessWidget {
  const _Pastilha(
      {required this.texto, required this.activa, required this.onTap});

  final String texto;
  final bool activa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: activa ? AppColors.primary : AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: activa ? AppColors.primary : AppColors.dividerStrong,
                width: 1.5),
          ),
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: activa ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
