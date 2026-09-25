import 'package:flutter_test/flutter_test.dart';
import 'package:bora_app/services/roles_service.dart';

/// MULTI-PAPEL — testes da lógica pura que decide os cards de convite/troca e
/// o parsing do resumo de papéis (`my_roles_summary`). Não toca em rede.
void main() {
  group('crossRoleStateFor', () {
    test('sem o outro papel (null) → convidar', () {
      expect(crossRoleStateFor(null), CrossRoleCardState.invite);
    });

    test('outro papel recusado → convidar (recandidatar)', () {
      expect(crossRoleStateFor('rejected'), CrossRoleCardState.invite);
    });

    test('outro papel em análise → pending', () {
      expect(crossRoleStateFor('pending'), CrossRoleCardState.pending);
    });

    test('outro papel aprovado → active (abrir/trocar)', () {
      expect(crossRoleStateFor('approved'), CrossRoleCardState.active);
    });

    test('estado desconhecido → convidar (fallback seguro)', () {
      expect(crossRoleStateFor('whatever'), CrossRoleCardState.invite);
    });
  });

  group('RolesSummary.fromJson', () {
    test('estafeta aprovado a candidatar-se a limpeza (só driver)', () {
      final s = RolesSummary.fromJson({
        'has_driver': true,
        'driver_status': 'approved',
        'has_cleaner': false,
        'cleaner_status': null,
        'driver_profile': {
          'name': 'Ana',
          'phone': '+351910000000',
          'email': 'ana@x.pt',
          'nif': '123456789',
          'photo_url': 'https://x/avatar.jpg',
        },
        'cleaner_profile': null,
      });
      expect(s.hasDriver, isTrue);
      expect(s.driverApproved, isTrue);
      expect(s.hasCleaner, isFalse);
      // Prefill para a candidatura de limpeza vem do perfil de driver.
      expect(s.driverProfile?['name'], 'Ana');
      expect(s.driverProfile?['photo_url'], 'https://x/avatar.jpg');
      expect(s.cleanerProfile, isNull);
      // O card de "Entregas e Viagens" na home da limpeza estaria em 'active'
      // (já é driver aprovado) — mas aqui ela ainda não é cleaner.
      expect(crossRoleStateFor(s.driverStatus), CrossRoleCardState.active);
    });

    test('profissional de limpeza aprovada, sem papel de estafeta', () {
      final s = RolesSummary.fromJson({
        'has_driver': false,
        'driver_status': null,
        'has_cleaner': true,
        'cleaner_status': 'approved',
        'driver_profile': null,
        'cleaner_profile': {'name': 'Rui', 'phone': '+351920000000'},
      });
      expect(s.hasCleaner, isTrue);
      expect(s.cleanerApproved, isTrue);
      expect(s.hasDriver, isFalse);
      // Card de estafeta na home da limpeza → convidar (ainda não é driver).
      expect(crossRoleStateFor(s.driverStatus), CrossRoleCardState.invite);
      // Prefill da candidatura a estafeta vem do perfil de limpeza.
      expect(s.cleanerProfile?['name'], 'Rui');
    });

    test('duplo papel: driver aprovado + candidatura de limpeza em análise', () {
      final s = RolesSummary.fromJson({
        'has_driver': true,
        'driver_status': 'approved',
        'has_cleaner': true,
        'cleaner_status': 'pending',
        'driver_profile': {'name': 'Zé'},
        'cleaner_profile': {'name': 'Zé'},
      });
      expect(s.hasDriver && s.hasCleaner, isTrue);
      expect(s.driverApproved, isTrue);
      expect(s.cleanerPending, isTrue);
      // No perfil, a entrada de limpeza mostra "A minha Limpeza" (has_cleaner).
      expect(s.hasCleaner, isTrue);
    });

    test('empty() é seguro (tudo falso/nulo)', () {
      final s = RolesSummary.empty();
      expect(s.hasDriver, isFalse);
      expect(s.hasCleaner, isFalse);
      expect(s.driverProfile, isNull);
      expect(crossRoleStateFor(s.driverStatus), CrossRoleCardState.invite);
    });
  });
}
