// lib/widgets/home/checkin_diario_card.dart
//
// Cartão "Check-in diário" da home do cliente (Bora Todo Dia, 13/10/2026).
// Mostra os 7 dias do ciclo com os tokens de cada um, destaca o de hoje e tem o
// botão verde "Fazer check-in". Depois de feito: "Volta amanhã para ganhar X
// tokens", com os tokens a entrar e o saldo a contar até ao novo valor.
//
// Tudo vem do servidor (`CheckinService`): se o check-in estiver desligado, se
// a função ainda não existir, ou se o pedido falhar, o cartão não aparece.
// Sem telemóvel válido na ficha: "Confirma o teu telemóvel para ganhar tokens"
// e o botão abre o ecrã de completar perfil que já existe.
// Sem laranja: a home já tem o seu elemento laranja (regra 1 por ecrã).
// PT-PT com `.tr` (o cliente tem alternador PT/EN).
import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../l10n/tr.dart';
import '../../screens/client/checkin_premios_screen.dart';
import '../../screens/complete_profile_screen.dart';
import '../../services/checkin_premios_service.dart';
import '../../services/checkin_service.dart';
import '../../services/wallet_service.dart';
import '../checkin/checkin_mes_sheet.dart';
import '../checkin/confete.dart';

class CheckinDiarioCard extends StatefulWidget {
  const CheckinDiarioCard({
    super.key,
    this.carregar,
    this.fazer,
    this.confirmarTelemovel,
    this.carregarPremios,
    this.abrirPremios,
    this.marcarVistos,
  });

  /// Lê o estado de hoje. Por omissão, `CheckinService.instance.estado`.
  final Future<CheckinEstado?> Function()? carregar;

  /// Faz o check-in. Por omissão, `CheckinService.instance.fazerCheckin`.
  final Future<CheckinEstado> Function()? fazer;

  /// Abre a confirmação do telemóvel. Por omissão, o ecrã de completar perfil.
  final Future<void> Function(BuildContext context)? confirmarTelemovel;

  /// Marcos do mês e vales (Bloco D, 21/10/2026). Por omissão,
  /// `CheckinPremiosService.instance.estado`. `null` = sem marcos (a semana
  /// fica exatamente como antes).
  final Future<CheckinPremiosEstado?> Function()? carregarPremios;

  /// Abre "Os meus prémios". Por omissão, o ecrã [CheckinPremiosScreen].
  final Future<void> Function(BuildContext context)? abrirPremios;

  /// Marca a festa de um prémio como vista. Por omissão, o servidor.
  final Future<void> Function(List<String> ids)? marcarVistos;

  @override
  State<CheckinDiarioCard> createState() => _CheckinDiarioCardState();
}

class _CheckinDiarioCardState extends State<CheckinDiarioCard>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const Color _verdeClaro = Color(0xFFDCFCE7);
  static const Color _cinza = Color(0xFFF3F4F6);
  static const Color _borda = Color(0xFFE5E7EB);

  CheckinEstado? _estado;
  bool _aFazer = false;
  bool _falhou = false;
  int _ganhos = 0;
  int? _saldo;

  // Marcos do check-in: vista do mês (seta) e festa quando nasce um prémio.
  CheckinPremiosEstado? _premios;
  String? _premioNovo;
  bool _confete = false;

  // Criado no initState, nunca "à preguiça": com o cartão escondido o
  // controlador nunca era lido e nascia dentro do dispose(), a procurar o
  // TickerMode num elemento já desativado (rebentou no CI, Flutter 3.41).
  late final AnimationController _entrada;

  @override
  void initState() {
    super.initState();
    _entrada = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    WidgetsBinding.instance.addObserver(this);
    unawaited(_carregar());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _entrada.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A app pode ficar aberta de um dia para o outro: ao voltar, relê-se.
    if (state == AppLifecycleState.resumed && !_aFazer) unawaited(_carregar());
  }

  /// Sobe a cada leitura e a cada check-in: uma leitura que chegue depois do
  /// check-in (lançada antes dele) é ignorada em vez de repor o botão.
  int _versao = 0;

  Future<void> _carregar() async {
    final minha = ++_versao;
    final e = await (widget.carregar ?? CheckinService.instance.estado)();
    if (!mounted || minha != _versao) return;
    unawaited(_lerPremios());
    // A tentativa que falhou por tempo pode ter ficado gravada no servidor:
    // se a releitura já a mostra feita, o perfil volta a ler o saldo.
    if (_falhou && e != null && e.alreadyDone) WalletService.saldoMudou.value++;
    setState(() {
      _falhou = false;
      _estado = e;
      // O saldo e o "Ganhaste" só valem logo a seguir ao check-in; numa
      // releitura (ex.: voltar à app depois de gastar tokens) somem.
      _saldo = null;
      _ganhos = 0;
    });
  }

  /// Lê os marcos; se houver um prémio que o cliente ainda não viu, faz a festa.
  Future<void> _lerPremios() async {
    final p = await (widget.carregarPremios ?? CheckinPremiosService.instance.estado)();
    if (!mounted) return;
    String? novo;
    if (p != null && p.marcosAtivos && p.novos.isNotEmpty) {
      for (final v in p.vales) {
        if (p.novos.contains(v.id)) {
          novo = v.titulo;
          break;
        }
      }
    }
    setState(() {
      _premios = (p != null && p.marcosAtivos) ? p : null;
      if (novo != null) {
        _premioNovo = novo;
        _confete = true;
      }
    });
    if (novo != null && p != null) {
      unawaited((widget.marcarVistos ?? CheckinPremiosService.instance.marcarVistos)(p.novos));
    }
  }

  Future<void> _abrirPremios() async {
    final abrir = widget.abrirPremios ??
        (BuildContext ctx) => Navigator.of(ctx).push<void>(
              MaterialPageRoute(builder: (_) => const CheckinPremiosScreen()),
            );
    await abrir(context);
    if (mounted) unawaited(_lerPremios());
  }

  void _abrirMes() {
    final p = _premios;
    if (p == null) return;
    mostrarCheckinMes(context, p, abrirPremios: _abrirPremios);
  }

  Future<void> _fazer() async {
    if (_aFazer) return;
    final anteriorFalhou = _falhou;
    _versao++;
    setState(() {
      _aFazer = true;
      _falhou = false;
    });
    try {
      final r = await (widget.fazer ?? CheckinService.instance.fazerCheckin)();
      if (!mounted) return;
      _versao++;
      final ganhos = r.tokensAwarded ?? 0;
      setState(() {
        _aFazer = false;
        _estado = r;
        _ganhos = ganhos;
        _saldo = r.balance ?? _saldo;
      });
      if (ganhos > 0) unawaited(_entrada.forward(from: 0));
      // O gatilho do servidor pode ter dado o prémio de um marco agora mesmo.
      unawaited(_lerPremios());
      // O saldo mostrado noutros ecrãs (perfil) volta a ser lido. Também quando
      // a tentativa anterior falhou por tempo: o servidor pode tê-la gravado.
      if (ganhos > 0 || (anteriorFalhou && r.alreadyDone)) {
        WalletService.saldoMudou.value++;
      }
    } catch (e) {
      debugPrint('[CheckinDiarioCard] fazer: $e');
      if (!mounted) return;
      setState(() {
        _aFazer = false;
        _falhou = true;
      });
    }
  }

  Future<void> _confirmarTelemovel() async {
    final abrir = widget.confirmarTelemovel ??
        (BuildContext ctx) => Navigator.of(ctx).push<bool>(
              MaterialPageRoute(builder: (_) => const CompleteProfileScreen()),
            );
    await abrir(context);
    if (mounted) await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final e = _estado;
    if (e == null || !e.mostrarCartao) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xl),
      child: Container(
        key: const Key('checkin_diario_card'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _borda),
          boxShadow: AppColors.shadowCard,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _cabecalho(),
                const SizedBox(height: 4),
                Text(
                  e.semTelemovel
                      ? 'Confirma o teu telemóvel para ganhar tokens'.tr
                      : 'Entra todos os dias e ganha mais tokens. Se falhares um dia, voltas ao Dia 1.'
                          .tr,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textSubtle, height: 1.3),
                ),
                const SizedBox(height: 10),
                _dias(e),
                const SizedBox(height: 12),
                _rodape(e),
                if (_premioNovo != null) ...[
                  const SizedBox(height: 10),
                  _premioGanho(_premioNovo!),
                ],
              ],
            ),
            Positioned(
              right: 0,
              top: 0,
              child: IgnorePointer(child: _tokensAEntrar()),
            ),
            if (_confete)
              Positioned.fill(
                child: Confete(
                  onFim: () {
                    if (mounted) setState(() => _confete = false);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cabecalho() {
    return Row(
      children: [
        const Icon(Icons.event_available, color: AppColors.primary, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Check-in diário'.tr,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
        if (_premios != null)
          IconButton(
            key: const Key('btn_checkin_mes'),
            tooltip: 'Ver os prémios do mês'.tr,
            visualDensity: VisualDensity.compact,
            onPressed: _abrirMes,
            icon: const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
          ),
        if (_saldo != null)
          TweenAnimationBuilder<int>(
            key: const Key('checkin_saldo'),
            tween: IntTween(
                begin: (_saldo! - _ganhos).clamp(0, _saldo!), end: _saldo!),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOut,
            builder: (_, v, __) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _verdeClaro,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Saldo: {0} tokens'.trArgs(['$v']),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _dias(CheckinEstado e) {
    return Row(
      children: [
        for (var dia = 1; dia <= 7; dia++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _caixaDia(
                dia: dia,
                tokens: e.rewards[dia - 1],
                feito: dia < e.streakDay || (e.alreadyDone && dia == e.streakDay),
                hoje: dia == e.streakDay,
              ),
            ),
          ),
      ],
    );
  }

  Widget _caixaDia({
    required int dia,
    required int tokens,
    required bool feito,
    required bool hoje,
  }) {
    final Color fundo = feito ? AppColors.primary : (hoje ? _verdeClaro : _cinza);
    final Color texto = feito
        ? Colors.white
        : (hoje ? AppColors.primaryDark : AppColors.textSubtle);
    return Column(
      key: Key('checkin_dia_$dia'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 46,
          decoration: BoxDecoration(
            color: fundo,
            borderRadius: BorderRadius.circular(10),
            border: hoje && !feito
                ? Border.all(color: AppColors.primary, width: 2)
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                feito
                    ? Icons.check_rounded
                    : (dia == 7 ? Icons.star_rounded : Icons.toll_rounded),
                size: 14,
                color: texto,
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '+$tokens',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: texto,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Dia {0}'.trArgs(['$dia']),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: hoje ? FontWeight.w700 : FontWeight.w500,
              color: hoje ? AppColors.primaryDark : AppColors.textSubtle,
            ),
          ),
        ),
      ],
    );
  }

  Widget _rodape(CheckinEstado e) {
    if (e.semTelemovel) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          key: const Key('btn_checkin_confirmar_telemovel'),
          onPressed: _confirmarTelemovel,
          icon: const Icon(Icons.phone_iphone, size: 18),
          label: Text('Confirmar telemóvel'.tr),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      );
    }

    if (e.alreadyDone) {
      return Row(
        key: const Key('checkin_feito'),
        children: [
          const Icon(Icons.check_circle, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_ganhos > 0)
                  Text(
                    'Ganhaste {0} tokens!'.trArgs(['$_ganhos']),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                Text(
                  'Volta amanhã para ganhar {0} tokens.'
                      .trArgs(['${e.nextReward}']),
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textSubtle),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          key: const Key('btn_checkin'),
          // Trava-se pelo SEU pedido (PADRAO 3.13), nunca por um estado global.
          onPressed: _aFazer ? null : _fazer,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          // Estilo no Text (herda a Inter do tema); no textStyle do botão
          // substituía a fonte inteira.
          child: Text(
            _aFazer ? 'A fazer check-in…'.tr : 'Fazer check-in'.tr,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
        if (_falhou) ...[
          const SizedBox(height: 6),
          Text(
            'Não foi possível fazer o check-in. Tenta de novo.'.tr,
            style: TextStyle(fontSize: 12, color: Colors.red.shade900),
          ),
        ],
      ],
    );
  }

  /// Faixa do prémio novo de um marco ("Ganhaste 2 salgados da Keli! Ver").
  Widget _premioGanho(String titulo) {
    return Container(
      key: const Key('checkin_premio_novo'),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: _verdeClaro,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.card_giftcard, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Ganhaste {0}!'.trArgs([titulo.tr]),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
            ),
          ),
          TextButton(
            key: const Key('btn_ver_premio'),
            onPressed: () {
              setState(() => _premioNovo = null);
              _abrirPremios();
            },
            child: Text('Ver'.tr),
          ),
        ],
      ),
    );
  }

  /// "+X tokens" a subir e a desaparecer, logo a seguir ao check-in.
  Widget _tokensAEntrar() {
    return AnimatedBuilder(
      animation: _entrada,
      builder: (_, __) {
        final v = _entrada.value;
        if (_ganhos <= 0 || v == 0 || v == 1) return const SizedBox.shrink();
        final t = Curves.easeOut.transform(v);
        return Transform.translate(
          offset: Offset(0, 34 - 34 * t),
          child: Opacity(
            opacity: v < 0.7 ? 1 : (1 - (v - 0.7) / 0.3).clamp(0.0, 1.0),
            child: Container(
              key: const Key('checkin_tokens_a_entrar'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(999),
                boxShadow: AppColors.shadowCard,
              ),
              child: Text(
                '+{0} tokens'.trArgs(['$_ganhos']),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
