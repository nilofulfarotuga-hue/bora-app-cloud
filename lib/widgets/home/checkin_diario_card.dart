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
//
// Com os marcos ligados (29/10/2026):
//  - a faixa mostra a SEMANA ATUAL da sequência (no dia 12: Dia 8 a 14), com os
//    tokens de cada dia tirados do ciclo de 7 a partir de hoje;
//  - a seta abre e fecha o calendário do ciclo DENTRO do cartão;
//  - escada de prémios: ao chegar a um degrau há festa (confete, som curto e
//    vibração, uma vez por degrau) e a escolha "Levantar agora" / "Continuar";
//    com um prémio guardado sem escolha pendente, uma linha "Tens guardado".
//
// Bloco G (10/11/2026, "faça uma coisa bem bonita"):
//  - o mês abre num CAMINHO de 30 dias (chama nos feitos, gelo no dia perdoado,
//    hoje a brilhar, foto real e valor em euros em cada prémio);
//  - barra "Faltam X dias para o açaí" com a foto do próximo prémio;
//  - confete pequeno a cada check-in e festa grande ao chegar a um degrau, com o
//    prémio em grande e "Quero este" / "Continuar para o próximo" (R3);
//  - "Falta 1 pedido para desbloquear" (R2), aviso do perdão do mês (R5) e o
//    botão do lembrete diário (R8).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../l10n/tr.dart';
import '../../screens/client/checkin_premios_screen.dart';
import '../../screens/complete_profile_screen.dart';
import '../../services/checkin_premios_service.dart';
import '../../services/checkin_service.dart';
import '../../services/sound_service.dart';
import '../../services/wallet_service.dart';
import '../../utils/checkin_regras.dart';
import '../checkin/checkin_barra_proximo.dart';
import '../checkin/checkin_caminho.dart';
import '../checkin/checkin_festa_premio.dart';
import '../checkin/confete.dart';

/// Festa de chegar a um degrau da escada: vibração forte e o som curto da Bora.
/// Nunca rebenta (sem vibrador, sem som, na web).
Future<void> festaDoDegrau() async {
  try {
    await HapticFeedback.heavyImpact();
  } catch (_) {}
  if (!kIsWeb) {
    try {
      if (await Vibration.hasVibrator()) await Vibration.vibrate(duration: 300);
    } catch (_) {}
  }
  try {
    final som = SoundService();
    await som.playOnce();
    unawaited(Future<void>.delayed(const Duration(seconds: 3), som.dispose));
  } catch (_) {
    unawaited(SystemSound.play(SystemSoundType.alert));
  }
}

class CheckinDiarioCard extends StatefulWidget {
  const CheckinDiarioCard({
    super.key,
    this.carregar,
    this.fazer,
    this.confirmarTelemovel,
    this.carregarPremios,
    this.abrirPremios,
    this.marcarVistos,
    this.levantarEscada,
    this.continuarEscada,
    this.festaEscada,
    this.marcarPerdaoVisto,
    this.definirLembrete,
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

  /// Escada: "Levantar agora". Por omissão, `CheckinPremiosService.instance.levantar`.
  final Future<CheckinEscadaResultado> Function()? levantarEscada;

  /// Escada: "Continuar". Por omissão, `CheckinPremiosService.instance.continuar`.
  final Future<CheckinEscadaResultado> Function()? continuarEscada;

  /// Som e vibração da festa do degrau. Por omissão, [festaDoDegrau].
  final Future<void> Function()? festaEscada;

  /// R5: o aviso do perdão já se viu. Por omissão, o servidor.
  final Future<void> Function()? marcarPerdaoVisto;

  /// R8: liga/desliga o lembrete diário. Por omissão, o servidor.
  final Future<bool> Function(bool ligado)? definirLembrete;

  @override
  State<CheckinDiarioCard> createState() => _CheckinDiarioCardState();
}

class _CheckinDiarioCardState extends State<CheckinDiarioCard>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const Color _verdeClaro = Color(0xFFDCFCE7);
  static const Color _verdeFundo = Color(0xFFF0FDF4);
  static const Color _cinza = Color(0xFFF3F4F6);
  static const Color _borda = Color(0xFFE5E7EB);

  /// Marca local da festa do degrau (uma vez por `guardado_em`).
  static const String _chaveFestaEscada = 'checkin_escada_festa_vista';

  CheckinEstado? _estado;
  bool _aFazer = false;
  bool _falhou = false;
  int _ganhos = 0;
  int? _saldo;

  // Marcos do check-in: vista do mês (seta) e festa quando nasce um prémio.
  CheckinPremiosEstado? _premios;
  String? _premioNovo;
  bool _confete = false;

  // Calendário do ciclo aberto dentro do cartão.
  bool _mesAberto = false;

  // Escada: escolha a caminho do servidor, erro curto e festa já feita.
  bool _aDecidir = false;
  String? _erroEscada;
  String? _festaEscadaFeita;

  // Bloco G: tamanho do confete (pequeno no check-in, grande no degrau), uma
  // série por festa (chave nova = confete novo), o aviso do perdão e o lembrete.
  int _quantosConfetes = 38;
  int _serieConfete = 0;
  bool _perdaoVisto = false;
  bool? _lembreteLigado;
  bool _aGravarLembrete = false;

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
    final ativos = (p != null && p.marcosAtivos) ? p : null;
    setState(() {
      _premios = ativos;
      if (ativos == null) _mesAberto = false;
      if (novo != null) {
        _premioNovo = novo;
        _confete = true;
        _quantosConfetes = 38;
        _serieConfete++;
      }
    });
    if (novo != null && p != null) {
      unawaited((widget.marcarVistos ?? CheckinPremiosService.instance.marcarVistos)(p.novos));
    }
    if (ativos != null) unawaited(_talvezFestaDoDegrau(ativos));
  }

  /// Chegou a um degrau e ainda não escolheu: festa uma vez por degrau
  /// (marca guardada no telemóvel; se as preferências falharem, faz-se na mesma).
  Future<void> _talvezFestaDoDegrau(CheckinPremiosEstado p) async {
    final esc = p.escada;
    final g = esc?.guardado;
    if (esc == null || !esc.ativa || !esc.pendenteDecisao || g == null) return;
    final marca = '${g.chave}|${g.guardadoEmTexto}';
    if (_festaEscadaFeita == marca) return;
    _festaEscadaFeita = marca;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_chaveFestaEscada) == marca) return;
      await prefs.setString(_chaveFestaEscada, marca);
    } catch (e) {
      debugPrint('[CheckinDiarioCard] festa do degrau (preferências): $e');
    }
    if (!mounted) return;
    setState(() {
      _confete = true;
      _quantosConfetes = 90;
      _serieConfete++;
    });
    unawaited((widget.festaEscada ?? festaDoDegrau)());
  }

  Future<void> _abrirPremios() async {
    final abrir = widget.abrirPremios ??
        (BuildContext ctx) => Navigator.of(ctx).push<void>(
              MaterialPageRoute(builder: (_) => const CheckinPremiosScreen()),
            );
    await abrir(context);
    if (mounted) unawaited(_lerPremios());
  }

  void _alternarMes() {
    if (_premios == null) return;
    setState(() => _mesAberto = !_mesAberto);
  }

  /// "Levantar agora": cria o vale, a sequência volta ao dia 1.
  Future<void> _levantar() async {
    if (_aDecidir) return;
    setState(() {
      _aDecidir = true;
      _erroEscada = null;
    });
    final r = await (widget.levantarEscada ?? CheckinPremiosService.instance.levantar)();
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _aDecidir = false;
        _erroEscada = mensagemErroEscada(r.reason, proximoPremioEm: r.proximoPremioEm);
      });
      if (r.reason != 'sem_rede') unawaited(_lerPremios());
      return;
    }
    final vale = r.vale;
    setState(() {
      _aDecidir = false;
      final p = _premios;
      final est = r.estado;
      if (p != null && est != null) _premios = p.juntar(est);
      if (vale != null) _premioNovo = vale.titulo;
    });
    // O vale novo chega em `novos`: a faixa "Ganhaste… Ver" faz a festa.
    await _lerPremios();
  }

  /// "Continuar": fica com o prémio e troca por um maior no degrau seguinte.
  Future<void> _continuar() async {
    if (_aDecidir) return;
    setState(() {
      _aDecidir = true;
      _erroEscada = null;
    });
    final r = await (widget.continuarEscada ?? CheckinPremiosService.instance.continuar)();
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _aDecidir = false;
        _erroEscada = mensagemErroEscada(r.reason, proximoPremioEm: r.proximoPremioEm);
      });
      if (r.reason != 'sem_rede') unawaited(_lerPremios());
      return;
    }
    setState(() {
      _aDecidir = false;
      final p = _premios;
      final est = r.estado;
      if (p != null && est != null) _premios = p.juntar(est);
    });
    unawaited(_lerPremios());
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
      // Confete pequeno a cada check-in (a festa grande fica para os degraus).
      if (ganhos > 0 && mounted) {
        setState(() {
          _confete = true;
          _quantosConfetes = 16;
          _serieConfete++;
        });
      }
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

  /// Último dia da sequência já feito (conta o check-in de hoje mesmo antes de
  /// os marcos serem relidos).
  int _feitoAte(CheckinEstado e, CheckinPremiosEstado p) {
    if (p.hojeFeito) return p.diaMarco;
    final hoje = p.diaDeHoje;
    return e.alreadyDone ? hoje : hoje - 1;
  }

  /// Dia do ciclo de tokens (1..7) do dia [dia] da sequência: o de hoje é o
  /// `streak_day` atual; os outros, o deslocamento a partir de hoje.
  int _diaTokens(CheckinEstado e, int hojeSeq, int dia) =>
      ((e.streakDay - 1 + (dia - hojeSeq)) % 7) + 1;

  @override
  Widget build(BuildContext context) {
    final e = _estado;
    if (e == null || !e.mostrarCartao) return const SizedBox.shrink();
    final p = _premios;
    final esc = p?.escada;
    final escolha = esc != null && esc.ativa && esc.pendenteDecisao && esc.guardado != null;
    final guardado = esc != null && esc.temGuardadoSemEscolha;

    // 11/11/2026 (Danilo: "estreitar o check-in"): margens mais curtas e a
    // frase das regras só no Dia 1 de hoje por fazer (é aí que interessa);
    // as regras completas continuam no mês (seta).
    final mostrarRegra =
        e.semTelemovel || (e.streakDay <= 1 && !e.alreadyDone);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Container(
        key: const Key('checkin_diario_card'),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
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
                if (mostrarRegra) ...[
                  const SizedBox(height: 2),
                  Text(
                    e.semTelemovel
                        ? 'Confirma o teu telemóvel para ganhar tokens'.tr
                        : 'Entra todos os dias e ganha mais tokens. Se falhares um dia, voltas ao Dia 1.'
                            .tr,
                    style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSubtle,
                        height: 1.3),
                  ),
                ],
                const SizedBox(height: 6),
                _dias(e),
                ..._barraEPerdao(e),
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: (_mesAberto && p != null)
                      ? Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: _calendario(e, p),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                const SizedBox(height: 8),
                _rodape(e),
                if (escolha) ...[
                  const SizedBox(height: 10),
                  CheckinFestaPremio(
                    guardado: esc.guardado!,
                    proximo: esc.proximoMaior,
                    aDecidir: _aDecidir,
                    onQueroEste: _levantar,
                    onContinuar: _continuar,
                    texto: esc.texto,
                    precisaPedido: p?.precisaPedido ?? false,
                  ),
                ] else if (guardado) ...[
                  const SizedBox(height: 10),
                  _linhaGuardado(esc),
                ],
                if (_erroEscada != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _erroEscada!,
                    key: const Key('checkin_escada_erro'),
                    style: TextStyle(fontSize: 12, color: Colors.red.shade900),
                  ),
                ],
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
                  key: ValueKey('confete_$_serieConfete'),
                  quantidade: _quantosConfetes,
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
            tooltip: _mesAberto ? 'Fechar o mês'.tr : 'Ver os prémios do mês'.tr,
            visualDensity: VisualDensity.compact,
            onPressed: _alternarMes,
            icon: AnimatedRotation(
              turns: _mesAberto ? 0.25 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
            ),
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
    final p = _premios;
    if (p == null) {
      // Sem marcos: Dia 1 a 7 do ciclo de tokens, exatamente como antes.
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
                  estrela: dia == 7,
                ),
              ),
            ),
        ],
      );
    }

    // Com marcos: a semana atual da sequência (no dia 12 → Dia 8 a 14).
    final ciclo = p.cicloDias < 7 ? 7 : p.cicloDias;
    final hojeSeq = p.diaDeHoje;
    final feitoAte = _feitoAte(e, p);
    final semana = hojeSeq <= 0 ? 0 : (hojeSeq - 1) ~/ 7;
    final inicio = (semana * 7 + 1).clamp(1, ciclo - 6);
    final premios = {for (final m in p.marcos) if (m.tipo != 'tokens') m.dia: m};
    return Row(
      children: [
        for (var dia = inicio; dia < inicio + 7; dia++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _caixaDia(
                dia: dia,
                tokens: e.rewards[_diaTokens(e, hojeSeq, dia) - 1],
                feito: dia <= feitoAte,
                hoje: dia == hojeSeq,
                estrela: _diaTokens(e, hojeSeq, dia) == 7,
                premio: premios[dia] == null ? null : _iconeMarco(premios[dia]!),
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
    required bool estrela,
    IconData? premio,
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
                    : (premio ?? (estrela ? Icons.star_rounded : Icons.toll_rounded)),
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

  static IconData _iconeMarco(CheckinMarco m) => switch (m.tipo) {
        'tokens' => Icons.star_rounded,
        'servico' => Icons.cleaning_services_outlined,
        _ => Icons.card_giftcard,
      };

  /// Calendário do ciclo (30 dias) dentro do cartão: feitos, hoje e os marcos.
  Widget _calendario(CheckinEstado e, CheckinPremiosEstado p) {
    final ciclo = p.cicloDias <= 0 ? 30 : p.cicloDias;
    final hojeSeq = p.diaDeHoje;
    final feitoAte = _feitoAte(e, p);
    final esc = p.escada;
    return Container(
      key: const Key('checkin_mes_calendario'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _verdeFundo,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            hojeSeq >= 1
                ? 'Estás no dia {0} de {1}.'.trArgs([hojeSeq, ciclo])
                : 'Amanhã começa a tua sequência no Dia 1.'.tr,
            key: const Key('checkin_mes_dia'),
            style: const TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
          ),
          if (esc != null && esc.ativa && esc.texto.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              esc.texto.tr,
              style: const TextStyle(fontSize: 12, height: 1.3, color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: 10),
          CheckinCaminho(
            dias: diasDoCaminho(p, feitoAte: feitoAte, hoje: hojeSeq),
            chaveDia: 'checkin_mes_dia_',
            chaveMarco: 'checkin_mes_marco_',
          ),
          const SizedBox(height: 4),
          for (final m in p.marcos)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Icon(_iconeMarco(m), size: 14, color: AppColors.primaryDark),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Dia {0}: {1}'.trArgs([
                        m.dia,
                        m.tipo == 'tokens' && m.tokens != null
                            ? '{0} tokens'.trArgs([m.tokens])
                            : m.titulo.tr,
                      ]),
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                  if (valorEmEuros(m.valorCents).isNotEmpty)
                    Text(
                      valorEmEuros(m.valorCents),
                      key: Key('checkin_mes_valor_${m.dia}'),
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                    ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('btn_os_meus_premios_cartao'),
              onPressed: _abrirPremios,
              icon: const Icon(Icons.card_giftcard, size: 16),
              label: Text(p.porUsar.isNotEmpty
                  ? 'Os meus prémios ({0})'.trArgs([p.porUsar.length])
                  : 'Os meus prémios'.tr),
            ),
          ),
          if (p.lembrete != null) _linhaLembrete(p.lembrete!),
        ],
      ),
    );
  }

  /// R8: o lembrete diário, à hora a que costuma fazer o check-in; desliga-se aqui.
  Widget _linhaLembrete(CheckinLembrete l) {
    final ligado = _lembreteLigado ?? l.ligado;
    final hora = l.hora;
    return SwitchListTile(
      key: const Key('checkin_lembrete_switch'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: ligado,
      activeThumbColor: AppColors.primary,
      onChanged: _aGravarLembrete ? null : _mudarLembrete,
      title: Text('Lembrete diário'.tr,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      subtitle: Text(
        hora == null
            ? 'Um aviso por dia, só enquanto vens fazer o check-in.'.tr
            : 'Um aviso por dia, por volta das {0}h, só enquanto vens fazer o check-in.'.trArgs([hora]),
        style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
      ),
    );
  }

  Future<void> _mudarLembrete(bool ligado) async {
    final antes = _lembreteLigado;
    setState(() {
      _lembreteLigado = ligado;
      _aGravarLembrete = true;
    });
    final ok = await (widget.definirLembrete ?? CheckinPremiosService.instance.definirLembrete)(ligado);
    if (!mounted) return;
    setState(() {
      _aGravarLembrete = false;
      if (!ok) _lembreteLigado = antes;
    });
  }

  /// A barra do próximo prémio e os avisos do perdão (R5), por baixo da semana.
  List<Widget> _barraEPerdao(CheckinEstado e) {
    final p = _premios;
    if (p == null) return const [];
    final prox = proximoPremio(p);
    final perdao = p.perdao;
    return [
      if (prox != null) ...[
        const SizedBox(height: 10),
        CheckinBarraProximo(
          marco: prox.marco,
          faltam: prox.faltam,
          progresso: prox.progresso,
          precisaPedido: p.precisaPedido,
        ),
      ],
      if (perdao != null && perdao.pendente && !e.alreadyDone) ...[
        const SizedBox(height: 8),
        _aviso(
          const Key('checkin_perdao_pendente'),
          'Ontem não deu, mas o teu perdão deste mês guarda a sequência. Faz o check-in de hoje!'.tr,
        ),
      ] else if (perdao != null && perdao.temAviso && !_perdaoVisto) ...[
        const SizedBox(height: 8),
        _aviso(
          const Key('checkin_perdao_aviso'),
          'Usámos o teu perdão deste mês: a tua sequência continua.'.tr,
          fechar: () {
            setState(() => _perdaoVisto = true);
            unawaited((widget.marcarPerdaoVisto ?? CheckinPremiosService.instance.marcarPerdaoVisto)());
          },
        ),
      ],
    ];
  }

  Widget _aviso(Key chave, String texto, {VoidCallback? fechar}) {
    return Container(
      key: chave,
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2FE),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.ac_unit_rounded, color: Color(0xFF0284C7), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto, style: const TextStyle(fontSize: 12.5, color: Color(0xFF075985))),
          ),
          if (fechar != null)
            TextButton(
              key: const Key('btn_perdao_ok'),
              onPressed: fechar,
              child: Text('OK'.tr),
            ),
        ],
      ),
    );
  }

  /// Prémio guardado sem escolha pendente: "Tens guardado: X até dd/mm".
  Widget _linhaGuardado(CheckinEscada esc) {
    final g = esc.guardado!;
    final ate = g.garantidoAte;
    return Container(
      key: const Key('checkin_escada_guardado'),
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: _cinza,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.bookmark_added_outlined, color: AppColors.primaryDark, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ate == null
                  ? 'Tens guardado: {0}'.trArgs([g.titulo.tr])
                  : 'Tens guardado: {0} até {1}'.trArgs([g.titulo.tr, _dataCurta(ate)]),
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            key: const Key('btn_escada_levantar_guardado'),
            onPressed: _aDecidir ? null : _levantar,
            child: Text('Levantar'.tr),
          ),
        ],
      ),
    );
  }

  static String _dataCurta(DateTime d) {
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(d.day)}/${dois(d.month)}';
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
            padding: const EdgeInsets.symmetric(vertical: 10),
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
