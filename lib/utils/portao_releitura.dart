import 'package:flutter/widgets.dart';

/// [16/11/2026 servidor-nao-travar] Decide se o "voltar à app" relê o
/// servidor (pedidos, corridas, limpezas, Casa, reservas, marcações).
///
/// - Só relê se a app esteve mesmo em segundo plano (`paused` ou `hidden`).
///   Janelas por cima (microfone, pedido de permissão, cortina de
///   notificações) dão `inactive → resumed` sem sair do ecrã e não contam.
/// - No web, mudar de separador dá `hidden → resumed`: conta, relê.
/// - No máximo uma releitura a cada [intervalo] (15 s), por muitas voltas que
///   haja: N voltas em 10 s dão no máximo 1 leitura.
class PortaoReleitura {
  PortaoReleitura({this.intervalo = const Duration(seconds: 15)});

  final Duration intervalo;
  bool _esteveEmSegundoPlano = false;
  DateTime? _ultimaReleitura;

  /// Chamar em cada `didChangeAppLifecycleState`. `true` = reler agora.
  bool deveReler(AppLifecycleState estado, DateTime agora) {
    if (estado == AppLifecycleState.paused ||
        estado == AppLifecycleState.hidden) {
      _esteveEmSegundoPlano = true;
      return false;
    }
    if (estado != AppLifecycleState.resumed) return false;
    if (!_esteveEmSegundoPlano) return false;
    _esteveEmSegundoPlano = false;
    final ultima = _ultimaReleitura;
    if (ultima != null && agora.difference(ultima) < intervalo) return false;
    _ultimaReleitura = agora;
    return true;
  }
}
