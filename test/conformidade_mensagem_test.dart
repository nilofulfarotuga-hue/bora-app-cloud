import 'package:bora_app/models/dados_fiscais_parceiro.dart';
import 'package:bora_app/utils/conformidade_mensagem.dart';
import 'package:bora_app/widgets/admin/admin_dados_fiscais_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Missão boom-burger-2026-10-27, F3 — dados fiscais do parceiro (DAC7).
///
/// O que estes testes fecham:
///  1. Os códigos `em_falta` do servidor viram rótulos legíveis, sem vazios
///     nem repetidos, e um código desconhecido aparece tal e qual.
///  2. O erro do portão `conformidade_incompleta: faltam nif, iban` vira
///     "Não dá para abrir a loja ao público: faltam NIF, IBAN." — com a HINT
///     colada, no formato toString, sem lista, e nada quando o erro é outro.
///  3. `parceiro_dados_fiscais` é lido para o modelo (datas, empresa,
///     completo).
///  4. O admin só envia o que mudou, e só valida o que mudou.
void main() {
  group('rótulos do em_falta', () {
    test('os seis códigos do servidor', () {
      expect(kCodigosEmFalta.map(rotuloEmFalta).toList(), [
        'Nome legal',
        'NIF',
        'Morada',
        'IBAN',
        'Data de nascimento',
        'Autocertificação',
      ]);
    });

    test('código desconhecido volta tal e qual (não se esconde nada)', () {
      expect(rotuloEmFalta('registo'), 'registo');
      expect(rotuloEmFalta('  nif '), 'NIF');
    });

    test('lista do servidor: limpa vazios, nulos e repetidos; não-lista = nada',
        () {
      expect(codigosEmFalta(['nif', '', null, 'iban', 'nif', ' morada ']),
          ['nif', 'iban', 'morada']);
      expect(rotulosEmFalta(['data_nascimento', 'autocertificacao']),
          ['Data de nascimento', 'Autocertificação']);
      expect(codigosEmFalta(null), isEmpty);
      expect(codigosEmFalta('nif, iban'), isEmpty);
      expect(codigosEmFalta(const []), isEmpty);
    });
  });

  group('mensagem ao abrir a loja (tirar o "Em breve")', () {
    const fim = 'Complete no cartão "Dados fiscais (DAC7)" da ficha do parceiro.';

    test('erro do portão com dois campos', () {
      expect(
        mensagemAbrirLojaConformidade(const PostgrestException(
            message: 'conformidade_incompleta: faltam nif, iban', code: 'P0001')),
        'Não dá para abrir a loja ao público: faltam NIF, IBAN. $fim',
      );
    });

    test('os seis campos, pela ordem do servidor', () {
      expect(
        mensagemAbrirLojaConformidade(const PostgrestException(
            message: 'conformidade_incompleta: faltam nome, nif, morada, iban, '
                'data_nascimento, autocertificacao')),
        'Não dá para abrir a loja ao público: faltam Nome legal, NIF, Morada, '
        'IBAN, Data de nascimento, Autocertificação. $fim',
      );
    });

    test('HINT colada à mensagem não entra na lista', () {
      expect(
        mensagemAbrirLojaConformidade(
            'conformidade_incompleta: faltam iban, autocertificacao. Antes de '
            'abrir a loja parceira ao público: nome legal, NIF, morada (DAC7)'),
        'Não dá para abrir a loja ao público: faltam IBAN, Autocertificação. $fim',
      );
    });

    test('formato toString de outra exceção (", code: P0001" não é campo)', () {
      expect(
        mensagemAbrirLojaConformidade(Exception(
            'PostgrestException(message: conformidade_incompleta: faltam nif, '
            'code: P0001, details: Bad Request, hint: null)')),
        'Não dá para abrir a loja ao público: faltam NIF. $fim',
      );
    });

    test('sem lista legível não inventa campos', () {
      expect(mensagemAbrirLojaConformidade('conformidade_incompleta'),
          'Não dá para abrir a loja ao público: faltam dados fiscais. $fim');
      expect(
          mensagemAbrirLojaConformidade(
              'conformidade_incompleta: faltam ???, 123'),
          'Não dá para abrir a loja ao público: faltam dados fiscais. $fim');
    });

    test('código novo do servidor aparece tal e qual', () {
      expect(
        mensagemAbrirLojaConformidade(
            const PostgrestException(message: 'conformidade_incompleta: faltam nif, cae')),
        'Não dá para abrir a loja ao público: faltam NIF, cae. $fim',
      );
    });

    test('outro erro qualquer → null (o ecrã mostra o erro de sempre)', () {
      expect(mensagemAbrirLojaConformidade(null), isNull);
      expect(
          mensagemAbrirLojaConformidade(
              const PostgrestException(message: 'permission denied for table restaurants')),
          isNull);
      expect(mensagemAbrirLojaConformidade(Exception('SocketException: sem rede')),
          isNull);
      expect(mensagemAbrirLojaConformidade('faltam nif'), isNull);
    });

    test('códigos lidos do texto: só a lista, sem repetidos', () {
      expect(codigosDoErroConformidade('conformidade_incompleta: faltam nif, nif, iban'),
          ['nif', 'iban']);
      expect(codigosDoErroConformidade('sem a palavra'), isEmpty);
      expect(codigosDoErroConformidade('faltam iban\nlinha seguinte, nif'), ['iban']);
    });
  });

  group('erros do admin ao gravar', () {
    test('cada erro conhecido em PT-BR', () {
      String m(String s) =>
          mensagemErroDadosFiscaisAdmin(PostgrestException(message: s));
      expect(m('admin_required'), 'Sem permissão de admin para esta ação.');
      expect(m('nif_invalido'), contains('NIF'));
      expect(m('iban_invalido'), contains('IBAN'));
      expect(m('menor_de_idade'), contains('18 anos'));
      expect(m('autocertificacao_no_futuro'), contains('futuro'));
      expect(m('loja_nao_encontrada'), contains('Loja não encontrada'));
      expect(m('outra coisa'), 'Não foi possível salvar os dados fiscais: outra coisa');
    });
  });

  group('modelo DadosFiscaisParceiro', () {
    test('lê o jsonb de parceiro_dados_fiscais', () {
      final d = DadosFiscaisParceiro.fromJson({
        'restaurant_id': 'rest-1',
        'loja': 'Boom! Burger',
        'legal_name': '  ',
        'nif': '509999999',
        'address': 'Rua X 1, 6300-000 Guarda',
        'iban': null,
        'birth_date': null,
        'dsa_self_certified_at': '2026-10-27T12:00:00+00:00',
        'dsa_self_cert_version': '2026-09-23',
        'empresa': true,
        'em_falta': ['nome', 'iban'],
      });
      expect(d.restaurantId, 'rest-1');
      expect(d.legalName, isNull, reason: 'texto em branco conta como vazio');
      expect(d.empresa, isTrue);
      expect(d.autocertificadoEm, DateTime.utc(2026, 10, 27, 12));
      expect(d.completo, isFalse);
      expect(d.rotulosEmFalta, ['Nome legal', 'IBAN']);
      expect(DadosFiscaisParceiro.fromJson({'em_falta': []}).completo, isTrue);
    });
  });

  group('admin: só se envia o que mudou', () {
    final antes = DadosFiscaisParceiro(
      restaurantId: 'r1',
      loja: 'Loja',
      legalName: 'Ana Silva',
      nif: '123456780', // checksum inválido, legado — não trava outros campos
      address: 'Rua A 1, Guarda',
      iban: null,
      birthDate: DateTime(1990, 5, 1),
      autocertificadoEm: DateTime.utc(2026, 10, 1, 12),
      autocertVersao: '2026-09-23',
      emFalta: const ['iban'],
    );
    final agora = DateTime(2026, 10, 27, 15);

    ({String? erro, AlteracaoDadosFiscais? alteracao}) comparar({
      String nome = 'Ana Silva',
      String nif = '123456780',
      String morada = 'Rua A 1, Guarda',
      String iban = '',
      DateTime? nascimento,
      DateTime? autocert,
      String versao = '2026-09-23',
    }) =>
        compararDadosFiscaisAdmin(
          antes: antes,
          nome: nome,
          nif: nif,
          morada: morada,
          iban: iban,
          nascimento: nascimento ?? DateTime(1990, 5, 1),
          autocertData: autocert ?? DateTime(2026, 10, 1),
          autocertVersao: versao,
          agora: agora,
        );

    test('nada mudou → alteração vazia', () {
      final r = comparar();
      expect(r.erro, isNull);
      expect(r.alteracao!.vazia, isTrue);
    });

    test('só o IBAN (com espaços e minúsculas) → só iban, normalizado', () {
      final r = comparar(iban: 'pt50 0002 0123 1234 5678 9015 4');
      expect(r.erro, isNull);
      expect(r.alteracao!.campos, ['iban']);
      expect(r.alteracao!.iban, 'PT50000201231234567890154');
      expect(r.alteracao!.nif, isNull, reason: 'NIF antigo não se reenvia');
    });

    test('NIF novo inválido é recusado; IBAN inválido também', () {
      expect(comparar(nif: '123456789').erro, contains('NIF inválido'));
      expect(comparar(iban: 'PT12').erro, contains('IBAN inválido'));
    });

    test('apagar um campo que existia é recusado', () {
      expect(comparar(nome: '  ').erro, contains('apagar o nome legal'));
      expect(comparar(morada: '').erro, contains('apagar a morada'));
    });

    test('data de nascimento nova de menor é recusada', () {
      expect(comparar(nascimento: DateTime(2010, 1, 1)).erro, contains('18 anos'));
      final ok = comparar(nascimento: DateTime(1985, 2, 3));
      expect(ok.alteracao!.campos, ['data_nascimento']);
      expect(ok.alteracao!.birthDateIso, '1985-02-03');
    });

    test('autocertificação: data nova vai ao meio-dia UTC com a versão', () {
      final r = comparar(autocert: DateTime(2026, 10, 27));
      expect(r.alteracao!.campos, ['autocertificacao']);
      expect(r.alteracao!.autocertificadoEmIso, '2026-10-27T12:00:00.000Z');
      expect(r.alteracao!.autocertVersao, '2026-09-23');
    });

    test('só a versão muda → reenvia a data antiga exata', () {
      final r = comparar(versao: '2026-10-28');
      expect(r.alteracao!.campos, ['autocertificacao']);
      expect(r.alteracao!.autocertificadoEmIso, '2026-10-01T12:00:00.000Z');
      expect(r.alteracao!.autocertVersao, '2026-10-28');
    });

    test('autocertificação no futuro é recusada', () {
      expect(comparar(autocert: DateTime(2026, 11, 5)).erro, contains('futuro'));
    });
  });
}
