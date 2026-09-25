import 'dart:io';

import 'package:bora_app/screens/admin/admin_menu_registry.dart';
import 'package:bora_app/screens/admin/admin_motoristas_documentos_screen.dart';
import 'package:bora_app/screens/driver/tvde/ficha_legal_form_screen.dart';
import 'package:bora_app/services/ficha_legal_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Missão motorista-ficha-legal-2026-09-23 (Lei 45/2018 rev. Lei 59/2026).
void main() {
  group('textos da ficha', () {
    test('datas do servidor em dd/mm/aaaa, vazio = por preencher', () {
      expect(FichaTexto.data('2027-03-01'), '01/03/2027');
      expect(FichaTexto.data(null), 'por preencher');
      expect(FichaTexto.data(''), 'por preencher');
    });

    test('hora de Lisboa: verão +1, inverno +0 (sem pacote de fusos)', () {
      // 23/09 16:49 UTC → 17:49 em Lisboa (hora de verão).
      expect(FichaTexto.dataHora('2026-09-23T16:49:28+00:00'), '23/09/2026 17:49');
      // 15/01 16:49 UTC → 16:49 em Lisboa (inverno).
      expect(FichaTexto.dataHora('2026-01-15T16:49:00Z'), '15/01/2026 16:49');
      // Mudança de hora: último domingo de Outubro de 2026 = 25/10, 01:00 UTC.
      expect(FichaTexto.dataHora('2026-10-25T00:59:00Z'), '25/10/2026 01:59');
      expect(FichaTexto.dataHora('2026-10-25T01:00:00Z'), '25/10/2026 01:00');
      expect(FichaTexto.dataHora(null), '—');
    });

    test('euro com vírgula, nulo = traço (nunca 0,00 inventado)', () {
      expect(FichaTexto.euro(500), '5,00 €');
      expect(FichaTexto.euro(100), '1,00 €');
      expect(FichaTexto.euro(null), '—');
    });

    test('meio de pagamento e estado nunca mostram o nome técnico', () {
      expect(FichaTexto.meio('mbway'), 'MB Way');
      expect(FichaTexto.meio('card'), 'Cartão');
      expect(FichaTexto.meio('cash'), 'Dinheiro');
      expect(FichaTexto.estado('a_expirar'), 'A expirar');
      expect(FichaTexto.estado('expirado'), 'Expirado');
      expect(FichaTexto.estado('qualquer_coisa'), 'Por preencher');
    });
  });

  group('ficha de fiscalização (JSON do servidor)', () {
    final json = <String, dynamic>{
      'gerado_em': '2026-09-23T18:35:13Z',
      'motorista': {'nome': 'Danilo', 'nif': '322151171'},
      'veiculo': {'matricula': 'CH-90-PX'},
      'operador': null,
      'plataforma': {'nome': 'Bora', 'nif': null, 'licenca': null, 'em_processo': true},
      'documentos': [
        {'doc': 'carta', 'rotulo': 'Carta de condução', 'estado': 'a_expirar', 'validade': '2026-10-10', 'dias': 17},
        {'doc': 'inspecao', 'rotulo': 'Inspeção periódica', 'estado': 'expirado', 'validade': '2026-09-01', 'dias': -22},
      ],
      'viagem': null,
      'verificacao': {
        'url': 'https://boraguarda.com/verificar/ZNqpxMtJqmQz',
        'expira_em': '2026-09-24T18:35:13Z',
      },
    };

    test('lê secções e documentos sem rebentar com nulos', () {
      final f = FichaFiscalizacao(json, offline: true);
      expect(f.offline, isTrue);
      expect(f.motorista['nome'], 'Danilo');
      expect(f.veiculo['matricula'], 'CH-90-PX');
      expect(f.operador, isNull);
      expect(f.viagem, isNull);
      expect(f.plataforma['em_processo'], isTrue);
      expect(f.documentos.map((d) => d.estado), ['a_expirar', 'expirado']);
      expect(f.documentos.last.dias, -22);
    });

    test('o QR só vale até o token expirar', () {
      final f = FichaFiscalizacao(json, offline: false);
      expect(f.tokenValido(DateTime.utc(2026, 9, 24, 18, 0)), isTrue);
      expect(f.tokenValido(DateTime.utc(2026, 9, 24, 18, 36)), isFalse);
    });
  });

  group('formulário grava só o que mudou', () {
    final original = <String, dynamic>{'matricula': 'CH-90-PX', 'veiculo_ano': '2019', 'carta_validade': ''};

    test('sem mudanças não manda nada (não apaga a matrícula)', () {
      expect(fichaCamposMudados(original, Map.of(original)), isEmpty);
    });

    test('muda só a validade da carta', () {
      final atual = Map<String, dynamic>.of(original)..['carta_validade'] = '2031-01-01';
      expect(fichaCamposMudados(original, atual), {'carta_validade': '2031-01-01'});
    });

    test('esvaziar de propósito conta como mudança', () {
      final atual = Map<String, dynamic>.of(original)..['matricula'] = '';
      expect(fichaCamposMudados(original, atual), {'matricula': ''});
    });
  });

  group('lei da casca sem fio: tudo tem chamador', () {
    String ler(String p) => File(p).readAsStringSync();

    test('o botão "Mostrar à autoridade" está no ecrã principal do motorista', () {
      final home = ler('lib/screens/driver/tvde/tvde_driver_home_screen.dart');
      expect(home, contains('FiscalizacaoScreen()'));
      expect(home, contains("'Mostrar à autoridade'"));
      // No mapa (visível) E no menu de topo.
      expect("'Mostrar à autoridade'".allMatches(home).length, greaterThanOrEqualTo(2));
      // Pergunta ao servidor antes de ligar o online.
      expect(home, contains('FichaLegalService.documentosExpirados()'));
      // O formulário é alcançável também de quem está à espera de aprovação.
      expect(home, contains('FichaLegalFormScreen()'));
    });

    test('o recibo abre no histórico e no acompanhamento da viagem', () {
      expect(ler('lib/screens/client/tvde/tvde_rides_history_screen.dart'),
          contains('abrirReciboViagem('));
      expect(ler('lib/screens/client/tvde/tvde_ride_tracking_screen.dart'),
          contains('abrirReciboViagem('));
    });

    test('o painel tem o hub com rota para o aviso diário', () {
      final item = adminMenuSections()
          .expand((s) => s.items)
          .firstWhere((i) => i.id == 'tvde_documentos_tvde');
      expect(item.archivedReason, isNull);
      expect(item.builder(), isA<AdminMotoristasDocumentosScreen>());
      expect(ler('lib/main.dart'), contains("'/admin/motoristas-documentos'"));
    });

    test('as Edge Functions e migrações estão no repo', () {
      expect(File('supabase/functions/tvde-recibo-viagem/index.ts').existsSync(), isTrue);
      expect(File('supabase/functions/ficha-fiscalizacao-email/index.ts').existsSync(), isTrue);
      final migs = Directory('supabase/migrations')
          .listSync()
          .map((e) => e.path)
          .where((p) => p.contains('20260923183444_motorista_ficha_legal'));
      expect(migs, isNotEmpty);
    });
  });
}
