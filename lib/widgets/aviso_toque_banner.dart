// lib/widgets/aviso_toque_banner.dart
//
// [10/10/2026] A 09/10 e 10/10 as ofertas ao estafeta só vibraram (Samsung
// A36, Android 16, em Vibrar/noite). As ofertas passaram a tocar pelo volume
// do ALARME; esta faixa diz ao profissional, no ecrã principal, o que ainda as
// pode calar (notificações, canal das ofertas, volume do alarme, ecrã
// inteiro, "Não incomodar") e leva-o à definição certa com "Corrigir".
//
// Lê o estado ao montar e sempre que a app volta ao primeiro plano (regresso
// das Definições). Vermelho se houver um problema grave; laranja se só houver
// avisos. Só Android: na web e no iPhone não desenha nada. Se a leitura falhar
// também não desenha nada — nunca se inventa um aviso.
//
// PT-PT (apps dos profissionais).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../services/permission_gate_service.dart';

class AvisoToqueBanner extends StatefulWidget {
  const AvisoToqueBanner({
    super.key,
    this.ativo = true,
    this.margem = const EdgeInsets.only(bottom: 8),
    this.lerProblemas,
    this.corrigir,
  });

  /// Só lê e só avisa enquanto o profissional está online / ao serviço.
  final bool ativo;

  final EdgeInsetsGeometry margem;

  /// Por omissão lê o Android ([PermissionGateService.estadoDoToque]); os
  /// testes injectam uma função.
  final Future<List<ProblemaToque>> Function()? lerProblemas;

  /// Por omissão abre a definição certa
  /// ([PermissionGateService.abrirCorrecao]); os testes injectam uma função.
  final Future<void> Function(CorrecaoToque correcao)? corrigir;

  static const String textoBotao = 'Corrigir';

  @override
  State<AvisoToqueBanner> createState() => _AvisoToqueBannerState();
}

class _AvisoToqueBannerState extends State<AvisoToqueBanner>
    with WidgetsBindingObserver {
  List<ProblemaToque> _problemas = const [];
  bool _aLer = false;
  bool _aCorrigir = false;

  static bool get _suportado =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.ativo) unawaited(_ler());
  }

  @override
  void didUpdateWidget(AvisoToqueBanner old) {
    super.didUpdateWidget(old);
    if (old.ativo == widget.ativo) return;
    if (widget.ativo) {
      unawaited(_ler());
    } else {
      // O build vem logo a seguir — não é preciso setState.
      _problemas = const [];
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.ativo) unawaited(_ler());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  static Future<List<ProblemaToque>> _lerDoAndroid() async {
    final estado = await PermissionGateService.estadoDoToque();
    return estado?.problemas ?? const [];
  }

  Future<void> _ler() async {
    if (_aLer || !_suportado || !widget.ativo) return;
    _aLer = true;
    var problemas = const <ProblemaToque>[];
    try {
      problemas = await (widget.lerProblemas ?? _lerDoAndroid)()
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[AvisoToqueBanner] leitura falhou (não avisa): $e');
    } finally {
      _aLer = false;
    }
    if (!mounted || !widget.ativo) return;
    setState(() => _problemas = problemas);
  }

  Future<void> _corrigir(ProblemaToque p) async {
    if (_aCorrigir) return;
    setState(() => _aCorrigir = true);
    try {
      await (widget.corrigir ?? PermissionGateService.abrirCorrecao)(
          p.correcao);
    } catch (e) {
      debugPrint('[AvisoToqueBanner] corrigir ${p.correcao}: $e');
    }
    if (!mounted) return;
    setState(() => _aCorrigir = false);
    // Pedidos do sistema (notificações) nem sempre passam por "resumed".
    await _ler();
  }

  static IconData _icone(CorrecaoToque c) => switch (c) {
        CorrecaoToque.notificacoes => Icons.notifications_off_outlined,
        CorrecaoToque.canalOfertas => Icons.notifications_paused_outlined,
        CorrecaoToque.volumeAlarme => Icons.volume_off_outlined,
        CorrecaoToque.ecraInteiro => Icons.screen_lock_portrait_outlined,
        CorrecaoToque.naoIncomodar => Icons.do_not_disturb_on_outlined,
      };

  @override
  Widget build(BuildContext context) {
    if (!_suportado || !widget.ativo || _problemas.isEmpty) {
      return const SizedBox.shrink();
    }
    // A lista vem do mais grave para o menos grave: o primeiro manda.
    final p = _problemas.first;
    final cor = p.grave ? AppColors.error : AppColors.accent;
    return Padding(
      padding: widget.margem,
      child: Material(
        key: const Key('aviso_toque_banner'),
        color: cor,
        borderRadius: BorderRadius.circular(12),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(
            children: [
              Icon(_icone(p.correcao), color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  p.texto,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const Key('aviso_toque_corrigir'),
                onPressed: _aCorrigir ? null : () => _corrigir(p),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: cor,
                  disabledBackgroundColor: Colors.white70,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  minimumSize: const Size(0, 36),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  AvisoToqueBanner.textoBotao,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
