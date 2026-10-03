import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/models/carwash_models.dart';

/// O bug que estes testes fecham (2026-08-27):
/// o cliente carregou em "Pedir lavagem" com os campos vazios e a app não lhe
/// disse NADA — o `Form.validate()` falhava em silêncio e os erros ficavam em
/// campos fora do ecrã. Ele concluiu que o pagamento estava bloqueado; nos
/// logs do servidor não havia uma única chamada, porque o pedido nunca saiu.
///
/// A regra passou a viver em `CarwashFormCheck` para poder ser provada sem
/// montar UI. Se algum destes testes ficar vermelho, o botão voltou a poder
/// falhar calado.
void main() {
  group('CarwashFormCheck — o botão tem de dizer o que falta', () {
    test('formulário vazio: aponta a morada, e não fica calado', () {
      final r = CarwashFormCheck.primeiroEmFalta(
          morada: '', matricula: '', telefone: '');
      expect(r, isNotNull);
      expect(r!.campo, CarwashCampo.morada);
      expect(r.mensagem, 'Falta dizer onde está o carro.');
    });

    test('só a morada preenchida: pede a matrícula', () {
      final r = CarwashFormCheck.primeiroEmFalta(
          morada: 'Rua do Torreão 14, Guarda', matricula: '', telefone: '');
      expect(r!.campo, CarwashCampo.matricula);
      expect(r.mensagem, 'Falta a matrícula do carro.');
    });

    test('falta o telemóvel: pede o telemóvel', () {
      final r = CarwashFormCheck.primeiroEmFalta(
          morada: 'Rua do Torreão 14, Guarda',
          matricula: 'AA-11-BB',
          telefone: '');
      expect(r!.campo, CarwashCampo.telefone);
      expect(r.mensagem, contains('telemóvel'));
    });

    test('telemóvel com menos de 9 dígitos não passa', () {
      final r = CarwashFormCheck.primeiroEmFalta(
          morada: 'Rua do Torreão 14, Guarda',
          matricula: 'AA-11-BB',
          telefone: '93750');
      expect(r!.campo, CarwashCampo.telefone);
    });

    test('telemóvel com espaços e traços conta os dígitos, não os símbolos', () {
      final r = CarwashFormCheck.primeiroEmFalta(
          morada: 'Rua do Torreão 14, Guarda',
          matricula: 'AA-11-BB',
          telefone: '937 501 673');
      expect(r, isNull, reason: 'nove dígitos é um número válido');
    });

    test('espaços em branco não contam como preenchido', () {
      final r = CarwashFormCheck.primeiroEmFalta(
          morada: '    ', matricula: 'AA-11-BB', telefone: '937501673');
      expect(r!.campo, CarwashCampo.morada);
    });

    test('tudo preenchido: deixa passar', () {
      final r = CarwashFormCheck.primeiroEmFalta(
          morada: 'Rua do Torreão 14, Guarda',
          matricula: 'AA-11-BB',
          telefone: '937501673');
      expect(r, isNull);
    });
  });

  group('CarwashBooking.addressLine — morada sem repetir a cidade', () {
    CarwashBooking comMorada(String rua, String cidade) =>
        CarwashBooking.fromSupabase({
          'id': 'x',
          'client_user_id': 'u',
          'service_type': 'exterior',
          'status': 'scheduled',
          'plate': 'AA-11-BB',
          'client_phone': '937501673',
          'scheduled_at': '2026-08-27T12:00:00Z',
          'address_street': rua,
          'address_city': cidade,
        });

    test('não repete a cidade quando a rua já a traz', () {
      expect(comMorada('Rua do Torreão 14, Guarda, Portugal', 'Guarda')
          .addressLine, 'Rua do Torreão 14, Guarda, Portugal');
    });

    test('junta a cidade quando falta mesmo', () {
      expect(comMorada('Rua do Torreão 14', 'Guarda').addressLine,
          'Rua do Torreão 14, Guarda');
    });

    test('aguenta cidade vazia', () {
      expect(comMorada('Rua do Torreão 14', '').addressLine,
          'Rua do Torreão 14');
    });
  });
}
