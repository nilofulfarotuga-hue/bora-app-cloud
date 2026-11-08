import 'package:flutter_test/flutter_test.dart';
import 'package:bora_app/services/minha_conta.dart';

/// Missão m2-estafeta-conta-fila-2026-11-08 — a regra do semáforo "A minha
/// conta". O SQL da proposta (driver_minha_conta_estado) segue as mesmas regras.
void main() {
  // O caso real do Vasco (08/11): aprovado, motorista TVDE, com foto de
  // perfil e morada, sem documento, sem número, sem IBAN, sem NIF/atividade.
  final valdemir = <String, dynamic>{
    'approval_status': 'approved',
    'vehicle_type': 'carro_passageiros',
    'photo_url': 'https://x/selfie.jpg',
    'registration_selfie_url': null,
    'document_photo_url': null,
    'document_number': null,
    'address': 'Guarda',
    'birth_date': null,
    'iban': null,
    'stripe_account_status': 'none',
    'debt_cents': 0,
    'blocked_for_debt': false,
  };

  group('montarMinhaConta', () {
    test('Vasco: mostra exatamente o que lhe falta, a vermelho', () {
      final e = montarMinhaConta(
        driver: valdemir,
        fiscal: {
          'completo': false,
          'bloqueado': false,
          'prazo': '2026-11-20',
        },
        atividadeStatus: 'por_enviar',
      );
      final falta = e.emFalta.map((i) => i.chave).toList();
      expect(falta, [
        'document',
        'document_number',
        'nascimento',
        'iban',
        'fiscal',
        'atividade',
      ]);
      // Tem selfie (foto de perfil) e morada: verdes.
      expect(e.item('selfie')!.estado, EstadoItemConta.ok);
      expect(e.item('morada')!.estado, EstadoItemConta.ok);
      // TVDE: o veículo vive na Conformidade TVDE, não aqui.
      expect(e.item('vehicle'), isNull);
      expect(e.item('license_plate'), isNull);
      // Ainda dentro do prazo: nada bloqueia o online.
      expect(e.bloqueantes, isEmpty);
      expect(e.resumoBarra,
          'Falta: documento, n.º do documento, data de nascimento, IBAN, NIF e comprovativo de atividade');
    });

    test('fiscal fora do prazo bloqueia o online', () {
      final e = montarMinhaConta(
        driver: valdemir,
        fiscal: {'completo': false, 'bloqueado': true, 'prazo': '2026-10-30'},
      );
      expect(e.bloqueantes.map((i) => i.chave), ['fiscal']);
      expect(e.item('fiscal')!.detalhe, 'Sem isto não podes ficar online.');
    });

    test('estafeta de mota com tudo enviado: só o opcional (Stripe) a vermelho',
        () {
      final e = montarMinhaConta(
        driver: {
          'approval_status': 'approved',
          'vehicle_type': 'motorcycle',
          'registration_selfie_url': 'a',
          'document_photo_url': 'b',
          'document_number': '123',
          'vehicle_photo_url': 'c',
          'license_plate': 'AA-00-AA',
          'address': 'Rua',
          'birth_date': '1990-01-01',
          'iban': 'PT50000201231234567890154',
        },
        fiscal: {'completo': true, 'bloqueado': false},
        atividadeStatus: 'aprovada',
        recibo: {'recibo_passado': true},
      );
      expect(e.tudoEmOrdem, isTrue);
      expect(e.resumoBarra, isNull);
      expect(e.item('stripe')!.emFalta, isTrue);
      expect(e.item('stripe')!.opcional, isTrue);
      expect(e.item('divida')!.estado, EstadoItemConta.ok);
    });

    test('dívida entra na barra com o valor, e só bloqueia com blocked_for_debt',
        () {
      final base = {...valdemir, 'vehicle_type': 'bicycle'};
      final e = montarMinhaConta(driver: base, dividaCents: 147);
      expect(e.item('divida')!.rotulo, 'Deves à Bora 1,47 €');
      expect(e.item('divida')!.rotuloCurto, 'dívida 1,47 €');
      expect(e.item('divida')!.bloqueiaOnline, isFalse);
      expect(e.resumoBarra, contains('dívida 1,47 €'));

      final b = montarMinhaConta(
          driver: {...base, 'blocked_for_debt': true}, dividaCents: 147);
      expect(b.bloqueantes.map((i) => i.chave), ['divida']);
    });

    test('a coluna debt_cents conta quando é maior', () {
      final e = montarMinhaConta(
          driver: {...valdemir, 'debt_cents': 500}, dividaCents: 147);
      expect(e.dividaCents, 500);
    });

    test('robô recusou a selfie: volta a vermelho com o motivo', () {
      final e = montarMinhaConta(
        driver: {...valdemir, 'registration_selfie_url': 's', 'photo_url': null},
        robo: {
          'drivers.registration_selfie_url':
              const DecisaoRobo('errado', 'A foto não mostra o rosto.'),
        },
      );
      final s = e.item('selfie')!;
      expect(s.estado, EstadoItemConta.falta);
      expect(s.detalhe, 'A foto não mostra o rosto.');
    });

    test('robô em dúvida: amarelo', () {
      final e = montarMinhaConta(
        driver: {...valdemir, 'document_photo_url': 'd'},
        robo: {'drivers.document_photo_url': const DecisaoRobo('duvida')},
      );
      expect(e.item('document')!.estado, EstadoItemConta.emAnalise);
    });

    test('conta por aprovar: item de aprovação amarelo e bloqueante', () {
      final e = montarMinhaConta(
          driver: {...valdemir, 'approval_status': 'pending'});
      final a = e.item('aprovacao')!;
      expect(a.estado, EstadoItemConta.emAnalise);
      expect(e.itens.first.chave, 'aprovacao');
    });

    test('comprovativo em análise com documento: amarelo', () {
      final e = montarMinhaConta(
          driver: valdemir,
          atividadeStatus: 'em_analise',
          atividadeTemDocumento: true);
      expect(e.item('atividade')!.estado, EstadoItemConta.emAnalise);
      final semDoc = montarMinhaConta(
          driver: valdemir, atividadeStatus: 'em_analise');
      expect(semDoc.item('atividade')!.estado, EstadoItemConta.falta);
    });

    test('recibo verde por passar diz o mês anterior', () {
      final e = montarMinhaConta(
        driver: valdemir,
        recibo: {'recibo_passado': false},
        hoje: DateTime(2026, 11, 8),
      );
      expect(e.item('recibo')!.rotulo, 'Recibo verde de outubro');
      expect(e.item('recibo')!.emFalta, isTrue);
    });
  });

  group('EstadoMinhaConta.fromJson (resposta do servidor)', () {
    test('lê a lista e o semáforo', () {
      final e = EstadoMinhaConta.fromJson({
        'ok': true,
        'divida_cents': 147,
        'itens': [
          {
            'chave': 'iban',
            'rotulo': 'IBAN (para receberes)',
            'rotulo_curto': 'IBAN',
            'estado': 'falta',
            'bloqueia': false,
          },
          {
            'chave': 'fiscal',
            'rotulo': 'NIF',
            'rotulo_curto': 'NIF',
            'estado': 'falta',
            'bloqueia': true,
          },
          {'chave': 'selfie', 'rotulo': 'Selfie', 'estado': 'ok'},
          {'chave': 'stripe', 'rotulo': 'Stripe', 'estado': 'falta', 'opcional': true},
        ],
      });
      expect(e.doServidor, isTrue);
      expect(e.dividaCents, 147);
      expect(e.emFalta.map((i) => i.chave), ['iban', 'fiscal']);
      expect(e.bloqueantes.map((i) => i.chave), ['fiscal']);
      expect(e.resumoBarra, 'Falta: IBAN e NIF');
    });

    test('resposta inválida = lista vazia (falha aberta)', () {
      expect(EstadoMinhaConta.fromJson(null).itens, isEmpty);
      expect(EstadoMinhaConta.fromJson({'ok': false}).itens, isEmpty);
    });

    test('ida e volta pelo JSON mantém o item', () {
      const i = ItemConta(
          chave: 'selfie',
          rotulo: 'Foto pessoal (selfie)',
          rotuloCurto: 'selfie',
          estado: EstadoItemConta.emAnalise,
          kindFoto: 'selfie');
      final j = ItemConta.fromJson(i.toJson());
      expect(j.estado, EstadoItemConta.emAnalise);
      expect(j.kindFoto, 'selfie');
      expect(j.eFoto, isTrue);
    });
  });

  group('IBAN', () {
    test('aceita um IBAN PT com o controlo certo, com espaços', () {
      expect(ibanPtValido('PT50 0002 0123 1234 5678 9015 4'), isTrue);
    });
    test('recusa um dígito trocado', () {
      expect(ibanPtValido('PT50000201231234567890155'), isFalse);
    });
    test('recusa outro país e tamanho errado', () {
      expect(ibanPtValido('ES9121000418450200051332'), isFalse);
      expect(ibanPtValido('PT5000020123'), isFalse);
    });
  });

  group('fila de espera do candidato', () {
    test('as cinco fases', () {
      expect(
          faseDoCandidato(
              approvalStatus: 'approved',
              emFalta: 3,
              roboAgir: true,
              roboTudoOk: false),
          FaseCandidato.aprovado);
      expect(
          faseDoCandidato(
              approvalStatus: 'pending',
              emFalta: 2,
              roboAgir: false,
              roboTudoOk: false),
          FaseCandidato.documentosPendentes);
      expect(
          faseDoCandidato(
              approvalStatus: 'pending',
              emFalta: 0,
              roboAgir: true,
              roboTudoOk: true,
              roboRecusouAlgum: true),
          FaseCandidato.documentosPendentes);
      expect(
          faseDoCandidato(
              approvalStatus: 'pending',
              emFalta: 0,
              roboAgir: true,
              roboTudoOk: false),
          FaseCandidato.emVerificacao);
      expect(
          faseDoCandidato(
              approvalStatus: 'pending',
              emFalta: 0,
              roboAgir: false,
              roboTudoOk: false),
          FaseCandidato.filaDeEspera);
      expect(
          faseDoCandidato(
              approvalStatus: 'rejected',
              emFalta: 0,
              roboAgir: false,
              roboTudoOk: false),
          FaseCandidato.recusado);
    });

    test('texto da fase ida e volta', () {
      for (final f in FaseCandidato.values) {
        expect(faseCandidatoDeTexto(faseCandidatoParaTexto(f)), f);
      }
    });
  });

  group('textos fixos da fila', () {
    test('nunca dizem "pouca procura" nem "não há pedidos"', () {
      final todos = [
        TextosFila.tudoEntregue,
        TextosFila.emFalta(['selfie', 'IBAN']),
        TextosFila.recusado('documento'),
        TextosFila.recusado('documento', ilegivel: false),
      ];
      for (final t in todos) {
        for (final p in TextosFila.proibidas) {
          expect(t.toLowerCase().contains(p), isFalse, reason: t);
        }
      }
    });
    test('lista do que falta com "e"', () {
      expect(TextosFila.emFalta(['selfie', 'documento', 'IBAN']),
          contains('falta enviar selfie, documento e IBAN.'));
    });
  });

  test('euros()', () {
    expect(euros(147), '1,47 €');
    expect(euros(-2500), '25,00 €');
  });
}
