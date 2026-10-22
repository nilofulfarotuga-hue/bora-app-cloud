// Missão documentos-todos-papeis-22-10: o que falta à limpeza e à lavagem é a
// mesma regra no painel e na app do prestador.
import 'package:bora_app/services/prestador_documentos.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _c(List l) => l.map((d) => d.chave as String).toList();

Map<String, dynamic> _legais() => {
      'legal_name': 'Maria Teste',
      'nif': '215645154',
      'address': 'Rua de Teste 1, Guarda',
      'birth_date': '1990-01-01',
      'iban': 'PT50000201231234567890154',
      'dsa_self_certified_at': '2026-10-22T10:00:00Z',
    };

void main() {
  test('docs com sim/não e lista não contam como documento (rebentava)', () {
    final c = <String, dynamic>{
      'docs': {
        'materials_ok': true,
        'materials_list': ['Aspirador'],
      },
    };
    expect(docCaminho(c, 'materials_ok'), isNull);
    expect(docCaminho(c, 'materials_list'), isNull);
    expect(docCaminho(c, 'id_doc'), isNull);
  });

  test('limpeza: lavadora real de 01/10 com tudo menos o comprovativo', () {
    final c = <String, dynamic>{
      'photo_url': 'https://x/avatars/u/avatar.jpg',
      'docs': {
        'id_doc': 'u/id_doc_1.jpg',
        'materials_ok': true,
        'materials_list': ['Aspirador'],
      },
      ..._legais(),
    };
    expect(documentosEmFaltaLimpeza(c), isEmpty);
    expect(_c(documentosEmFaltaLimpeza(c, atividadeEmFalta: true)),
        ['atividade']);
  });

  test('limpeza: candidatura antiga sem nada', () {
    expect(_c(documentosEmFaltaLimpeza(<String, dynamic>{'docs': {}})), [
      'photo',
      'id_doc',
      'materials',
      'legal_name',
      'nif',
      'address',
      'birth_date',
      'iban',
      'dsa',
    ]);
  });

  test('lavagem pede também a carta de condução', () {
    final w = <String, dynamic>{
      'photo_url': 'https://x/a.jpg',
      'docs': {'id_doc': 'u/id.jpg', 'materials_ok': true},
      ..._legais(),
    };
    expect(_c(documentosEmFaltaLavagem(w)), ['driving_license']);
    w['docs'] = {
      'id_doc': 'u/id.jpg',
      'driving_license': 'u/carta.jpg',
      'materials_ok': true,
    };
    expect(documentosEmFaltaLavagem(w), isEmpty);
  });

  test('lavadores reais de 27-28/08: aprovados sem documentos', () {
    final w = <String, dynamic>{
      'photo_url': 'https://x/a.jpg',
      'docs': {},
      'nif': '123',
    };
    final c = _c(documentosEmFaltaLavagem(w));
    expect(c, containsAll(['id_doc', 'driving_license', 'iban', 'dsa']));
    expect(c, isNot(contains('photo')));
  });
}
