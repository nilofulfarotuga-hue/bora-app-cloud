import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../l10n/tr.dart';
import '../services/client_live_location_service.dart';
import '../services/driver_live_feed.dart';

/// [Pontinho azul · 07/10/2026] Quem chega: muda só o texto do cartão.
enum QuemChega { motorista, estafeta }

/// Dono do envio da posição do cliente. Vive no `State` do ECRÃ (corrida /
/// rastreio), não no cartão: o cartão está dentro de um painel arrastável
/// (ListView) que desmonta o que sai de vista — se fosse ele a mandar, recolher
/// o painel parava a partilha.
///
/// O ecrã actualiza [aChegar] em cada build (`ctrl.aChegar = ride.isOnTheWay`)
/// e chama [dispose] ao fechar. Pára sozinho ao sair do estado "a chegar".
class PartilharLocalizacaoController extends ChangeNotifier {
  PartilharLocalizacaoController({this.rideId, this.orderId})
      : assert(rideId != null || orderId != null) {
    unawaited(_arrancar());
  }

  final String? rideId;
  final String? orderId;

  ClientLiveLocationSender? _sender;
  bool _aChegar = false;
  bool _ligado = false;
  bool _pronto = false;
  bool _aMudar = false;
  bool _fechado = false;

  /// A escolha do cliente (interruptor).
  bool get ligado => _ligado;

  /// Preferência e definições já lidas (até lá o cartão não aparece).
  bool get pronto => _pronto;

  bool get aMudar => _aMudar;

  /// Está mesmo a enviar neste momento.
  bool get aEnviar => _aChegar && _ligado && (_sender?.ativo ?? false);

  /// Cartão visível? Só com a funcionalidade ligada no painel.
  bool get visivel => _pronto && RastreioSettings.clientLiveLocationEnabled;

  bool get aChegar => _aChegar;
  set aChegar(bool v) {
    if (_aChegar == v) return;
    _aChegar = v;
    _sincronizar();
    notifyListeners();
  }

  Future<void> _arrancar() async {
    await RastreioSettings.carregar();
    final pref = await ClientLiveLocationSender.preferencia();
    if (_fechado) return;
    _ligado = pref;
    _pronto = true;
    _sincronizar();
    notifyListeners();
  }

  /// Liga/desliga pelo interruptor. `false` = sem permissão de localização
  /// (fica desligado e a preferência guardada a `false`).
  Future<bool> definirLigado(bool v) async {
    if (_aMudar || _fechado) return _ligado;
    _aMudar = true;
    notifyListeners();
    try {
      if (v && !await ClientLiveLocationSender.pedirPermissao()) {
        _ligado = false;
        await ClientLiveLocationSender.guardarPreferencia(false);
        _sincronizar();
        return false;
      }
      await ClientLiveLocationSender.guardarPreferencia(v);
      _ligado = v;
      _sincronizar();
      return true;
    } finally {
      _aMudar = false;
      if (!_fechado) notifyListeners();
    }
  }

  void _sincronizar() {
    if (!_pronto || _fechado) return;
    final deve = _aChegar && _ligado && RastreioSettings.clientLiveLocationEnabled;
    if (deve) {
      final s = _sender ??= ClientLiveLocationSender(
        rideId: rideId,
        orderId: orderId,
      );
      if (!s.ativo) {
        unawaited(s
            .iniciar(
                intervaloSegundos:
                    RastreioSettings.clientLiveLocationIntervalSeconds)
            .then((ok) {
          if (_fechado) return;
          if (!ok) {
            // Permissão retirada entretanto: desliga e diz ao cartão.
            _ligado = false;
            unawaited(ClientLiveLocationSender.guardarPreferencia(false));
          }
          notifyListeners();
        }));
      }
    } else {
      final s = _sender;
      _sender = null;
      if (s != null) unawaited(s.parar());
    }
  }

  @override
  void dispose() {
    _fechado = true;
    final s = _sender;
    _sender = null;
    if (s != null) unawaited(s.parar());
    super.dispose();
  }
}

/// Cartão "Partilhar a minha localização com o motorista/estafeta enquanto
/// ele chega", com interruptor (opt-in). Só pinta; a lógica é do
/// [PartilharLocalizacaoController].
class PartilharLocalizacaoCard extends StatelessWidget {
  const PartilharLocalizacaoCard({
    super.key,
    required this.controller,
    this.quem = QuemChega.motorista,
  });

  final PartilharLocalizacaoController controller;
  final QuemChega quem;

  Future<void> _mudar(BuildContext context, bool v) async {
    final ok = await controller.definirLigado(v);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Sem permissão de localização. Ativa-a nas definições do telemóvel para partilhares onde estás.'
              .tr,
        ),
        duration: const Duration(seconds: 6),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.visivel) return const SizedBox.shrink();
        final titulo = quem == QuemChega.motorista
            ? 'Partilhar a minha localização com o motorista enquanto ele chega'
                .tr
            : 'Partilhar a minha localização com o estafeta enquanto ele chega'
                .tr;
        final aEnviar = controller.aEnviar;
        return Semantics(
          identifier: 'card_partilhar_localizacao',
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md, vertical: Spacing.sm),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(Radii.lg),
              border:
                  Border.all(color: AppColors.info.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.info,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      if (aEnviar)
                        BoxShadow(
                          color: AppColors.info.withValues(alpha: 0.5),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        aEnviar
                            ? 'A partilhar — pára sozinho quando ele chegar.'.tr
                            : 'Só enquanto ele vem a caminho. Podes desligar quando quiseres.'
                                .tr,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: controller.ligado,
                  onChanged:
                      controller.aMudar ? null : (v) => _mudar(context, v),
                  activeTrackColor: AppColors.info,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
