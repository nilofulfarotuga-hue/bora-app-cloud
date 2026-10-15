import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'client_address_service.dart';

/// Morada com um toque (missão tvde-pedir-nunca-trava, 14/10/2026).
///
/// **Cicatriz:** a cliente Stela tinha a "Casa" guardada com coordenadas
/// (`client_addresses`) e mesmo assim não conseguia pedir, porque escrevia a
/// morada à mão e a pesquisa não a encontrava. Igual ao Uber/Bolt: as moradas
/// guardadas e os destinos recentes ficam à mão, por baixo dos campos.
@immutable
class AtalhoMorada {
  const AtalhoMorada({
    required this.rotulo,
    required this.morada,
    required this.coords,
    required this.recente,
  });

  /// O que aparece no chip: "Casa", "Trabalho"… ou o início da morada.
  final String rotulo;

  /// Morada completa que vai para o campo (e para a corrida).
  final String morada;
  final LatLng coords;

  /// true = destino de uma corrida anterior; false = morada guardada.
  final bool recente;
}

double? _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');

/// Rótulo curto para um destino recente: a 1.ª parte da morada.
String _rotuloCurto(String morada) {
  final primeira = morada.split(',').first.trim();
  return primeira.isEmpty ? morada.trim() : primeira;
}

/// Junta as moradas guardadas (só as que têm coordenadas) e os destinos
/// recentes das corridas (até [maxRecentes]), sem repetidos — o mesmo sítio
/// (menos de 60 m) ou a mesma morada escrita contam uma vez. Pura, sem rede.
///
/// [guardadas]: linhas de `client_addresses` (label, address, lat, lng).
/// [corridas]: linhas de `tvde_rides` (dest_label, dest_lat, dest_lng), da
/// mais recente para a mais antiga.
List<AtalhoMorada> montarAtalhos({
  required List<Map<String, dynamic>> guardadas,
  required List<Map<String, dynamic>> corridas,
  int maxRecentes = 3,
}) {
  const distancia = Distance();
  final out = <AtalhoMorada>[];

  bool repetido(String morada, LatLng c) => out.any((a) =>
      a.morada.trim().toLowerCase() == morada.trim().toLowerCase() ||
      distancia.as(LengthUnit.Meter, a.coords, c) < 60);

  for (final g in guardadas) {
    final lat = _num(g['lat']);
    final lng = _num(g['lng']);
    final morada = (g['address'] ?? '').toString().trim();
    if (lat == null || lng == null || morada.isEmpty) continue;
    final c = LatLng(lat, lng);
    if (repetido(morada, c)) continue;
    final rotulo = (g['label'] ?? '').toString().trim();
    out.add(AtalhoMorada(
      rotulo: rotulo.isEmpty ? _rotuloCurto(morada) : rotulo,
      morada: morada,
      coords: c,
      recente: false,
    ));
  }

  var recentes = 0;
  for (final r in corridas) {
    if (recentes >= maxRecentes) break;
    final lat = _num(r['dest_lat']);
    final lng = _num(r['dest_lng']);
    final morada = (r['dest_label'] ?? '').toString().trim();
    if (lat == null || lng == null || morada.isEmpty) continue;
    final c = LatLng(lat, lng);
    if (repetido(morada, c)) continue;
    out.add(AtalhoMorada(
      rotulo: _rotuloCurto(morada),
      morada: morada,
      coords: c,
      recente: true,
    ));
    recentes++;
  }
  return out;
}

/// Lê as moradas guardadas do cliente e os destinos das suas últimas corridas
/// TVDE. Nunca lança: sem sessão ou sem rede devolve lista vazia (os atalhos
/// são um presente, nunca uma condição para pedir).
Future<List<AtalhoMorada>> carregarAtalhosMorada() async {
  final sb = Supabase.instance.client;
  final uid = sb.auth.currentUser?.id;
  if (uid == null) return const [];

  var guardadas = <Map<String, dynamic>>[];
  try {
    final lista = await ClientAddressService.instance
        .list()
        .timeout(const Duration(seconds: 8));
    guardadas = [
      for (final a in lista)
        {'label': a.label, 'address': a.address, 'lat': a.lat, 'lng': a.lng},
    ];
  } catch (e) {
    debugPrint('AtalhosMorada: moradas guardadas indisponíveis => $e');
  }

  var corridas = <Map<String, dynamic>>[];
  try {
    final res = await sb
        .from('tvde_rides')
        .select('dest_label, dest_lat, dest_lng')
        .eq('client_id', uid)
        .order('created_at', ascending: false)
        .limit(15)
        .timeout(const Duration(seconds: 8));
    corridas = [
      for (final r in res as List) Map<String, dynamic>.from(r as Map),
    ];
  } catch (e) {
    debugPrint('AtalhosMorada: corridas recentes indisponíveis => $e');
  }

  return montarAtalhos(guardadas: guardadas, corridas: corridas);
}
