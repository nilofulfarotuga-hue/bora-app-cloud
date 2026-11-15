// Painel admin 15/11/2026 (auditoria S6, ecrãs dos robôs): verificações no código e
// funções puras, sem rede nem Supabase.
//  - Assistentes regista a auditoria pela RPC log_admin_action (o insert direto era recusado).
//  - Central do robô do suporte lê admin_suporte_sessoes e abre com p_session_id.
//  - WhatsApp da loja diz desde quando e porquê o envio está desligado.
//  - Lembretes conta o último envio e só diz "Envio parado" com lembretes da semana atrasados.
//  - Modelos de IA e Central chamam o mesmo campo "robô do suporte".
//  - Sugestões: aprovar em lote sem a função no servidor diz o que fazer.
//  - Tickets: lista vazia explica a permissão em proposta.
//  - Nenhum "Erro: $e" cru nos ecrãs tocados.
import 'dart:io';

import 'package:bora_app/screens/admin/_admin_rpc_errors.dart';
import 'package:bora_app/screens/admin/admin_ai_models_screen.dart';
import 'package:bora_app/screens/admin/admin_lembretes_screen.dart';
import 'package:bora_app/screens/admin/admin_skill_suggestions_screen.dart';
import 'package:bora_app/screens/admin/admin_support_tickets_screen.dart';
import 'package:bora_app/screens/admin/admin_whatsapp_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String _ler(String caminho) => File(caminho).readAsStringSync();

const _ecras = <String>[
  'lib/screens/admin/admin_suporte_central_screen.dart',
  'lib/screens/admin/admin_assistentes_screen.dart',
  'lib/screens/admin/admin_whatsapp_screen.dart',
  'lib/screens/admin/admin_lembretes_screen.dart',
  'lib/screens/admin/admin_ai_models_screen.dart',
  'lib/screens/admin/admin_motores_screen.dart',
  'lib/screens/admin/admin_assistente_screen.dart',
  'lib/screens/admin/admin_assistente_amigo.dart',
  'lib/screens/admin/admin_assistente_aprendidas.dart',
  'lib/screens/admin/admin_amigo_pesquisa_secao.dart',
  'lib/screens/admin/admin_amigo_rosto_secao.dart',
  'lib/screens/admin/admin_amigo_voz_secao.dart',
  'lib/screens/admin/admin_skill_suggestions_screen.dart',
  'lib/screens/admin/admin_support_tickets_screen.dart',
];

void main() {
  group('erros em PT-BR', () {
    test('nenhum "Erro: \$e" nem erro cru mostrado nos ecrãs dos robôs', () {
      // "Erro: $e", "Erro: $_erro", "Erro: ${snap.error}", "Erro ao carregar: $e",
      // "Não salvei x: $e" (o $e no fim de um texto).
      final cru = RegExp(r"Erro: \$|Erro ao (carregar|salvar): \$|: \$e'");
      for (final f in _ecras) {
        final linhas = _ler(f).split('\n');
        for (var i = 0; i < linhas.length; i++) {
          expect(cru.hasMatch(linhas[i]), isFalse, reason: '$f:${i + 1}: ${linhas[i].trim()}');
        }
      }
    });

    test('o erro guardado para mostrar passa pelo tradutor comum (fora Lembretes, que o teste dele lê)', () {
      final cru = RegExp(r'(_erro|_error) = e\.toString\(\)');
      for (final f in _ecras.where((f) => !f.endsWith('admin_lembretes_screen.dart'))) {
        expect(cru.hasMatch(_ler(f)), isFalse, reason: f);
        expect(_ler(f), contains('humanizeAdminRpcError('), reason: f);
      }
    });
  });

  test('Assistentes regista a auditoria pela RPC (AdminAuditService), não por insert direto', () {
    final src = _ler('lib/screens/admin/admin_assistentes_screen.dart');
    expect(src, isNot(contains("from('admin_audit_log')")));
    expect(src, contains('AdminAuditService.logAction('));
    // entity_id é uuid: um id que não seja uuid vai nos detalhes
    expect(src, contains("entityId: ehUuid ? tenantId : null"));
  });

  test('Central do robô do suporte: sessões e conversa pelas funções que existem', () {
    final src = _ler('lib/screens/admin/admin_suporte_central_screen.dart');
    expect(src, contains("'admin_suporte_sessoes'"));
    expect(src, contains("'p_limite': 100, 'p_so_nao_lidas': false"));
    expect(src, contains("'admin_suporte_conversa', {'p_session_id': id}"));
    expect(src, isNot(contains("'p_sessao'")));
  });

  group('WhatsApp da loja: barra do envio', () {
    test('desligado diz desde quando (dia de Lisboa) e o motivo guardado', () {
      final t = textoBarraEnvioWhatsapp(
        ligado: false,
        // tal como está em whatsapp_settings.envio_desligado_em
        desligadoEm: '2026-09-13 19:12:02.279491+00',
        motivo: 'pausa pedida pelo dono - vai falar com a loja',
      );
      expect(t, startsWith('Desligado de propósito desde 13/09. Motivo: pausa pedida pelo dono - vai falar com a loja.'));
      expect(t, contains('só lê e registra'));
    });

    test('sem data nem motivo fica o texto antigo; ligado não muda', () {
      expect(textoBarraEnvioWhatsapp(ligado: false), 'Bot DESLIGADO — só lê e registra');
      expect(textoBarraEnvioWhatsapp(ligado: true, desligadoEm: '2026-09-13T19:12:02Z', motivo: 'x'),
          'Bot LIGADO — responde sozinho a mensagens novas');
    });

    test('o dia é o de Lisboa, não o do aparelho', () {
      expect(diaMesLisboa('2026-07-31T23:30:00Z'), '01/08'); // verão: UTC+1
      expect(diaMesLisboa('2026-12-31T23:30:00Z'), '31/12'); // inverno: UTC+0
      expect(diaMesLisboa(null), isNull);
      expect(diaMesLisboa('não é data'), isNull);
    });

    test('a confirmação antes de ligar continua igual e nada liga o bot sozinho', () {
      final src = _ler('lib/screens/admin/admin_whatsapp_screen.dart');
      expect(src, contains("'Ligar o envio do bot?'"));
      expect(src, contains("'O bot passa a responder sozinho a mensagens NOVAS no WhatsApp da loja.'"));
      expect(src, contains('if (ok != true) return;'));
    });
  });

  group('Lembretes: estado do envio contado nos lembretes', () {
    final agora = DateTime.utc(2026, 11, 15, 12); // 15/11 12:00 em Lisboa (inverno)
    LembreteDono l(int id, DateTime quando, {DateTime? enviado, DateTime? feito, bool urgente = false}) =>
        LembreteDono(id: id, texto: 't$id', quando: quando, enviadoEm: enviado, feitoEm: feito, urgente: urgente);

    test('como em produção a 15/11: último envio 06/11, 2 antigos e enviados por marcar, sem "parado"', () {
      final r = resumoEnvioLembretes([
        l(4, DateTime.utc(2026, 10, 30, 9, 30)),
        l(21, DateTime.utc(2026, 10, 30, 5, 1), urgente: true),
        l(16, DateTime.utc(2026, 11, 5, 9, 30), enviado: DateTime.utc(2026, 11, 5, 9, 30, 20)),
        l(17, DateTime.utc(2026, 11, 6, 9, 30), enviado: DateTime.utc(2026, 11, 6, 9, 30, 23)),
        l(15, DateTime.utc(2026, 11, 4, 9, 30),
            enviado: DateTime.utc(2026, 11, 4, 9, 30), feito: DateTime.utc(2026, 11, 4, 12)),
      ], agora);
      expect(r.parado, isFalse);
      expect(r.texto, contains('Último envio: 06/11.'));
      expect(r.texto, contains('2 lembretes com mais de 7 dias nunca saíram'));
      expect(r.texto, contains('2 já foram enviados e continuam em Pendentes'));
      expect(r.texto, isNot(contains('Envio parado')));
    });

    test('um lembrete desta semana que já devia ter saído: "Envio parado" e o último envio', () {
      final r = resumoEnvioLembretes([
        l(30, DateTime.utc(2026, 11, 13, 9, 30)), // o diário de 13/11 (ou 14/11) devia tê-lo mandado
        l(17, DateTime.utc(2026, 11, 6, 9, 30), enviado: DateTime.utc(2026, 11, 6, 9, 30, 23)),
      ], agora);
      expect(r.parado, isTrue);
      expect(r.texto, startsWith('Envio parado: 1 lembrete desta semana'));
      expect(r.texto, contains('Último envio: 06/11.'));
    });

    test('urgente vencido há mais de meia hora também conta como parado', () {
      final r = resumoEnvioLembretes(
          [l(40, agora.subtract(const Duration(hours: 1)), urgente: true)], agora);
      expect(r.parado, isTrue);
      expect(r.texto, contains('Ainda nenhum lembrete foi enviado.'));
    });

    test('o que ainda está dentro do prazo não conta como parado', () {
      final r = resumoEnvioLembretes([
        l(31, DateTime.utc(2026, 11, 15, 14)), // hoje às 14:00
        l(32, DateTime.utc(2026, 11, 16, 9, 30)), // amanhã
        l(33, agora.subtract(const Duration(minutes: 10)), urgente: true), // urgente há 10 min
      ], agora);
      expect(r.parado, isFalse);
      expect(r.texto, 'Ainda nenhum lembrete foi enviado.');
    });

    test('lista vazia', () {
      final r = resumoEnvioLembretes(const [], agora);
      expect(r.parado, isFalse);
      expect(r.texto, 'Ainda nenhum lembrete foi enviado.');
    });
  });

  test('Modelos de IA e Central chamam o mesmo campo "robô do suporte"', () {
    expect(kNotaModeloSuporte, 'Este é o modelo do robô do suporte — o mesmo da Central.');
    expect(kRotuloModeloSuporte, startsWith('Robô do suporte'));
    final modelos = _ler('lib/screens/admin/admin_ai_models_screen.dart');
    expect(modelos, contains('nota: kNotaModeloSuporte'));
    expect(modelos, isNot(contains('Suporte / chatbot (volume)')));
    final central = _ler('lib/screens/admin/admin_suporte_central_screen.dart');
    expect(central, contains('Modelo do robô do suporte (o mesmo de "Modelos de IA")'));
    expect(central, isNot(contains("'Modelo (a IA que responde)'")));
  });

  test('Sugestões: aprovar em lote sem a função no servidor diz o que fazer; aprovar uma continua', () {
    const semFuncao = PostgrestException(
      message: 'Could not find the function public.admin_bulk_approve_skill_suggestions(p_ids) '
          'in the schema cache',
      code: 'PGRST202',
    );
    expect(mensagemAprovarEmLote(semFuncao), contains('Aprove uma de cada vez'));
    expect(mensagemAprovarEmLote(semFuncao), isNot(contains('PGRST202')));
    const outro = PostgrestException(message: 'admin_required');
    expect(mensagemAprovarEmLote(outro), humanizeAdminRpcError(outro));
    final src = _ler('lib/screens/admin/admin_skill_suggestions_screen.dart');
    expect(src, contains('_toast(mensagemAprovarEmLote(e), AppColors.error);'));
    expect(src, contains("_supabase.rpc('admin_approve_skill_suggestion'"));
  });

  test('Tickets: a lista vazia explica que a permissão de admin está em proposta', () {
    expect(kAvisoTicketsPermissao,
        'A lista mostra só os tickets que o servidor deixa o painel ler; a permissão de admin está em proposta.');
    final src = _ler('lib/screens/admin/admin_support_tickets_screen.dart');
    expect(src, contains(r"Text('Sem tickets.\n$kAvisoTicketsPermissao'"));
  });
}
