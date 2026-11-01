import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/tr.dart';
import '../models/casa_models.dart';
import '../models/falha_de_acao.dart';
import '../services/driver_foto_upload.dart' show prepararFotoParaEnvio;
import '../services/incoming_job_alert.dart';
import '../services/oferta_trabalho_aviso.dart';

/// CASA E MANUTENÇÃO — store do PROFISSIONAL (papel técnico `handyman`).
///
/// Molde do `WasherStore` / `CleanerStore`: a API pública que o `main.dart` e o
/// `TrabalhoOfertaOverlayHost` usam (loadProfile, profile, isApproved,
/// loadOffers, ofertasVivas, accept, reject, reset) é a mesma. Tudo passa por
/// RPC do contrato (`casa_*`, ESPEC da missão casa-manutencao-2026-10-30): o
/// servidor é que valida estados, fotos, valores e quem pode ver o quê.
///
/// A identidade é o `auth.uid()`: `casa_meu_perfil()` resolve o profissional
/// pelo `user_id` no servidor (lição do Valdemir, 16/08).
///
/// Ofertas: a RLS de `casa_pedidos` só deixa ver o pedido a quem já está
/// atribuído, por isso o tempo real NÃO traz ofertas novas. Chegam pelo push
/// `casa_offer` (que pede releitura) e por uma releitura periódica enquanto o
/// profissional estiver aprovado: a cada 10 s enquanto há ofertas por
/// responder, a cada 30 s sem nenhuma ([casaIntervaloSondagem], C5 da revisão
/// de 01/11). O tempo real de `casa_pedidos` serve para os trabalhos já
/// aceites.
class HandymanStore extends ChangeNotifier {
  HandymanStore()
      : _rpcDeTeste = null,
        _uidDeTeste = null;

  /// SÓ PARA TESTES: o "servidor" é uma função (sem Supabase, sem tempo real
  /// nem Storage). Serve para provar o fluxo inteiro com um servidor falso.
  @visibleForTesting
  HandymanStore.comServidor({
    required Future<dynamic> Function(String fn, Map<String, dynamic> params)
        rpc,
    String uid = 'u-profissional-teste',
  })  : _rpcDeTeste = rpc,
        _uidDeTeste = uid;

  final Future<dynamic> Function(String fn, Map<String, dynamic> params)?
      _rpcDeTeste;
  final String? _uidDeTeste;
  bool get _deTeste => _rpcDeTeste != null;

  SupabaseClient get _sb => Supabase.instance.client;
  String? get _uid => _uidDeTeste ?? _sb.auth.currentUser?.id;

  /// Todas as funções do servidor passam por aqui (a de teste, se houver).
  Future<dynamic> _rpc(String fn, [Map<String, dynamic>? params]) {
    final f = _rpcDeTeste;
    if (f != null) return f(fn, params ?? const <String, dynamic>{});
    return _sb.rpc(fn, params: params);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ESTADO
  // ══════════════════════════════════════════════════════════════════════════

  CasaPerfil? _perfil;
  CasaPerfil? get perfil => _perfil;

  /// Nome igual ao dos outros stores (o anfitrião da oferta lê `profile`).
  CasaPerfil? get profile => _perfil;
  bool get isHandyman => _perfil != null;
  bool get isApproved => _perfil?.aprovado == true;

  bool _profileLoaded = false;
  bool get profileLoaded => _profileLoaded;

  bool _perfilFalhou = false;

  /// A última leitura do perfil falhou (sem rede) e não há perfil em memória.
  bool get perfilFalhou => _perfilFalhou;

  CasaConfig _config = CasaConfig.vazia;
  CasaConfig get config => _config;
  bool _configCarregada = false;
  bool get configCarregada => _configCarregada;

  List<CasaOferta> _ofertas = const [];
  List<CasaOferta> get ofertas => _ofertas;

  List<CasaPedido> _trabalhos = const [];
  List<CasaPedido> get trabalhos => _trabalhos;

  List<CasaSlot> _slots = const [];
  List<CasaSlot> get slots => _slots;

  CasaGanhos _ganhos = CasaGanhos.vazio;
  CasaGanhos get ganhos => _ganhos;

  /// Orçamentos que enviei nesta sessão (pedido → orçamento), para poder
  /// retirar. Ver lacuna no relatório: `casa_minhas_ofertas` não devolve o id.
  final Map<String, String> _meusOrcamentos = <String, String>{};
  String? orcamentoDe(String pedidoId) => _meusOrcamentos[pedidoId];

  bool _busy = false;
  bool get busy => _busy;

  String? _lastError;
  String? get lastError => _lastError;

  bool _falhaDeRede = false;

  /// A última falha foi de rede (sem resposta do servidor)? O cartão da
  /// oferta fica para tentar outra vez nesse caso.
  bool get ultimaFalhaFoiDeRede => _falhaDeRede;

  RealtimeChannel? _channel;
  Timer? _relogioOfertas;

  /// Ids já avisados, para não tocar duas vezes pela mesma oferta.
  final Set<String> _ofertasJaAlertadas = <String>{};

  // ══════════════════════════════════════════════════════════════════════════
  // DERIVADOS (puros — testáveis com debugDefinir)
  // ══════════════════════════════════════════════════════════════════════════

  bool _viva(CasaOferta o, DateTime now) =>
      o.expiraEm == null || o.expiraEm!.isAfter(now);

  /// Ofertas de preço fixo/hora à espera de resposta AGORA (sem convites).
  List<CasaOferta> ofertasVivas({DateTime? agora}) {
    if (!isApproved) return const [];
    final now = agora ?? DateTime.now();
    return _ofertas.where((o) => !o.convite && _viva(o, now)).toList();
  }

  /// Convites para orçar ainda abertos.
  List<CasaOferta> convitesAbertos({DateTime? agora}) {
    if (!isApproved) return const [];
    final now = agora ?? DateTime.now();
    return _ofertas.where((o) => o.convite && _viva(o, now)).toList();
  }

  /// O que o cartão em ecrã inteiro mostra: ofertas e convites vivos onde
  /// ainda não respondi (um convite já orçado não volta a tocar).
  List<CasaOferta> ofertasParaAviso({DateTime? agora}) {
    if (!isApproved) return const [];
    final now = agora ?? DateTime.now();
    return _ofertas.where((o) => !o.jaOrcei && _viva(o, now)).toList();
  }

  CasaOferta? ofertaPorId(String pedidoId) {
    for (final o in _ofertas) {
      if (o.pedidoId == pedidoId) return o;
    }
    return null;
  }

  CasaPedido? trabalhoPorId(String pedidoId) {
    for (final p in _trabalhos) {
      if (p.id == pedidoId) return p;
    }
    return null;
  }

  /// O trabalho que manda no ecrã (regra 1.24): aceite e ainda por acabar.
  CasaPedido? get trabalhoAtivo {
    for (final p in _trabalhos) {
      if (p.estado.ativo) return p;
    }
    return null;
  }

  List<CasaPedido> get trabalhosAtivos =>
      _trabalhos.where((p) => p.estado.ativo).toList();

  /// Terminados, à espera do cliente, em disputa ou cancelados.
  List<CasaPedido> get historico =>
      _trabalhos.where((p) => !p.estado.ativo).toList();

  // ══════════════════════════════════════════════════════════════════════════
  // PERFIL, CONFIGURAÇÃO E CANDIDATURA
  // ══════════════════════════════════════════════════════════════════════════

  /// Lê o meu perfil (`casa_meu_perfil` → null se não for profissional). Liga
  /// o tempo real e a releitura das ofertas só para quem está aprovado.
  Future<void> loadProfile() async {
    try {
      if (_uid == null) {
        _profileLoaded = true;
        notifyListeners();
        return;
      }
      final res = await _rpc('casa_meu_perfil').timeout(kAcaoTimeout);
      _aplicarPerfil(res);
      _profileLoaded = true;
      _perfilFalhou = false;
      notifyListeners();
      if (isApproved) {
        _ligar();
        await refreshAll();
      } else {
        _desligar();
      }
    } catch (e) {
      debugPrint('HandymanStore.loadProfile => $e');
      _profileLoaded = true;
      // Sem perfil lido (rede): o ecrã mostra "tentar de novo", não o convite.
      if (_perfil == null) _perfilFalhou = true;
      notifyListeners();
    }
  }

  void _aplicarPerfil(dynamic res) {
    final m = _mapaOuNulo(res);
    _perfil = (m == null || m['perfil'] is! Map) ? null : CasaPerfil.fromJson(m);
    _slots = _perfil == null
        ? const []
        : _perfil!.disponibilidade.map(CasaSlot.fromJson).toList();
  }

  /// `casa_config()` — ofícios e serviços (para escolher ofícios na
  /// candidatura e mostrar as perguntas do serviço no trabalho).
  Future<void> loadConfig() async {
    try {
      final res = await _rpc('casa_config').timeout(kAcaoTimeout);
      final m = _mapaOuNulo(res);
      if (m != null) _config = CasaConfig.fromJson(m);
      _configCarregada = true;
      notifyListeners();
    } catch (e) {
      debugPrint('HandymanStore.loadConfig => $e');
    }
  }

  /// Candidatura (ou recandidatura) — `casa_candidatura`. Devolve o perfil
  /// novo. Lança o erro do servidor (o ecrã diz em que passo falhou).
  Future<CasaPerfil?> candidatura({
    required String nome,
    required String telefone,
    String email = '',
    String fotoUrl = '',
    String bio = '',
    String nif = '',
    String moradaBase = '',
    double? baseLat,
    double? baseLng,
    double raioKm = 15,
    bool temCarrinha = false,
    bool temFerramentas = true,
    required List<String> oficios,
    List<CasaSlot> disponibilidade = const [],
  }) async {
    _setBusy(true);
    try {
      final res = await _rpc('casa_candidatura', {
        'p_name': nome,
        'p_phone': telefone,
        'p_email': email,
        'p_photo_url': fotoUrl,
        'p_bio': bio,
        'p_nif': nif,
        'p_base_address': moradaBase,
        'p_base_lat': baseLat,
        'p_base_lng': baseLng,
        'p_service_radius_km': raioKm,
        'p_has_van': temCarrinha,
        'p_has_tools': temFerramentas,
        'p_oficios': oficios,
        'p_disponibilidade': disponibilidade.map((s) => s.toJson()).toList(),
      }).timeout(kAcaoTimeout);
      _aplicarPerfil(res);
      _profileLoaded = true;
      notifyListeners();
      return _perfil;
    } catch (e) {
      debugPrint('HandymanStore.candidatura => $e');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  /// Envia a imagem de um documento para o balde privado `handyman-documents`
  /// (`<uid>/<tag>_<ms>.<ext>`) e regista-o (`casa_registar_documento`). Serve
  /// também para reenviar um documento recusado ou caducado. Lança o erro.
  Future<String?> registarDocumento({
    required XFile ficheiro,
    required String tipo,
    String? oficio,
    String? numero,
    DateTime? validade,
    bool recarregarPerfil = true,
  }) async {
    final path = await _subir(
      ficheiro,
      balde: kCasaBaldeDocumentos,
      caminho: (uid, ext, ms) => casaCaminhoDocumento(
          uid, oficio == null ? tipo : '${tipo}_$oficio', ext, ms),
    );
    final res = await _rpc('casa_registar_documento', {
      'p_tipo': tipo,
      'p_oficio': oficio,
      'p_storage_path': path,
      'p_numero': (numero ?? '').trim().isEmpty ? null : numero!.trim(),
      'p_validade': validade == null ? null : casaDataIso(validade),
    }).timeout(kAcaoTimeout);
    if (recarregarPerfil) await loadProfile();
    return _mapaOuNulo(res)?['id']?.toString();
  }

  /// Grelha semanal inteira (`casa_definir_disponibilidade`).
  Future<bool> definirDisponibilidade(List<CasaSlot> novos) async {
    final r = await _chamar('casa_definir_disponibilidade',
        {'p_slots': novos.map((s) => s.toJson()).toList()},
        recarregar: false);
    if (r.ok) {
      _slots = List.of(novos);
      notifyListeners();
    }
    return r.ok;
  }

  /// Liga/desliga um ofício aprovado (`casa_ligar_oficio`). O papel inteiro
  /// liga-se e desliga-se na caixa de papéis (definir_preferencia_papel).
  Future<bool> ligarOficio(String codigo, bool ligado) async {
    final r = await _chamar(
        'casa_ligar_oficio', {'p_oficio': codigo, 'p_ligado': ligado},
        recarregar: false);
    if (r.ok) await loadProfile();
    return r.ok;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // OFERTAS E TRABALHOS
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> refreshAll() async {
    await Future.wait([loadOffers(), loadJobs()]);
  }

  /// O mesmo nome do store do cliente: relê o que está a acompanhar.
  Future<void> refreshTracked() => refreshAll();

  Future<void> loadOffers() async {
    try {
      if (!isApproved) return;
      final res = await _rpc('casa_minhas_ofertas').timeout(kAcaoTimeout);
      final linhas = _listaDeMapas(res);
      for (final l in linhas) {
        final id = (l['meu_orcamento_id'] ??
                (l['meu_orcamento'] is Map ? l['meu_orcamento']['id'] : null))
            ?.toString();
        if (id != null && id.isNotEmpty) {
          _meusOrcamentos[(l['pedido_id'] ?? '').toString()] = id;
        }
      }
      _ofertas = linhas.map(CasaOferta.fromJson).toList();
      notifyListeners();
      for (final o in _ofertas) {
        _talvezAlertarOfertaNova(o);
      }
    } catch (e) {
      debugPrint('HandymanStore.loadOffers => $e');
    } finally {
      _ajustarSondagem();
    }
  }

  /// `casa_meus_trabalhos` — ativos primeiro, depois o histórico.
  Future<void> loadJobs() async {
    try {
      if (_perfil == null) return;
      final res = await _rpc('casa_meus_trabalhos').timeout(kAcaoTimeout);
      _trabalhos = _listaDeMapas(res).map(CasaPedido.fromJson).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('HandymanStore.loadJobs => $e');
    }
  }

  /// Relê um pedido (`casa_pedido`) e substitui-o na lista.
  Future<CasaPedido?> pedido(String pedidoId) async {
    try {
      final res = await _rpc('casa_pedido', {'p_pedido_id': pedidoId})
          .timeout(kAcaoTimeout);
      final m = _mapaOuNulo(res);
      if (m == null) return null;
      final p = CasaPedido.fromJson(m);
      final i = _trabalhos.indexWhere((t) => t.id == p.id);
      final nova = List.of(_trabalhos);
      if (i >= 0) {
        nova[i] = p;
      } else {
        nova.insert(0, p);
      }
      _trabalhos = nova;
      notifyListeners();
      return p;
    } catch (e) {
      debugPrint('HandymanStore.pedido => $e');
      return null;
    }
  }

  void _talvezAlertarOfertaNova(CasaOferta o) {
    if (o.pedidoId.isEmpty || o.jaOrcei) return;
    if (o.expiraEm != null && !o.expiraEm!.isAfter(DateTime.now())) return;
    // Com a app à frente quem mostra é o cartão global em ecrã inteiro (som em
    // ciclo). Em segundo plano toca a notificação com Aceitar/Recusar.
    if (!kIsWeb &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      return;
    }
    if (!_ofertasJaAlertadas.add(o.pedidoId)) return;
    final ganho = o.ganhoCents;
    unawaited(mostrarOfertaDeTrabalho(
      categoria: 'casa',
      bookingId: o.pedidoId,
      titulo: o.convite ? '🔧 Pedido de orçamento!'.tr : '🔧 Novo trabalho de casa!'.tr,
      corpo: [
        if (!o.convite && ganho != null && ganho > 0)
          'Ganhas {0}'.trArgs([casaEuro(ganho)]),
        if (o.convite) 'Envia o teu preço'.tr,
        if (o.localidade.trim().isNotEmpty) o.localidade.trim(),
        // C15: as fotos do cliente podem ainda estar a subir — não prometer.
        o.convite ? 'Vê o pedido e orça.'.tr : 'Aceita ou recusa.'.tr,
      ].join(' · '),
    ));
  }

  /// Aceitar uma oferta de preço fixo/hora (`casa_aceitar_oferta`).
  Future<bool> accept(String pedidoId) async {
    unawaited(IncomingJobAlert.dismiss(pedidoId));
    final r = await _chamar('casa_aceitar_oferta', {'p_pedido_id': pedidoId});
    // Só depois de o servidor aceitar (falha de rede não cala o toque).
    if (r.ok) unawaited(marcarOfertaTrabalhoTratada(pedidoId));
    return r.ok;
  }

  Future<bool> aceitarOferta(String pedidoId) => accept(pedidoId);

  /// Recusar cala o aviso e devolve o pedido à rotação.
  Future<bool> reject(String pedidoId) async {
    unawaited(IncomingJobAlert.dismiss(pedidoId));
    unawaited(marcarOfertaTrabalhoTratada(pedidoId));
    _ofertasJaAlertadas.remove(pedidoId);
    final r = await _chamar('casa_recusar_oferta', {'p_pedido_id': pedidoId});
    return r.ok;
  }

  Future<bool> recusarOferta(String pedidoId) => reject(pedidoId);

  /// Orçamento para um convite (`casa_enviar_orcamento`). Preço em cêntimos.
  Future<bool> enviarOrcamento({
    required String pedidoId,
    required int precoCents,
    required String inclui,
    String materiais = '',
    bool materiaisIncluidos = false,
    String prazo = '',
    int? duracaoMin,
  }) async {
    final r = await _chamar('casa_enviar_orcamento', {
      'p_pedido_id': pedidoId,
      'p_preco_cents': precoCents,
      'p_inclui': inclui.trim(),
      'p_materiais': materiais.trim(),
      'p_materiais_incluidos': materiaisIncluidos,
      'p_prazo': prazo.trim(),
      'p_duracao_min': duracaoMin,
    });
    if (r.ok) {
      final id = _mapaOuNulo(r.dados)?['id']?.toString();
      if (id != null && id.isNotEmpty) _meusOrcamentos[pedidoId] = id;
      unawaited(IncomingJobAlert.dismiss(pedidoId));
      unawaited(marcarOfertaTrabalhoTratada(pedidoId));
    }
    return r.ok;
  }

  Future<bool> retirarOrcamento(String orcamentoId) async {
    final r = await _chamar(
        'casa_retirar_orcamento', {'p_orcamento_id': orcamentoId});
    if (r.ok) _meusOrcamentos.removeWhere((_, v) => v == orcamentoId);
    return r.ok;
  }

  /// a_caminho | chegou | em_curso | concluido (`casa_avancar`). Concluir
  /// exige pelo menos uma foto 'depois' — o servidor valida outra vez.
  Future<bool> avancar(String pedidoId, String para) async {
    if (!kCasaPassosValidos.contains(para)) {
      _lastError = casaErroTexto('estado_invalido');
      notifyListeners();
      return false;
    }
    final local = trabalhoPorId(pedidoId);
    if (para == 'concluido' && local != null && !casaPodeConcluir(local)) {
      _lastError = casaErroTexto('foto_depois_em_falta');
      notifyListeners();
      return false;
    }
    final r = await _chamar(
        'casa_avancar', {'p_pedido_id': pedidoId, 'p_para': para});
    if (r.ok) {
      final m = _mapaOuNulo(r.dados);
      if (m != null && m['id'] != null) _substituir(CasaPedido.fromJson(m));
    }
    return r.ok;
  }

  /// Foto do trabalho: balde `casa-fotos`, `<uid>/<pedido_id>/<tipo>_<ms>.<ext>`
  /// (a extensão é a do tipo real — PNG/WebP não sobem como `.jpg`, C14), e
  /// depois `casa_adicionar_foto`. Tipos do profissional: antes|depois|extra.
  Future<bool> adicionarFoto(String pedidoId, String tipo, XFile ficheiro) async {
    _setBusy(true);
    _lastError = null;
    _falhaDeRede = false;
    try {
      final path = await _subir(
        ficheiro,
        balde: kCasaBaldeFotos,
        caminho: (uid, ext, ms) =>
            casaCaminhoFoto(uid, pedidoId, tipo, ms, ext: ext),
      );
      await _rpc('casa_adicionar_foto', {
        'p_pedido_id': pedidoId,
        'p_tipo': tipo,
        'p_storage_path': path,
      }).timeout(kAcaoTimeout);
      await pedido(pedidoId);
      return true;
    } catch (e) {
      _lastError = casaErroTexto(e);
      _falhaDeRede = casaFalhaDeRede(e);
      debugPrint('HandymanStore.adicionarFoto => $e');
      return false;
    } finally {
      _setBusy(false);
    }
  }

  /// Valor extra (o cliente consente na app antes de contar).
  Future<bool> pedirExtra(String pedidoId, int valorCents, String motivo) async {
    final r = await _chamar('casa_pedir_extra', {
      'p_pedido_id': pedidoId,
      'p_valor_cents': valorCents,
      'p_motivo': motivo.trim(),
    }, recarregar: false);
    if (r.ok) await pedido(pedidoId);
    return r.ok;
  }

  Future<bool> avaliarCliente(String pedidoId, int nota) async {
    final r = await _chamar('casa_avaliar_cliente',
        {'p_pedido_id': pedidoId, 'p_nota': nota.clamp(1, 5)},
        recarregar: false);
    if (r.ok) await pedido(pedidoId);
    return r.ok;
  }

  /// Desistir devolve o pedido à rotação (`casa_desistir`).
  Future<bool> desistir(String pedidoId, String motivo) => _chamar(
        'casa_desistir',
        {'p_pedido_id': pedidoId, 'p_motivo': motivo.trim()},
      ).then((r) => r.ok);

  // ══════════════════════════════════════════════════════════════════════════
  // CHAT, FOTOS E GANHOS
  // ══════════════════════════════════════════════════════════════════════════

  /// Só com `pode_contactar` (o servidor recusa antes disso).
  Future<List<Map<String, dynamic>>> mensagens(String pedidoId) async {
    final res = await _rpc('casa_mensagens', {'p_pedido_id': pedidoId})
        .timeout(kAcaoTimeout);
    return _listaDeMapas(res);
  }

  Future<bool> enviarMensagem(String pedidoId, String texto) => _chamar(
        'casa_enviar_mensagem',
        {'p_pedido_id': pedidoId, 'p_texto': texto.trim()},
        recarregar: false,
        ocupado: false,
      ).then((r) => r.ok);

  /// URL assinado (1 h) de uma foto do balde privado `casa-fotos`. null se
  /// o Storage recusar (ver lacuna no relatório).
  Future<String?> urlDaFoto(String storagePath) async {
    if (storagePath.isEmpty || _deTeste) return null;
    try {
      return await _sb.storage
          .from(kCasaBaldeFotos)
          .createSignedUrl(storagePath, 3600)
          .timeout(kAcaoTimeout);
    } catch (e) {
      debugPrint('HandymanStore.urlDaFoto => $e');
      return null;
    }
  }

  Future<void> carregarGanhos() async {
    try {
      final res = await _rpc('casa_meus_ganhos').timeout(kAcaoTimeout);
      final m = _mapaOuNulo(res);
      _ganhos = m == null ? CasaGanhos.vazio : CasaGanhos.fromJson(m);
      notifyListeners();
    } catch (e) {
      debugPrint('HandymanStore.carregarGanhos => $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // INFRA
  // ══════════════════════════════════════════════════════════════════════════

  Future<({bool ok, dynamic dados})> _chamar(
    String fn,
    Map<String, dynamic> params, {
    bool recarregar = true,
    bool ocupado = true,
  }) async {
    if (ocupado) _setBusy(true);
    _lastError = null;
    _falhaDeRede = false;
    try {
      final res = await _rpc(fn, params).timeout(kAcaoTimeout);
      if (recarregar) await refreshAll();
      return (ok: true, dados: res);
    } catch (e) {
      _lastError = casaErroTexto(e);
      _falhaDeRede = casaFalhaDeRede(e);
      debugPrint('HandymanStore.$fn => $e');
      return (ok: false, dados: null);
    } finally {
      if (ocupado) _setBusy(false);
    }
  }

  Future<String> _subir(
    XFile ficheiro, {
    required String balde,
    required String Function(String uid, String ext, int ms) caminho,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('not_authenticated');
    final bytes = await ficheiro.readAsBytes();
    if (bytes.isEmpty) throw StateError('empty_file');
    // Tipo pelos bytes; HEIC do iPhone sai como JPEG (mesma peça dos outros
    // uploads da app).
    final foto = await prepararFotoParaEnvio(bytes);
    if (foto == null) throw StateError('empty_file: formato ilegivel');
    final ext = casaExtensaoFoto(foto.mime).ext;
    final path = caminho(uid, ext, DateTime.now().millisecondsSinceEpoch);
    // O servidor falso dos testes não tem Storage: só devolve o caminho.
    if (_deTeste) return path;
    try {
      await _sb.storage.from(balde).uploadBinary(
            path,
            foto.bytes,
            fileOptions: FileOptions(contentType: foto.mime),
          );
    } on StorageException catch (e) {
      debugPrint('[HandymanStore] upload $balde status=${e.statusCode} '
          'error=${e.error} msg=${e.message}');
      rethrow;
    }
    return path;
  }

  void _substituir(CasaPedido p) {
    final i = _trabalhos.indexWhere((t) => t.id == p.id);
    if (i < 0) return;
    final nova = List.of(_trabalhos)..[i] = p;
    _trabalhos = nova;
    notifyListeners();
  }

  void _ligar() {
    final p = _perfil;
    if (p == null) return;
    // Sem filtro: a RLS já limita aos pedidos onde sou o profissional (ou o
    // cliente). A OFERTA não passa aqui (vive em offer_profissional_id): para
    // isso há a sondagem abaixo (C5).
    if (!_deTeste) {
      _channel ??= _sb.channel('casa_profissional_${p.id}')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'casa_pedidos',
          callback: (_) => refreshAll(),
        )
        ..subscribe();
    }
    if (_relogioOfertas == null) {
      _intervaloSondagem =
          casaIntervaloSondagem(ofertasParaAviso().length);
      _relogioOfertas =
          Timer.periodic(_intervaloSondagem!, (_) => loadOffers());
    }
  }

  Duration? _intervaloSondagem;

  /// De quanto em quanto tempo se relêem as ofertas agora (null = parado).
  @visibleForTesting
  Duration? get intervaloSondagem =>
      _relogioOfertas == null ? null : _intervaloSondagem;

  /// Depois de cada leitura: 10 s com ofertas por responder, 30 s sem
  /// nenhuma. Só mexe se a sondagem estiver ligada e o ritmo mudar.
  void _ajustarSondagem() {
    if (_relogioOfertas == null) return;
    final novo = casaIntervaloSondagem(ofertasParaAviso().length);
    if (novo == _intervaloSondagem) return;
    _relogioOfertas!.cancel();
    _intervaloSondagem = novo;
    _relogioOfertas = Timer.periodic(novo, (_) => loadOffers());
  }

  void _desligar() {
    _relogioOfertas?.cancel();
    _relogioOfertas = null;
    _intervaloSondagem = null;
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        _sb.removeChannel(ch);
      } catch (_) {}
    }
  }

  void _setBusy(bool v) {
    _busy = v;
    notifyListeners();
  }

  /// SÓ PARA TESTES: põe dados no store sem Supabase.
  @visibleForTesting
  void debugDefinir({
    CasaPerfil? perfil,
    List<CasaOferta>? ofertas,
    List<CasaPedido>? trabalhos,
    CasaConfig? config,
    CasaGanhos? ganhos,
  }) {
    if (perfil != null) {
      _perfil = perfil;
      _profileLoaded = true;
      _slots = perfil.disponibilidade.map(CasaSlot.fromJson).toList();
    }
    if (ofertas != null) _ofertas = List.of(ofertas);
    if (trabalhos != null) _trabalhos = List.of(trabalhos);
    if (config != null) _config = config;
    if (ganhos != null) _ganhos = ganhos;
    notifyListeners();
  }

  /// Sessão terminada (ou outra pessoa entrou): esquece tudo e desliga o
  /// tempo real — a oferta de uma conta nunca aparece a outra.
  void reset() {
    _desligar();
    _perfil = null;
    _profileLoaded = false;
    _perfilFalhou = false;
    _ofertas = const [];
    _trabalhos = const [];
    _slots = const [];
    _ganhos = CasaGanhos.vazio;
    _meusOrcamentos.clear();
    _ofertasJaAlertadas.clear();
    _lastError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _desligar();
    super.dispose();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PEÇAS PURAS (testadas sem rede)
// ════════════════════════════════════════════════════════════════════════════

const String kCasaBaldeDocumentos = 'handyman-documents';
const String kCasaBaldeFotos = 'casa-fotos';

/// Os passos que o profissional pode pedir a `casa_avancar`.
const Set<String> kCasaPassosValidos = {
  'a_caminho',
  'chegou',
  'em_curso',
  'concluido',
};

/// `<uid>/<tag>_<ms>.<ext>` (contrato do balde `handyman-documents`).
String casaCaminhoDocumento(String uid, String tag, String ext, int ms) =>
    '$uid/${tag}_$ms.$ext';

/// `<uid>/<pedido_id>/<tipo>_<ms>.<ext>` (contrato do balde `casa-fotos`: o
/// servidor só exige o prefixo `<uid>/<pedido_id>/`). A extensão segue o tipo
/// real da imagem (C14); sem ela fica `.jpg`.
String casaCaminhoFoto(String uid, String pedidoId, String tipo, int ms,
        {String ext = 'jpg'}) =>
    '$uid/$pedidoId/${tipo}_$ms.${casaExtensaoFoto(ext).ext}';

/// C5 (revisão 01/11): o tempo real não traz ofertas (RLS), por isso a app
/// relê-as. Com ofertas por responder relê a cada 10 s (a oferta dura poucos
/// minutos); sem nenhuma, a cada 30 s.
Duration casaIntervaloSondagem(int ofertasPorResponder) =>
    ofertasPorResponder > 0
        ? const Duration(seconds: 10)
        : const Duration(seconds: 30);

/// '2026-11-03' para colunas `date`.
String casaDataIso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// '03/11'.
String casaDiaMes(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

/// Euros escritos pela pessoa → cêntimos. Aceita "25", "25,5", "25,50",
/// "25.50" e "25 €". null se não for um valor positivo com até 2 casas.
int? casaEurosParaCents(String texto) {
  final t = texto.replaceAll('€', '').replaceAll(' ', '').replaceAll(',', '.');
  if (!RegExp(r'^\d{1,5}(\.\d{1,2})?$').hasMatch(t)) return null;
  final v = double.tryParse(t);
  if (v == null) return null;
  final c = (v * 100).round();
  return c > 0 ? c : null;
}

/// A falha foi de rede (sem resposta) e não uma recusa do servidor?
bool casaFalhaDeRede(Object e) {
  if (e is TimeoutException) return true;
  final s = e.toString();
  return s.contains('SocketException') ||
      s.contains('ClientException') ||
      s.contains('Failed host lookup') ||
      s.contains('Connection closed') ||
      s.contains('Network is unreachable');
}

/// Erro do servidor (código curto do contrato) → frase PT-PT.
String casaErroTexto(Object erro) {
  if (casaFalhaDeRede(erro)) return 'Sem rede. Tenta outra vez.'.tr;
  final raw = erro is PostgrestException
      ? '${erro.message} ${erro.details ?? ''} ${erro.code ?? ''}'
      : erro.toString();
  // Cada frase com `.tr` colado ao literal (o gerador do dicionário só vê assim).
  if (raw.contains('casa_desligada')) {
    return 'A Casa ainda não está ligada. Avisamos-te quando abrir.'.tr;
  }
  if (raw.contains('valores_por_autorizar')) {
    return 'Os valores da Casa ainda estão a ser aprovados. Tenta mais tarde.'.tr;
  }
  if (raw.contains('dinheiro_acima_do_limite')) {
    return 'Este valor passa o limite do pagamento em dinheiro.'.tr;
  }
  if (raw.contains('sem_permissao')) {
    return 'Não tens permissão para fazer isto.'.tr;
  }
  if (raw.contains('estado_invalido')) {
    return 'Este trabalho já mudou de estado. Atualiza a lista.'.tr;
  }
  if (raw.contains('pagamento_cartao_indisponivel')) {
    return 'O pagamento com cartão ainda não está disponível.'.tr;
  }
  if (raw.contains('foto_depois_em_falta')) {
    return 'Tira pelo menos uma foto de como ficou antes de concluir.'.tr;
  }
  if (raw.contains('limite_fotos')) {
    return 'Já chegaste ao limite de fotos deste trabalho.'.tr;
  }
  if (raw.contains('orcamentos_completos')) {
    return 'Este pedido já recebeu todos os orçamentos.'.tr;
  }
  if (raw.contains('nao_e_profissional')) {
    return 'A tua conta de profissional da Casa não está ativa.'.tr;
  }
  if (raw.contains('antecedencia_minima')) {
    return 'Já falta pouco para a hora marcada.'.tr;
  }
  if (raw.contains('morada_em_falta')) return 'Falta a morada.'.tr;
  if (raw.contains('empty_file')) {
    return 'Não foi possível ler a imagem. Tira ou escolhe a foto de novo.'.tr;
  }
  // C9 (revisão 01/11): os outros códigos que as funções casa_* (e os dados
  // fiscais/papéis) levantam — lista tirada do servidor com
  // pg_get_functiondef. Nenhum pode cair na frase genérica.
  if (raw.contains('oferta_expirada')) {
    return 'Esta oferta já expirou. Fica atento às próximas.'.tr;
  }
  if (raw.contains('profissional_ocupado')) {
    return 'Já tens outro trabalho marcado a essa hora.'.tr;
  }
  if (raw.contains('extra_por_responder')) {
    return 'O cliente ainda não respondeu ao valor extra. Espera pela resposta.'.tr;
  }
  if (raw.contains('oficio_por_aprovar')) {
    return 'Este ofício ainda não foi aprovado pela equipa Bora.'.tr;
  }
  if (raw.contains('oficio_invalido')) {
    return 'Este ofício não existe ou já não está disponível.'.tr;
  }
  if (raw.contains('oficios_em_falta')) {
    return 'Escolhe pelo menos um ofício.'.tr;
  }
  if (raw.contains('preco_invalido')) {
    return 'Escreve um preço válido, maior do que zero.'.tr;
  }
  if (raw.contains('motivo_em_falta') || raw.contains('motivo_obrigatorio')) {
    return 'Escreve o motivo antes de enviar.'.tr;
  }
  if (raw.contains('conta_bloqueada')) {
    return 'A tua conta está bloqueada. Fala com o suporte do Bora.'.tr;
  }
  if (raw.contains('nome_em_falta')) {
    return 'Falta o teu nome.'.tr;
  }
  if (raw.contains('invalid_role') || raw.contains('PAPEL_NAO_ATRIBUIDO')) {
    return 'A tua conta ainda não tem este papel ativo. Fala com o suporte do Bora.'.tr;
  }
  if (raw.contains('nif_invalido')) {
    return 'O NIF não é válido. Confirma os 9 dígitos.'.tr;
  }
  if (raw.contains('iban_invalido')) {
    return 'O IBAN não é válido. Confirma que começa por PT50 e tem 25 caracteres.'.tr;
  }
  if (raw.contains('menor_de_idade')) {
    return 'Tens de ter pelo menos 18 anos para trabalhar no Bora.'.tr;
  }
  if (raw.contains('tipo_invalido')) {
    return 'Este tipo de foto ou documento não é aceite aqui.'.tr;
  }
  if (raw.contains('caminho_invalido')) {
    return 'Não foi possível guardar a imagem. Tenta outra vez.'.tr;
  }
  if (raw.contains('contacto_fechado')) {
    return 'As mensagens só abrem depois de o trabalho estar aceite e pago.'.tr;
  }
  if (raw.contains('mensagem_invalida')) {
    return 'A mensagem está vazia ou é demasiado comprida.'.tr;
  }
  if (raw.contains('ja_avaliado')) {
    return 'Já deixaste a tua avaliação.'.tr;
  }
  if (raw.contains('nota_invalida')) {
    return 'Escolhe de 1 a 5 estrelas.'.tr;
  }
  if (raw.contains('orcamento_expirado')) {
    return 'Este orçamento já expirou.'.tr;
  }
  if (raw.contains('garantia_terminou')) {
    return 'A garantia deste trabalho já terminou.'.tr;
  }
  if (raw.contains('metodo_invalido')) {
    return 'Escolhe como queres pagar.'.tr;
  }
  if (raw.contains('quantidade_invalida')) {
    return 'Escolhe uma quantidade válida.'.tr;
  }
  if (raw.contains('servico_indisponivel')) {
    return 'Este serviço já não está disponível. Escolhe outro.'.tr;
  }
  if (raw.contains('not_authenticated') ||
      raw.toLowerCase().contains('unauthenticated') ||
      raw.contains('42501')) {
    return 'A tua sessão expirou. Volta a entrar e tenta de novo.'.tr;
  }
  return 'Não foi possível concluir. Tenta outra vez.'.tr;
}

/// Os códigos curtos que o servidor da Casa pode devolver ao profissional
/// (RAISE EXCEPTION das funções `casa_*`, `_casa_*`, `provider_update_legal_fields`
/// e `definir_preferencia_papel`, lidos com pg_get_functiondef a 01/11/2026).
/// O teste garante que nenhum cai na frase genérica de [casaErroTexto].
const List<String> kCasaCodigosDeErro = [
  'antecedencia_minima',
  'caminho_invalido',
  'casa_desligada',
  'conta_bloqueada',
  'contacto_fechado',
  'dinheiro_acima_do_limite',
  'estado_invalido',
  'extra_por_responder',
  'foto_depois_em_falta',
  'garantia_terminou',
  'ja_avaliado',
  'limite_fotos',
  'mensagem_invalida',
  'metodo_invalido',
  'morada_em_falta',
  'motivo_em_falta',
  'motivo_obrigatorio',
  'nao_e_profissional',
  'nome_em_falta',
  'not_authenticated',
  'nota_invalida',
  'oferta_expirada',
  'oficio_invalido',
  'oficio_por_aprovar',
  'oficios_em_falta',
  'orcamento_expirado',
  'orcamentos_completos',
  'pagamento_cartao_indisponivel',
  'preco_invalido',
  'profissional_ocupado',
  'quantidade_invalida',
  'sem_permissao',
  'servico_indisponivel',
  'tipo_invalido',
  'valores_por_autorizar',
  // Dados fiscais e papéis (chamados no fim da candidatura).
  'invalid_role',
  'unauthenticated',
  'nif_invalido',
  'iban_invalido',
  'menor_de_idade',
  'UNAUTHENTICATED',
  'PAPEL_NAO_ATRIBUIDO',
];

/// Concluir só com pelo menos uma foto 'depois'.
bool casaPodeConcluir(CasaPedido p) => p.fotosDe('depois').isNotEmpty;

/// O botão principal do trabalho, por estado. null = nada a avançar.
({String para, String rotulo})? casaProximoPasso(CasaEstado e) => switch (e) {
      CasaEstado.aceite => (para: 'a_caminho', rotulo: 'Estou a caminho'.tr),
      CasaEstado.aCaminho => (para: 'chegou', rotulo: 'Cheguei'.tr),
      CasaEstado.chegou => (para: 'em_curso', rotulo: 'Iniciar trabalho'.tr),
      CasaEstado.emCurso => (para: 'concluido', rotulo: 'Concluir trabalho'.tr),
      _ => null,
    };

/// Nome do dia (weekday 0 = domingo), PT-PT.
String casaNomeDoDia(int weekday) => switch (weekday) {
      0 => 'Domingo'.tr,
      1 => 'Segunda'.tr,
      2 => 'Terça'.tr,
      3 => 'Quarta'.tr,
      4 => 'Quinta'.tr,
      5 => 'Sexta'.tr,
      _ => 'Sábado'.tr,
    };

/// "15" para 15.0, "12,5" para 12.5.
String casaPct(double pct) => pct == pct.roundToDouble()
    ? pct.round().toString()
    : pct.toStringAsFixed(1).replaceAll('.', ',');

/// A comissão em palavras, a partir do que o servidor diz (comissao_pct e
/// sem_comissao_ate). Nunca calcula valores.
String casaTextoComissao(double pct, DateTime? semComissaoAte,
    {DateTime? agora}) {
  final hoje = agora ?? DateTime.now();
  final dia = DateTime(hoje.year, hoje.month, hoje.day);
  if (semComissaoAte != null) {
    final ate = DateTime(
        semComissaoAte.year, semComissaoAte.month, semComissaoAte.day);
    if (!ate.isBefore(dia)) {
      return 'Sem comissão até {0}. Depois, o Bora fica com {1}% de cada trabalho concluído.'.trArgs([casaDiaMes(ate), casaPct(pct)]);
    }
  }
  return 'O Bora fica com {0}% de cada trabalho concluído. O resto é teu.'.trArgs([casaPct(pct)]);
}

/// Nome PT-PT de um tipo de documento.
String casaNomeDocumento(String tipo) => switch (tipo) {
      'cartao_cidadao' => 'Cartão de cidadão'.tr,
      'seguro_acidentes' => 'Seguro de acidentes de trabalho'.tr,
      'seguro_rc' => 'Seguro de responsabilidade civil'.tr,
      'dgeg_eletricidade' => 'Certificado DGEG (eletricidade)'.tr,
      'dgeg_gas' => 'Certificado DGEG (gás)'.tr,
      'impic' => 'Registo IMPIC'.tr,
      _ => 'Outro documento'.tr,
    };

/// Tipos que levam número (apólice/certificado) e validade.
bool casaDocumentoPedeNumero(String tipo) => const {
      'seguro_acidentes',
      'seguro_rc',
      'dgeg_eletricidade',
      'dgeg_gas',
      'impic',
    }.contains(tipo);

/// Dias até caducar (negativo = já caducou). null sem validade.
int? casaDiasParaCaducar(DateTime? validade, {DateTime? agora}) {
  if (validade == null) return null;
  final h = agora ?? DateTime.now();
  final hoje = DateTime(h.year, h.month, h.day);
  final v = DateTime(validade.year, validade.month, validade.day);
  return v.difference(hoje).inDays;
}

/// Com quantos dias de antecedência se avisa a caducidade.
const int kCasaAvisoCaducidadeDias = 30;

/// O que falta ao profissional, a partir de `casa_meu_perfil`.
class CasaFalta {
  const CasaFalta({
    required this.tipo,
    this.oficio,
    this.oficioNome,
    required this.razao,
    this.motivo,
  });

  final String tipo;
  final String? oficio;
  final String? oficioNome;

  /// 'em_falta' | 'recusado' | 'caducado'
  final String razao;
  final String? motivo;

  String get titulo {
    final nome = casaNomeDocumento(tipo);
    return (oficioNome == null || oficioNome!.isEmpty)
        ? nome
        : '$nome · $oficioNome';
  }

  String get explicacao => switch (razao) {
        'recusado' => (motivo == null || motivo!.trim().isEmpty)
            ? 'Foi recusado. Envia outra vez.'.tr
            : 'Foi recusado: {0}'.trArgs([motivo!.trim()]),
        'caducado' => 'Já caducou. Envia o novo.'.tr,
        _ => 'Ainda não enviaste.'.tr,
      };
}

/// O documento mais recente de cada (tipo, ofício).
List<CasaDocumento> casaDocumentosAtuais(List<CasaDocumento> docs) {
  final porChave = <String, CasaDocumento>{};
  for (final d in docs) {
    final k = '${d.tipo}|${d.oficio ?? ''}';
    final atual = porChave[k];
    final dNovo = d.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final aVelho = atual?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    if (atual == null || dNovo.isAfter(aVelho)) porChave[k] = d;
  }
  return porChave.values.toList();
}

/// Documentos em falta, recusados ou caducados. Gerais: cartão de cidadão e
/// seguro de acidentes de trabalho. Por ofício: o `documento_exigido`.
List<CasaFalta> casaDocumentosEmFalta(CasaPerfil p, {DateTime? agora}) {
  final atuais = casaDocumentosAtuais(p.documentos);
  CasaDocumento? doc(String tipo, String? oficio) {
    for (final d in atuais) {
      if (d.tipo == tipo && (d.oficio ?? '') == (oficio ?? '')) return d;
    }
    // Documento geral registado com ofício (ou o contrário) também conta.
    if (oficio == null) {
      for (final d in atuais) {
        if (d.tipo == tipo) return d;
      }
    }
    return null;
  }

  CasaFalta? avaliar(String tipo, {String? oficio, String? oficioNome}) {
    final d = doc(tipo, oficio);
    if (d == null) {
      return CasaFalta(
          tipo: tipo, oficio: oficio, oficioNome: oficioNome, razao: 'em_falta');
    }
    if (d.estado == 'rejected') {
      return CasaFalta(
          tipo: tipo,
          oficio: oficio,
          oficioNome: oficioNome,
          razao: 'recusado',
          motivo: d.motivo);
    }
    final dias = casaDiasParaCaducar(d.validade, agora: agora);
    if (d.estado == 'expired' || (dias != null && dias < 0)) {
      return CasaFalta(
          tipo: tipo, oficio: oficio, oficioNome: oficioNome, razao: 'caducado');
    }
    return null;
  }

  final faltas = <CasaFalta>[];
  for (final t in kCasaDocumentosGerais) {
    final f = avaliar(t);
    if (f != null) faltas.add(f);
  }
  for (final o in p.oficios) {
    final exigido = o.documentoExigido;
    if (exigido == null || exigido.isEmpty) continue;
    if (o.estado == 'rejected' || o.estado == 'suspended') continue;
    final f = avaliar(exigido, oficio: o.codigo, oficioNome: o.nome);
    if (f != null) faltas.add(f);
  }
  return faltas;
}

/// Os documentos que todos os profissionais da Casa enviam.
const List<String> kCasaDocumentosGerais = ['cartao_cidadao', 'seguro_acidentes'];

/// Uma janela da disponibilidade semanal (weekday 0 = domingo).
class CasaSlot {
  const CasaSlot({required this.weekday, required this.start, required this.end});

  final int weekday;
  final String start; // 'HH:MM'
  final String end;

  static String _hhmm(dynamic v) {
    final s = (v ?? '').toString();
    return s.length >= 5 ? s.substring(0, 5) : s;
  }

  factory CasaSlot.fromJson(Map<String, dynamic> m) => CasaSlot(
        weekday: int.tryParse('${m['weekday']}') ?? 0,
        start: _hhmm(m['start'] ?? m['start_time']),
        end: _hhmm(m['end'] ?? m['end_time']),
      );

  Map<String, dynamic> toJson() =>
      {'weekday': weekday, 'start': start, 'end': end};

  @override
  bool operator ==(Object other) =>
      other is CasaSlot &&
      other.weekday == weekday &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(weekday, start, end);
}

int _i(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse('${v ?? ''}') ?? 0;
}

DateTime? _d(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

/// Um acerto semanal (casa_meus_ganhos.acertos).
class CasaAcerto {
  const CasaAcerto({
    required this.id,
    this.inicio,
    this.fim,
    this.trabalhos = 0,
    this.liquidoCents = 0,
    this.direcao = '',
    this.estado = '',
    this.pagoEm,
  });

  final String id;
  final DateTime? inicio;
  final DateTime? fim;
  final int trabalhos;
  final int liquidoCents;
  final String direcao;
  final String estado;
  final DateTime? pagoEm;

  /// O valor vai do Bora para o profissional? As direções do servidor
  /// (`casa_acertos_semanais.direction`) são `bora_to_handyman`,
  /// `handyman_to_bora` e `zero` — as duas primeiras contêm "bora", por isso
  /// compara-se o valor inteiro (C8, revisão 01/11). O valor
  /// (`net_payout_cents`) vem sempre sem sinal.
  bool get aReceber => direcao == 'bora_to_handyman';

  /// O profissional paga ao Bora (recebeu em dinheiro mais do que ganhou).
  bool get aPagar => direcao == 'handyman_to_bora';

  /// Semana sem nada a acertar.
  bool get semAcerto => !aReceber && !aPagar;

  bool get pago => pagoEm != null || estado == 'paid' || estado == 'pago';

  factory CasaAcerto.fromJson(Map<String, dynamic> m) => CasaAcerto(
        id: (m['id'] ?? '').toString(),
        inicio: _d(m['week_start_at']),
        fim: _d(m['week_end_at']),
        trabalhos: _i(m['total_jobs']),
        liquidoCents: _i(m['net_payout_cents']),
        direcao: (m['direction'] ?? '').toString(),
        estado: (m['status'] ?? '').toString(),
        pagoEm: _d(m['paid_at']),
      );
}

/// Um trabalho pago (casa_meus_ganhos.trabalhos).
class CasaTrabalhoPago {
  const CasaTrabalhoPago({
    required this.id,
    this.servicoNome = '',
    this.confirmadoEm,
    this.totalCents = 0,
    this.comissaoCents = 0,
    this.ganhoCents = 0,
    this.metodo = '',
  });

  final String id;
  final String servicoNome;
  final DateTime? confirmadoEm;
  final int totalCents;
  final int comissaoCents;
  final int ganhoCents;
  final String metodo;

  factory CasaTrabalhoPago.fromJson(Map<String, dynamic> m) => CasaTrabalhoPago(
        id: (m['id'] ?? '').toString(),
        servicoNome: (m['servico_nome'] ?? '').toString(),
        confirmadoEm: _d(m['confirmed_at']),
        totalCents: _i(m['total_cents']),
        comissaoCents: _i(m['comissao_cents']),
        ganhoCents: _i(m['ganho_cents']),
        metodo: (m['payment_method'] ?? '').toString(),
      );
}

/// `casa_meus_ganhos()`.
class CasaGanhos {
  const CasaGanhos({
    this.inicio,
    this.fim,
    this.trabalhos = 0,
    this.brutoCents = 0,
    this.comissaoCents = 0,
    this.ganhoCents = 0,
    this.recebidoEmMaoCents = 0,
    this.aReceberCents = 0,
    this.acertos = const [],
    this.lista = const [],
  });

  static const vazio = CasaGanhos();

  final DateTime? inicio;
  final DateTime? fim;
  final int trabalhos;
  final int brutoCents;
  final int comissaoCents;
  final int ganhoCents;
  final int recebidoEmMaoCents;
  final int aReceberCents;
  final List<CasaAcerto> acertos;
  final List<CasaTrabalhoPago> lista;

  factory CasaGanhos.fromJson(Map<String, dynamic> m) {
    final s = m['semana'] is Map
        ? Map<String, dynamic>.from(m['semana'] as Map)
        : const <String, dynamic>{};
    List<Map<String, dynamic>> l(dynamic v) => v is List
        ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : const [];
    return CasaGanhos(
      inicio: _d(s['inicio']),
      fim: _d(s['fim']),
      trabalhos: _i(s['trabalhos']),
      brutoCents: _i(s['bruto_cents']),
      comissaoCents: _i(s['comissao_cents']),
      ganhoCents: _i(s['ganho_cents']),
      recebidoEmMaoCents: _i(s['recebido_em_mao_cents']),
      aReceberCents: _i(s['a_receber_cents']),
      acertos: l(m['acertos']).map(CasaAcerto.fromJson).toList(),
      lista: l(m['trabalhos']).map(CasaTrabalhoPago.fromJson).toList(),
    );
  }
}

Map<String, dynamic>? _mapaOuNulo(dynamic res) {
  if (res is Map) return Map<String, dynamic>.from(res);
  if (res is List && res.isNotEmpty && res.first is Map) {
    return Map<String, dynamic>.from(res.first as Map);
  }
  return null;
}

List<Map<String, dynamic>> _listaDeMapas(dynamic res) => res is List
    ? res.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : const [];
