// Missão cadastro-estafeta-fotos-22-10: a regra do que falta a um estafeta é
// a mesma no painel e no ecrã "Conta em análise"; o tipo da foto vem dos bytes.
import 'dart:typed_data';

import 'package:bora_app/services/driver_documentos.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _chaves(List<DocEmFalta> l) => l.map((d) => d.chave).toList();

void main() {
  group('documentosEmFaltaEstafeta', () {
    test('caso do SAM (22/10): só tipo de doc, NIF, veículo e IBAN', () {
      final sam = <String, dynamic>{
        'vehicle_type': 'motorcycle',
        'document_type': 'Cartão Cidadão',
        'nif': '322641543',
        'iban': 'PT50000000000000000000000',
        'photo_url': null,
        'registration_selfie_url': null,
        'document_photo_url': null,
        'document_number': null,
        'vehicle_photo_url': null,
        'license_plate': null,
      };
      expect(_chaves(documentosEmFaltaEstafeta(sam)), [
        'selfie',
        'document',
        'document_number',
        'vehicle',
        'license_plate',
      ]);
    });

    test('comprovativo de atividade entra quando falta', () {
      final d = <String, dynamic>{
        'vehicle_type': 'bicycle',
        'registration_selfie_url': 'driver-documents/u/selfie.jpg',
        'document_photo_url': 'driver-documents/u/doc.jpg',
        'document_number': '123',
        'iban': 'PT50',
      };
      expect(documentosEmFaltaEstafeta(d), isEmpty);
      expect(_chaves(documentosEmFaltaEstafeta(d, atividadeEmFalta: true)),
          ['atividade']);
    });

    test('bicicleta não precisa de matrícula nem foto do veículo', () {
      final d = <String, dynamic>{'vehicle_type': 'bicycle'};
      final c = _chaves(documentosEmFaltaEstafeta(d));
      expect(c, isNot(contains('license_plate')));
      expect(c, isNot(contains('vehicle')));
    });

    test('photo_url (já aprovado) também conta como selfie; espaços = vazio',
        () {
      final d = <String, dynamic>{
        'vehicle_type': 'car',
        'photo_url': 'https://x/y.jpg',
        'document_photo_url': '   ',
      };
      final c = _chaves(documentosEmFaltaEstafeta(d));
      expect(c, isNot(contains('selfie')));
      expect(c, contains('document'));
    });

    test('fotos em falta trazem o kind que a Edge aceita', () {
      final l = documentosEmFaltaEstafeta(<String, dynamic>{});
      final kinds = {for (final d in l) d.chave: d.kindFoto};
      expect(kinds['selfie'], 'selfie');
      expect(kinds['document'], 'document');
      expect(kinds['vehicle'], 'vehicle');
      expect(kinds['iban'], isNull);
    });
  });

  test('parametroDoRegisto liga cada item ao RPC do cadastro', () {
    expect(parametroDoRegisto('selfie'), 'p_registration_selfie_url');
    expect(parametroDoRegisto('document'), 'p_document_photo_url');
    expect(parametroDoRegisto('vehicle'), 'p_vehicle_photo_url');
    expect(parametroDoRegisto('vehicle_doc'), 'p_vehicle_doc_url');
    expect(parametroDoRegisto('document_number'), 'p_document_number');
    expect(parametroDoRegisto('license_plate'), 'p_license_plate');
    expect(parametroDoRegisto('iban'), isNull);
    expect(parametroDoRegisto('atividade'), isNull);
  });

  test('veiculoEmPortugues nunca mostra o valor técnico em inglês', () {
    expect(veiculoEmPortugues('motorcycle'), 'Mota');
    expect(veiculoEmPortugues('bicycle'), 'Bicicleta');
    expect(veiculoEmPortugues('car'), 'Carro');
    expect(veiculoEmPortugues('carro_passageiros'), 'Carro de passageiros');
    expect(veiculoEmPortugues(null), '—');
  });

  test('juntarComE', () {
    expect(juntarComE([]), '');
    expect(juntarComE(['a']), 'a');
    expect(juntarComE(['a', 'b']), 'a e b');
    expect(juntarComE(['a', 'b', 'c']), 'a, b e c');
  });

  test('idadeEmAnos conta o aniversário', () {
    final hoje = DateTime(2026, 10, 22);
    expect(idadeEmAnos(DateTime(1994, 9, 15), hoje), 32);
    expect(idadeEmAnos(DateTime(1994, 10, 23), hoje), 31);
    expect(idadeEmAnos(null, hoje), isNull);
  });

  group('tipo da foto pelos bytes', () {
    test('JPEG, PNG, WebP, HEIC', () {
      expect(tipoDaFoto(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])),
          TipoFoto.jpeg);
      expect(
          tipoDaFoto(Uint8List.fromList(
              [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])),
          TipoFoto.png);
      expect(
          tipoDaFoto(Uint8List.fromList(
              'RIFF\x00\x00\x00\x00WEBP'.codeUnits)),
          TipoFoto.webp);
      expect(
          tipoDaFoto(
              Uint8List.fromList('\x00\x00\x00\x18ftypheic'.codeUnits)),
          TipoFoto.heic);
      expect(tipoDaFoto(Uint8List(0)), TipoFoto.desconhecido);
    });

    test('mimeDaFoto dá o nome oficial (nunca image/jpg)', () {
      expect(mimeDaFoto(TipoFoto.jpeg), 'image/jpeg');
      expect(mimeDaFoto(TipoFoto.png), 'image/png');
      expect(mimeDaFoto(TipoFoto.webp), 'image/webp');
      expect(mimeDaFoto(TipoFoto.heic), isNull);
    });

    test('normalizarMime corrige image/jpg (a causa do bug de 22/10)', () {
      expect(normalizarMime('image/jpg'), 'image/jpeg');
      expect(normalizarMime('IMAGE/JPG'), 'image/jpeg');
      expect(normalizarMime(null), 'image/jpeg');
      expect(normalizarMime('image/png'), 'image/png');
    });
  });
}
