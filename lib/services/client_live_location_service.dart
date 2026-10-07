import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/rastreio_interpolacao.dart';

/// [Pontinho azul · 07/10/2026] O CLIENTE partilha a sua posição com o
/// condutor/estafeta enquanto ele chega — como na Uber, quando o passageiro
/// se afasta do pino e o motorista o vê a mexer.
///
/// Sempre opt-in: o interruptor vive no cartão do ecrã da corrida/entrega e a
/// escolha fica guardada no telemóvel (`SharedPreferences`). O envio corre só
/// enquanto o estado é "a chegar" e pára sozinho ao sair dele, ao fechar o
/// ecrã ou quando o servidor diz que não (desligado no painel, corrida sem
/// condutor). O servidor valida tudo na RPC `client_live_location_upsert`
/// (migração `20261007230000_rastreio_tempo_real`): a corrida/pedido tem de
/// ser do cliente e ter condutor atribuído; é ele que descobre o
/// `driver_user_id`. Nada disto toca no despacho.
class ClientLiveLocationSender {
  ClientLiveLocationSender({this.rideId, this.orderId})
      : assert(rideId != null || orderId != null);

  static const String prefKey = 'bora_client.partilhar_localizacao';

  final String? rideId;
  final String? orderId;

  Timer? _ticker;
  bool _ativo = false;
  bool _emVoo = false;
  bool _haLinhaNoServidor = false;

  /// Motivo da última recusa do servidor (para o cartão explicar), ou null.
  String? ultimoMotivo;

  bool get ativo => _ativo;

  /// A escolha guardada no telemóvel (por omissão: desligado — é opt-in).
  static Future<bool> preferencia() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(prefKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> guardarPreferencia(bool ligado) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(prefKey, ligado);
    } catch (_) {/* sem prefs, a escolha vale só nesta sessão */}
  }

  /// Pede a permissão de localização ao sistema. `true` quando se pode ler.
  static Future<bool> pedirPermissao() async {
    try {
      if (!kIsWeb && !await Geolocator.isLocationServiceEnabled()) {
        return false;
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      return p == LocationPermission.whileInUse ||
          p == LocationPermission.always;
    } catch (e) {
      debugPrint('[ClientLiveLocation] permissão: $e');
      return false;
    }
  }

  /// Começa a enviar a cada [intervaloSegundos]. Idempotente.
  /// Devolve `false` se não houver permissão.
  Future<bool> iniciar({required int intervaloSegundos}) async {
    if (_ativo) return true;
    if (!await pedirPermissao()) return false;
    _ativo = true;
    final s = intervaloSegundos.clamp(2, 60);
    unawaited(_enviarUmaVez());
    _ticker = Timer.periodic(Duration(seconds: s), (_) => _enviarUmaVez());
    return true;
  }

  /// Pára de enviar e apaga a linha no servidor. Idempotente.
  Future<void> parar() async {
    _ticker?.cancel();
    _ticker = null;
    if (!_ativo) return;
    _ativo = false;
    if (!_haLinhaNoServidor) return;
    _haLinhaNoServidor = false;
    try {
      await Supabase.instance.client.rpc('client_live_location_stop', params: {
        'p_ride_id': rideId,
        'p_order_id': orderId,
      }).timeout(const Duration(seconds: 8));
    } catch (e) {
      // O servidor apaga sozinho quando a corrida/pedido termina (gatilhos) e
      // o condutor ignora linhas expiradas — não fica nada pendurado.
      debugPrint('[ClientLiveLocation] stop falhou: $e');
    }
  }

  Future<void> _enviarUmaVez() async {
    if (!_ativo || _emVoo) return;
    _emVoo = true;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 10));
      if (!_ativo) return;
      final res = await Supabase.instance.client
          .rpc('client_live_location_upsert', params: {
        'p_ride_id': rideId,
        'p_order_id': orderId,
        'p_lat': pos.latitude,
        'p_lng': pos.longitude,
        'p_heading': pos.heading.isFinite && pos.heading >= 0
            ? pos.heading
            : null,
        'p_accuracy': pos.accuracy.isFinite ? pos.accuracy : null,
      }).timeout(const Duration(seconds: 8));
      if (res is Map && res['ok'] == false) {
        // O servidor recusou (desligado no painel, corrida já sem condutor):
        // pára sozinho — insistir era gastar bateria e rede à toa.
        ultimoMotivo = res['motivo']?.toString();
        _ticker?.cancel();
        _ticker = null;
        _ativo = false;
        return;
      }
      _haLinhaNoServidor = true;
    } catch (e) {
      debugPrint('[ClientLiveLocation] envio falhou: $e');
    } finally {
      _emVoo = false;
    }
  }
}

/// Lado do CONDUTOR: ouve `client_live_locations` (Realtime, filtro
/// `driver_user_id = eu`) e entrega cada posição do cliente como
/// [AmostraPosicao]; avisa quando a linha é apagada (o cliente desligou, ou a
/// corrida acabou). O ecrã desenha o pontinho azul com a mesma interpolação
/// do carro no mapa do cliente.
class ClientLiveLocationFeed {
  ClientLiveLocationFeed({
    required this.driverUserId,
    required this.onAmostra,
    required this.onApagado,
  });

  final String driverUserId;
  final void Function(AmostraPosicao amostra, String? rideId, String? orderId)
      onAmostra;
  final void Function() onApagado;

  /// Sem amostra nova há mais do que isto, o pontinho some — cobre o caso de
  /// o DELETE não chegar (rede) e o da linha expirada.
  static const Duration validade = Duration(seconds: 30);

  RealtimeChannel? _canal;
  bool _ligado = false;

  bool get ligado => _ligado;

  void iniciar() {
    if (_ligado) return;
    _ligado = true;
    try {
      final sb = Supabase.instance.client;
      final filtro = PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'driver_user_id',
        value: driverUserId,
      );
      final sufixo = math.Random().nextInt(1 << 30);
      _canal = sb.channel('client_live_${driverUserId}_$sufixo')
        ..onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'client_live_locations',
          filter: filtro,
          callback: (p) => _entregar(p.newRecord),
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'client_live_locations',
          filter: filtro,
          callback: (p) => _entregar(p.newRecord),
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'client_live_locations',
          filter: filtro,
          callback: (_) => onApagado(),
        )
        ..subscribe();
    } catch (e) {
      debugPrint('[ClientLiveLocationFeed] canal falhou: $e');
    }
  }

  Future<void> parar() async {
    _ligado = false;
    final c = _canal;
    _canal = null;
    if (c == null) return;
    try {
      await c.unsubscribe();
    } catch (_) {/* já fechado */}
  }

  void _entregar(Map<String, dynamic> row) {
    final a = amostraDeLinha(row);
    if (a == null) return;
    final expira = DateTime.tryParse('${row['expires_at'] ?? ''}');
    if (expira != null && expira.toUtc().isBefore(DateTime.now().toUtc())) {
      onApagado();
      return;
    }
    onAmostra(a, row['ride_id']?.toString(), row['order_id']?.toString());
  }

  /// Linha de `client_live_locations` → amostra. Pura.
  static AmostraPosicao? amostraDeLinha(Map<String, dynamic> row) {
    final lat = row['lat'] as num?;
    final lng = row['lng'] as num?;
    if (lat == null || lng == null) return null;
    final em = DateTime.tryParse('${row['updated_at'] ?? ''}');
    return AmostraPosicao(
      ponto: LatLng(lat.toDouble(), lng.toDouble()),
      em: (em ?? DateTime.now()).toUtc(),
      heading: (row['heading'] as num?)?.toDouble(),
    );
  }
}
