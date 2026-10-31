// CASA (missão casa-manutencao-2026-10-30): documentos, reenvio, trabalho em
// curso e frases de falha do profissional da Casa e manutenção. A Casa nunca
// pode cair na regra, no balde ou na tabela da limpeza ou da lavagem.
import 'package:bora_app/models/falha_de_acao.dart' as falha;
import 'package:bora_app/services/prestador_documentos.dart';
import 'package:bora_app/services/prestador_reenvio_service.dart';
import 'package:bora_app/services/provider_upload_service.dart';
import 'package:bora_app/services/trabalho_em_curso.dart' as curso;
import 'package:flutter_test/flutter_test.dart';

List<String> _c(List l) => l.map((d) => d.chave as String).toList();

void main() {
  group('documentosEmFaltaCasa — o que falta ao profissional da Casa', () {
    test('sem nada: foto, documento de identificação e os dados legais', () {
      final falta = _c(documentosEmFaltaCasa(<String, dynamic>{}));
      expect(falta.take(2).toList(), ['photo', 'cartao_cidadao']);
      expect(falta, containsAll(<String>['legal_name', 'nif', 'iban', 'dsa']));
      // Nada da lavagem nem da limpeza.
      expect(falta, isNot(contains('driving_license')));
      expect(falta, isNot(contains('materials')));
      expect(falta, isNot(contains('id_doc')));
    });

    test('o cartão de cidadão pendente ou aprovado conta como enviado', () {
      for (final estado in ['pending', 'approved']) {
        final p = <String, dynamic>{
          'documentos': [
            {'tipo': 'cartao_cidadao', 'estado': estado},
          ],
        };
        expect(_c(documentosEmFaltaCasa(p)), isNot(contains('cartao_cidadao')),
            reason: estado);
      }
    });

    test('recusado ou caducado volta a faltar', () {
      for (final estado in ['rejected', 'expired']) {
        final p = <String, dynamic>{
          'documentos': [
            {'tipo': 'cartao_cidadao', 'estado': estado},
          ],
        };
        expect(_c(documentosEmFaltaCasa(p)), contains('cartao_cidadao'),
            reason: estado);
      }
    });

    test('o comprovativo de atividade só entra quando conta', () {
      expect(_c(documentosEmFaltaCasa({})), isNot(contains('atividade')));
      expect(_c(documentosEmFaltaCasa({}, atividadeEmFalta: true)),
          contains('atividade'));
    });

    test('documentosEmFaltaPrestador("handyman") usa a regra da Casa', () {
      final linha = <String, dynamic>{'docs': {}};
      expect(_c(documentosEmFaltaPrestador('handyman', linha)),
          _c(documentosEmFaltaCasa(linha)));
      expect(_c(documentosEmFaltaPrestador('handyman', linha)),
          isNot(contains('materials')),
          reason: 'a Casa não pode cair na regra da limpeza');
    });
  });

  group('reenvio da Casa', () {
    test('o documento envia-se por foto; o resto pelo caminho certo', () {
      expect(comoEnviarPrestador('handyman', 'cartao_cidadao'),
          ComoEnviar.foto);
      expect(comoEnviarPrestador('handyman', 'iban'), ComoEnviar.dadosFiscais);
      expect(comoEnviarPrestador('handyman', kChaveDadosFiscais),
          ComoEnviar.dadosFiscais);
      expect(comoEnviarPrestador('handyman', 'atividade'),
          ComoEnviar.comprovativo);
      // Sem RPC de foto de perfil para a Casa: vai pelo Suporte.
      expect(comoEnviarPrestador('handyman', 'photo'), ComoEnviar.suporte);
      expect(comoEnviarPrestador('handyman', 'materials'), ComoEnviar.suporte);
      expect(comoEnviarPrestador('handyman', 'driving_license'),
          ComoEnviar.suporte);
    });

    test('balde e tabela próprios — nunca os da lavagem nem da limpeza', () {
      expect(ProviderUploadService.bucketCasa, 'handyman-documents');
      expect(PrestadorReenvioService.tabela('handyman'), 'casa_profissionais');
      expect(PrestadorReenvioService.tabela('washer'), 'washers');
      expect(PrestadorReenvioService.tabela('cleaner'), 'cleaners');
    });
  });

  group('trabalho em curso da Casa', () {
    curso.TrabalhoEmCurso t(String estado) => curso.TrabalhoEmCurso(
          categoria: 'casa',
          bookingId: 'x',
          estado: estado,
          morada: '',
          ganhoCents: 0,
        );

    test('a barra diz que é um trabalho da Casa', () {
      expect(t('aceite').titulo, 'Trabalho da Casa a decorrer');
    });

    test('os estados da Casa têm palavras próprias', () {
      expect(t('aceite').passo, 'aceite');
      expect(t('a_caminho').passo, 'a caminho');
      expect(t('chegou').passo, 'no local');
      expect(t('em_curso').passo, 'a trabalhar');
    });

    test('a lavagem e a limpeza continuam iguais', () {
      curso.TrabalhoEmCurso outro(String c) => curso.TrabalhoEmCurso(
          categoria: c, bookingId: 'y', estado: '', morada: '', ganhoCents: 0);
      expect(outro('lavagem').titulo, 'Lavagem a decorrer');
      expect(outro('limpeza').titulo, 'Limpeza a decorrer');
    });
  });

  group('frases de falha da Casa', () {
    test('masculino: "Este trabalho … atribuído"', () {
      final msg = falha.mensagemDeFalhaDeAcao(
          Exception('booking_not_yours'),
          trabalho: falha.TrabalhoEmCurso.casa);
      expect(msg, 'Este trabalho já não está atribuído a ti.');
    });

    test('pedido já criado lê-se como sucesso', () {
      final m = const falha.JaFicouCriado(falha.TrabalhoEmCurso.casa).mensagem;
      expect(m, contains('já ficou feito'));
      expect(m.toLowerCase(), isNot(contains('tenta outra vez')));
    });
  });
}
