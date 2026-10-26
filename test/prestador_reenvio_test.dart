// Missão docs-reenvio-26-10: o prestador pendente (limpeza, lavagem, motorista
// TVDE) vê o que falta e envia ali mesmo. A lista é a do painel; aqui prova-se
// COMO cada item se envia, o agrupar dos dados fiscais, o juntar dos docs sem
// perder os outros e a leitura dos impedimentos TVDE do servidor.
import 'dart:async';

import 'package:bora_app/services/prestador_documentos.dart';
import 'package:bora_app/services/prestador_reenvio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show StorageException;

List<String> _c(List l) => l.map((d) => d.chave as String).toList();

void main() {
  group('documentosEmFaltaPrestador — a mesma regra do painel', () {
    final semNada = <String, dynamic>{'docs': {}};

    test('lavagem pede a carta de condução; limpeza não', () {
      expect(_c(documentosEmFaltaPrestador('washer', semNada)),
          _c(documentosEmFaltaLavagem(semNada)));
      expect(_c(documentosEmFaltaPrestador('cleaner', semNada)),
          _c(documentosEmFaltaLimpeza(semNada)));
      expect(_c(documentosEmFaltaPrestador('washer', semNada)),
          contains('driving_license'));
      expect(_c(documentosEmFaltaPrestador('cleaner', semNada)),
          isNot(contains('driving_license')));
    });

    test('o comprovativo só entra quando conta', () {
      expect(_c(documentosEmFaltaPrestador('cleaner', semNada)),
          isNot(contains('atividade')));
      expect(
          _c(documentosEmFaltaPrestador('cleaner', semNada,
              atividadeEmFalta: true)),
          contains('atividade'));
    });
  });

  group('comoEnviarPrestador', () {
    test('limpeza: tudo pela app — documento e materiais pela RPC '
        'cleaner_reenviar_docs (26/10)',
        () {
      expect(comoEnviarPrestador('cleaner', 'photo'), ComoEnviar.foto);
      expect(comoEnviarPrestador('cleaner', 'id_doc'), ComoEnviar.foto);
      expect(comoEnviarPrestador('cleaner', 'materials'), ComoEnviar.materiais);
      expect(comoEnviarPrestador('cleaner', 'atividade'),
          ComoEnviar.comprovativo);
      for (final k in kChavesDadosLegais) {
        expect(comoEnviarPrestador('cleaner', k), ComoEnviar.dadosFiscais,
            reason: k);
      }
      expect(comoEnviarPrestador('cleaner', kChaveDadosFiscais),
          ComoEnviar.dadosFiscais);
    });

    test('lavagem: tudo pela app', () {
      expect(comoEnviarPrestador('washer', 'photo'), ComoEnviar.foto);
      expect(comoEnviarPrestador('washer', 'id_doc'), ComoEnviar.foto);
      expect(comoEnviarPrestador('washer', 'driving_license'), ComoEnviar.foto);
      expect(comoEnviarPrestador('washer', 'materials'), ComoEnviar.materiais);
      expect(comoEnviarPrestador('washer', 'atividade'),
          ComoEnviar.comprovativo);
      expect(comoEnviarPrestador('washer', 'iban'), ComoEnviar.dadosFiscais);
    });

    test('chave desconhecida nunca inventa um envio', () {
      expect(comoEnviarPrestador('washer', 'outra_coisa'), ComoEnviar.suporte);
      expect(comoEnviarPrestador('cleaner', 'driving_license'),
          ComoEnviar.suporte);
    });

    test('cada item que a lista da lavagem pode dar tem envio na app', () {
      final todos = documentosEmFaltaLavagem(<String, dynamic>{'docs': {}},
          atividadeEmFalta: true);
      for (final d in todos) {
        expect(comoEnviarPrestador('washer', d.chave),
            isNot(ComoEnviar.suporte),
            reason: d.chave);
      }
    });
  });

  group('agruparDadosLegais', () {
    test('candidatura antiga: os seis dados legais viram uma linha só, no '
        'sítio do primeiro', () {
      final falta = agruparDadosLegais(
          documentosEmFaltaLimpeza(<String, dynamic>{'docs': {}},
              atividadeEmFalta: true));
      expect(_c(falta),
          ['photo', 'id_doc', 'materials', kChaveDadosFiscais, 'atividade']);
      expect(
          falta[3].rotulo,
          'Dados fiscais (nome legal, NIF, morada, data de nascimento, IBAN '
          'e declaração (autocertificação DSA))');
    });

    test('só o IBAN e a declaração em falta', () {
      final linha = <String, dynamic>{
        'photo_url': 'https://x/a.jpg',
        'docs': {'id_doc': 'u/id.jpg', 'materials_ok': true},
        'legal_name': 'Maria Teste',
        'nif': '215645154',
        'address': 'Rua de Teste 1, Guarda',
        'birth_date': '1990-01-01',
      };
      final falta = agruparDadosLegais(documentosEmFaltaLimpeza(linha));
      expect(_c(falta), [kChaveDadosFiscais]);
      expect(falta.single.rotulo,
          'Dados fiscais (IBAN e declaração (autocertificação DSA))');
    });

    test('sem dados legais em falta a lista fica igual', () {
      final linha = <String, dynamic>{'docs': {}};
      final sem = documentosEmFaltaLavagem(linha)
          .where((d) => !kChavesDadosLegais.contains(d.chave))
          .toList();
      expect(_c(agruparDadosLegais(sem)), _c(sem));
      expect(agruparDadosLegais(const []), isEmpty);
    });
  });

  test('minusculaInicial: siglas ficam, o resto começa em minúscula', () {
    expect(minusculaInicial('Foto de perfil'), 'foto de perfil');
    expect(minusculaInicial('NIF'), 'NIF');
    expect(minusculaInicial('IBAN'), 'IBAN');
    expect(minusculaInicial('Carta de condução'), 'carta de condução');
    expect(minusculaInicial(''), '');
  });

  test('docsCom junta o documento novo sem apagar os outros', () {
    final linha = <String, dynamic>{
      'docs': {
        'id_doc': 'u/id_doc_1.jpg',
        'materials_ok': true,
        'materials_list': ['Aspirador portátil'],
      },
    };
    final novos = docsCom(linha, {'driving_license': 'u/carta_2.jpg'});
    expect(novos['id_doc'], 'u/id_doc_1.jpg');
    expect(novos['materials_ok'], true);
    expect(novos['materials_list'], ['Aspirador portátil']);
    expect(novos['driving_license'], 'u/carta_2.jpg');
    // A linha original não muda (o envio só grava depois de confirmar).
    expect((linha['docs'] as Map).containsKey('driving_license'), isFalse);
    // docs vazio ou estragado não rebenta.
    expect(docsCom(<String, dynamic>{'docs': 'x'}, {'id_doc': 'a'}),
        {'id_doc': 'a'});
  });

  group('motivosTvdeEmFalta — impedimentos do servidor', () {
    test('resposta real de tvde_minha_conformidade (motorista sem nada)', () {
      final conf = {
        'bloqueado': true,
        'motivos': [
          {
            'codigo': 'cmtvde_em_falta',
            'rotulo': 'Certificado de motorista TVDE (CMTVDE) em falta'
          },
          {
            'codigo': 'contrato_operador_em_falta',
            'rotulo': 'Contrato escrito com o operador em falta'
          },
          {'codigo': 'veiculo_em_falta', 'rotulo': 'Sem veículo TVDE associado'},
        ],
        'avisos': [
          {'codigo': 'lingua_por_declarar', 'rotulo': 'Declarar se fala português'},
        ],
      };
      final f = motivosTvdeEmFalta(conf);
      expect(_c(f), [
        'cmtvde_em_falta',
        'contrato_operador_em_falta',
        'veiculo_em_falta',
      ]);
      expect(f.first.rotulo,
          'Certificado de motorista TVDE (CMTVDE) em falta');
      // Avisos não são "falta" (não impedem).
      expect(_c(f), isNot(contains('lingua_por_declarar')));
    });

    test('tudo em ordem, resposta estranha ou nula: lista vazia', () {
      expect(motivosTvdeEmFalta({'motivos': []}), isEmpty);
      expect(motivosTvdeEmFalta({'motivos': 'x'}), isEmpty);
      expect(motivosTvdeEmFalta(null), isEmpty);
      expect(motivosTvdeEmFalta('x'), isEmpty);
    });

    test('motivo sem rótulo usa o código; sem nada é ignorado', () {
      final f = motivosTvdeEmFalta({
        'motivos': [
          {'codigo': 'seguro_caducado'},
          {'codigo': '', 'rotulo': ' '},
          'lixo',
        ],
      });
      expect(_c(f), ['seguro_caducado']);
      expect(f.single.rotulo, 'seguro_caducado');
    });
  });

  group('mensagemDeErroReenvio — nunca calado, sempre PT-PT', () {
    test('sessão, imagem ilegível, rede lenta', () {
      expect(mensagemDeErroReenvio(StateError('not_authenticated')),
          contains('sessão terminou'));
      expect(mensagemDeErroReenvio(StateError('empty_file: formato ilegivel')),
          contains('ler a imagem'));
      expect(mensagemDeErroReenvio(TimeoutException('x')),
          contains('ligação está lenta'));
    });

    test('o Storage diz a causa real', () {
      final m = mensagemDeErroReenvio(
          const StorageException('mime type not supported', statusCode: '415'));
      expect(m, contains('415'));
      expect(m, contains('mime type not supported'));
    });

    test('a frase de um ReenvioException passa tal e qual', () {
      expect(mensagemDeErroReenvio(const ReenvioException('Olá')), 'Olá');
    });

    test('o resto dá a frase genérica', () {
      expect(mensagemDeErroReenvio(Exception('???')),
          'Não foi possível enviar. Verifica a ligação e tenta outra vez.');
    });
  });
}
