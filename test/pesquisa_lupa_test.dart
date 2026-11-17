// Missão servidor-busca-leve-2026-11-17 (B2): a lupa não pesquisa a cada letra.
import 'dart:async';

import 'package:bora_app/utils/pesquisa_lupa.dart';
import 'package:flutter_test/flutter_test.dart';

/// Temporizador de mentira: só corre quando o teste manda ([Agenda.disparar]).
class _TemporizadorFalso implements Timer {
  _TemporizadorFalso(this.duracao, this.f);
  final Duration duracao;
  final void Function() f;
  bool _ativo = true;

  @override
  void cancel() => _ativo = false;

  @override
  bool get isActive => _ativo;

  @override
  int get tick => 0;
}

class _Agenda {
  final List<_TemporizadorFalso> todos = [];

  Timer agendar(Duration d, void Function() f) {
    final t = _TemporizadorFalso(d, f);
    todos.add(t);
    return t;
  }

  int get ativos => todos.where((t) => t.isActive).length;

  /// Corre os temporizadores que não foram cancelados (a pessoa parou).
  void disparar() {
    for (final t in List.of(todos)) {
      if (t.isActive) {
        t._ativo = false;
        t.f();
      }
    }
  }
}

/// Deixa correr as respostas que já chegaram.
Future<void> _assentar() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('letrasDaPesquisa (o mesmo que o servidor conta)', () {
    test('acentos, espaços e pontuação não contam', () {
      expect(letrasDaPesquisa('pa'), 2);
      expect(letrasDaPesquisa('pão'), 3);
      expect(letrasDaPesquisa(' p ã '), 2);
      expect(letrasDaPesquisa('7up'), 3);
      expect(letrasDaPesquisa('Água!'), 4);
      expect(letrasDaPesquisa(''), 0);
    });

    test('os limites ficam como pedido: espera 400 ms, memória 5 min, produtos a partir de 3', () {
      expect(kEsperaLupa, const Duration(milliseconds: 400));
      expect(kMemoriaLupa, const Duration(minutes: 5));
      expect(kLetrasProdutos, 3);
    });
  });

  group('chaveDaPesquisa', () {
    test('o mesmo texto escrito de outra maneira dá a mesma chave', () {
      expect(chaveDaPesquisa('Leite '), chaveDaPesquisa('leite'));
      expect(chaveDaPesquisa('Pão'), chaveDaPesquisa('pao'));
      expect(chaveDaPesquisa('coca   cola'), chaveDaPesquisa('Coca Cola'));
    });

    test('a loja faz parte da chave', () {
      expect(
        chaveDaPesquisa('leite', loja: 'continente-guarda'),
        isNot(chaveDaPesquisa('leite')),
      );
      expect(
        chaveDaPesquisa('leite', loja: 'continente-guarda'),
        isNot(chaveDaPesquisa('leite', loja: 'pingo-doce-guarda')),
      );
    });
  });

  group('MemoriaPesquisa', () {
    test('guarda 5 minutos e depois esquece', () {
      var agora = DateTime(2026, 11, 17, 9);
      final m = MemoriaPesquisa<int>(relogio: () => agora);
      m.guardar('k', 7);
      agora = agora.add(const Duration(minutes: 4, seconds: 59));
      expect(m.ler('k'), 7);
      agora = agora.add(const Duration(seconds: 1));
      expect(m.ler('k'), isNull);
      expect(m.tamanho, 0);
    });

    test('não cresce sem fim: sai a mais antiga', () {
      final m = MemoriaPesquisa<int>(maximo: 2);
      m.guardar('a', 1);
      m.guardar('b', 2);
      m.guardar('c', 3);
      expect(m.ler('a'), isNull);
      expect(m.ler('b'), 2);
      expect(m.ler('c'), 3);
    });

    test('duas pesquisas iguais ao mesmo tempo fazem um pedido só', () async {
      final m = MemoriaPesquisa<String>();
      var pedidos = 0;
      final c = Completer<String>();
      Future<String> buscar() {
        pedidos++;
        return c.future;
      }

      final a = m.obter('k', buscar);
      final b = m.obter('k', buscar);
      c.complete('resposta');
      expect(await a, 'resposta');
      expect(await b, 'resposta');
      expect(pedidos, 1);
      // e a seguir vem da memória
      expect(await m.obter('k', buscar), 'resposta');
      expect(pedidos, 1);
    });

    test(
      'um erro não fica guardado: a próxima vez volta a perguntar',
      () async {
        final m = MemoriaPesquisa<String>();
        var pedidos = 0;
        Future<String> falha() async {
          pedidos++;
          throw StateError('sem rede');
        }

        await expectLater(m.obter('k', falha), throwsStateError);
        await _assentar();
        expect(m.ler('k'), isNull);
        expect(await m.obter('k', () async => 'ok'), 'ok');
        expect(pedidos, 1);
      },
    );
  });

  group('LupaAgendada', () {
    late _Agenda agenda;
    late MemoriaPesquisa<String> memoria;
    late List<String> pedidos;
    late Map<String, Completer<String>> respostas;
    late LupaAgendada<String> lupa;

    setUp(() {
      agenda = _Agenda();
      memoria = MemoriaPesquisa<String>();
      pedidos = [];
      respostas = {};
      lupa = LupaAgendada<String>(
        buscar: (t) {
          pedidos.add(t);
          return (respostas[t] = Completer<String>()).future;
        },
        memoria: memoria,
        agendar: agenda.agendar,
      );
    });

    test(
      'a escrever "l", "le", "lei", "leit", "leite" sai UMA pesquisa, a última',
      () async {
        final chegou = <String>[];
        for (final t in ['l', 'le', 'lei', 'leit', 'leite']) {
          lupa.escrever(t, chaveDaPesquisa(t), aoChegar: chegou.add);
        }
        expect(agenda.ativos, 1);
        expect(agenda.todos.last.duracao, kEsperaLupa);
        agenda.disparar();
        expect(pedidos, ['leite']);
        respostas['leite']!.complete('R-leite');
        await _assentar();
        expect(chegou, ['R-leite']);
      },
    );

    test('a resposta antiga que chega depois da nova é deitada fora', () async {
      final chegou = <String>[];
      lupa.escrever('lei', chaveDaPesquisa('lei'), aoChegar: chegou.add);
      agenda.disparar(); // parou: sai "lei"
      lupa.escrever('leite', chaveDaPesquisa('leite'), aoChegar: chegou.add);
      agenda.disparar(); // parou outra vez: sai "leite"
      expect(pedidos, ['lei', 'leite']);
      respostas['leite']!.complete('R-leite');
      await _assentar();
      respostas['lei']!.complete('R-lei'); // chega tarde
      await _assentar();
      expect(chegou, ['R-leite']);
      // mas fica guardada para quando a pessoa voltar a escrever "lei"
      expect(memoria.ler(chaveDaPesquisa('lei')), 'R-lei');
    });

    test(
      'a mesma pesquisa outra vez vem da memória, sem ir ao servidor',
      () async {
        final chegou = <String>[];
        var comecou = 0;
        void escrever() => lupa.escrever(
          'leite',
          chaveDaPesquisa('leite'),
          aoChegar: chegou.add,
          aoComecar: () => comecou++,
        );
        escrever();
        agenda.disparar();
        respostas['leite']!.complete('R-leite');
        await _assentar();
        escrever();
        agenda.disparar();
        await _assentar();
        expect(pedidos, ['leite']);
        expect(chegou, ['R-leite', 'R-leite']);
        expect(comecou, 1);
      },
    );

    test('apagar o texto (parar) ignora o que estava a caminho', () async {
      final chegou = <String>[];
      lupa.escrever('leite', chaveDaPesquisa('leite'), aoChegar: chegou.add);
      agenda.disparar();
      lupa.parar();
      respostas['leite']!.complete('R-leite');
      await _assentar();
      expect(chegou, isEmpty);
    });

    test('parar antes de a pessoa parar de escrever: nada sai', () {
      lupa.escrever('leite', chaveDaPesquisa('leite'), aoChegar: (_) {});
      lupa.parar();
      agenda.disparar();
      expect(pedidos, isEmpty);
    });

    test('sem rede: avisa a falha da pesquisa mais recente', () async {
      Object? erro;
      lupa.escrever(
        'leite',
        chaveDaPesquisa('leite'),
        aoChegar: (_) {},
        aoFalhar: (e) => erro = e,
      );
      agenda.disparar();
      respostas['leite']!.completeError(TimeoutException('12 s'));
      await _assentar();
      expect(erro, isA<TimeoutException>());
      expect(memoria.ler(chaveDaPesquisa('leite')), isNull);
    });

    test(
      '"pesquisar" no teclado sai logo; dois toques fazem um pedido só',
      () async {
        final chegou = <String>[];
        final a = lupa.agora(
          'leite',
          chaveDaPesquisa('leite'),
          aoChegar: chegou.add,
        );
        final b = lupa.agora(
          'leite',
          chaveDaPesquisa('leite'),
          aoChegar: chegou.add,
        );
        expect(pedidos, ['leite']);
        respostas['leite']!.complete('R-leite');
        await a;
        await b;
        expect(chegou, ['R-leite']); // só a do último toque é mostrada
      },
    );

    test('depois de fechar o ecrã (dispose) não chama nada', () async {
      final chegou = <String>[];
      lupa.escrever('leite', chaveDaPesquisa('leite'), aoChegar: chegou.add);
      agenda.disparar();
      lupa.dispose();
      respostas['leite']!.complete('R-leite');
      await _assentar();
      expect(chegou, isEmpty);
    });
  });
}
