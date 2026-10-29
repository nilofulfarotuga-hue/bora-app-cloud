import 'package:flutter/foundation.dart';

import 'definicoes_publicas.dart';

/// Interruptores do painel admin que ligam e desligam funções novas das apps
/// (adendo 4 e paridade, 29/10/2026). Todos vivem em `platform_settings` e
/// nenhum mexe em valores cobrados ou pagos.
///
/// A leitura passa por [lerDefinicoesPublicas] (tabela com sessão, `get_setting`
/// sem sessão). Se a leitura falhar, vale o valor de recurso de cada chave:
/// as funções simples ficam ligadas, as que dependem de IA ficam desligadas.
///
/// Cache de 2 minutos: o admin liga ou desliga e a app apanha logo a seguir.
class InterruptoresApp {
  InterruptoresApp._();
  static final InterruptoresApp instance = InterruptoresApp._();

  // Paridade pequena (chaves da página paridade-mundo).
  static const talheres = 'ask_cutlery';
  static const troco = 'ask_cash_change';
  static const detalhesMorada = 'ask_address_details';
  static const juntarMais = 'cart_add_more_strip';

  // Adendo 4.
  static const barraPedidoAtivo = 'feature_barra_pedido_ativo';
  static const fotoEntregaCliente = 'feature_foto_entrega_cliente';
  static const esgotadoAviso = 'feature_esgotado_aviso_cliente';
  static const esgotadoMinutos = 'feature_esgotado_minutos';
  static const habituaisHome = 'feature_habituais_home';
  static const avaliacaoComFoto = 'feature_avaliacao_com_foto';
  static const etiquetasMenu = 'feature_etiquetas_menu';
  static const etiquetasMenuIa = 'feature_etiquetas_menu_ia';
  static const resumoAvaliacoesIa = 'feature_resumo_avaliacoes_ia';
  static const funilPratos = 'feature_funil_pratos';
  static const ofertaGanhoVisivel = 'feature_oferta_ganho_visivel';
  static const mapaProcuraEstafeta = 'feature_mapa_procura_estafeta';

  // C6 (29/10/2026): modo ocupado do parceiro (+10 / +20 / +30 min). Nasce
  // DESLIGADO: sem resposta do servidor a app comporta-se como se não existisse.
  static const modoOcupadoParceiro = 'partner_busy_mode_enabled';

  /// Valor de recurso quando o servidor não responde.
  static const Map<String, Object> _recurso = <String, Object>{
    talheres: true,
    troco: true,
    detalhesMorada: true,
    juntarMais: true,
    barraPedidoAtivo: true,
    fotoEntregaCliente: true,
    esgotadoAviso: true,
    esgotadoMinutos: 10,
    habituaisHome: true,
    avaliacaoComFoto: true,
    etiquetasMenu: true,
    etiquetasMenuIa: false,
    resumoAvaliacoesIa: false,
    funilPratos: true,
    ofertaGanhoVisivel: true,
    mapaProcuraEstafeta: true,
    modoOcupadoParceiro: false,
  };

  final Map<String, Object?> _cache = <String, Object?>{};
  DateTime? _lidoEm;
  Future<void>? _aLer;

  /// Só para testes: fixa valores sem ir ao servidor.
  @visibleForTesting
  void definirParaTeste(Map<String, Object?> valores) {
    _cache
      ..clear()
      ..addAll(valores);
    _lidoEm = DateTime.now();
    _aLer = null;
  }

  @visibleForTesting
  void esquecer() {
    _cache.clear();
    _lidoEm = null;
    _aLer = null;
  }

  bool get _fresco =>
      _lidoEm != null && DateTime.now().difference(_lidoEm!).inMinutes < 2;

  Future<void> _garantir() {
    if (_fresco) return Future<void>.value();
    return _aLer ??= _ler().whenComplete(() => _aLer = null);
  }

  Future<void> _ler() async {
    try {
      final lido = await lerDefinicoesPublicas(_recurso.keys.toList());
      _cache
        ..clear()
        ..addAll(lido);
      // Só conta como lido se veio alguma coisa: mapa vazio = sem rede, volta
      // a tentar na próxima.
      if (lido.isNotEmpty) _lidoEm = DateTime.now();
    } catch (e) {
      debugPrint('[InterruptoresApp] leitura falhou: $e');
    }
  }

  static bool _comoBool(Object? v, bool recurso) {
    if (v is bool) return v;
    if (v is String) {
      final s = v.replaceAll('"', '').trim().toLowerCase();
      if (s == 'true') return true;
      if (s == 'false') return false;
    }
    return recurso;
  }

  static int _comoInt(Object? v, int recurso) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.replaceAll('"', '').trim()) ?? recurso;
    return recurso;
  }

  /// A função [chave] está ligada? Nunca lança.
  Future<bool> ligado(String chave) async {
    await _garantir();
    final recurso = (_recurso[chave] as bool?) ?? true;
    return _comoBool(_cache[chave], recurso);
  }

  /// Valor inteiro de [chave] (minutos, por exemplo). Nunca lança.
  Future<int> inteiro(String chave) async {
    await _garantir();
    final recurso = (_recurso[chave] as int?) ?? 0;
    return _comoInt(_cache[chave], recurso);
  }
}
