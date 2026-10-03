// Parceiro edita pedido (2026-09-22) — o que a app decide sozinha.
// O dinheiro é todo do servidor (provado em SQL: provas/parceiro-edita-pedido-2026-09-22/);
// aqui testa-se o que a app monta e mostra: o JSON enviado, a conta rápida do
// rascunho, o agrupamento das propostas, os textos de estado, a pesquisa sem
// acentos e a hora de Lisboa do painel.
import 'package:bora_app/models/order_edit.dart';
import 'package:bora_app/models/product_option.dart';
import 'package:bora_app/services/order_edit_service.dart';
import 'package:bora_app/utils/hora_lisboa.dart';
import 'package:bora_app/utils/search_text.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _linha({
  required String id,
  required String grupo,
  String tipo = 'remove',
  String estado = 'aplicado',
  String nome = 'Açaí 500ml',
  int qtd = 1,
  double antes = 20.00,
  double depois = 17.85,
  String criado = '2026-09-22T19:00:00Z',
  Map<String, dynamic> liq = const {},
}) =>
    {
      'id': id,
      'grupo_id': grupo,
      'order_id': 'o1',
      'restaurant_id': 'r1',
      'tipo': tipo,
      'linha_idx': 0,
      'product_id': 'p1',
      'nome': nome,
      'opcoes': [
        {'group': 'Extras', 'items': ['Mel']}
      ],
      'quantidade': qtd,
      'preco_unitario': 2.05,
      'subtotal_antes': 15,
      'subtotal_depois': 12.95,
      'total_antes': antes,
      'total_depois': depois,
      'estado': estado,
      'liquidacao': liq,
      'criado_em': criado,
    };

void main() {
  group('pesquisa sem acentos (lista de produtos da loja)', () {
    test('açaí encontra-se escrevendo acai, AÇAÍ ou com espaços a mais', () {
      expect(normalizarPesquisa('  Açaí   Grande '), 'acai grande');
      expect(correspondePesquisa('Copo Açaí 500ml', 'acai'), isTrue);
      expect(correspondePesquisa('Copo Açaí 500ml', 'AÇAÍ 500'), isTrue);
      expect(correspondePesquisa('Pão de Queijo', 'pao queijo'), isTrue);
    });

    test('todas as palavras têm de aparecer; vazio deixa passar tudo', () {
      expect(correspondePesquisa('Copo Açaí 500ml', 'acai morango'), isFalse);
      expect(correspondePesquisa('qualquer coisa', ''), isTrue);
      expect(correspondePesquisa('qualquer coisa', '   '), isTrue);
    });
  });

  group('rascunho do parceiro → JSON que o servidor recebe', () {
    test('tirar monta remove com linha, produto e unidades; desconta o preço da linha', () {
      final r = OrderEditRascunho()
        ..tirar(linhaIdx: 2, productId: 'p9', quantidade: 2, preco: 1.17)
        ..tirar(linhaIdx: 0, productId: 'p1', quantidade: 0, preco: 9.99); // 0 → ignora
      expect(r.alteracoes, [
        {'tipo': 'remove', 'linha_idx': 2, 'product_id': 'p9', 'quantidade': 2}
      ]);
      expect(r.deltaSubtotal, -2.34);
    });

    test('acrescentar leva as opções como o carrinho (nomes), e soma ao cêntimo', () {
      final r = OrderEditRascunho()
        ..acrescentar(
          productId: 'copo-mega',
          quantidade: 2,
          precoUnitarioComExtras: 16.00,
          opcoes: const [
            SelectedOption(group: 'Deseja Extras?', items: ['Mel', 'Kiwi'])
          ],
        )
        ..acrescentar(productId: 'agua', quantidade: 3, precoUnitarioComExtras: 1.17);
      expect(r.alteracoes.first, {
        'tipo': 'add',
        'product_id': 'copo-mega',
        'quantidade': 2,
        'opcoes': [
          {'group': 'Deseja Extras?', 'items': ['Mel', 'Kiwi']}
        ],
      });
      expect(r.alteracoes.last.containsKey('opcoes'), isFalse);
      expect(r.deltaSubtotal, 35.51); // 32,00 + 3,51 — sem lixo de vírgula flutuante
    });

    test('a conta do rascunho não acumula erro de vírgula flutuante (0,01…200,00)', () {
      for (var c = 1; c <= 20000; c += 7) {
        final preco = c / 100;
        final r = OrderEditRascunho()
          ..acrescentar(productId: 'x', quantidade: 3, precoUnitarioComExtras: preco)
          ..tirar(linhaIdx: 0, productId: 'x', quantidade: 1, preco: preco);
        expect((r.deltaSubtotal * 100).round(), c * 2, reason: 'preço $preco');
      }
    });
  });

  group('propostas vindas de order_edits', () {
    test('linhas do mesmo grupo juntam-se; mais recente primeiro', () {
      final linhas = [
        _linha(id: 'a', grupo: 'g1', criado: '2026-09-22T18:00:00Z'),
        _linha(id: 'b', grupo: 'g2', tipo: 'add', estado: 'pendente_cliente',
            antes: 17.85, depois: 21.05, criado: '2026-09-22T19:00:00Z', nome: 'Água', qtd: 2),
        _linha(id: 'c', grupo: 'g1', nome: 'Paçoca', qtd: 2, criado: '2026-09-22T18:00:00Z'),
      ].map(OrderEditLinha.fromMap);
      final grupos = OrderEditGrupo.agrupar(linhas);
      expect(grupos.map((g) => g.grupoId), ['g2', 'g1']);
      expect(grupos.last.linhas.length, 2);
      expect(grupos.last.resumo, '1× Açaí 500ml, 2× Paçoca');
      expect(grupos.last.eTirar, isTrue);
      expect(grupos.last.diferenca, -2.15);
      expect(grupos.first.diferenca, 3.20);
      expect(grupos.first.linhas.first.opcoes.first.items, ['Mel']);
    });

    test('textos de estado (PT-PT) que o parceiro e o cliente leem', () {
      OrderEditGrupo g(String estado, {String tipo = 'add', Map<String, dynamic> liq = const {}}) =>
          OrderEditGrupo('g', [OrderEditLinha.fromMap(_linha(id: 'x', grupo: 'g', tipo: tipo, estado: estado, liq: liq))]);
      expect(orderEditEstadoTexto(g('pendente_cliente')), 'À espera do cliente');
      expect(orderEditEstadoTexto(g('aceite')), 'Aceite');
      expect(orderEditEstadoTexto(g('aceite', liq: {'estado': 'a_cobrar'})), 'Aceite · a pagar');
      expect(g('aceite', liq: {'estado': 'a_cobrar'}).aguardaPagamento, isTrue);
      expect(orderEditEstadoTexto(g('aplicado')), 'Aceite');
      expect(orderEditEstadoTexto(g('aplicado', tipo: 'remove')), 'Em falta · devolvido');
      expect(orderEditEstadoTexto(g('recusado')), 'Recusado');
      expect(orderEditEstadoTexto(g('cancelado')), 'Cancelado');
    });

    test('estado desconhecido cai em "à espera" (nunca finge que aplicou)', () {
      expect(orderEditEstadoFromDb('xpto'), OrderEditEstado.pendenteCliente);
      expect(orderEditEstadoFromDb(null), OrderEditEstado.pendenteCliente);
    });
  });

  group('erros do servidor → frase para a pessoa', () {
    test('cada código conhecido tem frase própria', () {
      expect(mensagemErroEdicao('LIMITE_DINHEIRO: pagamento em dinheiro só até 40.00 €'),
          contains('40 €'));
      expect(mensagemErroEdicao('JA_RECOLHIDO: o pedido já saiu da loja'),
          contains('já saiu da loja'));
      expect(mensagemErroEdicao('EDICAO_DESLIGADA'), contains('ainda não está ligada'));
      expect(mensagemErroEdicao('PEDIDO_FICA_VAZIO'), contains('Não dá para tirar tudo'));
      expect(mensagemErroEdicao('coisa estranha'), 'Não foi possível concluir. Tenta outra vez.');
    });
  });

  group('hora de Lisboa no painel (nunca o fuso do navegador)', () {
    test('verão = UTC+1, inverno = UTC+0, e as mudanças caem no domingo certo', () {
      expect(dataHoraLisboa('2026-09-22T19:05:00Z'), '22/09 20:05');
      expect(dataHoraLisboa('2026-01-10T23:30:00Z'), '10/01 23:30');
      // 2026: verão começa a 29/03 01:00 UTC e acaba a 25/10 01:00 UTC
      expect(dataHoraLisboa('2026-03-29T00:59:00Z'), '29/03 00:59');
      expect(dataHoraLisboa('2026-03-29T01:00:00Z'), '29/03 02:00');
      expect(dataHoraLisboa('2026-10-25T00:59:00Z'), '25/10 01:59');
      expect(dataHoraLisboa('2026-10-25T01:00:00Z'), '25/10 01:00');
      expect(dataHoraLisboa(null), '—');
    });
  });
}
