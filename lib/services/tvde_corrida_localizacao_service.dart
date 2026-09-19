import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Serviço em primeiro plano de LOCALIZAÇÃO para corridas TVDE.
///
/// ## Porque é que isto existe (2026-09-05)
///
/// O mapa das ENTREGAS já corria em primeiro plano com tipo `location`
/// (`driver_home_screen.dart` e `driver_map_screen.dart` passam um
/// `foregroundNotificationConfig` ao `AndroidSettings`). O mapa da corrida
/// TVDE não passava — o `AndroidSettings` era criado sem esse campo. Sem ele
/// o Android estrangula o GPS quando o motorista minimiza a app a meio da
/// corrida, e o cliente deixa de ver o carro a andar.
///
/// ## Como funciona (não inventa um segundo padrão)
///
/// Quando `foregroundNotificationConfig` é passado, o geolocator arranca o
/// serviço `com.baseflow.geolocator.GeolocatorLocationService`, que o próprio
/// plugin já declara com `android:foregroundServiceType="location"` no seu
/// AndroidManifest (geolocator_android 5.0.3) e que o merger do Gradle junta
/// ao manifesto final da app. A permissão `FOREGROUND_SERVICE_LOCATION` já
/// está declarada em `android/app/src/main/AndroidManifest.xml`.
///
/// **Não** se usa aqui o `flutter_foreground_task`: o serviço desse plugin é
/// partilhado com o estafeta (Online) e com o parceiro (loja aberta), e arranca
/// sempre com TODOS os tipos declarados no manifesto
/// (`ServiceInfo.FOREGROUND_SERVICE_TYPE_MANIFEST`). Acrescentar-lhe `location`
/// obrigaria o PARCEIRO a ter permissão de localização concedida para abrir a
/// loja — sem ela o `startForeground()` atira `SecurityException` em Android
/// 14+ e a app do parceiro rebenta.
///
/// ## Limite honesto
///
/// Isto impede o estrangulamento do GPS com a app MINIMIZADA. Não sobrevive a
/// um swipe-away que destrua a Activity — quem mantém o processo vivo nesse
/// caso é o foreground service do estafeta Online (`BoraForegroundService`),
/// que já arranca quando o motorista fica online.
///
/// ## Ordem de arranque
///
/// `iniciar()` tem de ser chamado com a app em primeiro plano (o motorista
/// acabou de aceitar a corrida). Em Android 12+ arrancar um foreground service
/// a partir do background é bloqueado com `ForegroundServiceStartNotAllowedException`.
class TvdeCorridaLocalizacao {
  TvdeCorridaLocalizacao._();

  /// Texto da notificação persistente (PT-PT).
  static const String tituloNotificacao = 'Bora — Corrida a decorrer';
  static const String textoNotificacao =
      'A partilhar a tua localização com o cliente.';
  static const String nomeDoCanal = 'Corridas TVDE';

  static final StreamController<Position> _controlador =
      StreamController<Position>.broadcast();
  static StreamSubscription<Position>? _subscricao;
  static bool _comServicoEmPrimeiroPlano = false;

  /// `true` enquanto o stream da corrida estiver ligado.
  static bool get estaAtiva => _subscricao != null;

  /// `true` só quando o stream arrancou mesmo com o serviço em primeiro plano
  /// (permissão concedida + localização ligada). Se for `false` com
  /// [estaAtiva] a `true`, o GPS funciona mas será estrangulado em background.
  static bool get temServicoEmPrimeiroPlano => _comServicoEmPrimeiroPlano;

  /// Posições da corrida. Broadcast e permanente — sobrevive a [parar] e pode
  /// ser ouvido antes de [iniciar].
  static Stream<Position> get posicoes => _controlador.stream;

  /// Definições de GPS de uma corrida a decorrer.
  ///
  /// Só ativa o serviço em primeiro plano quando os requisitos do Android 14+
  /// estão cumpridos (localização ligada no aparelho + `ACCESS_FINE_LOCATION`
  /// ou `ACCESS_COARSE_LOCATION` concedida). Sem isso devolve as mesmas
  /// definições sem `foregroundNotificationConfig`, para nunca provocar o
  /// `SecurityException` do `startForeground()`.
  ///
  /// Pode ser usado sozinho: basta passar o resultado a
  /// `Geolocator.getPositionStream(locationSettings: ...)`.
  static Future<LocationSettings> definicoesDeCorrida({
    String texto = textoNotificacao,
  }) async {
    const accuracy = LocationAccuracy.bestForNavigation;
    const distanceFilter = 3;

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
      );
    }

    final podeUsarPrimeiroPlano = await _requisitosCumpridos();
    return AndroidSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
      intervalDuration: const Duration(milliseconds: 700),
      foregroundNotificationConfig: podeUsarPrimeiroPlano
          ? ForegroundNotificationConfig(
              notificationTitle: tituloNotificacao,
              notificationText: texto,
              notificationChannelName: nomeDoCanal,
              // A corrida é navegação: o CPU não pode adormecer entre pontos.
              enableWakeLock: true,
              // Persistente — o motorista não a pode dispensar por engano.
              setOngoing: true,
            )
          : null,
    );
  }

  /// Arranca o GPS da corrida com serviço em primeiro plano.
  ///
  /// Idempotente: chamar duas vezes não abre um segundo stream.
  /// Devolve `true` quando o stream ficou ligado — ver
  /// [temServicoEmPrimeiroPlano] para saber se ficou mesmo protegido.
  static Future<bool> iniciar({String texto = textoNotificacao}) async {
    if (_subscricao != null) return true;
    try {
      final definicoes = await definicoesDeCorrida(texto: texto);
      _comServicoEmPrimeiroPlano = definicoes is AndroidSettings &&
          definicoes.foregroundNotificationConfig != null;
      _subscricao =
          Geolocator.getPositionStream(locationSettings: definicoes).listen(
        _controlador.add,
        onError: (Object e) =>
            debugPrint('[TvdeCorridaLocalizacao] erro no stream: $e'),
        cancelOnError: false,
      );
      debugPrint('[TvdeCorridaLocalizacao] iniciar OK '
          '(primeiroPlano=$_comServicoEmPrimeiroPlano)');
      return true;
    } catch (e) {
      // Inclui SecurityException / ForegroundServiceStartNotAllowedException
      // vindas do lado nativo: a corrida continua, sem proteção de background.
      debugPrint('[TvdeCorridaLocalizacao] iniciar FALHOU: $e');
      _comServicoEmPrimeiroPlano = false;
      return false;
    }
  }

  /// Pára o GPS e retira a notificação persistente. Idempotente.
  ///
  /// Chamar SEMPRE ao fim da corrida (entregue, cancelada, ou ao sair do ecrã)
  /// — senão a notificação fica pendurada e o GPS continua a gastar bateria.
  static Future<void> parar() async {
    _comServicoEmPrimeiroPlano = false;
    final sub = _subscricao;
    _subscricao = null;
    if (sub == null) return;
    try {
      await sub.cancel();
      debugPrint('[TvdeCorridaLocalizacao] parar OK');
    } catch (e) {
      debugPrint('[TvdeCorridaLocalizacao] parar erro: $e');
    }
  }

  /// Requisitos do Android 14+ para um foreground service de tipo `location`:
  /// serviço de localização ligado no aparelho e permissão de localização
  /// concedida em tempo de execução. `ACCESS_BACKGROUND_LOCATION` NÃO é
  /// preciso — é o próprio serviço em primeiro plano que dá acesso em background.
  static Future<bool> _requisitosCumpridos() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        debugPrint('[TvdeCorridaLocalizacao] localização desligada '
            '— sem serviço em primeiro plano');
        return false;
      }
      final permissao = await Geolocator.checkPermission();
      final ok = permissao == LocationPermission.always ||
          permissao == LocationPermission.whileInUse;
      if (!ok) {
        debugPrint('[TvdeCorridaLocalizacao] permissão=$permissao '
            '— sem serviço em primeiro plano');
      }
      return ok;
    } catch (e) {
      debugPrint('[TvdeCorridaLocalizacao] verificação falhou: $e');
      return false;
    }
  }
}
