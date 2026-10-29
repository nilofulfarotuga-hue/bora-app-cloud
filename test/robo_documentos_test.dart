// Robô "fiscal de documentos" (missão final-app-2026-10-29, adendo 3): as peças
// puras que o painel e as apps partilham. Sem rede, sem Supabase, sem dados
// reais (os nomes aqui são inventados).
import 'package:bora_app/services/robo_documentos.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> linha({
  int id = 1,
  String campo = 'provider_atividade.documento_path',
  String decisao = 'ok',
  String acao = 'nenhuma',
  String modo = 'sombra',
  String? detetado = 'comprovativo_atividade_AT',
  double conf = 1.0,
  String? path = 'u1/comprovativo_1.pdf',
  String? revertido,
  bool? nomeBate,
  bool? nifBate,
  bool? legivel = true,
}) =>
    {
      'id': id,
      'user_id': 'u1',
      'campo': campo,
      'decisao': decisao,
      'acao': acao,
      'modo': modo,
      'tipo_detectado': detetado,
      'confianca': conf,
      'path': path,
      'revertido_em': revertido,
      'nome_bate': nomeBate,
      'nif_bate': nifBate,
      'legivel': legivel,
      'created_at': '2026-10-29T15:00:00Z',
    };

void main() {
  group('VereditoRobo e escolha do veredito', () {
    test('lê a linha do banco (confiança pode vir como texto)', () {
      final v = VereditoRobo.fromMap({...linha(), 'confianca': '0.912'});
      expect(v.confianca, 0.912);
      expect(v.ok, isTrue);
      expect(v.desfeito, isFalse);
      expect(v.agiu, isFalse);
    });

    test('só o último veredito de cada campo conta e os desfeitos saem', () {
      final por = ultimoPorCampo([
        linha(id: 1, decisao: 'errado'),
        linha(id: 3, decisao: 'ok'),
        linha(id: 2, decisao: 'duvida'),
        linha(id: 9, decisao: 'errado', revertido: '2026-10-29T16:00:00Z'),
        linha(id: 4, campo: 'drivers.vehicle_photo_url', decisao: 'errado'),
      ]);
      expect(por['provider_atividade.documento_path']!.id, 3);
      expect(por['provider_atividade.documento_path']!.ok, isTrue);
      expect(por['drivers.vehicle_photo_url']!.errado, isTrue);
    });

    test('o veredito é do ficheiro que se mostra (URL assinado ou caminho, com %)', () {
      final v = VereditoRobo.fromMap(linha(path: 'u1/foto%201.jpg'));
      expect(vereditoDoFicheiro(v, 'https://x.supabase.co/storage/v1/object/sign/driver-documents/u1/foto%201.jpg?token=abc'), isTrue);
      expect(vereditoDoFicheiro(v, 'u1/foto 1.jpg'), isTrue);
      expect(vereditoDoFicheiro(v, 'u1/outro_ficheiro.jpg'), isFalse);
      expect(vereditoDoFicheiro(v, null), isFalse);
      expect(vereditoDoFicheiro(VereditoRobo.fromMap(linha(path: null)), 'qualquer'), isTrue);
    });
  });

  group('frases do painel (PT-BR)', () {
    test('cartão de cidadão no lugar do comprovativo', () {
      final v = VereditoRobo.fromMap(linha(decisao: 'errado', detetado: 'cartao_cidadao', conf: 0.97));
      expect(textoDoVeredito(v),
          'Robô: parece um cartão de cidadão, não é o comprovativo das Finanças (97% de certeza)');
    });

    test('folha qualquer (outro) e ficheiro ilegível', () {
      expect(
        textoDoVeredito(VereditoRobo.fromMap(linha(decisao: 'errado', detetado: 'outro', conf: 1))),
        'Robô: não parece o comprovativo das Finanças (100% de certeza)',
      );
      expect(
        textoDoVeredito(VereditoRobo.fromMap(linha(decisao: 'errado', legivel: false, conf: 0.9))),
        'Robô: não consegue ler este ficheiro (90% de certeza)',
      );
    });

    test('dúvida diz porquê; ok diz o que confere', () {
      expect(
        textoDoVeredito(VereditoRobo.fromMap(linha(decisao: 'duvida', nomeBate: false, nifBate: false))),
        'Robô: dúvida — o nome não bate com o da conta e o NIF não bate com o da conta',
      );
      expect(
        textoDoVeredito(VereditoRobo.fromMap(linha(decisao: 'ok', nomeBate: true, nifBate: true, conf: 0.95))),
        'Robô: parece o comprovativo de atividade das Finanças — nome confere e NIF confere (95% de certeza)',
      );
    });

    test('rótulos dos campos', () {
      expect(rotuloDoCampo('drivers.registration_selfie_url'), 'Selfie');
      expect(rotuloDoCampo('cleaners.docs.id_doc'), 'Documento de identificação');
      expect(rotuloDoCampo('washers.docs.driving_license'), 'Carta de condução');
      expect(rotuloDoCampo('campo.novo'), 'campo.novo');
    });
  });

  group('aprovar: o que o robô tem a dizer', () {
    Map<String, dynamic> pessoa(List<Map<String, dynamic>> vereditos, {Map<String, dynamic>? atividade}) => {
          'user_id': 'u1',
          '_robo': ultimoPorCampo(vereditos),
          if (atividade != null) '_atividade': atividade,
        };

    test('só os errados avisam, um por documento', () {
      final p = pessoa([
        linha(id: 1, decisao: 'errado', detetado: 'cartao_cidadao'),
        linha(id: 2, campo: 'drivers.vehicle_photo_url', decisao: 'ok', detetado: 'foto_veiculo'),
        linha(id: 3, campo: 'drivers.vehicle_doc_url', decisao: 'errado', detetado: 'carta_conducao'),
      ]);
      final avisos = avisosParaAprovar(p);
      expect(avisos, hasLength(2));
      expect(avisos.first, startsWith('Comprovativo de atividade — Robô: parece um cartão de cidadão'));
      expect(avisos.last, startsWith('Documento do veículo — Robô: parece uma carta de condução'));
      expect(avisosParaAprovar({'user_id': 'u1'}), isEmpty);
    });

    test('o servidor recusava com 400: o painel avisa antes, com o que o robô viu', () {
      final p = pessoa(
        [linha(decisao: 'errado', detetado: 'cartao_cidadao')],
        atividade: {'obrigatoria': true, 'atividade_status': 'em_analise', 'documento_path': 'u1/x.pdf'},
      );
      final b = bloqueioDaAtividade(p)!;
      expect(b, startsWith('Falta aprovar o comprovativo de atividade desta pessoa'));
      expect(b, contains('Robô: parece um cartão de cidadão'));
    });

    test('sem comprovativo enviado diz que ainda não o enviou', () {
      final p = pessoa([], atividade: {'obrigatoria': true, 'atividade_status': 'por_enviar', 'documento_path': null});
      expect(bloqueioDaAtividade(p), startsWith('Falta o comprovativo de atividade desta pessoa: ainda não o enviou.'));
    });

    test('aprovado ou não obrigatório não bloqueia', () {
      expect(bloqueioDaAtividade(pessoa([], atividade: {'obrigatoria': true, 'atividade_status': 'aprovada'})), isNull);
      expect(bloqueioDaAtividade(pessoa([], atividade: {'obrigatoria': false, 'atividade_status': 'por_enviar'})), isNull);
      expect(bloqueioDaAtividade({'user_id': 'u1'}), isNull);
    });

    test('resumo das listas', () {
      expect(resumoDoRobo({'_robo': <String, VereditoRobo>{}}).nivel, 'nada');
      expect(resumoDoRobo(pessoa([linha(decisao: 'ok')])).texto, 'Robô: tudo certo no documento visto');
      expect(
        resumoDoRobo(pessoa([linha(id: 1), linha(id: 2, campo: 'drivers.vehicle_photo_url')])).texto,
        'Robô: tudo certo nos 2 documentos vistos',
      );
      expect(resumoDoRobo(pessoa([linha(decisao: 'duvida')])).texto, 'Robô: 1 dúvida');
      final dois = resumoDoRobo(pessoa([
        linha(id: 1, decisao: 'errado'),
        linha(id: 2, campo: 'drivers.vehicle_photo_url', decisao: 'errado'),
      ]));
      expect(dois.texto, 'Robô: 2 documentos errados');
      expect(dois.nivel, 'errado');
    });
  });

  group('app do candidato (PT-PT)', () {
    test('a frase da verificação na hora, palavra por palavra', () {
      expect(
        mensagemDaPrevia(campo: 'provider_atividade.documento_path', tipoDetetado: 'cartao_cidadao'),
        'Isto parece um cartão de cidadão, não o comprovativo das Finanças. Escolhe outro ficheiro.',
      );
      expect(
        mensagemDaPrevia(campo: 'provider_atividade.documento_path', tipoDetetado: 'outro'),
        'Isto não parece o comprovativo das Finanças. Escolhe outro ficheiro.',
      );
      expect(
        mensagemDaPrevia(campo: 'drivers.registration_selfie_url', tipoDetetado: 'fatura_ou_talao'),
        'Isto parece uma fatura ou um talão, não uma selfie. Escolhe outro ficheiro.',
      );
    });

    test('estado devolvido pelo servidor', () {
      final e = EstadoDocumentosApp.fromJson({
        'ativo': true,
        'itens': [
          {'campo': 'provider_atividade.documento_path', 'decisao': 'errado', 'motivo_pt': 'Enviaste o cartão de cidadão no lugar do comprovativo.'},
          {'campo': 'drivers.registration_selfie_url', 'decisao': 'ok', 'motivo_pt': null},
          {'campo': 'drivers.vehicle_photo_url', 'decisao': 'duvida'},
        ],
      });
      expect(e.ativo, isTrue);
      expect(e.aCorrigir, hasLength(1));
      expect(e.itens[0].estado, 'Precisa de ser enviado de novo');
      expect(e.itens[1].estado, 'Recebido e parece certo');
      expect(e.itens[2].estado, 'Em análise');
      expect(EstadoDocumentosApp.fromJson({'ativo': false, 'itens': []}).itens, isEmpty);
    });
  });
}
