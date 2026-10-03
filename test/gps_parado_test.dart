import 'package:bora_app/utils/gps_parado.dart';
import 'package:flutter_test/flutter_test.dart';

/// [ronda-fecho-2026-09-22 · A10] O painel tem de dizer "GPS parado há X min".
///
/// **A cicatriz (23/09):** Euliney Fernandes aparecia "online" com heartbeat
/// de 3 s (o serviço em segundo plano continuava a bater) e a última posição
/// GPS tinha 19 horas. A app tinha morrido e ele continuava a receber ofertas
/// que não podia aceitar — e o painel não mostrava nada de errado.
void main() {
  group('gpsParadoTexto', () {
    test('sem posição nunca → "sem GPS"', () {
      expect(gpsParadoTexto(null), 'sem GPS');
      expect(gpsParadoHaTexto(null), 'sem GPS');
    });

    test('arredonda os minutos para cima (181 s já são 4 min)', () {
      expect(gpsParadoTexto(181), 'GPS parado há 4 min');
      expect(gpsParadoTexto(240), 'GPS parado há 4 min');
      expect(gpsParadoTexto(1140), 'GPS parado há 19 min');
    });

    test('nunca diz "0 min" — relógio adiantado ou segundos vão a 1 min', () {
      expect(gpsParadoTexto(0), 'GPS parado há 1 min');
      expect(gpsParadoTexto(30), 'GPS parado há 1 min');
      expect(gpsParadoTexto(-5), 'GPS parado há 1 min');
    });

    test('60 min ainda em minutos; acima disso "mais de 1 h"', () {
      expect(gpsParadoTexto(3600), 'GPS parado há 60 min');
      expect(gpsParadoTexto(3601), 'GPS parado há mais de 1 h');
      // O caso Euliney: 19 horas sem posição.
      expect(gpsParadoTexto(19 * 3600), 'GPS parado há mais de 1 h');
    });

    test('versão sem prefixo, para linhas que já dizem "GPS:"', () {
      expect(gpsParadoHaTexto(1140), 'parado há 19 min');
      expect(gpsParadoHaTexto(3601), 'parado há mais de 1 h');
    });
  });

  group('gpsParado', () {
    test('no limite exacto ainda é fresco; um segundo acima é parado', () {
      // Igual ao servidor: fresco = last_at > now() - limite.
      expect(gpsParado(180, 180), isFalse);
      expect(gpsParado(181, 180), isTrue);
      expect(gpsParado(0, 180), isFalse);
    });

    test(
        'sem posição conta como parado (o servidor também não o dá por fresco)',
        () {
      expect(gpsParado(null, 180), isTrue);
    });

    test('respeita o limite vindo do painel, não um número fixo', () {
      expect(gpsParado(500, 600), isFalse);
      expect(gpsParado(700, 600), isTrue);
      expect(gpsParado(200, 60), isTrue);
    });
  });

  group('gpsIdadeTexto (GPS fresco, texto neutro)', () {
    test('segundos, minutos, horas, dias', () {
      expect(gpsIdadeTexto(12), 'há 12 s');
      expect(gpsIdadeTexto(59), 'há 59 s');
      expect(gpsIdadeTexto(60), 'há 1 min');
      expect(gpsIdadeTexto(150), 'há 2 min');
      expect(gpsIdadeTexto(3 * 3600 + 5), 'há 3 h');
      expect(gpsIdadeTexto(3 * 86400), 'há 3 dias');
    });

    test('sem posição e relógio adiantado', () {
      expect(gpsIdadeTexto(null), 'sem GPS');
      expect(gpsIdadeTexto(-10), 'há 0 s');
    });
  });

  test('o fallback do limite é 180 s enquanto ninguém leu platform_settings',
      () {
    expect(kGpsFrescoSegundosPadrao, 180);
    expect(limiteGpsFrescoCache, 180);
  });
}
