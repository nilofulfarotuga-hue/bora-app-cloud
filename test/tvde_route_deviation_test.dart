import 'package:bora_app/utils/route_deviation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// [Missão TVDE 05/09] O mapa do motorista deixava de recalcular a rota quando
/// ele desviava — porque a app NUNCA perguntava se tinha saído da linha.
/// Pedia rota nova a cada ~111 m (a chave era `toStringAsFixed(3)`), o que
/// a conduzir dava um pedido HTTP ao Directions de ~8 em ~8 segundos, e mesmo
/// assim o recálculo a sério nunca chegava na hora.
///
/// Estes testes trancam as duas metades do conserto:
///  1. quem SEGUE a rota não dispara recálculo nenhum (é o que corta a factura
///     do Directions de dezenas de chamadas para uma ou duas);
///  2. quem SAI da rota dispara UM recálculo, e só um.
///
/// Coordenadas reais da Guarda. As distâncias de referência foram calculadas à
/// mão por trigonometria (1 grau de longitude a 40,535 graus de latitude vale
/// cerca de 84 506 metros) — não saem da função em teste, senão o teste era
/// circular.
void main() {
  // Rua a direito no sentido norte-sul: longitude constante, latitude a variar.
  // Dois pontos apenas, ~1,1 km de comprimento — de propósito: é exactamente
  // esta a geometria em que medir ao VÉRTICE mais próximo dava falso desvio.
  final rota = <LatLng>[
    const LatLng(40.5300, -7.2670),
    const LatLng(40.5400, -7.2670),
  ];

  // Um grau de longitude aqui = 84 505,8 m. Logo:
  const grauPor60m = 60 / 84505.8; // ~0,00071 graus
  const grauPor10m = 10 / 84505.8;

  group('distância à rota — perpendicular ao segmento, não ao vértice', () {
    test('carro em cima da linha, longe dos dois extremos, está a ~0 m', () {
      // A meio do segmento: a 550 m de CADA vértice. Medir ao vértice mais
      // próximo daria 550 m de "desvio" com o carro em cima da estrada.
      const meio = LatLng(40.5350, -7.2670);
      expect(distanciaARotaMetros(meio, rota), lessThan(1.0));
    });

    test('carro 60 m ao lado da linha mede ~60 m', () {
      const fora = LatLng(40.5350, -7.2670 + grauPor60m);
      expect(distanciaARotaMetros(fora, rota), closeTo(60, 2));
    });

    test('carro 10 m ao lado da linha mede ~10 m', () {
      const quase = LatLng(40.5350, -7.2670 + grauPor10m);
      expect(distanciaARotaMetros(quase, rota), closeTo(10, 1));
    });

    test('sem rota desenhada não há desvio para medir', () {
      expect(distanciaARotaMetros(const LatLng(40.535, -7.267), const []),
          double.infinity);
    });
  });

  group('motorista a SEGUIR a rota — não pode disparar recálculo nenhum', () {
    test('vinte leituras ao longo da estrada: zero recálculos', () {
      final det = OffRouteDetector(metrosLimite: 45, leiturasSeguidas: 3);
      var disparos = 0;
      for (var i = 0; i <= 20; i++) {
        final lat = 40.5300 + (0.0100 * i / 20); // percorre a rua toda
        if (det.adicionarLeitura(LatLng(lat, -7.2670), rota)) disparos++;
      }
      expect(disparos, 0,
          reason: 'seguir a rota não pode custar uma chamada ao Directions');
    });

    test('encostado à linha (10 m, dentro do limite de 45) não dispara', () {
      final det = OffRouteDetector(metrosLimite: 45, leiturasSeguidas: 3);
      var disparos = 0;
      for (var i = 0; i < 10; i++) {
        const p = LatLng(40.5350, -7.2670 + grauPor10m);
        if (det.adicionarLeitura(p, rota)) disparos++;
      }
      expect(disparos, 0);
    });
  });

  group('motorista SAI da rota — dispara UM recálculo, e só um', () {
    test('a 60 m durante 3 leituras seguidas dispara exactamente uma vez', () {
      final det = OffRouteDetector(metrosLimite: 45, leiturasSeguidas: 3);
      const fora = LatLng(40.5350, -7.2670 + grauPor60m);

      expect(det.adicionarLeitura(fora, rota), isFalse, reason: '1.ª leitura');
      expect(det.adicionarLeitura(fora, rota), isFalse, reason: '2.ª leitura');
      expect(det.adicionarLeitura(fora, rota), isTrue, reason: '3.ª dispara');
      // E a 4.ª NÃO volta a disparar — senão era um recálculo por leitura.
      expect(det.adicionarLeitura(fora, rota), isFalse, reason: '4.ª leitura');
      expect(det.adicionarLeitura(fora, rota), isFalse, reason: '5.ª leitura');
    });

    test('dez leituras seguidas fora da linha dão 3 recálculos, não 10', () {
      final det = OffRouteDetector(metrosLimite: 45, leiturasSeguidas: 3);
      const fora = LatLng(40.5350, -7.2670 + grauPor60m);
      var disparos = 0;
      for (var i = 0; i < 10; i++) {
        if (det.adicionarLeitura(fora, rota)) disparos++;
      }
      expect(disparos, 3); // uma a cada 3 leituras, não uma por leitura
    });

    test('um salto de GPS isolado não conta como desvio', () {
      // O caso real: uma leitura má no meio de um percurso certo. Sem o
      // "leituras SEGUIDAS" isto pedia rota nova por ruído de GPS.
      final det = OffRouteDetector(metrosLimite: 45, leiturasSeguidas: 3);
      const emCima = LatLng(40.5350, -7.2670);
      const fora = LatLng(40.5350, -7.2670 + grauPor60m);

      expect(det.adicionarLeitura(fora, rota), isFalse);
      expect(det.adicionarLeitura(emCima, rota), isFalse); // zera o contador
      expect(det.adicionarLeitura(fora, rota), isFalse);
      expect(det.adicionarLeitura(fora, rota), isFalse);
      expect(det.leiturasForaSeguidas, 2, reason: 'contagem recomeçou do zero');
    });

    test('rota nova desenhada esquece o histórico', () {
      final det = OffRouteDetector(metrosLimite: 45, leiturasSeguidas: 3);
      const fora = LatLng(40.5350, -7.2670 + grauPor60m);
      det.adicionarLeitura(fora, rota);
      det.adicionarLeitura(fora, rota);
      det.reset();
      expect(det.adicionarLeitura(fora, rota), isFalse,
          reason: 'depois do reset volta a precisar de 3 leituras');
    });

    test('os limites vêm das settings — 90 m não dispara com limite a 100', () {
      final det = OffRouteDetector(metrosLimite: 100, leiturasSeguidas: 3);
      const noventaM = LatLng(40.5350, -7.2670 + (90 / 84505.8));
      var disparos = 0;
      for (var i = 0; i < 6; i++) {
        if (det.adicionarLeitura(noventaM, rota)) disparos++;
      }
      expect(disparos, 0);
    });
  });

  group('a rota apaga-se atrás do carro', () {
    test('o troço que falta começa mesmo à frente do carro', () {
      const meio = LatLng(40.5350, -7.2670);
      final p = projetarNaRota(rota, meio);
      // Primeiro ponto do que falta = o pé da perpendicular, à latitude do carro.
      expect(p.aFrente.first.latitude, closeTo(40.5350, 0.0001));
      expect(p.aFrente.last, rota.last); // e acaba no destino
      expect(p.distanciaMetros, lessThan(1.0));
    });

    test('quanto mais o carro avança, menos linha resta para trás', () {
      const inicio = LatLng(40.5310, -7.2670);
      const fim = LatLng(40.5390, -7.2670);
      final a = projetarNaRota(rota, inicio).aFrente.first.latitude;
      final b = projetarNaRota(rota, fim).aFrente.first.latitude;
      expect(b, greaterThan(a));
    });

    test('rota vazia não rebenta', () {
      final p = projetarNaRota(const [], const LatLng(40.535, -7.267));
      expect(p.aFrente, isEmpty);
      expect(p.distanciaMetros, double.infinity);
    });
  });
}
