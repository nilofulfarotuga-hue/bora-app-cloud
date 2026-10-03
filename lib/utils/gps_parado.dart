// lib/utils/gps_parado.dart
//
// [ronda-fecho-2026-09-22 · A10] "GPS parado há X min" no painel admin (PT-BR).
//
// A cicatriz (23/09 12:40Z): Euliney Fernandes aparecia "online" com heartbeat
// de 3 s (o serviço em segundo plano continuava a bater) e a última posição GPS
// tinha 19 horas — a app tinha morrido, mas continuava a receber ofertas que
// não podia aceitar. O servidor passou a tratar online = heartbeat vivo E GPS
// fresco (`platform_settings.dispatch_gps_fresh_seconds`, 180 s). O painel tem
// de DIZER quando é o GPS que está parado, senão o Danilo vê "ligado" e não
// percebe porque é que o pedido não chega.
//
// As funções de texto/decisão são puras (testam-se sem Flutter nem Supabase:
// `test/gps_parado_test.dart`). O limite lê-se de `platform_settings` via
// `get_setting`, com fallback 180 e cache em memória (uma leitura por sessão).
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fallback de arranque/offline. A verdade vive em `platform_settings`
/// (`dispatch_gps_fresh_seconds`, categoria dispatch).
const int kGpsFrescoSegundosPadrao = 180;

/// "GPS parado há X min" (X = minutos arredondados para cima, nunca 0),
/// "GPS parado há mais de 1 h" acima de 60 min, "sem GPS" quando nunca houve
/// posição (`gps_age_s` nulo).
String gpsParadoTexto(int? gpsAgeS) {
  if (gpsAgeS == null) return 'sem GPS';
  return 'GPS ${gpsParadoHaTexto(gpsAgeS)}';
}

/// O mesmo sem o prefixo "GPS " — para linhas que já têm o rótulo "GPS:"
/// à frente ("GPS: parado há 19 min"). "sem GPS" quando nunca houve posição.
String gpsParadoHaTexto(int? gpsAgeS) {
  if (gpsAgeS == null) return 'sem GPS';
  final s = gpsAgeS < 0 ? 0 : gpsAgeS; // relógio adiantado → nunca negativo
  if (s > 3600) return 'parado há mais de 1 h';
  final min = (s / 60).ceil();
  return 'parado há ${min < 1 ? 1 : min} min';
}

/// Idade da posição em texto neutro, para quando o GPS está fresco:
/// "há 12 s", "há 2 min", "há 3 h", "há 2 dias". "sem GPS" se nunca houve.
String gpsIdadeTexto(int? gpsAgeS) {
  if (gpsAgeS == null) return 'sem GPS';
  final s = gpsAgeS < 0 ? 0 : gpsAgeS;
  if (s < 60) return 'há $s s';
  if (s < 3600) return 'há ${s ~/ 60} min';
  if (s < 48 * 3600) return 'há ${s ~/ 3600} h';
  return 'há ${s ~/ 86400} dias';
}

/// O GPS está parado? Verdadeiro quando a idade passa o limite — e também
/// quando nunca houve posição (o servidor, em `driver_gps_fresh`, também não
/// trata "sem posição" como fresco). No limite exacto ainda é fresco, como no
/// servidor (`last_at > now() - limite`).
bool gpsParado(int? gpsAgeS, int limiteS) {
  if (gpsAgeS == null) return true;
  return gpsAgeS > limiteS;
}

int? _limiteCache;

/// Limite já carregado nesta sessão, ou o fallback se ainda ninguém chamou
/// [carregarLimiteGpsFresco] (ou se a leitura falhou).
int get limiteGpsFrescoCache => _limiteCache ?? kGpsFrescoSegundosPadrao;

/// Lê `dispatch_gps_fresh_seconds` (jsonb número) uma vez por sessão e guarda
/// em memória. Em erro ou valor disparatado devolve o fallback 180 sem o
/// guardar — a próxima chamada volta a tentar.
Future<int> carregarLimiteGpsFresco() async {
  final cached = _limiteCache;
  if (cached != null) return cached;
  try {
    final v = await Supabase.instance.client
        .rpc('get_setting', params: {'p_key': 'dispatch_gps_fresh_seconds'});
    final n = v is num
        ? v.toInt()
        : int.tryParse('${v ?? ''}'.replaceAll('"', '').trim());
    if (n != null && n > 0) {
      _limiteCache = n;
      return n;
    }
  } catch (e) {
    debugPrint('[gps_parado] dispatch_gps_fresh_seconds: $e');
  }
  return kGpsFrescoSegundosPadrao;
}
