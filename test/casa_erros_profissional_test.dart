// CASA — C9 da revisão de 01/11/2026: as mensagens de erro do PROFISSIONAL
// caíam na frase genérica ("Não foi possível concluir"). Aceitar uma oferta
// que expirou não dizia porquê.
//
// A lista dos códigos vem do servidor (RAISE EXCEPTION das funções casa_*,
// _casa_*, provider_update_legal_fields e definir_preferencia_papel, lidas
// com pg_get_functiondef a 01/11/2026) e vive em [kCasaCodigosDeErro].
// Nenhum pode cair na frase genérica; cada um tem UMA frase em PT-PT.
import 'dart:async';

import 'package:bora_app/stores/handyman_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _generica = 'Não foi possível concluir. Tenta outra vez.';

String _erro(String codigo, {String? code}) =>
    casaErroTexto(PostgrestException(message: codigo, code: code));

void main() {
  group('tabela código → frase (os 10 da revisão)', () {
    const tabela = <String, String>{
      'oferta_expirada': 'Esta oferta já expirou. Fica atento às próximas.',
      'profissional_ocupado': 'Já tens outro trabalho marcado a essa hora.',
      'extra_por_responder':
          'O cliente ainda não respondeu ao valor extra. Espera pela resposta.',
      'oficio_por_aprovar':
          'Este ofício ainda não foi aprovado pela equipa Bora.',
      'preco_invalido': 'Escreve um preço válido, maior do que zero.',
      'motivo_em_falta': 'Escreve o motivo antes de enviar.',
      'conta_bloqueada':
          'A tua conta está bloqueada. Fala com o suporte do Bora.',
      'nome_em_falta': 'Falta o teu nome.',
      'oficios_em_falta': 'Escolhe pelo menos um ofício.',
      'invalid_role':
          'A tua conta ainda não tem este papel ativo. Fala com o suporte do Bora.',
    };
    for (final e in tabela.entries) {
      test(e.key, () => expect(_erro(e.key), e.value));
    }
  });

  group('nenhum código do servidor cai na frase genérica', () {
    test('a lista não está vazia e cobre os 10 da revisão', () {
      expect(kCasaCodigosDeErro, isNotEmpty);
      expect(
          kCasaCodigosDeErro,
          containsAll(const [
            'oferta_expirada',
            'profissional_ocupado',
            'extra_por_responder',
            'oficio_por_aprovar',
            'preco_invalido',
            'motivo_em_falta',
            'conta_bloqueada',
            'nome_em_falta',
            'oficios_em_falta',
            'invalid_role',
          ]));
    });

    for (final codigo in kCasaCodigosDeErro) {
      test(codigo, () {
        final frase = _erro(codigo);
        expect(frase, isNot(_generica), reason: '$codigo caiu na genérica');
        expect(frase, isNot(contains('_')),
            reason: 'nunca o código cru no ecrã (PADRAO_BORA 1.16)');
        expect(frase.trim(), endsWith('.'), reason: 'uma frase inteira');
      });
    }

    test('com o formato real do servidor (texto + detalhe + código)', () {
      // RAISE EXCEPTION 'invalid_role: %' e 'PAPEL_NAO_ATRIBUIDO: %'.
      expect(_erro('invalid_role: handyman'), isNot(_generica));
      expect(_erro('PAPEL_NAO_ATRIBUIDO: casa'), isNot(_generica));
      expect(_erro('oferta_expirada', code: 'P0001'),
          'Esta oferta já expirou. Fica atento às próximas.');
    });
  });

  group('a ordem das perguntas não troca frases', () {
    test('sem_permissao e nao_e_profissional vêm com 42501 e não são "sessão"',
        () {
      expect(_erro('sem_permissao', code: '42501'),
          'Não tens permissão para fazer isto.');
      expect(_erro('nao_e_profissional', code: '42501'),
          'A tua conta de profissional da Casa não está ativa.');
      expect(_erro('qualquer', code: '42501'),
          'A tua sessão expirou. Volta a entrar e tenta de novo.');
    });

    test('códigos parecidos têm frases diferentes', () {
      expect(_erro('oficio_invalido'), isNot(_erro('oficios_em_falta')));
      expect(_erro('orcamento_expirado'), isNot(_erro('oferta_expirada')));
      expect(_erro('motivo_em_falta'), _erro('motivo_obrigatorio'));
      expect(_erro('tipo_invalido'), isNot(_erro('caminho_invalido')));
    });

    test('sem rede e desconhecido continuam como estavam', () {
      expect(
          casaErroTexto(TimeoutException('x')), 'Sem rede. Tenta outra vez.');
      expect(casaErroTexto(Exception('coisa nova')), _generica);
    });
  });
}
