// lib/widgets/driver_push_warning_card.dart
//
// [ronda-fecho-2026-09-22 · A8] Estafeta ONLINE sem aparelho para receber
// notificações = não vai receber pedidos e não sabe. Foi assim que o Ney
// ficou 24 h "online" no iPhone sem uma única oferta (16/09).
//
// Enquanto o estafeta está online, este cartão pergunta ao servidor
// (`meu_estado_push()` → {tem_token, aparelhos, legacy, verificado_em}) se há
// algum aparelho registado: no arranque, quando a app volta à frente e a cada
// 2 minutos. Sem token → cartão vermelho com o botão "Ativar notificações",
// que volta a registar o token e re-verifica; com token, ou se o servidor não
// responder, não desenha nada (nunca lança, nunca bloqueia — PADRAO §1.26).
//
// Montado nos DOIS desenhos do ecrã do estafeta (mapa ocioso e lista de
// pedidos — PADRAO 2.6: "o ecrã do estafeta tem dois desenhos").
//
// PT-PT (app do estafeta).
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../services/push_token_service.dart';
import '../services/web_presence.dart';
import '../stores/driver_store.dart';

class DriverPushWarningCard extends StatefulWidget {
  const DriverPushWarningCard({
    super.key,
    required this.isOnline,
    this.checker,
    this.reativar,
    this.intervalo = const Duration(minutes: 2),
  });

  /// Só pergunta e só avisa enquanto o estafeta está online.
  final bool isOnline;

  /// Devolve `true` quando há aparelho registado. Por omissão pergunta ao
  /// servidor (RPC `meu_estado_push`); os testes injectam uma função.
  final Future<bool> Function()? checker;

  /// O que o botão faz. Por omissão volta a registar o token deste aparelho
  /// (e, no navegador, pede a permissão a partir do toque).
  final Future<void> Function()? reativar;

  /// Cadência da verificação enquanto online.
  final Duration intervalo;

  static const String textoAviso =
      'Sem notificações: não vais receber pedidos.';
  static const String textoBotao = 'Ativar notificações';

  @override
  State<DriverPushWarningCard> createState() => _DriverPushWarningCardState();
}

class _DriverPushWarningCardState extends State<DriverPushWarningCard>
    with WidgetsBindingObserver {
  bool _semToken = false;
  bool _aVerificar = false;
  bool _aAtivar = false;
  bool _tentouSemSucesso = false;
  Timer? _timer;

  /// Regra dos gémeos: no navegador o `DriverWebCards` já tem o botão
  /// "Ativar notificações" (e o aviso de bloqueio) enquanto a permissão do
  /// navegador não está dada. Este cartão só entra na web quando a permissão
  /// está dada e, mesmo assim, o servidor não tem aparelho registado.
  bool get _redundanteNaWeb =>
      kIsWeb && WebPresence.instance.notificationPermission != 'granted';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.isOnline) _arrancar();
  }

  @override
  void didUpdateWidget(DriverPushWarningCard old) {
    super.didUpdateWidget(old);
    if (old.isOnline == widget.isOnline) return;
    if (widget.isOnline) {
      _arrancar();
    } else {
      _parar();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.isOnline) {
      unawaited(_verificar());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  void _arrancar() {
    unawaited(_verificar());
    _timer?.cancel();
    _timer = Timer.periodic(widget.intervalo, (_) => _verificar());
  }

  /// Só é chamado de `didUpdateWidget` — o build vem logo a seguir, não é
  /// preciso `setState`.
  void _parar() {
    _timer?.cancel();
    _timer = null;
    _semToken = false;
    _tentouSemSucesso = false;
  }

  static Future<bool> _viaServidor() async {
    final res = await Supabase.instance.client.rpc('meu_estado_push');
    // Forma inesperada = não se avisa (só se avisa com um "não" claro).
    if (res is Map) return res['tem_token'] == true;
    return true;
  }

  Future<void> _verificar() async {
    if (_aVerificar || !widget.isOnline || _redundanteNaWeb) return;
    _aVerificar = true;
    var semToken = false;
    try {
      final tem = await (widget.checker ?? _viaServidor)()
          .timeout(const Duration(seconds: 10));
      semToken = !tem;
    } catch (e) {
      // Servidor em baixo / sem rede / tempo esgotado: não se inventa aviso.
      debugPrint('[DriverPushWarningCard] meu_estado_push: $e');
      semToken = false;
    } finally {
      _aVerificar = false;
    }
    if (!mounted || semToken == _semToken) return;
    setState(() {
      _semToken = semToken;
      if (!semToken) _tentouSemSucesso = false;
    });
  }

  Future<void> _reativarPorOmissao() async {
    if (kIsWeb) {
      // O navegador só pede permissão a partir de um gesto do utilizador.
      try {
        await context.read<DriverStore>().registarPushAposToque();
      } catch (e) {
        debugPrint('[DriverPushWarningCard] registarPushAposToque: $e');
      }
    }
    await PushTokenService.registerForRole('driver');
  }

  Future<void> _ativar() async {
    if (_aAtivar) return;
    setState(() {
      _aAtivar = true;
      _tentouSemSucesso = false;
    });
    try {
      // No iOS o registo pode esperar pelo APNs (até 60 s). Não se prende o
      // botão a isso: ao fim de 20 s re-verifica-se, e a verificação
      // periódica apanha o token quando ele chegar.
      await (widget.reativar ?? _reativarPorOmissao)()
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('[DriverPushWarningCard] ativar: $e');
    }
    await _verificar();
    if (!mounted) return;
    setState(() {
      _aAtivar = false;
      _tentouSemSucesso = _semToken;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOnline || !_semToken || _redundanteNaWeb) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        key: const Key('driver_push_warning_card'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFECACA)),
          boxShadow: AppColors.shadowCard,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_off_outlined,
                    color: Color(0xFFB91C1C)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    DriverPushWarningCard.textoAviso,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.red.shade900,
                    ),
                  ),
                ),
              ],
            ),
            if (_tentouSemSucesso) ...[
              const SizedBox(height: 4),
              Text(
                'Ainda sem aparelho registado. Verifica as notificações da '
                'Bora nas definições do telemóvel e tenta de novo.',
                style: TextStyle(fontSize: 12, color: Colors.red.shade900),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const Key('btn_ativar_notificacoes_push'),
                onPressed: _aAtivar ? null : _ativar,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                child: Text(
                  _aAtivar ? 'A ativar…' : DriverPushWarningCard.textoBotao,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
