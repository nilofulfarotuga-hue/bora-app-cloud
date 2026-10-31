// CASA (missão casa-manutencao-2026-10-30): o papel novo 'handyman' (Casa e
// manutenção) tem de existir em TODAS as listas partilhadas onde a limpeza e a
// lavagem já estavam — regra 1.18 do PADRAO_BORA (nada de listas fixas
// incompletas nem de "o resto é a lavagem").
import 'package:bora_app/services/papeis_de_trabalho.dart';
import 'package:bora_app/services/push_token_service.dart';
import 'package:bora_app/services/roles_service.dart';
import 'package:bora_app/services/legal_fields_service.dart';
import 'package:flutter_test/flutter_test.dart';

RolesSummary _r({String? d, String? c, String? w, String? h}) =>
    RolesSummary.fromJson({
      'has_driver': d != null,
      'driver_status': d,
      'has_cleaner': c != null,
      'cleaner_status': c,
      'has_washer': w != null,
      'washer_status': w,
      'has_handyman': h != null,
      'handyman_status': h,
    });

void main() {
  group('RolesSummary lê a Casa do JSON da RPC', () {
    test('has_handyman / handyman_status / handyman_profile', () {
      final r = RolesSummary.fromJson({
        'has_handyman': true,
        'handyman_status': 'pending',
        'handyman_profile': {'name': 'Rui', 'phone': '910000002'},
      });
      expect(r.hasHandyman, isTrue);
      expect(r.handymanPending, isTrue);
      expect(r.handymanApproved, isFalse);
      expect(r.handymanProfile?['phone'], '910000002');
      expect(r.temAlgumPapel, isTrue,
          reason: 'quem só faz Casa já é alguém no Bora');
      expect(r.dadosJaConhecidos?['name'], 'Rui');
    });

    test('o resumo vazio não tem Casa', () {
      final r = RolesSummary.empty();
      expect(r.hasHandyman, isFalse);
      expect(r.handymanStatus, isNull);
      expect(r.handymanProfile, isNull);
    });

    test('o construtor antigo (sem Casa) continua a compilar e diz "sem Casa"',
        () {
      final r = RolesSummary(
        hasDriver: true,
        driverStatus: 'approved',
        hasCleaner: false,
        cleanerStatus: null,
        hasWasher: false,
        washerStatus: null,
        driverProfile: null,
        cleanerProfile: null,
        washerProfile: null,
      );
      expect(r.hasHandyman, isFalse);
      expect(r.handymanApproved, isFalse);
    });
  });

  group('o portão abre a Casa a quem só tem a Casa aprovada', () {
    test('só Casa aprovada → entra na Casa', () {
      expect(entradaDoPrestador(_r(d: 'rejected', h: 'approved')),
          EntradaDoPrestador.casa);
    });

    test('Casa pendente não abre nada', () {
      expect(entradaDoPrestador(_r(h: 'pending')), EntradaDoPrestador.nenhuma);
    });

    test('último modo "casa" abre a Casa se continuar aprovada', () {
      final todos = _r(d: 'approved', c: 'approved', h: 'approved');
      expect(entradaDoPrestador(todos), EntradaDoPrestador.estafeta);
      expect(entradaDoPrestador(todos, ultimoModo: 'casa'),
          EntradaDoPrestador.casa);
      expect(
          entradaDoPrestador(_r(d: 'approved', h: 'suspended'),
              ultimoModo: 'casa'),
          EntradaDoPrestador.estafeta);
    });

    test('trabalho da Casa à espera manda mais do que o último modo', () {
      final dois = _r(d: 'approved', h: 'approved');
      expect(
          entradaDoPrestador(dois,
              ultimoModo: 'estafeta',
              pendente: const TrabalhoPendente(casa: true)),
          EntradaDoPrestador.casa);
      // O estafeta ligado nunca é tirado do ecrã dele.
      expect(
          entradaDoPrestador(dois,
              pendente: const TrabalhoPendente(estafeta: true, casa: true)),
          EntradaDoPrestador.estafeta);
    });

    test('TrabalhoPendente lê a chave "casa"', () {
      expect(TrabalhoPendente.fromJson({'casa': true}).casa, isTrue);
      expect(TrabalhoPendente.fromJson({'lavagem': true}).casa, isFalse);
      expect(TrabalhoPendente.nenhum.casa, isFalse);
    });

    test('modo ↔ entrada fazem ida e volta para todos os modos', () {
      for (final e in EntradaDoPrestador.values) {
        final modo = modoDaEntrada(e);
        if (e == EntradaDoPrestador.nenhuma) {
          expect(modo, isNull);
          continue;
        }
        expect(modo, isNotNull, reason: '$e sem modo guardado');
        expect(entradaDoModo(modo), e, reason: '$modo não volta a $e');
      }
      expect(modoDaEntrada(EntradaDoPrestador.casa), 'casa');
      expect(entradaDoModo('casa'), EntradaDoPrestador.casa);
    });
  });

  group('as listas de papéis conhecem a Casa', () {
    test('a porta "Quero trabalhar" mostra a Casa e manutenção', () {
      final a = atividadesDisponiveis(RolesSummary.empty());
      expect(a.map((x) => x.papel), contains('handyman'));
      expect(a.firstWhere((x) => x.papel == 'handyman').titulo,
          'Casa e manutenção');
    });

    test('a caixa "O que queres aceitar?" tem nome de gente para handyman', () {
      expect(PapelDeTrabalho.conhecidos, contains('handyman'));
      const p = PapelDeTrabalho(papel: 'handyman', aceita: true);
      expect(p.titulo, 'Casa e manutenção');
      expect(p.temNomeProprio, isTrue);
    });

    test('o profissional da Casa pode receber avisos (push)', () {
      expect(PushTokenService.papeisComPush, contains('handyman'));
      expect(PushTokenService.tabelaDoPapel('handyman'),
          'provider_push_tokens (role=handyman)');
    });

    test('os dados fiscais aceitam o papel handyman', () {
      expect(LegalFieldsService.roles, contains('handyman'));
    });
  });
}
