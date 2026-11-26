// Missão fechar-bora-motorista (04/11/2026): o Bora Motorista (TVDE de
// passageiros) fecha nas apps com `platform_settings.tvde_app_visivel`.
// Estes testes provam o FECHADO: começa fechado (na dúvida, esconde), e
// fechado não se desenha nem o ladrilho, nem a "Nova categoria", nem as
// encomendas pelo motor TVDE, nem o papel "Corridas de passageiros", nem os
// avisos de corridas no sininho. Reabrir volta a mostrar tudo.
import 'package:bora_app/models/driver_model.dart';
import 'package:bora_app/services/in_app_notifications_service.dart';
import 'package:bora_app/services/minha_conta.dart';
import 'package:bora_app/services/papeis_de_trabalho.dart';
import 'package:bora_app/services/tvde_visibilidade.dart';
import 'package:bora_app/stores/tvde_store.dart';
import 'package:bora_app/utils/mensagem_online_recusado.dart';
import 'package:bora_app/widgets/caixa_de_papeis.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _caixa() => MaterialApp(
      home: Scaffold(
        body: CaixaDePapeis(
          iniciais: const [
            PapelDeTrabalho(papel: 'driver', aceita: true),
            PapelDeTrabalho(papel: 'delivery', aceita: true),
            PapelDeTrabalho(papel: 'cleaner', aceita: true),
          ],
        ),
      ),
    );

void main() {
  // Tem de correr primeiro: o estado de arranque, antes de qualquer leitura.
  test('o interruptor começa FECHADO e por ler (na dúvida, esconde)', () {
    expect(TvdeVisibilidade.lido, isFalse);
    expect(TvdeVisibilidade.aberto, isFalse);
  });

  test('sem servidor (Supabase por iniciar) a leitura falha e fica fechado',
      () async {
    await TvdeVisibilidade.refresh();
    expect(TvdeVisibilidade.aberto, isFalse);
  }, timeout: const Timeout(Duration(seconds: 30)));

  group('TvdeStore', () {
    test('fechado: nada do Bora Motorista na home', () {
      TvdeVisibilidade.definirParaTeste(false);
      final s = TvdeStore();
      addTearDown(s.dispose);
      expect(s.appVisivel, isFalse);
      expect(s.mostrarBoraMotorista, isFalse);
      expect(s.mostrarCategoriaPorDescobrir, isFalse);
      expect(s.encomendasEnabled, isFalse);
    });

    test('avisa quem o ouve quando o interruptor muda, e deixa de ouvir '
        'depois do dispose', () {
      TvdeVisibilidade.definirParaTeste(false);
      final s = TvdeStore();
      var avisos = 0;
      s.addListener(() => avisos++);
      TvdeVisibilidade.definirParaTeste(true);
      expect(avisos, 1);
      expect(s.appVisivel, isTrue);
      s.dispose();
      // Depois do dispose mudar o interruptor não rebenta (ouvinte tirado).
      TvdeVisibilidade.definirParaTeste(false);
      expect(avisos, 1);
    });
  });

  group('caixa "O que queres aceitar?"', () {
    testWidgets('fechado: sem "Corridas de passageiros"', (tester) async {
      TvdeVisibilidade.definirParaTeste(false);
      await tester.pumpWidget(_caixa());
      expect(find.text('Corridas de passageiros'), findsNothing);
      expect(find.text('Entregas'), findsOneWidget);
      expect(find.text('Limpeza'), findsOneWidget);
    });

    testWidgets('aberto: volta a aparecer', (tester) async {
      TvdeVisibilidade.definirParaTeste(true);
      addTearDown(() => TvdeVisibilidade.definirParaTeste(false));
      await tester.pumpWidget(_caixa());
      expect(find.text('Corridas de passageiros'), findsOneWidget);
    });
  });

  test('sininho: os avisos de corridas reconhecem-se pelo tipo', () {
    expect(eAvisoDoBoraMotorista({'kind': 'tvde_cancel_comp'}), isTrue);
    expect(eAvisoDoBoraMotorista({'kind': 'tvde_goodwill_credit'}), isTrue);
    expect(eAvisoDoBoraMotorista({'kind': 'ride_update'}), isTrue);
    expect(eAvisoDoBoraMotorista({'kind': 'cashback'}), isFalse);
    expect(eAvisoDoBoraMotorista({'kind': 'order_weight_adjusted'}), isFalse);
    expect(eAvisoDoBoraMotorista({'kind': null}), isFalse);
  });

  // ── 26/11/2026 (arquivo-tvde-total): o que faltou fechar ──────────────────

  test('sininho: avisos dos documentos da Ficha legal também saem', () {
    expect(eAvisoDoBoraMotorista({'kind': 'motorista_documento'}), isTrue);
    expect(eAvisoDoBoraMotorista({'kind': 'ficha_legal_caducada'}), isTrue);
    expect(eAvisoDoBoraMotorista({'kind': 'tvde_conformidade'}), isTrue);
    expect(eAvisoDoBoraMotorista({'kind': 'provider_atividade'}), isFalse);
    expect(eAvisoDoBoraMotorista({'kind': 'recibo_verde'}), isFalse);
  });

  group('recusa de ficar online', () {
    final proibidas = RegExp(
        r'TVDE|Ficha legal|conformidade|limite legal|\bIMT\b|Motorista',
        caseSensitive: false);

    test('fechado: sem TVDE, Ficha legal nem limite legal de horas', () {
      TvdeVisibilidade.definirParaTeste(false);
      final bloqueado = mensagemOnlineRecusado('TVDE_BLOQUEADO',
          mensagemServidor: 'Não podes ficar online: Certificado TVDE');
      final documento = mensagemOnlineRecusado('DOCUMENTO_EXPIRADO',
          mensagemServidor: 'Dístico TVDE caducado');
      final horas = mensagemOnlineRecusado('LIMITE_HORAS',
          mensagemServidor: '10,2 h de serviço TVDE');
      for (final m in [bloqueado, documento, horas]) {
        expect(m, isNotEmpty);
        expect(proibidas.hasMatch(m), isFalse, reason: m);
        expect(m.contains('Dístico'), isFalse, reason: m);
      }
      expect(bloqueado,
          'Não podes ficar online agora. Fala com o suporte da Bora.');
      expect(documento, contains('documento fora da validade'));
      expect(documento, contains('suporte da Bora'));
      // As recusas da conta não mudam.
      expect(mensagemOnlineRecusado('CONTA_BLOQUEADA'),
          'A tua conta está bloqueada. Fala com o suporte da Bora.');
    });

    test('aberto: tudo como antes', () {
      TvdeVisibilidade.definirParaTeste(true);
      addTearDown(() => TvdeVisibilidade.definirParaTeste(false));
      expect(
          mensagemOnlineRecusado('TVDE_BLOQUEADO',
              mensagemServidor: 'Não podes ficar online: seguro caducado'),
          'Não podes ficar online: seguro caducado');
      expect(mensagemOnlineRecusado('DOCUMENTO_EXPIRADO'),
          contains('Ficha legal'));
      expect(mensagemOnlineRecusado('LIMITE_HORAS'),
          contains('limite legal de horas'));
    });
  });

  group('caixa dos papéis conta só o que se vê', () {
    const driver = PapelDeTrabalho(papel: 'driver', aceita: true);
    const limpeza = PapelDeTrabalho(papel: 'cleaner', aceita: true);
    const entregas = PapelDeTrabalho(papel: 'delivery', aceita: true);

    test('fechado: corridas + limpeza não chega para mostrar a caixa', () {
      TvdeVisibilidade.definirParaTeste(false);
      expect(mostrarCaixaDePapeis(const [driver, limpeza]), isFalse);
      expect(mostrarCaixaDePapeis(const [driver, limpeza, entregas]), isTrue);
      // As corridas escondidas não deixam desligar o último que se vê.
      expect(podeDesligar(const [driver, limpeza]), isFalse);
      expect(podeDesligar(const [driver, limpeza, entregas]), isTrue);
    });

    test('aberto: as corridas contam como antes', () {
      TvdeVisibilidade.definirParaTeste(true);
      addTearDown(() => TvdeVisibilidade.definirParaTeste(false));
      expect(mostrarCaixaDePapeis(const [driver, limpeza]), isTrue);
      expect(podeDesligar(const [driver, limpeza]), isTrue);
    });
  });

  group('carro de passageiros = estafeta de carro', () {
    final carroPassageiros = <String, dynamic>{
      'approval_status': 'approved',
      'vehicle_type': 'carro_passageiros',
      'photo_url': 'https://x/selfie.jpg',
      'document_photo_url': 'd',
      'document_number': '123',
      'vehicle_photo_url': null,
      'license_plate': null,
      'address': 'Guarda',
      'birth_date': '1990-01-01',
      'iban': 'PT50000201231234567890154',
    };

    test('fechado: "A minha conta" pede o veículo e a matrícula', () {
      TvdeVisibilidade.definirParaTeste(false);
      final e = montarMinhaConta(driver: carroPassageiros);
      expect(e.item('vehicle'), isNotNull);
      expect(e.item('vehicle')!.estado, EstadoItemConta.falta);
      expect(e.item('license_plate'), isNotNull);
    });

    test('aberto: o veículo vive na Conformidade TVDE (como antes)', () {
      TvdeVisibilidade.definirParaTeste(true);
      addTearDown(() => TvdeVisibilidade.definirParaTeste(false));
      final e = montarMinhaConta(driver: carroPassageiros);
      expect(e.item('vehicle'), isNull);
      expect(e.item('license_plate'), isNull);
    });

    test('rótulo do veículo: "Carro" fechado, "Carro — Passageiros" aberto',
        () {
      TvdeVisibilidade.definirParaTeste(false);
      expect(VehicleType.carPassengers.label, 'Carro');
      expect(VehicleTypeDb.fromDb('carro_passageiros').label, 'Carro');
      TvdeVisibilidade.definirParaTeste(true);
      addTearDown(() => TvdeVisibilidade.definirParaTeste(false));
      expect(VehicleType.carPassengers.label, 'Carro — Passageiros');
    });
  });
}
