import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Uma célula do mapa de procura: um quadrado de cerca de 500 m, a uma hora do
/// dia, com os pedidos de loja dos últimos dias (adendo 4 · item 10).
@immutable
class CelulaProcura {
  const CelulaProcura({
    required this.hora,
    required this.lat,
    required this.lng,
    required this.pedidos,
  });

  /// Hora de Lisboa, 0 a 23.
  final int hora;

  /// Centro da célula.
  final double lat;
  final double lng;
  final int pedidos;

  factory CelulaProcura.fromJson(Map<String, dynamic> j) => CelulaProcura(
        hora: (j['hora'] as num?)?.toInt() ?? 0,
        lat: (j['lat_celula'] as num?)?.toDouble() ?? 0,
        lng: (j['lng_celula'] as num?)?.toDouble() ?? 0,
        pedidos: (j['pedidos'] as num?)?.toInt() ?? 0,
      );
}

/// As células de uma hora, as mais procuradas primeiro.
List<CelulaProcura> celulasDaHora(Iterable<CelulaProcura> todas, int hora) =>
    todas.where((c) => c.hora == hora).toList()
      ..sort((a, b) => b.pedidos.compareTo(a.pedidos));

/// Quantos pedidos há em cada hora (para o seletor de horas mostrar onde
/// vale a pena olhar).
Map<int, int> pedidosPorHora(Iterable<CelulaProcura> todas) {
  final m = <int, int>{};
  for (final c in todas) {
    m[c.hora] = (m[c.hora] ?? 0) + c.pedidos;
  }
  return m;
}

/// De 0 a 1: quão forte é esta célula comparada com a mais forte da hora.
double intensidade(int pedidos, int maximo) =>
    maximo <= 0 ? 0 : (pedidos / maximo).clamp(0.0, 1.0);

/// A hora em que o seletor abre: a hora atual se houver dados nela; senão a
/// hora seguinte com dados (a dar a volta ao dia); senão a atual.
int horaInicial(Map<int, int> porHora, int horaAtual) {
  if ((porHora[horaAtual] ?? 0) > 0) return horaAtual;
  for (var i = 1; i < 24; i++) {
    final h = (horaAtual + i) % 24;
    if ((porHora[h] ?? 0) > 0) return h;
  }
  return horaAtual;
}

/// Lê o mapa de procura (só estafeta aprovado ou admin: a função do servidor
/// recusa os outros).
class MapaProcuraService {
  MapaProcuraService._();

  static Future<List<CelulaProcura>> ler({int dias = 30, SupabaseClient? cliente}) async {
    final db = cliente ?? Supabase.instance.client;
    final r = await db.rpc('estafeta_mapa_procura', params: {'p_dias': dias});
    return [
      for (final l in (r as List? ?? const []))
        CelulaProcura.fromJson((l as Map).cast<String, dynamic>()),
    ];
  }
}
