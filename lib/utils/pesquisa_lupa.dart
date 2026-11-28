// Lupa leve (17/11/2026, missão servidor-busca-leve-2026-11-17).
//
// Às 06:32 e às 07:12 de 17/11 três telemóveis de teste da Google puseram o
// servidor a 57-61%: cada letra escrita na lupa era uma pesquisa (~730 ms de
// CPU cada). Aqui fica o que as três lupas da app passam a fazer igual:
//  * só pesquisa quando a pessoa pára de escrever [kEsperaLupa] (400 ms);
//  * produtos só a partir de [kLetrasProdutos] letras (com 2 o servidor só
//    devolve as secções; a lupa do menu nem lhe pergunta);
//  * a resposta de uma pesquisa antiga que chega depois da nova é deitada fora;
//  * a mesma pesquisa (texto + loja) feita há menos de [kMemoriaLupa] vem da
//    memória do telemóvel, sem ir ao servidor; e duas iguais ao mesmo tempo
//    (toque duplo no "pesquisar") fazem um pedido só.
library;

import 'dart:async';
import 'dart:collection';

import 'cozinhas.dart' show normalizarTexto;

/// Quanto tempo a pessoa tem de parar de escrever para a pesquisa sair.
const Duration kEsperaLupa = Duration(milliseconds: 400);

/// Quanto tempo uma resposta fica na memória do telemóvel.
const Duration kMemoriaLupa = Duration(minutes: 5);

/// A partir de quantas letras se pesquisam produtos (igual ao servidor).
const int kLetrasProdutos = 3;

final RegExp _letraOuAlgarismo = RegExp(r'[a-z0-9]');

/// Letras e algarismos que o servidor conta: o mesmo que
/// `length(replace(bora_normalize(q), ' ', ''))` (sem acentos, sem espaços nem
/// pontuação). "pão" = 3, "p ã" = 2, "7up" = 3.
int letrasDaPesquisa(String texto) =>
    _letraOuAlgarismo.allMatches(normalizarTexto(texto)).length;

/// Chave da memória: a loja (ou `*` na lupa de todas as lojas) e o texto como
/// o servidor o lê (minúsculas, sem acentos, espaços normalizados).
String chaveDaPesquisa(String texto, {String? loja}) =>
    '${loja ?? '*'}|${normalizarTexto(texto)}';

class _Guardado<T> {
  _Guardado(this.quando, this.valor);
  final DateTime quando;
  final T valor;
}

/// Memória curta das respostas da lupa, por [chaveDaPesquisa].
class MemoriaPesquisa<T> {
  MemoriaPesquisa({
    this.validade = kMemoriaLupa,
    this.maximo = 40,
    DateTime Function()? relogio,
  }) : _relogio = relogio ?? DateTime.now;

  final Duration validade;
  final int maximo;
  final DateTime Function() _relogio;
  final LinkedHashMap<String, _Guardado<T>> _itens =
      LinkedHashMap<String, _Guardado<T>>();
  final Map<String, Future<T>> _emVoo = <String, Future<T>>{};

  int get tamanho => _itens.length;

  /// A resposta guardada para [chave], se ainda estiver dentro da validade.
  T? ler(String chave) {
    final g = _itens[chave];
    if (g == null) return null;
    if (_relogio().difference(g.quando) >= validade) {
      _itens.remove(chave);
      return null;
    }
    return g.valor;
  }

  void guardar(String chave, T valor) {
    _itens.remove(chave); // volta ao fim: é a mais recente
    _itens[chave] = _Guardado<T>(_relogio(), valor);
    while (_itens.length > maximo) {
      _itens.remove(_itens.keys.first);
    }
  }

  void limpar() {
    _itens.clear();
    _emVoo.clear();
  }

  /// Da memória se houver; senão junta-se ao pedido igual que já está a
  /// caminho; senão faz [buscar] e guarda a resposta. Um erro não se guarda.
  Future<T> obter(String chave, Future<T> Function() buscar) {
    final g = ler(chave);
    if (g != null) return Future<T>.value(g);
    final emVoo = _emVoo[chave];
    if (emVoo != null) return emVoo;
    final pedido = buscar().then((valor) {
      guardar(chave, valor);
      return valor;
    });
    _emVoo[chave] = pedido;
    // tira-se do "a caminho" quando acabar, dê certo ou não (o erro chega a
    // quem esperava pelo pedido; aqui só não pode ficar por tratar)
    pedido.then((_) {}, onError: (Object _) {}).whenComplete(() {
      if (identical(_emVoo[chave], pedido)) _emVoo.remove(chave);
    });
    return pedido;
  }
}

/// Agenda a pesquisa para quando a pessoa pára de escrever ([espera]), passa
/// pela [memoria] e só entrega a resposta da ÚLTIMA pesquisa pedida.
class LupaAgendada<T> {
  LupaAgendada({
    required this.buscar,
    required this.memoria,
    this.espera = kEsperaLupa,
    Timer Function(Duration, void Function())? agendar,
  }) : _agendar = agendar ?? ((d, f) => Timer(d, f));

  /// O pedido ao servidor para um texto.
  final Future<T> Function(String texto) buscar;
  final MemoriaPesquisa<T> memoria;
  final Duration espera;
  final Timer Function(Duration, void Function()) _agendar;

  Timer? _temporizador;
  int _pedido = 0;
  bool _fechada = false;

  /// A pessoa escreveu [texto]: cancela o que estava agendado e agenda este.
  /// [aoComecar] corre quando o pedido sai mesmo para o servidor (não quando
  /// vem da memória); [aoChegar] / [aoFalhar] só para a pesquisa mais recente.
  void escrever(
    String texto,
    String chave, {
    required void Function(T resultado) aoChegar,
    void Function(Object erro)? aoFalhar,
    void Function()? aoComecar,
  }) {
    _temporizador?.cancel();
    final n = ++_pedido;
    _temporizador = _agendar(
      espera,
      () => _correr(n, texto, chave, aoChegar, aoFalhar, aoComecar),
    );
  }

  /// Pesquisar já (botão "pesquisar" do teclado), sem esperar.
  Future<void> agora(
    String texto,
    String chave, {
    required void Function(T resultado) aoChegar,
    void Function(Object erro)? aoFalhar,
    void Function()? aoComecar,
  }) {
    _temporizador?.cancel();
    final n = ++_pedido;
    return _correr(n, texto, chave, aoChegar, aoFalhar, aoComecar);
  }

  /// O texto ficou curto ou foi apagado: nada agendado e nenhuma resposta a
  /// caminho serve.
  void parar() {
    _temporizador?.cancel();
    _temporizador = null;
    _pedido++;
  }

  void dispose() {
    _fechada = true;
    _temporizador?.cancel();
  }

  Future<void> _correr(
    int n,
    String texto,
    String chave,
    void Function(T resultado) aoChegar,
    void Function(Object erro)? aoFalhar,
    void Function()? aoComecar,
  ) async {
    if (_fechada || n != _pedido) return;
    final guardado = memoria.ler(chave);
    if (guardado != null) {
      aoChegar(guardado);
      return;
    }
    aoComecar?.call();
    try {
      final r = await memoria.obter(chave, () => buscar(texto));
      if (_fechada || n != _pedido) return; // chegou tarde: há uma mais nova
      aoChegar(r);
    } catch (e) {
      if (_fechada || n != _pedido) return;
      aoFalhar?.call(e);
    }
  }
}
