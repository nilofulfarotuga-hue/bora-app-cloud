import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../l10n/tr.dart';
import '../models/casa_models.dart';
import '../models/falha_de_acao.dart';

/// CASA (Casa & Manutenção) — store reativo do CLIENTE (31/10/2026).
///
/// Molde: CleaningStore / CarwashStore. Camada fina sobre as RPC do contrato
/// (`.claude/.ai/provas/casa-manutencao-2026-10-30/ESPEC.md`): preços, estados e
/// permissões vivem TODOS no servidor; aqui só se chama e se reage.
///
/// Nunca rebenta ao ler: `refreshSettings`, `carregarMeusPedidos` e
/// `refreshTracked` engolem o erro e deixam o último estado bom (a home e a
/// categoria nunca ficam presas — regra 1.27). As AÇÕES (criar, aceitar,
/// confirmar…) lançam, e o ecrã mostra [casaMensagemDeErro].
class CasaStore extends ChangeNotifier {
  CasaStore()
      : _semRede = false,
        _rpcDeTeste = null,
        _uidDeTeste = null;

  /// Store sem rede, só para testes de ecrã: começa já com dados e nenhuma
  /// leitura sai para o servidor.
  @visibleForTesting
  CasaStore.semRede({
    CasaConfig config = CasaConfig.vazia,
    List<CasaPedido> pedidos = const [],
    Map<String, List<CasaMensagem>> mensagens = const {},
  })  : _semRede = true,
        _rpcDeTeste = null,
        _uidDeTeste = null {
    _config = config;
    _configCarregada = true;
    _pedidos = pedidos;
    _pedidosCarregados = true;
    _mensagens.addAll(mensagens);
  }

  /// SÓ PARA TESTES: o "servidor" é uma função (sem Supabase, sem tempo real
  /// nem Storage). As ações correm de verdade contra um servidor falso — serve
  /// para provar o fluxo pedir → aceitar → … → confirmar sem rede.
  @visibleForTesting
  CasaStore.comServidor({
    required Future<dynamic> Function(String fn, Map<String, dynamic> params)
        rpc,
    CasaConfig config = CasaConfig.vazia,
    String uid = 'u-cliente-teste',
  })  : _semRede = false,
        _rpcDeTeste = rpc,
        _uidDeTeste = uid {
    _config = config;
    _configCarregada = true;
  }

  final bool _semRede;
  final Future<dynamic> Function(String fn, Map<String, dynamic> params)?
      _rpcDeTeste;
  final String? _uidDeTeste;

  /// Sem tempo real nem Storage (servidor falso dos testes).
  bool get _semCanais => _semRede || _rpcDeTeste != null;

  SupabaseClient get _sb => Supabase.instance.client;
  String? get _uid {
    if (_uidDeTeste != null) return _uidDeTeste;
    try {
      return _sb.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// Todas as funções do servidor passam por aqui (a de teste, se houver).
  Future<dynamic> _rpc(String fn, [Map<String, dynamic>? params]) {
    final f = _rpcDeTeste;
    if (f != null) return f(fn, params ?? const <String, dynamic>{});
    return _sb.rpc(fn, params: params);
  }

  static const _balde = 'casa-fotos';

  // ══════════════════════════════════════════════════════════════════════════
  // DEFINIÇÕES (casa_config)
  // ══════════════════════════════════════════════════════════════════════════

  CasaConfig _config = CasaConfig.vazia;
  CasaConfig get config => _config;

  /// A categoria aparece ao cliente (visivel = enabled, ou testador).
  bool get enabled => _config.visivel;

  bool _configCarregada = false;

  /// Já houve pelo menos uma leitura boa do casa_config.
  bool get configCarregada => _configCarregada;

  bool _configFalhou = false;

  /// A última leitura falhou (fica a config anterior, ou a vazia).
  bool get configFalhou => _configFalhou;

  /// Lê casa_config. Nunca rebenta: em erro fica a config anterior (ou
  /// [CasaConfig.vazia], que esconde a categoria).
  Future<void> refreshSettings() async {
    if (_semRede) return;
    try {
      final res = await _rpc('casa_config').timeout(kAcaoTimeout);
      _config = CasaConfig.fromJson(_asMap(res));
      _configCarregada = true;
      _configFalhou = false;
    } catch (e) {
      debugPrint('CasaStore.refreshSettings => $e');
      _configFalhou = true;
    }
    notifyListeners();
  }

  /// Serviço do catálogo pelo id (para mostrar as perguntas num pedido).
  CasaServico? servicoPorId(String? id) {
    if (id == null) return null;
    for (final s in _config.servicos) {
      if (s.id == id) return s;
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // OS MEUS PEDIDOS
  // ══════════════════════════════════════════════════════════════════════════

  List<CasaPedido> _pedidos = const [];

  /// Todos os meus pedidos (por resolver primeiro, depois o histórico).
  List<CasaPedido> get meusPedidos => _pedidos;

  /// Os que ainda não acabaram (para um selo na home, por exemplo).
  List<CasaPedido> get pedidosAtivos =>
      _pedidos.where((p) => !p.estado.terminal).toList();

  bool _pedidosCarregados = false;
  bool get pedidosCarregados => _pedidosCarregados;

  bool _pedidosFalharam = false;

  /// A última leitura de [carregarMeusPedidos] falhou (a lista é a anterior):
  /// o ecrã avisa em vez de dizer "ainda não tens pedidos".
  bool get pedidosFalharam => _pedidosFalharam;

  RealtimeChannel? _canalLista;

  /// casa_meus_pedidos. Nunca rebenta.
  Future<void> carregarMeusPedidos() async {
    if (_semRede) return;
    if (_uid == null) return;
    try {
      final res = await _rpc('casa_meus_pedidos').timeout(kAcaoTimeout);
      final lista = _lista(res).map(CasaPedido.fromJson).toList();
      _pedidos = _ordenar(lista);
      _pedidosCarregados = true;
      _pedidosFalharam = false;
      // casa_meus_pedidos devolve o pedido inteiro (o mesmo JSON do
      // casa_pedido): o aberto passa a ser o da lista, comparado por ID.
      final aberto = _aberto;
      if (aberto != null) {
        for (final p in _pedidos) {
          if (p.id == aberto.id) {
            _aberto = p;
            break;
          }
        }
      }
      _ouvirMeusPedidos();
    } catch (e) {
      debugPrint('CasaStore.carregarMeusPedidos => $e');
      _pedidosFalharam = true;
    }
    notifyListeners();
  }

  /// Por resolver primeiro; dentro de cada grupo, o mais recente primeiro.
  static List<CasaPedido> _ordenar(List<CasaPedido> lista) {
    final copia = [...lista];
    copia.sort((a, b) {
      final ta = a.estado.terminal ? 1 : 0;
      final tb = b.estado.terminal ? 1 : 0;
      if (ta != tb) return ta - tb;
      final da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });
    return copia;
  }

  /// Tempo real da lista: qualquer mudança num pedido meu recarrega a lista
  /// (e o pedido aberto, se for esse).
  void _ouvirMeusPedidos() {
    if (_semCanais || _canalLista != null) return;
    final uid = _uid;
    if (uid == null) return;
    try {
      _canalLista = _sb.channel('casa_meus_pedidos_$uid')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'casa_pedidos',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'client_user_id',
            value: uid,
          ),
          callback: (payload) {
            final id = payload.newRecord['id']?.toString() ??
                payload.oldRecord['id']?.toString();
            _agendarRecarga(lista: true, aberto: id != null && id == _aberto?.id);
          },
        )
        ..subscribe();
    } catch (e) {
      debugPrint('CasaStore._ouvirMeusPedidos => $e');
      _canalLista = null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PEDIDO ABERTO (acompanhamento, com tempo real)
  // ══════════════════════════════════════════════════════════════════════════

  CasaPedido? _aberto;

  /// O pedido aberto no ecrã de acompanhamento (atualizado em tempo real).
  CasaPedido? get aberto => _aberto;

  RealtimeChannel? _canalAberto;
  String? _canalAbertoId;
  Timer? _recarga;
  bool _recarregarLista = false;
  bool _recarregarAberto = false;

  /// Abre um pedido no acompanhamento e liga o tempo real dele (o pedido, os
  /// orçamentos que chegam e os pedidos de valor extra).
  void abrirPedido(CasaPedido pedido) {
    _aberto = pedido;
    _ouvirPedido(pedido.id);
    notifyListeners();
  }

  /// Fecha o acompanhamento (ao sair do ecrã). Calado de propósito: é chamado
  /// no `dispose` do ecrã, com a árvore trancada — avisar os ouvintes aí
  /// rebentava ("markNeedsBuild called when widget tree was locked"). Nenhum
  /// outro ecrã depende do [aberto].
  void fecharPedido([String? id]) {
    if (id != null && _aberto?.id != id) return;
    _largarCanalAberto();
    _aberto = null;
  }

  void _ouvirPedido(String id) {
    if (_semCanais) return;
    if (_canalAbertoId == id && _canalAberto != null) return;
    _largarCanalAberto();
    try {
      PostgresChangeFilter doPedido(String coluna) => PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: coluna,
            value: id,
          );
      void reage(PostgresChangePayload _) => _agendarRecarga(aberto: true);
      _canalAberto = _sb.channel('casa_pedido_$id')
        ..onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'casa_pedidos',
          filter: doPedido('id'),
          callback: reage,
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'casa_orcamentos',
          filter: doPedido('pedido_id'),
          callback: reage,
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'casa_extras',
          filter: doPedido('pedido_id'),
          callback: reage,
        )
        ..subscribe();
      _canalAbertoId = id;
    } catch (e) {
      debugPrint('CasaStore._ouvirPedido => $e');
      _canalAberto = null;
      _canalAbertoId = null;
    }
  }

  /// Junta várias mudanças seguidas (orçamento + pedido) numa só leitura.
  void _agendarRecarga({bool lista = false, bool aberto = false}) {
    _recarregarLista = _recarregarLista || lista;
    _recarregarAberto = _recarregarAberto || aberto;
    _recarga?.cancel();
    _recarga = Timer(const Duration(milliseconds: 400), () async {
      final l = _recarregarLista;
      final a = _recarregarAberto;
      _recarregarLista = false;
      _recarregarAberto = false;
      if (a) await _recarregarPedidoAberto();
      if (l) await carregarMeusPedidos();
    });
  }

  Future<void> _recarregarPedidoAberto() async {
    final id = _aberto?.id;
    if (id == null) return;
    final novo = await pedido(id);
    if (novo != null) _aplicar(novo);
  }

  /// Espelho do servidor (ao voltar ao primeiro plano, ou puxar para baixo):
  /// relê o pedido aberto e os meus pedidos. O tempo real pode ter perdido
  /// eventos com a app em fundo — o ecrã nunca assume o estado local.
  Future<void> refreshTracked() async {
    if (_semRede) return;
    await _recarregarPedidoAberto();
    await carregarMeusPedidos();
  }

  /// casa_pedido. null em erro (o ecrã fica com o que tinha).
  Future<CasaPedido?> pedido(String id) async {
    if (_semRede) return null;
    try {
      final res =
          await _rpc('casa_pedido', {'p_pedido_id': id}).timeout(kAcaoTimeout);
      if (res == null) return null;
      return CasaPedido.fromJson(_asMap(res));
    } catch (e) {
      debugPrint('CasaStore.pedido($id) => $e');
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CRIAR PEDIDO + FOTOS
  // ══════════════════════════════════════════════════════════════════════════

  /// Cria o pedido (preço 100% no servidor) e começa a segui-lo.
  ///
  /// [chave] — idempotência: o assistente cria UMA chave e manda sempre a
  /// mesma, por isso um segundo toque (ou a repetição do tecto de tempo)
  /// devolve o pedido que já existe em vez de criar outro. Sem chave, nasce
  /// uma aqui (fora do fecho, como na limpeza).
  Future<CasaPedido> criarPedido({
    required CasaServico servico,
    required double quantidade,
    required String descricao,
    required Map<String, dynamic> respostas,
    required String rua,
    required String cidade,
    required String codigoPostal,
    double? lat,
    double? lng,
    required DateTime scheduledAt,
    required String metodoPagamento,
    String? chave,
  }) async {
    _semRedeFalha();
    final chaveDoPedido = chave ?? const Uuid().v4();
    final params = <String, dynamic>{
      'p_servico_id': servico.id,
      'p_quantidade': quantidade,
      'p_descricao': descricao,
      'p_respostas': respostas,
      'p_address_street': rua,
      'p_address_city': cidade,
      'p_address_postal': codigoPostal,
      'p_lat': lat,
      'p_lng': lng,
      'p_scheduled_at': scheduledAt.toUtc().toIso8601String(),
      // No orçamento o servidor ignora; manda-se 'cash' para não ir nulo.
      'p_payment_method': metodoPagamento,
      'p_idempotency_key': chaveDoPedido,
    };
    dynamic res;
    try {
      res = await criarComTectoSeguro(
        () => _rpc('casa_criar_pedido', params),
        trabalho: TrabalhoEmCurso.casa,
      );
    } catch (e) {
      // A mesma chave a bater no índice único = o primeiro já ficou criado.
      final t = e.toString();
      if (t.contains('ux_casa_pedidos_idem') || t.contains('23505')) {
        await carregarMeusPedidos();
        throw const JaFicouCriado(TrabalhoEmCurso.casa);
      }
      rethrow;
    }
    final p = CasaPedido.fromJson(_asMap(res));
    _aplicar(p, juntarNaLista: true);
    abrirPedido(p);
    unawaited(carregarMeusPedidos());
    return p;
  }

  /// Sobe uma foto do problema para o balde privado `casa-fotos`
  /// (`<uid>/<pedido_id>/problema_<ms>.<ext>`, com a extensão real — C14) e
  /// regista-a (casa_adicionar_foto). Lança em erro real; o assistente segue
  /// na mesma (a foto é um extra).
  Future<String> adicionarFoto(
    String pedidoId,
    Uint8List bytes, {
    String extensao = 'jpg',
  }) async {
    _semRedeFalha();
    final uid = _uid;
    if (uid == null) throw StateError('not_authenticated');
    if (bytes.isEmpty) throw StateError('empty_file');
    final mime = casaExtensaoFoto(extensao).mime;
    final caminho = casaCaminhoFotoProblema(
        uid, pedidoId, extensao, DateTime.now().millisecondsSinceEpoch);
    // Sem upsert: o caminho leva a hora, nunca há conflito. O servidor falso
    // dos testes não tem Storage: só regista a foto.
    if (_rpcDeTeste == null) {
      await _sb.storage
          .from(_balde)
          .uploadBinary(caminho, bytes,
              fileOptions: FileOptions(contentType: mime))
          .timeout(const Duration(seconds: 40));
    }
    await _rpc('casa_adicionar_foto', {
      'p_pedido_id': pedidoId,
      'p_tipo': 'problema',
      'p_storage_path': caminho,
    }).timeout(kAcaoTimeout);
    return caminho;
  }

  final Map<String, ({String url, DateTime ate})> _urls = {};

  /// URL assinado (1 h) de uma foto do balde privado. null em erro.
  Future<String?> urlFoto(String storagePath) async {
    if (_semCanais || storagePath.isEmpty) return null;
    final guardado = _urls[storagePath];
    if (guardado != null && DateTime.now().isBefore(guardado.ate)) {
      return guardado.url;
    }
    try {
      final url = await _sb.storage
          .from(_balde)
          .createSignedUrl(storagePath, 3600)
          .timeout(kAcaoTimeout);
      _urls[storagePath] = (
        url: url,
        ate: DateTime.now().add(const Duration(minutes: 50)),
      );
      return url;
    } catch (e) {
      debugPrint('CasaStore.urlFoto($storagePath) => $e');
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // AÇÕES DO CLIENTE (todas lançam em erro; o ecrã mostra casaMensagemDeErro)
  // ══════════════════════════════════════════════════════════════════════════

  Future<CasaPedido> aceitarOrcamento(String orcamentoId, String metodo) =>
      _acaoQueDevolvePedido('casa_aceitar_orcamento', {
        'p_orcamento_id': orcamentoId,
        'p_payment_method': metodo,
      });

  Future<CasaPedido> responderExtra(String extraId, bool aceitar) =>
      _acaoQueDevolvePedido('casa_responder_extra', {
        'p_extra_id': extraId,
        'p_aceitar': aceitar,
      });

  Future<CasaPedido> confirmarConclusao(String pedidoId) =>
      _acaoQueDevolvePedido(
          'casa_confirmar_conclusao', {'p_pedido_id': pedidoId});

  Future<CasaPedido> pedirRefazer(String pedidoId, String motivo) =>
      _acaoQueDevolvePedido('casa_pedir_refazer', {
        'p_pedido_id': pedidoId,
        'p_motivo': motivo,
      });

  /// Avalia o profissional (1–5). Só depois de confirmado e pago.
  Future<void> avaliar(String pedidoId, int nota, {String comentario = ''}) async {
    _semRedeFalha();
    await _rpc('casa_avaliar', {
      'p_pedido_id': pedidoId,
      'p_nota': nota,
      'p_comentario': comentario,
    }).timeout(kAcaoTimeout);
    await _recarregarDepoisDeAcao(pedidoId);
  }

  /// Quanto custa cancelar agora (o valor final é sempre do servidor).
  Future<CasaSimulacaoCancelamento> simularCancelamento(String pedidoId) async {
    _semRedeFalha();
    final res = await _rpc('casa_cancelar_simulacao',
        {'p_pedido_id': pedidoId}).timeout(kAcaoTimeout);
    return CasaSimulacaoCancelamento.fromJson(_asMap(res));
  }

  /// Cancela. Devolve a taxa cobrada (cêntimos).
  Future<int> cancelar(String pedidoId, {String motivo = ''}) async {
    _semRedeFalha();
    final res = await _rpc('casa_cancelar', {
      'p_pedido_id': pedidoId,
      'p_motivo': motivo,
    }).timeout(kAcaoTimeout);
    final m = _asMap(res);
    await _recarregarDepoisDeAcao(pedidoId);
    final v = m['cancel_fee_cents'];
    return v is num ? v.round() : int.tryParse('${v ?? 0}') ?? 0;
  }

  Future<CasaPedido> _acaoQueDevolvePedido(
      String rpc, Map<String, dynamic> params) async {
    _semRedeFalha();
    final res = await _rpc(rpc, params).timeout(kAcaoTimeout);
    final p = CasaPedido.fromJson(_asMap(res));
    _aplicar(p);
    return p;
  }

  Future<void> _recarregarDepoisDeAcao(String pedidoId) async {
    final p = await pedido(pedidoId);
    if (p != null) _aplicar(p);
    unawaited(carregarMeusPedidos());
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MENSAGENS (só com pode_contactar — o servidor recusa antes disso)
  // ══════════════════════════════════════════════════════════════════════════

  final Map<String, List<CasaMensagem>> _mensagens = {};
  final Map<String, RealtimeChannel> _canaisMensagens = {};

  List<CasaMensagem> mensagensDe(String pedidoId) =>
      _mensagens[pedidoId] ?? const [];

  bool _mensagensFalharam = false;
  bool get mensagensFalharam => _mensagensFalharam;

  /// casa_mensagens. Nunca rebenta.
  Future<void> carregarMensagens(String pedidoId) async {
    if (_semRede) return;
    try {
      final res = await _rpc('casa_mensagens',
          {'p_pedido_id': pedidoId}).timeout(kAcaoTimeout);
      final lista = _lista(res).map(CasaMensagem.fromJson).toList()
        ..sort((a, b) => (a.createdAt ?? DateTime(0))
            .compareTo(b.createdAt ?? DateTime(0)));
      _mensagens[pedidoId] = lista;
      _mensagensFalharam = false;
    } catch (e) {
      debugPrint('CasaStore.carregarMensagens => $e');
      _mensagensFalharam = true;
    }
    notifyListeners();
  }

  /// Liga o chat: lê as mensagens e ouve as novas em tempo real.
  void ouvirMensagens(String pedidoId) {
    unawaited(carregarMensagens(pedidoId));
    if (_semCanais || _canaisMensagens.containsKey(pedidoId)) return;
    try {
      _canaisMensagens[pedidoId] = _sb.channel('casa_mensagens_$pedidoId')
        ..onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'casa_mensagens',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'pedido_id',
            value: pedidoId,
          ),
          callback: (payload) {
            final m = CasaMensagem.fromJson(payload.newRecord);
            final atual = _mensagens[pedidoId] ?? const <CasaMensagem>[];
            if (atual.any((x) => x.id == m.id)) return;
            _mensagens[pedidoId] = [...atual, m];
            notifyListeners();
          },
        )
        ..subscribe();
    } catch (e) {
      debugPrint('CasaStore.ouvirMensagens => $e');
      _canaisMensagens.remove(pedidoId);
    }
  }

  /// Desliga o chat (ao sair do ecrã). Usa o store guardado no initState.
  void pararMensagens(String pedidoId) {
    final canal = _canaisMensagens.remove(pedidoId);
    if (canal != null) {
      try {
        _sb.removeChannel(canal);
      } catch (_) {}
    }
  }

  /// casa_enviar_mensagem. Lança em erro.
  Future<void> enviarMensagem(String pedidoId, String texto) async {
    _semRedeFalha();
    final limpo = texto.trim();
    if (limpo.isEmpty) return;
    await _rpc('casa_enviar_mensagem', {
      'p_pedido_id': pedidoId,
      'p_texto': limpo,
    }).timeout(kAcaoTimeout);
    await carregarMensagens(pedidoId);
  }

  // ── infra ────────────────────────────────────────────────────────────────

  /// Troca o pedido (por ID — o tempo real substitui objetos, nunca comparar
  /// por referência) no aberto e na lista.
  void _aplicar(CasaPedido p, {bool juntarNaLista = false}) {
    if (_aberto?.id == p.id) _aberto = p;
    final achou = _pedidos.any((x) => x.id == p.id);
    final nova = [for (final x in _pedidos) x.id == p.id ? p : x];
    if (!achou && juntarNaLista) nova.insert(0, p);
    _pedidos = _ordenar(nova);
    notifyListeners();
  }

  void _semRedeFalha() {
    if (_semRede) throw StateError('sem_rede');
  }

  static Map<String, dynamic> _asMap(dynamic res) {
    if (res is Map) return Map<String, dynamic>.from(res);
    if (res is List && res.isNotEmpty && res.first is Map) {
      return Map<String, dynamic>.from(res.first as Map);
    }
    throw StateError('Resposta inesperada da RPC: $res');
  }

  static List<Map<String, dynamic>> _lista(dynamic res) {
    if (res is List) {
      return res
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  void _largarCanalAberto() {
    final canal = _canalAberto;
    _canalAberto = null;
    _canalAbertoId = null;
    if (canal != null) {
      try {
        _sb.removeChannel(canal);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _recarga?.cancel();
    _largarCanalAberto();
    final lista = _canalLista;
    _canalLista = null;
    if (lista != null) {
      try {
        _sb.removeChannel(lista);
      } catch (_) {}
    }
    for (final c in _canaisMensagens.values) {
      try {
        _sb.removeChannel(c);
      } catch (_) {}
    }
    _canaisMensagens.clear();
    super.dispose();
  }
}

/// Uma mensagem do chat do pedido (casa_mensagens).
class CasaMensagem {
  const CasaMensagem({
    required this.id,
    required this.senderRole,
    required this.texto,
    this.createdAt,
  });

  final String id;

  /// client | handyman | admin
  final String senderRole;
  final String texto;
  final DateTime? createdAt;

  factory CasaMensagem.fromJson(Map<String, dynamic> m) => CasaMensagem(
        id: '${m['id'] ?? ''}',
        senderRole: '${m['sender_role'] ?? ''}',
        texto: '${m['message'] ?? m['texto'] ?? ''}',
        createdAt: m['created_at'] == null
            ? null
            : DateTime.tryParse('${m['created_at']}')?.toLocal(),
      );
}

/// Resposta de casa_cancelar_simulacao.
class CasaSimulacaoCancelamento {
  const CasaSimulacaoCancelamento({
    required this.taxaCents,
    required this.escalao,
  });

  final int taxaCents;

  /// gratis | metade | total
  final String escalao;

  bool get gratis => escalao == 'gratis' || taxaCents <= 0;

  factory CasaSimulacaoCancelamento.fromJson(Map<String, dynamic> m) {
    final v = m['cancel_fee_cents'];
    return CasaSimulacaoCancelamento(
      taxaCents: v is num ? v.round() : int.tryParse('${v ?? 0}') ?? 0,
      escalao: '${m['escalao'] ?? 'gratis'}',
    );
  }
}

/// Frase PT-PT curta para uma falha de ação da Casa.
///
/// Primeiro os códigos do contrato (RAISE EXCEPTION em minúsculas, ESPEC.md);
/// o resto cai na tradução geral da app ([mensagemDeFalhaDeAcao]).
String casaMensagemDeErro(Object erro, {int? maxCashCents}) {
  if (erro is JaFicouCriado) return erro.mensagem;
  final t = erro.toString();
  bool tem(String c) => t.contains(c);

  if (tem('casa_desligada')) {
    return 'A Casa está temporariamente indisponível. Tenta mais tarde.'.tr;
  }
  if (tem('valores_por_autorizar')) {
    return 'Este serviço ainda não está disponível para marcar. Tenta mais tarde ou pede um orçamento.'.tr;
  }
  if (tem('dinheiro_acima_do_limite')) {
    if (maxCashCents != null) {
      return 'Em dinheiro só até {0}. Acima disso, só cartão ou MB Way.'.trArgs([casaEuro(maxCashCents)]);
    }
    return 'Este valor passa o limite para pagar em dinheiro.'.tr;
  }
  if (tem('pagamento_cartao_indisponivel')) {
    return 'Cartão e MB Way chegam brevemente. Por agora, paga em dinheiro.'.tr;
  }
  if (tem('antecedencia_minima')) {
    return 'Escolhe uma hora com mais antecedência.'.tr;
  }
  if (tem('morada_em_falta')) {
    return 'Falta a morada. Escreve a rua e a localidade.'.tr;
  }
  if (tem('limite_fotos')) {
    return 'Já chegaste ao limite de fotos deste pedido.'.tr;
  }
  if (tem('orcamentos_completos')) {
    return 'Este pedido já recebeu todos os orçamentos.'.tr;
  }
  if (tem('foto_depois_em_falta')) {
    return 'Falta a foto do trabalho feito.'.tr;
  }
  if (tem('nao_e_profissional')) {
    return 'Esta conta não é de profissional.'.tr;
  }
  // Códigos que o servidor (casa_03_cliente.sql) também levanta, além dos do
  // ESPEC.
  if (tem('servico_indisponivel')) {
    return 'Este serviço já não está disponível. Escolhe outro.'.tr;
  }
  if (tem('quantidade_invalida')) {
    return 'Escolhe uma quantidade válida.'.tr;
  }
  if (tem('metodo_invalido')) {
    return 'Escolhe como queres pagar.'.tr;
  }
  if (tem('orcamento_expirado')) {
    return 'Este orçamento já não é válido. Escolhe outro ou espera por novos.'.tr;
  }
  if (tem('profissional_ocupado')) {
    return 'Este profissional já não está livre nessa hora. Escolhe outro orçamento.'.tr;
  }
  if (tem('garantia_terminou')) {
    return 'A garantia deste trabalho já terminou.'.tr;
  }
  if (tem('ja_avaliado')) {
    return 'Já avaliaste este trabalho.'.tr;
  }
  if (tem('nota_invalida')) {
    return 'Escolhe de 1 a 5 estrelas.'.tr;
  }
  if (tem('contacto_fechado')) {
    return 'As mensagens só abrem depois de o trabalho estar aceite e pago.'.tr;
  }
  if (tem('mensagem_invalida')) {
    return 'A mensagem está vazia ou é demasiado comprida.'.tr;
  }
  if (tem('tipo_invalido') || tem('caminho_invalido')) {
    return 'Não consegui guardar a foto. Tenta outra vez.'.tr;
  }
  if (tem('sem_permissao')) {
    return 'Este pedido não é teu ou já não podes mexer nele.'.tr;
  }
  if (tem('estado_invalido')) {
    return 'O pedido já mudou entretanto. Atualiza para veres como está agora.'.tr;
  }
  return mensagemDeFalhaDeAcao(erro, trabalho: TrabalhoEmCurso.casa);
}
