import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/rastreio_interpolacao.dart';

/// [Rastreio em tempo real · 07/10/2026] A posição do condutor atribuído, em
/// tempo real, para o mapa do CLIENTE — corrida TVDE, entrega de
/// restaurante/mercado, favor.
///
/// Fonte: Supabase Realtime na linha do condutor em `driver_locations`
/// (filtro `driver_id = user_id do condutor`). É a mesma tabela que a RPC
/// `tvde_ride_driver_card` já lê e que o matching usa — não se inventa uma
/// segunda verdade. A RLS dessa tabela só deixava o próprio condutor ler a sua
/// linha; a migração `20261007230000_rastreio_tempo_real` abre a leitura ao
/// cliente da corrida/pedido em curso. Enquanto essa migração não estiver no
/// ar, o canal fica mudo e os ecrãs continuam com o poll de reserva
/// (`tvde_ride_driver_card` na corrida, `orders.driver_lat` na entrega).
///
/// Não escreve nada; não toca no despacho.
class DriverLiveFeed {
  DriverLiveFeed({
    required this.driverUserId,
    required this.onAmostra,
  });

  final String driverUserId;
  final void Function(AmostraPosicao amostra) onAmostra;

  RealtimeChannel? _canal;
  bool _ligado = false;

  bool get ligado => _ligado;

  /// Abre o canal. Idempotente.
  void iniciar() {
    if (_ligado) return;
    _ligado = true;
    try {
      final sb = Supabase.instance.client;
      final sufixo = math.Random().nextInt(1 << 30);
      _canal = sb.channel('driver_live_${driverUserId}_$sufixo')
        ..onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'driver_locations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: driverUserId,
          ),
          callback: (p) => _entregar(p.newRecord),
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'driver_locations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: driverUserId,
          ),
          callback: (p) => _entregar(p.newRecord),
        )
        ..subscribe();
    } catch (e) {
      debugPrint('[DriverLiveFeed] canal falhou: $e');
    }
  }

  /// Fecha o canal. Idempotente.
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
    if (a != null) onAmostra(a);
  }

  /// Lê a linha do condutor uma vez (reserva ao canal). `null` quando a RLS
  /// ainda não deixa (migração por aplicar) ou não há linha.
  Future<AmostraPosicao?> lerAgora() async {
    try {
      final row = await Supabase.instance.client
          .from('driver_locations')
          .select('latitude, longitude, heading, speed_kmh, last_updated')
          .eq('driver_id', driverUserId)
          .maybeSingle();
      if (row == null) return null;
      return amostraDeLinha(row);
    } catch (_) {
      return null;
    }
  }

  /// Converte uma linha de `driver_locations` (ou do cartão da RPC, que usa
  /// `lat`/`lng`/`location_updated_at`) numa [AmostraPosicao]. Pura.
  static AmostraPosicao? amostraDeLinha(Map<String, dynamic> row) {
    final lat = (row['latitude'] ?? row['lat']) as num?;
    final lng = (row['longitude'] ?? row['lng']) as num?;
    if (lat == null || lng == null) return null;
    final em = DateTime.tryParse(
        (row['last_updated'] ?? row['location_updated_at'] ?? '').toString());
    final heading = (row['heading'] as num?)?.toDouble();
    final v = (row['speed_kmh'] as num?)?.toDouble();
    return AmostraPosicao(
      ponto: LatLng(lat.toDouble(), lng.toDouble()),
      em: (em ?? DateTime.now()).toUtc(),
      heading: heading,
      velocidadeKmh: v,
    );
  }
}

/// Definições do rastreio lidas de `platform_settings` (uma vez por sessão,
/// best-effort — sem rede ficam os valores de arranque).
class RastreioSettings {
  RastreioSettings._();

  static int driverCardPollSeconds = 4;
  static int rideGpsIntervalSeconds = 5;
  static bool clientLiveLocationEnabled = true;
  static int clientLiveLocationIntervalSeconds = 4;

  static Future<void>? _aCarregar;

  static Future<void> carregar() {
    return _aCarregar ??= _ler();
  }

  static Future<void> _ler() async {
    final sb = Supabase.instance.client;
    Future<dynamic> get(String k) =>
        sb.rpc('get_setting', params: {'p_key': k}).timeout(
              const Duration(seconds: 8),
            );
    try {
      final r = await Future.wait<dynamic>([
        get('tvde_driver_card_poll_seconds').catchError((_) => null),
        get('tvde_ride_gps_interval_seconds').catchError((_) => null),
        get('client_live_location_enabled').catchError((_) => null),
        get('client_live_location_interval_seconds').catchError((_) => null),
      ]);
      final poll = int.tryParse('${r[0]}');
      if (poll != null && poll >= 1 && poll <= 60) driverCardPollSeconds = poll;
      final gps = int.tryParse('${r[1]}');
      if (gps != null && gps >= 1 && gps <= 60) rideGpsIntervalSeconds = gps;
      if (r[2] is bool) clientLiveLocationEnabled = r[2] as bool;
      if ('${r[2]}' == 'false') clientLiveLocationEnabled = false;
      final cli = int.tryParse('${r[3]}');
      if (cli != null && cli >= 2 && cli <= 60) {
        clientLiveLocationIntervalSeconds = cli;
      }
    } catch (e) {
      debugPrint('[RastreioSettings] $e');
      _aCarregar = null; // tenta outra vez na próxima chamada
    }
  }
}
