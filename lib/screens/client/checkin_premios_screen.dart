// lib/screens/client/checkin_premios_screen.dart
//
// "Os meus prémios" (Bloco D, 21/10/2026): os vales dos marcos do check-in.
// Por usar → "Usar" (produto: abre a loja certa com o prémio no carrinho) ou
// "Escolher" (30 dias: limpeza de 2 h ou lavagem exterior). Guardado (tecto do
// mês) e "Falta 1 pedido" dizem o que falta. Usados/expirados ficam por baixo.
// Escada de prémios (29/10/2026): com a escada ligada, o texto da regra em
// destaque, o prémio guardado com "Levantar" e os degraus (10, 15, 30) a dizer
// qual está guardado e qual é o próximo.
import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../l10n/tr.dart';
import '../../services/checkin_premios_service.dart';
import '../../utils/premio_checkin_fluxo.dart';
import '../../widgets/checkin/checkin_mes_sheet.dart';
import 'checkin_premio_servico_screen.dart';

class CheckinPremiosScreen extends StatefulWidget {
  const CheckinPremiosScreen({
    super.key,
    this.carregar,
    this.usarProduto,
    this.escolherServico,
    this.levantarEscada,
  });

  final Future<CheckinPremiosEstado?> Function()? carregar;
  final Future<void> Function(BuildContext context, CheckinVale vale)? usarProduto;
  final Future<void> Function(BuildContext context, CheckinVale vale)? escolherServico;

  /// Escada: "Levantar". Por omissão, `CheckinPremiosService.instance.levantar`.
  final Future<CheckinEscadaResultado> Function()? levantarEscada;

  @override
  State<CheckinPremiosScreen> createState() => _CheckinPremiosScreenState();
}

class _CheckinPremiosScreenState extends State<CheckinPremiosScreen> {
  CheckinPremiosEstado? _estado;
  bool _aCarregar = true;
  String? _aUsar;
  bool _aLevantar = false;

  @override
  void initState() {
    super.initState();
    _ler();
  }

  Future<void> _ler() async {
    final e = await (widget.carregar ?? CheckinPremiosService.instance.estado)();
    if (!mounted) return;
    setState(() {
      _estado = e;
      _aCarregar = false;
    });
    if (e != null && e.novos.isNotEmpty) {
      await CheckinPremiosService.instance.marcarVistos(e.novos);
    }
  }

  Future<void> _usar(CheckinVale v) async {
    if (_aUsar != null) return;
    setState(() => _aUsar = v.id);
    try {
      if (v.ehProduto) {
        await (widget.usarProduto ?? usarPremioProduto)(context, v);
      } else {
        await (widget.escolherServico ??
            (ctx, vale) => Navigator.of(ctx).push(MaterialPageRoute<void>(
                  builder: (_) => CheckinPremioServicoScreen(vale: vale),
                )))(context, v);
      }
    } finally {
      if (mounted) setState(() => _aUsar = null);
      await _ler();
    }
  }

  Future<void> _levantar() async {
    if (_aLevantar) return;
    setState(() => _aLevantar = true);
    final r = await (widget.levantarEscada ?? CheckinPremiosService.instance.levantar)();
    if (!mounted) return;
    setState(() => _aLevantar = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.ok ? 'Prémio levantado! Já está em "Por usar".'.tr : mensagemErroEscada(r.reason)),
    ));
    await _ler();
  }

  @override
  Widget build(BuildContext context) {
    final e = _estado;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('Os meus prémios'.tr)),
      body: _aCarregar
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _ler,
              child: ListView(
                key: const Key('lista_premios'),
                padding: const EdgeInsets.all(16),
                children: [
                  if (e == null)
                    _vazio('Não foi possível ver os teus prémios. Puxa para tentar de novo.'.tr)
                  else ...[
                    if (e.marcos.isNotEmpty)
                      OutlinedButton.icon(
                        key: const Key('btn_ver_marcos'),
                        onPressed: () => mostrarCheckinMes(context, e),
                        icon: const Icon(Icons.calendar_month_outlined, size: 18),
                        label: Text(e.diasSeguidos > 0
                            ? 'Os marcos do check-in · dia {0}'.trArgs([e.diaMarco])
                            : 'Os marcos do check-in'.tr),
                      ),
                    const SizedBox(height: 12),
                    if (e.escadaAtiva) ...[
                      _EscadaCartao(estado: e, aLevantar: _aLevantar, onLevantar: _levantar),
                      const SizedBox(height: 12),
                    ],
                    if (e.porUsar.isEmpty && e.historico.isEmpty)
                      _vazio('Ainda não tens prémios. Faz o check-in todos os dias: aos 10 dias seguidos ganhas o primeiro.'.tr),
                    if (e.porUsar.isNotEmpty) ...[
                      _titulo('Por usar'.tr),
                      for (final v in e.porUsar) _ValeCartao(vale: v, aUsar: _aUsar == v.id, onUsar: () => _usar(v)),
                    ],
                    if (e.historico.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _titulo('Usados e expirados'.tr),
                      for (final v in e.historico) _ValeCartao(vale: v, aUsar: false, onUsar: null),
                    ],
                  ],
                ],
              ),
            ),
    );
  }

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      );

  Widget _vazio(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(t, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
      );
}

String _data(DateTime? d) {
  if (d == null) return '';
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${dois(d.day)}/${dois(d.month)}';
}

class _ValeCartao extends StatelessWidget {
  const _ValeCartao({required this.vale, required this.aUsar, required this.onUsar});

  final CheckinVale vale;
  final bool aUsar;
  final VoidCallback? onUsar;

  String _subtitulo() {
    final v = vale;
    switch (v.estado) {
      case 'por_usar':
      case 'reservado':
        final onde = v.ehProduto && (v.lojaNome ?? '').isNotEmpty ? '${v.lojaNome} · ' : '';
        return '$onde${'Vale até {0}'.trArgs([_data(v.validoAte)])}';
      case 'guardado':
        return 'Este mês já não há mais prémios de {0} dias. Fica disponível a {1}.'
            .trArgs([v.marco, _data(v.ativarEm)]);
      case 'a_espera_pedido':
        return 'Falta 1 pedido para desbloquear o prémio. Tens até {0}.'.trArgs([_data(v.esperarAte)]);
      case 'usado':
        return 'Usado a {0}'.trArgs([_data(v.usadoEm)]);
      case 'expirado':
        return 'Expirou a {0}'.trArgs([_data(v.validoAte ?? v.esperarAte)]);
      default:
        return textoEstadoVale(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = vale;
    final podeUsar = onUsar != null && v.usavel;
    return Card(
      key: Key('vale_${v.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: podeUsar ? AppColors.primary : const Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: podeUsar ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${v.marco}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(v.titulo.tr, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(_subtitulo(), style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.3)),
                ],
              ),
            ),
            if (podeUsar) ...[
              const SizedBox(width: 8),
              FilledButton(
                key: Key('btn_usar_${v.id}'),
                onPressed: aUsar ? null : onUsar,
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: Text(aUsar ? '…' : (v.ehProduto ? 'Usar'.tr : 'Escolher'.tr)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Escada de prémios: a regra em destaque, o prémio guardado com "Levantar" e
/// os degraus a dizer qual está guardado e qual é o próximo.
class _EscadaCartao extends StatelessWidget {
  const _EscadaCartao({required this.estado, required this.aLevantar, required this.onLevantar});

  final CheckinPremiosEstado estado;
  final bool aLevantar;
  final VoidCallback onLevantar;

  @override
  Widget build(BuildContext context) {
    final esc = estado.escada!;
    final g = esc.guardado;
    final prox = esc.proximoMaior;
    final degraus = estado.marcos.where((m) => m.tipo != 'tokens').toList()
      ..sort((a, b) => a.dia.compareTo(b.dia));
    return Container(
      key: const Key('premios_escada'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (esc.texto.isNotEmpty)
            Text(
              esc.texto.tr,
              key: const Key('premios_escada_texto'),
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, height: 1.35, color: AppColors.primaryDark),
            ),
          if (g != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.bookmark_added_outlined, color: AppColors.primaryDark, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    g.garantidoAte == null
                        ? 'Tens guardado: {0}'.trArgs([g.titulo.tr])
                        : 'Tens guardado: {0} até {1}'.trArgs([g.titulo.tr, _data(g.garantidoAte)]),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('btn_escada_levantar_ecra'),
                  onPressed: aLevantar ? null : onLevantar,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                  child: Text(aLevantar ? '…' : 'Levantar'.tr),
                ),
              ],
            ),
          ],
          if (degraus.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final m in degraus)
              _DegrauLinha(
                marco: m,
                guardado: g?.chave == m.chave,
                proximo: prox?.chave == m.chave ? prox : null,
              ),
          ],
        ],
      ),
    );
  }
}

class _DegrauLinha extends StatelessWidget {
  const _DegrauLinha({required this.marco, required this.guardado, this.proximo});

  final CheckinMarco marco;
  final bool guardado;
  final CheckinDegrau? proximo;

  @override
  Widget build(BuildContext context) {
    final p = proximo;
    final String? etiqueta = guardado
        ? 'Guardado'.tr
        : (p == null
            ? null
            : (p.faltam == 1 ? 'Próximo · falta 1 dia'.tr : 'Próximo · faltam {0} dias'.trArgs([p.faltam])));
    return Padding(
      key: Key('degrau_${marco.dia}'),
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: guardado ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: guardado || p != null ? AppColors.primary : const Color(0xFFE5E7EB)),
            ),
            child: Text(
              '${marco.dia}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: guardado ? Colors.white : AppColors.primaryDark,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(marco.titulo.tr, style: const TextStyle(fontSize: 13, height: 1.3)),
          ),
          if (etiqueta != null) ...[
            const SizedBox(width: 8),
            Text(
              etiqueta,
              key: Key('degrau_${marco.dia}_etiqueta'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
            ),
          ],
        ],
      ),
    );
  }
}
