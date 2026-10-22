import 'package:bora_app/utils/home_destino.dart' show categoriasDestino;
import 'package:bora_app/utils/pesquisa_atalhos.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pesquisa única (15/10/2026): a lupa leva também ao motorista, à limpeza e
/// aos serviços de beleza, e não só a lojas e produtos.
void main() {
  test('táxi, boleia e uber levam ao Bora Motorista', () {
    expect(atalhosDaPesquisa('Táxi'), contains('motorista'));
    expect(atalhosDaPesquisa('preciso de boleia'), contains('motorista'));
    expect(atalhosDaPesquisa('uber'), contains('motorista'));
  });

  test('limpeza e empregada levam à Limpeza', () {
    expect(atalhosDaPesquisa('limpeza'), ['limpeza']);
    expect(atalhosDaPesquisa('Empregada'), contains('limpeza'));
  });

  test('barbearia, unhas e o começo de palavra levam à Beleza', () {
    expect(atalhosDaPesquisa('barbearia'), contains('servicos'));
    expect(atalhosDaPesquisa('unhas de gel'), contains('servicos'));
    expect(atalhosDaPesquisa('barb'), contains('servicos'));
  });

  test('farmácia e supermercado levam à secção certa', () {
    expect(atalhosDaPesquisa('farmácia'), contains('farmacia'));
    expect(atalhosDaPesquisa('supermercado'), contains('supermercados'));
  });

  test('pratos e lojas comuns não inventam atalhos', () {
    expect(atalhosDaPesquisa('pizza'), isEmpty);
    expect(atalhosDaPesquisa('sushi'), isEmpty);
    expect(atalhosDaPesquisa('açaí'), isEmpty);
  });

  test('menos de 2 letras não procura nada', () {
    expect(atalhosDaPesquisa(''), isEmpty);
    expect(atalhosDaPesquisa('t'), isEmpty);
  });

  test('todas as chaves existem nas categorias da home', () {
    for (final q in [
      'taxi', 'limpeza', 'barbearia', 'supermercado', 'farmacia',
      'restaurante', 'festa', 'sobremesa', 'loja',
    ]) {
      for (final k in atalhosDaPesquisa(q)) {
        expect(categoriasDestino.containsKey(k), isTrue, reason: '$q → $k');
      }
    }
  });
}
