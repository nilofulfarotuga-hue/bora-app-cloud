// CASA (missão casa-manutencao-2026-10-30): a pesquisa e as faixas da home
// levam à Casa e manutenção; quem escreve "torneira" ou "montar móveis" deixa
// de ver "não encontrámos".
import 'package:bora_app/screens/client/casa/casa_categoria_screen.dart';
import 'package:bora_app/utils/home_destino.dart';
import 'package:bora_app/utils/pesquisa_atalhos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a Casa é uma categoria que as faixas e a pesquisa podem abrir', () {
    expect(categoriasDestino['casa'], 'Casa');
    expect(ecraDaCategoriaParaTeste('casa'), isA<CasaCategoriaScreen>());
    expect(ecraDaCategoriaParaTeste('Casa'), isA<CasaCategoriaScreen>(),
        reason: 'a chave normaliza maiúsculas');
  });

  test('torneira, autoclismo e sifão levam à Casa', () {
    expect(atalhosDaPesquisa('torneira'), contains('casa'));
    expect(atalhosDaPesquisa('Autoclismo a pingar'), contains('casa'));
    expect(atalhosDaPesquisa('sifão'), contains('casa'));
  });

  test('montar móveis do IKEA e pendurar a televisão levam à Casa', () {
    expect(atalhosDaPesquisa('montagem de móveis'), contains('casa'));
    expect(atalhosDaPesquisa('ikea'), contains('casa'));
    expect(atalhosDaPesquisa('pendurar televisão'), contains('casa'));
    expect(atalhosDaPesquisa('quadros'), contains('casa'));
  });

  test('faz tudo e marido de aluguer (frases) levam à Casa', () {
    expect(atalhosDaPesquisa('preciso de um faz tudo'), contains('casa'));
    expect(atalhosDaPesquisa('marido de aluguer'), contains('casa'));
  });

  test('jardim, relva e mudanças com carrinha levam à Casa', () {
    expect(atalhosDaPesquisa('cortar a relva'), contains('casa'));
    expect(atalhosDaPesquisa('jardinagem'), contains('casa'));
    expect(atalhosDaPesquisa('mudanças'), contains('casa'));
    expect(atalhosDaPesquisa('carrinha'), contains('casa'));
  });

  test('o começo de uma palavra (3+ letras) também chega', () {
    expect(atalhosDaPesquisa('torn'), contains('casa'));
    expect(atalhosDaPesquisa('jard'), contains('casa'));
  });

  test('a Casa não rouba as pesquisas dos outros', () {
    expect(atalhosDaPesquisa('limpeza'), ['limpeza']);
    expect(atalhosDaPesquisa('pizza'), isEmpty);
    expect(atalhosDaPesquisa('sushi'), isEmpty);
    expect(atalhosDaPesquisa('Táxi'), isNot(contains('casa')));
  });

  test('todas as chaves da Casa existem nas categorias da home', () {
    for (final q in ['torneira', 'ikea', 'faz tudo', 'jardim', 'casa']) {
      for (final k in atalhosDaPesquisa(q)) {
        expect(categoriasDestino.containsKey(k), isTrue, reason: '$q → $k');
      }
    }
  });
}
