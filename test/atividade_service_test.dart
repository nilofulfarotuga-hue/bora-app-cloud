// Comprovativo de atividade (Bloco C · 20/10/2026): NIF com as MESMAS regras
// do servidor, estados, tipo do ficheiro pelos bytes, mensagens de erro e o
// CSV do painel (só metadados).
import 'dart:io';
import 'dart:typed_data';

import 'package:bora_app/screens/admin/admin_comprovativo_atividade_screen.dart';
import 'package:bora_app/services/atividade_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NIF — paridade com public._nif_valido (valores lidos da base a 20/10)',
      () {
    // Saída literal de `select n, public._nif_valido(n) from unnest(...)`.
    const servidor = <String, bool>{
      '245123458': true,
      '245123459': false,
      '123456789': false,
      '111111111': false,
      '999999999': false,
      '000000000': false,
      '501442600': true,
      '500000000': true,
      '503504564': true,
      '745123451': false,
      '451234561': false,
      '299999998': true,
      '12345678': false,
      '2451234580': false,
      '245 123 458': true,
      'PT245123458': true,
      '980000003': false,
      '610000005': false,
    };
    for (final e in servidor.entries) {
      test('${e.key} → ${e.value}', () {
        expect(nifAtividadeValido(e.key), e.value);
      });
    }

    test('mensagens do campo', () {
      expect(validarNifAtividade(''), 'Indica o teu NIF.');
      expect(validarNifAtividade('12345'), 'O NIF tem 9 algarismos.');
      expect(validarNifAtividade('245123459'), contains('não é válido'));
      expect(validarNifAtividade('245123458'), isNull);
    });
  });

  group('estado do comprovativo', () {
    AtividadeEstado e(String status,
            {bool doc = false, bool prestador = true, String? motivo}) =>
        AtividadeEstado.fromJson({
          'e_prestador': prestador,
          'papeis': ['limpeza'],
          'atividade_status': status,
          'tem_documento': doc,
          'motivo': motivo,
          'obrigatoria': false,
          'interruptor': true,
        });

    test('por enviar → aviso e pode enviar', () {
      final x = e('por_enviar');
      expect(x.status, AtividadeStatus.porEnviar);
      expect(x.mostrarAviso, isTrue);
      expect(x.podeEnviar, isTrue);
      expect(x.rotulo, 'Por enviar');
    });

    test('em análise SEM documento (disse que tem) → ainda pede o comprovativo',
        () {
      final x = e('em_analise');
      expect(x.precisaDeEnviar, isTrue);
      expect(x.mostrarAviso, isTrue);
      expect(x.rotulo, 'Falta o comprovativo');
      expect(x.explicacao, contains('Falta enviares o comprovativo'));
    });

    test('em análise COM documento → sem aviso, pode reenviar', () {
      final x = e('em_analise', doc: true);
      expect(x.mostrarAviso, isFalse);
      expect(x.podeEnviar, isTrue);
      expect(x.rotulo, 'Em análise');
    });

    test('recusada → aviso com o motivo', () {
      final x = e('recusada', doc: true, motivo: 'foto ilegível');
      expect(x.mostrarAviso, isTrue);
      expect(x.explicacao, contains('foto ilegível'));
    });

    test('aprovada → nada a pedir, não pode reenviar', () {
      final x = e('aprovada', doc: true);
      expect(x.mostrarAviso, isFalse);
      expect(x.podeEnviar, isFalse);
    });

    test('quem não é prestador nunca vê o aviso', () {
      expect(e('por_enviar', prestador: false).mostrarAviso, isFalse);
    });

    test('estado desconhecido cai em "por enviar" (nunca rebenta)', () {
      expect(atividadeStatusDe('qualquer'), AtividadeStatus.porEnviar);
      expect(atividadeStatusDe(null), AtividadeStatus.porEnviar);
    });
  });

  group('tipo do ficheiro pelos bytes', () {
    Uint8List b(List<int> x) =>
        Uint8List.fromList([...x, ...List.filled(20, 0)]);

    test('pdf, jpg e png aceites', () {
      expect(tipoDoComprovativo(b([0x25, 0x50, 0x44, 0x46, 0x2D])),
          TipoComprovativo.pdf);
      expect(tipoDoComprovativo(b([0xFF, 0xD8, 0xFF, 0xE0])),
          TipoComprovativo.jpg);
      expect(
          tipoDoComprovativo(
              b([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])),
          TipoComprovativo.png);
      expect(problemaDoComprovativo(b([0x25, 0x50, 0x44, 0x46, 0x2D])), isNull);
    });

    test('HEIC do iPhone é apanhado com mensagem própria', () {
      final heic = b([0, 0, 0, 0x18, ...'ftypheic'.codeUnits]);
      expect(tipoDoComprovativo(heic), TipoComprovativo.heic);
      expect(problemaDoComprovativo(heic), contains('HEIC'));
    });

    test('vazio, desconhecido e grande demais recusados', () {
      expect(problemaDoComprovativo(Uint8List(0)), contains('vazio'));
      expect(problemaDoComprovativo(b([1, 2, 3])), contains('JPG ou PNG'));
      final grande = Uint8List(kComprovativoMaxBytes + 1)
        ..setAll(0, [0x25, 0x50, 0x44, 0x46, 0x2D]);
      expect(problemaDoComprovativo(grande), contains('10 MB'));
    });
  });

  test('erros do servidor em PT-PT', () {
    expect(mensagemDoErroAtividade(Exception('nif_invalido')), contains('NIF'));
    expect(mensagemDoErroAtividade(Exception('ja_aprovada')),
        contains('já está aprovado'));
    expect(mensagemDoErroAtividade(Exception('nao_e_prestador')),
        contains('candidatura'));
    expect(mensagemDoErroAtividade(Exception('documento_nao_encontrado')),
        contains('não chegou'));
    expect(mensagemDoErroAtividade(Exception('outra coisa')),
        contains('Verifica a ligação'));
  });

  group('painel (PT-BR)', () {
    test('rótulos nunca mostram o nome técnico', () {
      for (final p in [
        'estafeta',
        'motorista_tvde',
        'limpeza',
        'lavagem',
        'servicos'
      ]) {
        expect(rotuloPapelAtividade(p), isNot(p));
      }
      expect(rotuloPapelAtividade('novo_papel'), 'Outro trabalho');
      expect(rotuloEstadoAtividade('em_analise', temDocumento: false),
          'Disse que tem (sem documento)');
    });

    test('CSV só com metadados (sem caminho do ficheiro)', () {
      final csv = construirCsvAtividade([
        {
          'nome': 'Teste',
          'email': 't@x.pt',
          'papeis': ['limpeza', 'lavagem'],
          'atividade_status': 'em_analise',
          'tem_documento': true,
          'documento_tipo': 'pdf',
          'documento_path': 'uid/comprovativo_1.pdf',
          'nif': '245123458',
          'obrigatoria': false,
        },
      ]);
      final linhas = csv.trim().split('\n');
      expect(linhas.first, kCabecalhoCsvAtividade.join(';'));
      expect(linhas[1], contains('Limpeza + Lavagem de carros'));
      expect(linhas[1], contains('Em análise'));
      expect(csv, isNot(contains('comprovativo_1.pdf')));
    });
  });

  // Lei da casca sem fio (PADRAO §1.5): peça nova sem chamadores não está feita.
  group('fios ligados', () {
    String ler(String p) => File(p).readAsStringSync();

    test('o aviso está no ecrã principal de cada papel (e nos de espera)', () {
      for (final p in [
        'lib/screens/driver_home_screen.dart',
        'lib/screens/driver/tvde/tvde_driver_home_screen.dart',
        'lib/screens/cleaner/cleaner_home_screen.dart',
        'lib/screens/washer/washer_home_screen.dart',
        'lib/screens/partner/services/partner_services_hub_screen.dart',
        'lib/screens/driver_pending_screen.dart',
        'lib/screens/pending_approval_screen.dart',
      ]) {
        expect(ler(p), contains('AvisoAtividadeBanner('), reason: p);
      }
    });

    test('o passo do comprovativo corre no fim de cada candidatura', () {
      for (final p in [
        'lib/screens/cleaner/cleaner_apply_screen.dart',
        'lib/screens/washer/washer_apply_screen.dart',
        'lib/screens/driver/driver_role_apply_screen.dart',
        'lib/screens/driver_signup_screen.dart',
      ]) {
        expect(
            ler(p),
            contains(
                'ComprovativoAtividadeScreen.depoisDaCandidatura(context)'),
            reason: p);
      }
      // No registo do estafeta o passo vem ANTES do logout (precisa da sessão).
      final s = ler('lib/screens/driver_signup_screen.dart');
      expect(s.indexOf('depoisDaCandidatura'),
          lessThan(s.indexOf('logout(wipeBiometrics: false)')));
    });

    test('tocar no push abre o ecrã de envio pelo gancho único', () {
      final n = ler('lib/services/notification_service.dart');
      expect(
          n,
          contains(
              "const String kKindComprovativoAtividade = 'provider_atividade';"));
      expect("abrirTrabalho?.call('atividade', '')".allMatches(n).length, 3,
          reason: 'app aberta, push aberto pelo sistema e arranque a frio');
      final m = ler('lib/main.dart');
      expect(m, contains("'atividade' => const ComprovativoAtividadeScreen()"));
      expect(m, contains("'/admin/comprovativo-atividade': (_) =>"));
    });

    test('o painel tem o ecrã no menu', () {
      expect(ler('lib/screens/admin/admin_menu_registry.dart'),
          contains('builder: () => const AdminComprovativoAtividadeScreen()'));
    });
  });
}
