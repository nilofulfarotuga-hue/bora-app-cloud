// CASA — regras do lado do cliente (31/10/2026, missão casa-manutencao).
//
// Lógica pura, sem rede: o limite do dinheiro (decisão 3 do Danilo), o texto
// "desde X €" vindo SEMPRE do modelo (nunca escrito no código), os botões que
// aparecem em cada estado, a validação do assistente (o botão nunca falha
// calado) e as frases de erro por código do contrato.
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/models/casa_models.dart';
import 'package:bora_app/models/falha_de_acao.dart';
import 'package:bora_app/screens/client/casa/casa_regras.dart';
import 'package:bora_app/stores/casa_store.dart';

CasaServico _servico({
  String modo = 'fixo',
  int? preco = 2500,
  String unidade = 'movel',
  num min = 1,
  num max = 10,
  List<Map<String, dynamic>> perguntas = const [],
}) =>
    CasaServico.fromJson({
      'id': 's1',
      'oficio': 'montagem',
      'nome': 'Montar um móvel',
      'modo': modo,
      'preco_cents': preco,
      'unidade': unidade,
      'min_quantidade': min,
      'max_quantidade': max,
      'duracao_min': 60,
      'perguntas': perguntas,
    });

CasaPedido _pedido(Map<String, dynamic> extra) => CasaPedido.fromJson({
      'id': 'p1',
      'servico_nome': 'Montar um móvel',
      'modo': 'fixo',
      'estado': 'procura',
      'payment_method': 'cash',
      'payment_status': 'unpaid',
      ...extra,
    });

const _profissional = {
  'id': 'pro1',
  'name': 'Rui',
  'rating_avg': 4.8,
  'ratings_count': 12,
  'jobs_done': 30,
};

void main() {
  const config = CasaConfig(visivel: true, enabled: true, maxCashCents: 4000);

  group('Dinheiro só até max_cash_cents (decisão 3)', () {
    test('no limite exato ainda pode', () {
      expect(casaDinheiroPermitido(4000, 4000), isTrue);
    });

    test('um cêntimo acima já não pode', () {
      expect(casaDinheiroPermitido(4001, 4000), isFalse);
    });

    test('abaixo do limite: dinheiro disponível, cartão e MB Way "brevemente"',
        () {
      final m = casaMetodosPagamento(totalCents: 3500, config: config);
      expect(m.map((x) => x.codigo), ['cash', 'card', 'mbway']);
      expect(m[0].disponivel, isTrue);
      expect(m[1].disponivel, isFalse);
      expect(m[1].rotulo, contains('brevemente'));
      expect(m[2].disponivel, isFalse);
      expect(m[2].rotulo, contains('brevemente'));
      expect(casaMetodoPorDefeito(totalCents: 3500, config: config), 'cash');
    });

    test('acima do limite sem cartão: nada disponível e explica porquê', () {
      final m = casaMetodosPagamento(totalCents: 4500, config: config);
      expect(m.any((x) => x.disponivel), isFalse);
      expect(m[0].rotulo, 'Dinheiro — só até 40,00 €');
      expect(casaMetodoPorDefeito(totalCents: 4500, config: config), isNull);
      final falta = casaFaltaNoPagamento(
        servico: _servico(),
        metodo: 'cash',
        totalCents: 4500,
        config: config,
      );
      expect(falta, isNotNull);
      expect(falta!.campo, CasaCampo.pagamento);
      expect(falta.mensagem, contains('40,00 €'));
      expect(falta.mensagem, contains('só cartão ou MB Way'));
    });

    test('acima do limite com cartão ligado: escolhe o cartão', () {
      const comCartao = CasaConfig(
          visivel: true, maxCashCents: 4000, pagamentoCartao: true);
      expect(casaMetodoPorDefeito(totalCents: 4500, config: comCartao), 'card');
      expect(
        casaFaltaNoPagamento(
          servico: _servico(),
          metodo: 'card',
          totalCents: 4500,
          config: comCartao,
        ),
        isNull,
      );
    });

    test('no orçamento não se escolhe pagamento ao pedir', () {
      expect(
        casaFaltaNoPagamento(
          servico: _servico(modo: 'orcamento', preco: null, unidade: 'tarefa'),
          metodo: null,
          totalCents: 0,
          config: config,
        ),
        isNull,
      );
    });

    test('pago: dinheiro só quando confirmado; cartão quando retido', () {
      expect(casaPedidoPago(_pedido({'estado': 'aceite'})), isFalse);
      expect(casaPedidoPago(_pedido({'estado': 'confirmado'})), isTrue);
      expect(
          casaPedidoPago(_pedido({
            'estado': 'confirmado',
            'payment_method': 'card',
            'payment_status': 'unpaid',
          })),
          isFalse);
      expect(
          casaPedidoPago(_pedido({
            'estado': 'aceite',
            'payment_method': 'mbway',
            'payment_status': 'held',
          })),
          isTrue);
    });
  });

  group('Preço vem do modelo (preco_cents do servidor)', () {
    test('fixo por móvel', () {
      expect(casaTextoPreco(_servico(preco: 2750), quoteMaxPros: 3),
          'desde 27,50 € por móvel');
    });

    test('fixo por tarefa', () {
      expect(
          casaTextoPreco(_servico(preco: 3000, unidade: 'tarefa'),
              quoteMaxPros: 3),
          'desde 30,00 €');
    });

    test('à hora', () {
      expect(
          casaTextoPreco(_servico(modo: 'hora', preco: 2000, unidade: 'hora'),
              quoteMaxPros: 3),
          'desde 20,00 € por hora');
    });

    test('orçamento: grátis e até N profissionais (N do servidor)', () {
      expect(
          casaTextoPreco(
              _servico(modo: 'orcamento', preco: null, unidade: 'tarefa'),
              quoteMaxPros: 4),
          'Pedir orçamento — grátis, até 4 profissionais respondem');
    });

    test('total indicativo = preço × quantidade; orçamento não tem total', () {
      expect(casaTotalEstimadoCents(_servico(preco: 2500), 3), 7500);
      expect(
          casaTotalEstimadoCents(
              _servico(modo: 'hora', preco: 2000, unidade: 'hora'), 2.5),
          5000);
      expect(
          casaTotalEstimadoCents(
              _servico(modo: 'orcamento', preco: null, unidade: 'tarefa'), 1),
          isNull);
    });

    test('quantidade em texto e passo de meia hora', () {
      final hora = _servico(modo: 'hora', preco: 2000, unidade: 'hora');
      expect(casaQuantidadeTexto(hora, 2), '2 h');
      expect(casaQuantidadeTexto(_servico(), 1), '1 móvel');
      expect(casaQuantidadeTexto(_servico(), 3), '3 móveis');
      expect(casaPassoQuantidade(hora), 1);
      expect(
          casaPassoQuantidade(
              _servico(modo: 'hora', unidade: 'hora', min: 1.5, max: 4)),
          0.5);
    });
  });

  group('Assistente — diz sempre o que falta', () {
    final comEscolha = _servico(perguntas: const [
      {'id': 'tipo', 'texto': 'Que móvel é?', 'tipo': 'texto'},
      {
        'id': 'marca',
        'texto': 'É do IKEA?',
        'tipo': 'escolha',
        'opcoes': ['IKEA', 'Outra'],
      },
    ]);

    test('pergunta de escolha por responder aponta essa pergunta', () {
      final f = casaFaltaNoServico(
        servico: comEscolha,
        respostas: const {},
        quantidade: 1,
        descricao: '',
      );
      expect(f!.campo, CasaCampo.pergunta);
      expect(f.perguntaId, 'marca');
      expect(f.mensagem, contains('É do IKEA?'));
    });

    test('pergunta de texto é opcional no preço fixo', () {
      expect(
        casaFaltaNoServico(
          servico: comEscolha,
          respostas: const {'marca': 'IKEA'},
          quantidade: 2,
          descricao: '',
        ),
        isNull,
      );
    });

    test('quantidade fora do catálogo não passa', () {
      final f = casaFaltaNoServico(
        servico: _servico(min: 1, max: 4),
        respostas: const {},
        quantidade: 5,
        descricao: '',
      );
      expect(f!.campo, CasaCampo.quantidade);
    });

    test('orçamento sem dizer o que é preciso não passa', () {
      final orc = _servico(modo: 'orcamento', preco: null, unidade: 'tarefa');
      final f = casaFaltaNoServico(
        servico: orc,
        respostas: const {},
        quantidade: 1,
        descricao: 'porta',
      );
      expect(f!.campo, CasaCampo.descricao);
      expect(
        casaFaltaNoServico(
          servico: orc,
          respostas: const {},
          quantidade: 1,
          descricao: 'A porta da cozinha roça no chão',
        ),
        isNull,
      );
    });

    final agora = DateTime.utc(2026, 11, 2, 10);

    test('sem dia e hora', () {
      final f = casaFaltaNoQuandoOnde(
          quando: null,
          agora: agora,
          minLeadHours: 2,
          rua: 'Rua do Comércio 5',
          cidade: 'Guarda');
      expect(f!.campo, CasaCampo.data);
    });

    test('antecedência mínima', () {
      final f = casaFaltaNoQuandoOnde(
          quando: agora.add(const Duration(hours: 1)),
          agora: agora,
          minLeadHours: 2,
          rua: 'Rua do Comércio 5',
          cidade: 'Guarda');
      expect(f!.campo, CasaCampo.data);
      expect(f.mensagem, contains('2 h'));
    });

    test('rua e localidade em falta, por esta ordem', () {
      final semRua = casaFaltaNoQuandoOnde(
          quando: agora.add(const Duration(hours: 3)),
          agora: agora,
          minLeadHours: 2,
          rua: '  ',
          cidade: '');
      expect(semRua!.campo, CasaCampo.rua);
      final semCidade = casaFaltaNoQuandoOnde(
          quando: agora.add(const Duration(hours: 3)),
          agora: agora,
          minLeadHours: 2,
          rua: 'Rua do Comércio 5',
          cidade: ' ');
      expect(semCidade!.campo, CasaCampo.cidade);
    });

    test('tudo certo', () {
      expect(
        casaFaltaNoQuandoOnde(
            quando: agora.add(const Duration(hours: 3)),
            agora: agora,
            minLeadHours: 2,
            rua: 'Rua do Comércio 5',
            cidade: 'Guarda'),
        isNull,
      );
    });
  });

  group('Morada automática partida nos três campos', () {
    test('linha do Google com código postal', () {
      final m = casaPartirMorada(
          'R. Dr. Francisco dos Prazeres 12, 6300-690 Guarda, Portugal');
      expect(m.rua, 'R. Dr. Francisco dos Prazeres 12');
      expect(m.cidade, 'Guarda');
      expect(m.codigoPostal, '6300-690');
    });

    test('sem código postal: a última parte é a localidade', () {
      final m = casaPartirMorada('Rua do Comércio 5, Guarda');
      expect(m.rua, 'Rua do Comércio 5');
      expect(m.cidade, 'Guarda');
      expect(m.codigoPostal, '');
    });

    test('só a rua: fica tudo na rua', () {
      final m = casaPartirMorada('Rua do Comércio 5');
      expect(m.rua, 'Rua do Comércio 5');
      expect(m.cidade, '');
    });
  });

  group('Botões por estado', () {
    final agora = DateTime(2026, 11, 2, 10);

    test('à espera de orçamentos, com um aberto: aceitar e cancelar', () {
      final a = CasaAcoesCliente.de(
        _pedido({
          'modo': 'orcamento',
          'estado': 'orcamentos',
          'orcamentos': [
            {'id': 'o1', 'preco_cents': 4500, 'estado': 'enviado'},
          ],
        }),
        agora: agora,
      );
      expect(a.aceitarOrcamentos, isTrue);
      expect(a.cancelar, isTrue);
      expect(a.contactar, isFalse);
      expect(a.confirmarConclusao, isFalse);
    });

    test('orçamento já retirado não se aceita', () {
      final a = CasaAcoesCliente.de(
        _pedido({
          'modo': 'orcamento',
          'estado': 'orcamentos',
          'orcamentos': [
            {'id': 'o1', 'preco_cents': 4500, 'estado': 'retirado'},
          ],
        }),
        agora: agora,
      );
      expect(a.aceitarOrcamentos, isFalse);
    });

    test('chat e telefone só com pode_contactar (decisão 4)', () {
      final sem = CasaAcoesCliente.de(
        _pedido({'estado': 'aceite', 'profissional': _profissional}),
        agora: agora,
      );
      expect(sem.contactar, isFalse);
      final com = CasaAcoesCliente.de(
        _pedido({
          'estado': 'aceite',
          'pode_contactar': true,
          'profissional': {..._profissional, 'phone': '+351910000000'},
        }),
        agora: agora,
      );
      expect(com.contactar, isTrue);
      expect(com.cancelar, isTrue);
    });

    test('orçamento fora da validade não se aceita', () {
      final a = CasaAcoesCliente.de(
        _pedido({
          'modo': 'orcamento',
          'estado': 'orcamentos',
          'orcamentos': [
            {
              'id': 'o1',
              'preco_cents': 4500,
              'estado': 'enviado',
              'expira_em':
                  agora.subtract(const Duration(hours: 1)).toIso8601String(),
            },
          ],
        }),
        agora: agora,
      );
      expect(a.aceitarOrcamentos, isFalse);
    });

    test('profissional já chegou: ainda se cancela (com o custo da simulação)',
        () {
      final a =
          CasaAcoesCliente.de(_pedido({'estado': 'chegou'}), agora: agora);
      expect(a.cancelar, isTrue);
    });

    test('trabalho em curso: já não se cancela', () {
      final a = CasaAcoesCliente.de(_pedido({'estado': 'em_curso'}),
          agora: agora);
      expect(a.cancelar, isFalse);
    });

    test('valor extra por responder aparece; num pedido cancelado não', () {
      final extras = [
        {'id': 'e1', 'valor_cents': 1000, 'motivo': 'Peça', 'estado': 'pedido'},
      ];
      expect(
          CasaAcoesCliente.de(
                  _pedido({'estado': 'em_curso', 'extras': extras}),
                  agora: agora)
              .responderExtras,
          isTrue);
      expect(
          CasaAcoesCliente.de(
                  _pedido({'estado': 'cancelado', 'extras': extras}),
                  agora: agora)
              .responderExtras,
          isFalse);
      expect(
          CasaAcoesCliente.de(
                  _pedido({'estado': 'concluido', 'extras': extras}),
                  agora: agora)
              .responderExtras,
          isFalse,
          reason: 'o servidor só aceita a resposta até ao fim do trabalho');
    });

    test('concluído: confirmar e refazer; avaliar ainda não', () {
      final a = CasaAcoesCliente.de(_pedido({'estado': 'concluido'}),
          agora: agora);
      expect(a.confirmarConclusao, isTrue);
      expect(a.refazer, isTrue);
      expect(a.avaliar, isFalse);
    });

    test('confirmado e pago em dinheiro: avaliar uma vez', () {
      expect(
          CasaAcoesCliente.de(_pedido({'estado': 'confirmado'}), agora: agora)
              .avaliar,
          isTrue);
      expect(
          CasaAcoesCliente.de(
                  _pedido({'estado': 'confirmado', 'rating_cliente': 5}),
                  agora: agora)
              .avaliar,
          isFalse);
    });

    test('confirmado com cartão por pagar: não avalia', () {
      expect(
          CasaAcoesCliente.de(
                  _pedido({
                    'estado': 'confirmado',
                    'payment_method': 'card',
                    'payment_status': 'unpaid',
                  }),
                  agora: agora)
              .avaliar,
          isFalse);
    });

    test('garantia: refazer até garantia_ate, depois já não', () {
      final dentro = CasaAcoesCliente.de(
        _pedido({
          'estado': 'confirmado',
          'garantia_ate': agora.add(const Duration(days: 3)).toIso8601String(),
        }),
        agora: agora,
      );
      expect(dentro.refazer, isTrue);
      final fora = CasaAcoesCliente.de(
        _pedido({
          'estado': 'confirmado',
          'garantia_ate':
              agora.subtract(const Duration(days: 1)).toIso8601String(),
        }),
        agora: agora,
      );
      expect(fora.refazer, isFalse);
    });

    test('fotos do problema: só antes do trabalho e até ao limite', () {
      final fotos = [
        for (var i = 0; i < 5; i++)
          {'id': 'f$i', 'tipo': 'problema', 'storage_path': 'u/p1/x$i.jpg'},
      ];
      expect(
          CasaAcoesCliente.de(_pedido({'estado': 'procura'}), agora: agora)
              .adicionarFotos,
          isTrue);
      expect(
          CasaAcoesCliente.de(_pedido({'estado': 'procura', 'fotos': fotos}),
                  agora: agora, maxFotos: 5)
              .adicionarFotos,
          isFalse);
      expect(
          CasaAcoesCliente.de(_pedido({'estado': 'em_curso'}), agora: agora)
              .adicionarFotos,
          isFalse);
    });
  });

  group('Linha do tempo', () {
    test('orçamento começa à espera de orçamentos; fixo à procura', () {
      expect(casaPassosDaLinha(CasaModo.orcamento).first, CasaEstado.orcamentos);
      expect(casaPassosDaLinha(CasaModo.fixo).first, CasaEstado.procura);
    });

    test('disputa fica no passo concluído; cancelado sai da linha', () {
      final passos = casaPassosDaLinha(CasaModo.fixo);
      expect(casaIndiceNaLinha(CasaEstado.disputa, passos),
          passos.indexOf(CasaEstado.concluido));
      expect(casaIndiceNaLinha(CasaEstado.cancelado, passos), -1);
      expect(casaIndiceNaLinha(CasaEstado.emCurso, passos),
          passos.indexOf(CasaEstado.emCurso));
    });

    test('o texto traduzível do estado é igual ao do modelo', () {
      for (final e in CasaEstado.values) {
        expect(casaEstadoTr(e), e.textoPt);
      }
    });
  });

  group('Erros do contrato em PT-PT', () {
    test('dinheiro acima do limite diz o limite', () {
      final msg = casaMensagemDeErro(
          Exception('PostgrestException(message: dinheiro_acima_do_limite)'),
          maxCashCents: 4000);
      expect(msg, contains('40,00 €'));
    });

    test('categoria desligada', () {
      expect(casaMensagemDeErro(Exception('casa_desligada')),
          contains('indisponível'));
    });

    test('valores por autorizar não deixa marcar e não fala em preços', () {
      final msg = casaMensagemDeErro(Exception('valores_por_autorizar'));
      expect(msg, contains('ainda não está disponível'));
    });

    test('código desconhecido cai na frase geral, sem nomes técnicos', () {
      final msg = casaMensagemDeErro(Exception('xpto_qualquer'));
      expect(msg, isNotEmpty);
      expect(msg, isNot(contains('Exception')));
      expect(msg, isNot(contains('xpto')));
    });

    test('JaFicouCriado é sucesso, não erro', () {
      expect(casaMensagemDeErro(const JaFicouCriado(TrabalhoEmCurso.casa)),
          contains('não fizeste dois'));
    });
  });

  group('Respostas do servidor', () {
    test('mensagem do chat', () {
      final m = CasaMensagem.fromJson({
        'id': 'm1',
        'sender_role': 'handyman',
        'message': 'Chego às 10h',
        'created_at': '2026-11-02T10:00:00Z',
      });
      expect(m.senderRole, 'handyman');
      expect(m.texto, 'Chego às 10h');
      expect(m.createdAt, isNotNull);
    });

    test('simulação do cancelamento', () {
      final gratis = CasaSimulacaoCancelamento.fromJson(
          {'cancel_fee_cents': 0, 'escalao': 'gratis'});
      expect(gratis.gratis, isTrue);
      final metade = CasaSimulacaoCancelamento.fromJson(
          {'cancel_fee_cents': 1250, 'escalao': 'metade'});
      expect(metade.gratis, isFalse);
      expect(metade.taxaCents, 1250);
    });
  });
}
