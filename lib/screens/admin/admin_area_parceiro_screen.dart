// ÁREA DO PARCEIRO — painel admin (PT-BR). 15/11/2026, missão
// painel-admin-15-11 (ordem do Danilo): o admin escolhe uma loja e faz por
// ela o que o parceiro faz na app dele, com cada ação registrada no log de
// auditoria.
//
// Um ecrã só, seis cartões, cada um com uma frase a dizer para que serve:
//   1 Loja agora · 2 Pedidos da loja agora · 3 Menu · 4 Dinheiro da semana
//   (só leitura) · 5 Reservas e marcações · 6 Histórico do admin nesta loja.
//
// Todas as chamadas ao servidor deste ecrã passam por AdminAreaParceiroService
// (o teste troca-o por um falso). As peças do painel que já existem e são
// reaproveitadas (escolher a loja, cancelar pedido, escolher entregador, ficha
// da loja, lista de reservas e o ecrã "Chamar estafeta" da loja) seguem os
// caminhos delas, já provados; o "entregue sem código" passa pelo serviço.
//
// Cada ação que muda alguma coisa pede confirmação com motivo (mínimo 3
// letras). O que o parceiro faz e o servidor ainda não deixa o admin fazer
// (aceitar, recusar, marcar pronto, retirada no balcão, falta de item, decidir
// reservas) aparece desligado com a frase kAreaParceiroFraseFuncaoNova.
//
// Dinheiro: só leitura, nenhum botão de pagamento. Preços: na ficha da loja.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/admin/admin_order_service.dart' show AdminCancelOrderResult;
import '../../services/admin_area_parceiro_service.dart';
import '../../services/modo_ocupado_service.dart' show kMinutosOcupado;
import '../../stores/restaurant_store.dart' show RestaurantStore;
import '../../utils/euros.dart' as euros;
import '../../utils/hora_lisboa.dart' show dataHoraLisboa, horaLisboa;
import '../../utils/ofertas_em_palavras.dart' show forcarChamadaEmPalavras;
import '../../widgets/admin/admin_entregue_sem_codigo_button.dart'
    show AdminEntregueSemCodigoButton;
import '../../widgets/admin/escolher_estafeta_sheet.dart'
    show escolherEstafetaParaPedido;
import '../../widgets/bora/bora_screen_app_bar.dart';
import '../partner_call_driver_screen.dart' show PartnerCallDriverScreen;
import '_admin_cancel_order_dialog.dart' show AdminCancelOrderDialog;
import '_admin_rpc_errors.dart' show humanizeAdminRpcError;
import 'admin_opcoes_produto_screen.dart' show AdminEscolherLoja;
import 'admin_partner_detail_screen.dart' show AdminPartnerDetailScreen;
import 'admin_reservations_screen.dart' show AdminReservationsScreen;

/// Frase dos botões que o servidor ainda não deixa o admin usar.
const String kAreaParceiroFraseFuncaoNova =
    'Precisa de uma função nova no servidor (proposta enviada)';

/// O que o ecrã diz quando ainda não há loja escolhida.
const String kAreaParceiroEscolhaLoja =
    'Escolha a loja para agir por ela, como o parceiro faz no app dele.';

/// As seis secções: chave, título e a frase do que cada uma serve.
const List<(String, String, String)> kAreaParceiroSecoes =
    <(String, String, String)>[
  (
    'loja',
    'Loja agora',
    'Para ver se a loja está aberta e abrir, fechar, pausar ou mudar o modo '
        'ocupado no lugar do parceiro.',
  ),
  (
    'pedidos',
    'Pedidos da loja agora',
    'Para acompanhar os pedidos em curso desta loja e agir neles quando o '
        'parceiro não consegue.',
  ),
  (
    'menu',
    'Menu',
    'Para marcar produtos como disponíveis ou esgotados; preços, categorias e '
        'fotos ficam na ficha da loja.',
  ),
  (
    'dinheiro',
    'Dinheiro da semana',
    'Para ver, só para leitura, quanto a loja vendeu esta semana e o que fica '
        'para ela; aqui não se paga nada.',
  ),
  (
    'reservas',
    'Reservas e marcações',
    'Para ver quantas reservas de mesa a loja tem e abrir a lista completa.',
  ),
  (
    'historico',
    'Histórico do admin nesta loja',
    'Para ver o que os admins já fizeram nesta loja, do mais recente para o '
        'mais antigo.',
  ),
];

/// Estados em que o admin pode escolher (ou reservar) o entregador.
const Set<String> _kEstadosEscolher = <String>{
  'created',
  'preparing',
  'callingDriver',
  'driverAccepted',
};

/// Quantas linhas do extrato se mostram aqui (o resto fica no menu Extratos).
const int _kMaxLinhasExtrato = 10;

String _dd(int n) => n.toString().padLeft(2, '0');

/// "14:05" em hora de Lisboa; "—" se não houver hora.
String _hora(DateTime? d) {
  if (d == null) return '—';
  final l = horaLisboa(d);
  return '${_dd(l.hour)}:${_dd(l.minute)}';
}

/// "15/11" em hora de Lisboa; "—" se não houver data.
String _dia(DateTime? d) {
  if (d == null) return '—';
  final l = horaLisboa(d);
  return '${_dd(l.day)}/${_dd(l.month)}';
}

String _cents(int? c) => c == null ? '—' : euros.eurCents(c);

/// Erro do servidor em palavras simples (PT-BR).
String _erroLegivel(Object e) {
  if (e is TimeoutException) {
    return 'O servidor demorou a responder. Tente de novo.';
  }
  if (e is AreaParceiroErro) return e.mensagem;
  if (e is PostgrestException) {
    final m = e.message;
    if (m.contains('reason required')) return 'Escreva o motivo (mínimo 3 letras).';
    if (m.contains('restaurant not found')) return 'Loja não encontrada.';
    if (m.contains('product not found')) return 'Produto não encontrado.';
    if (m.contains('ends_at must be future')) {
      return 'A hora do fim tem de ser no futuro.';
    }
    if (m.contains('invalid state')) return 'Estado inválido (só abrir ou fechar).';
    if (m.contains('forbidden') || m.contains('so_admin')) {
      return 'Sem permissão de administrador.';
    }
  }
  return humanizeAdminRpcError(e);
}

class AdminAreaParceiroScreen extends StatefulWidget {
  const AdminAreaParceiroScreen({
    super.key,
    this.restaurantId,
    this.service,
    this.agora,
  });

  /// Loja já escolhida (restaurants.id é TEXT). Sem isto, começa pela escolha.
  final String? restaurantId;

  /// Só para testes: troca o servidor por um falso.
  final AdminAreaParceiroService? service;

  /// Só para testes: relógio fixo.
  final DateTime Function()? agora;

  @override
  State<AdminAreaParceiroScreen> createState() => _AdminAreaParceiroScreenState();
}

class _AdminAreaParceiroScreenState extends State<AdminAreaParceiroScreen> {
  late final AdminAreaParceiroService _api =
      widget.service ?? SupabaseAdminAreaParceiroService();
  final TextEditingController _procurar = TextEditingController();

  String? _lojaId;

  /// Sobe a cada carga ou troca de loja: respostas antigas são ignoradas.
  int _geracao = 0;

  LojaAgora? _loja;
  String? _erroLoja;
  bool _aCarregarLoja = false;

  List<PedidoDaLoja> _pedidos = const <PedidoDaLoja>[];
  Map<String, int> _recebeCents = const <String, int>{};
  Set<String> _telefone = const <String>{};
  String? _erroPedidos;
  bool _aCarregarPedidos = false;

  List<ProdutoDoMenu> _menu = const <ProdutoDoMenu>[];
  String? _erroMenu;
  bool _aCarregarMenu = false;

  DinheiroDaSemana? _dinheiro;
  String? _erroDinheiro;
  bool _aCarregarDinheiro = false;

  ResumoReservas? _reservas;
  String? _erroReservas;
  bool _aCarregarReservas = false;

  List<AcaoDoAdmin> _historico = const <AcaoDoAdmin>[];
  String? _erroHistorico;
  bool _aCarregarHistorico = false;

  /// Ações em curso, uma chave por botão: cada botão trava pelo SEU pedido
  /// (PADRAO_BORA 3.13), nunca por um estado global.
  final Set<String> _aCorrer = <String>{};

  DateTime _agora() => widget.agora?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    final id = widget.restaurantId?.trim();
    if (id != null && id.isNotEmpty) {
      _lojaId = id;
      unawaited(_carregarTudo());
    }
  }

  @override
  void dispose() {
    _procurar.dispose();
    super.dispose();
  }

  // ─── Cargas ───────────────────────────────────────────────────────────────

  bool _vale(String id, int g) => mounted && g == _geracao && id == _lojaId;

  Future<void> _carregarTudo() async {
    final id = _lojaId;
    if (id == null) return;
    final g = ++_geracao;
    setState(() {
      _aCarregarLoja = _aCarregarPedidos = _aCarregarMenu =
          _aCarregarDinheiro = _aCarregarReservas = _aCarregarHistorico = true;
    });
    await _carregarLoja(id, g);
    if (!_vale(id, g)) return;
    await Future.wait<void>(<Future<void>>[
      _carregarPedidos(id, g),
      _carregarMenu(id, g),
      _carregarDinheiro(id, g),
      _carregarReservas(id, g),
      _carregarHistorico(id, g),
    ]);
  }

  Future<void> _recarregar(Future<void> Function(String id, int g) carregar) async {
    final id = _lojaId;
    if (id == null) return;
    await carregar(id, _geracao);
  }

  Future<void> _recarregarLojaEHistorico() async {
    final id = _lojaId;
    if (id == null) return;
    final g = _geracao;
    await Future.wait<void>(<Future<void>>[
      _carregarLoja(id, g),
      _carregarHistorico(id, g),
    ]);
  }

  Future<void> _recarregarPedidosEHistorico() async {
    final id = _lojaId;
    if (id == null) return;
    final g = _geracao;
    await Future.wait<void>(<Future<void>>[
      _carregarPedidos(id, g),
      _carregarHistorico(id, g),
    ]);
  }

  Future<void> _carregarLoja(String id, int g) async {
    if (!_vale(id, g)) return;
    setState(() {
      _aCarregarLoja = true;
      _erroLoja = null;
    });
    try {
      final l = await _api.lerLoja(id);
      if (!_vale(id, g)) return;
      setState(() {
        _loja = l;
        _aCarregarLoja = false;
      });
    } catch (e) {
      if (!_vale(id, g)) return;
      setState(() {
        _erroLoja = _erroLegivel(e);
        _aCarregarLoja = false;
      });
    }
  }

  Future<void> _carregarPedidos(String id, int g) async {
    if (!_vale(id, g)) return;
    final nome = _loja?.nome;
    if (nome == null) {
      setState(() {
        _pedidos = const <PedidoDaLoja>[];
        _aCarregarPedidos = false;
        _erroPedidos = 'Sem os dados da loja não dá para listar os pedidos.';
      });
      return;
    }
    setState(() {
      _aCarregarPedidos = true;
      _erroPedidos = null;
    });
    try {
      final lista = await _api.pedidosAgora(nomeLoja: nome);
      var recebe = const <String, int>{};
      var telefone = const <String>{};
      try {
        recebe = await _api.lojaRecebeCents(<String>[for (final p in lista) p.id]);
      } catch (e) {
        debugPrint('[AreaParceiro] loja recebe: $e');
      }
      try {
        telefone = await _api.encomendasPorTelefoneAbertas(id);
      } catch (e) {
        debugPrint('[AreaParceiro] encomendas por telefone: $e');
      }
      if (!_vale(id, g)) return;
      setState(() {
        _pedidos = lista;
        _recebeCents = recebe;
        _telefone = telefone;
        _aCarregarPedidos = false;
      });
    } catch (e) {
      if (!_vale(id, g)) return;
      setState(() {
        _erroPedidos = _erroLegivel(e);
        _aCarregarPedidos = false;
      });
    }
  }

  Future<void> _carregarMenu(String id, int g) async {
    if (!_vale(id, g)) return;
    setState(() {
      _aCarregarMenu = true;
      _erroMenu = null;
    });
    try {
      final lista = await _api.menu(id, procurar: _procurar.text);
      if (!_vale(id, g)) return;
      setState(() {
        _menu = lista;
        _aCarregarMenu = false;
      });
    } catch (e) {
      if (!_vale(id, g)) return;
      setState(() {
        _erroMenu = _erroLegivel(e);
        _aCarregarMenu = false;
      });
    }
  }

  Future<void> _carregarDinheiro(String id, int g) async {
    if (!_vale(id, g)) return;
    setState(() {
      _aCarregarDinheiro = true;
      _erroDinheiro = null;
    });
    try {
      final d = await _api.dinheiroDaSemana(id);
      if (!_vale(id, g)) return;
      setState(() {
        _dinheiro = d;
        _aCarregarDinheiro = false;
      });
    } catch (e) {
      if (!_vale(id, g)) return;
      setState(() {
        _erroDinheiro = _erroLegivel(e);
        _aCarregarDinheiro = false;
      });
    }
  }

  Future<void> _carregarReservas(String id, int g) async {
    if (!_vale(id, g)) return;
    setState(() {
      _aCarregarReservas = true;
      _erroReservas = null;
    });
    try {
      final r = await _api.reservas(id, agora: _agora());
      if (!_vale(id, g)) return;
      setState(() {
        _reservas = r;
        _aCarregarReservas = false;
      });
    } catch (e) {
      if (!_vale(id, g)) return;
      setState(() {
        _erroReservas = _erroLegivel(e);
        _aCarregarReservas = false;
      });
    }
  }

  Future<void> _carregarHistorico(String id, int g) async {
    if (!_vale(id, g)) return;
    setState(() {
      _aCarregarHistorico = true;
      _erroHistorico = null;
    });
    try {
      final h = await _api.historico(id);
      if (!_vale(id, g)) return;
      setState(() {
        _historico = h;
        _aCarregarHistorico = false;
      });
    } catch (e) {
      if (!_vale(id, g)) return;
      setState(() {
        _erroHistorico = _erroLegivel(e);
        _aCarregarHistorico = false;
      });
    }
  }

  void _escolherLoja(String? id) {
    final limpo = id?.trim();
    if (limpo == null || limpo.isEmpty) return;
    setState(() => _lojaId = limpo);
    unawaited(_carregarTudo());
  }

  void _trocarLoja() {
    setState(() {
      _geracao++;
      _lojaId = null;
      _loja = null;
      _pedidos = const <PedidoDaLoja>[];
      _recebeCents = const <String, int>{};
      _telefone = const <String>{};
      _menu = const <ProdutoDoMenu>[];
      _dinheiro = null;
      _reservas = null;
      _historico = const <AcaoDoAdmin>[];
      _erroLoja = _erroPedidos =
          _erroMenu = _erroDinheiro = _erroReservas = _erroHistorico = null;
      _aCarregarLoja = _aCarregarPedidos = _aCarregarMenu =
          _aCarregarDinheiro = _aCarregarReservas = _aCarregarHistorico = false;
      _aCorrer.clear();
      _procurar.clear();
    });
  }

  // ─── Ações (todas com motivo) ─────────────────────────────────────────────

  void _msg(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(texto),
        backgroundColor: erro ? AppColors.error : null,
      ));
  }

  /// Corre uma ação com o botão dela travado; erros viram SnackBar PT-BR.
  Future<void> _correr(String chave, Future<void> Function() acao) async {
    if (_aCorrer.contains(chave)) return;
    setState(() => _aCorrer.add(chave));
    try {
      await acao();
    } catch (e) {
      _msg(_erroLegivel(e), erro: true);
    } finally {
      if (mounted) setState(() => _aCorrer.remove(chave));
    }
  }

  bool _pedidoOcupado(String pedidoId) =>
      _aCorrer.any((k) => k.startsWith('pedido:') && k.endsWith(':$pedidoId'));

  /// Linha `area_parceiro_<acao>` no log de auditoria, com a loja como entidade.
  Future<void> _registar(String acao, Map<String, dynamic> detalhes) async {
    final id = _lojaId;
    if (id == null) return;
    final ok = await _api.registarAuditoria(
      acao: acao,
      restaurantId: id,
      detalhes: detalhes,
    );
    if (!ok) {
      _msg('Feito, mas não consegui gravar no log de auditoria.', erro: true);
    }
  }

  Future<_RespostaMotivo?> _pedirMotivo({
    required String titulo,
    required String explicacao,
    String confirmar = 'Confirmar',
    List<(String, int)> opcoes = const <(String, int)>[],
    String? perguntaOpcoes,
  }) async {
    if (!mounted) return null;
    return showDialog<_RespostaMotivo>(
      context: context,
      builder: (_) => _MotivoDialog(
        titulo: titulo,
        explicacao: explicacao,
        confirmar: confirmar,
        opcoes: opcoes,
        perguntaOpcoes: perguntaOpcoes,
      ),
    );
  }

  Future<void> _forcar({required bool abrir}) async {
    final id = _lojaId;
    if (id == null) return;
    final r = await _pedirMotivo(
      titulo: abrir ? 'Forçar ABRIR a loja' : 'Forçar FECHAR a loja',
      explicacao: abrir
          ? 'A loja fica aberta para os clientes mesmo fora do horário. O '
              'parceiro recebe um aviso.'
          : 'A loja deixa de receber pedidos. O parceiro recebe um aviso com o '
              'motivo.',
      confirmar: abrir ? 'Forçar abrir' : 'Forçar fechar',
      perguntaOpcoes: 'Por quanto tempo?',
      opcoes: const <(String, int)>[
        ('1 hora', 60),
        ('2 horas', 120),
        ('4 horas', 240),
        ('Sem limite', 0),
      ],
    );
    if (r == null) return;
    await _correr('forcar', () async {
      final minutos = r.opcao ?? 0;
      final ate = minutos > 0 ? _agora().add(Duration(minutes: minutos)) : null;
      final res = await _api.forcarEstado(id,
          abrir: abrir, motivo: r.motivo, ate: ate);
      if (res['success'] == true) {
        // O servidor já grava partner_status_override_set com o motivo e a loja.
        _msg(abrir ? 'Loja aberta à força.' : 'Loja fechada à força.');
        await _recarregarLojaEHistorico();
      } else {
        _msg('Não foi possível: ${res['error'] ?? 'resposta inesperada do servidor'}.',
            erro: true);
      }
    });
  }

  Future<void> _voltarAoHorario() async {
    final id = _lojaId;
    if (id == null) return;
    final r = await _pedirMotivo(
      titulo: 'Voltar ao horário normal',
      explicacao: 'Tira o abrir/fechar à força: a loja volta a abrir e fechar '
          'pelo horário dela.',
      confirmar: 'Voltar ao horário',
    );
    if (r == null) return;
    await _correr('horario', () async {
      final res = await _api.voltarAoHorario(id);
      if (res['success'] == true) {
        await _registar(AcoesAreaParceiro.voltarAoHorario, <String, dynamic>{
          'motivo': r.motivo,
          'desfeitos': res['cleared_count'],
        });
        _msg('A loja voltou ao horário normal.');
        await _recarregarLojaEHistorico();
      } else {
        _msg('Não foi possível: ${res['error'] ?? 'resposta inesperada do servidor'}.',
            erro: true);
      }
    });
  }

  Future<void> _pausar() async {
    final id = _lojaId;
    if (id == null) return;
    final r = await _pedirMotivo(
      titulo: 'Pausar a loja',
      explicacao: 'Os clientes veem "Fechada temporariamente" e não fazem '
          'pedidos. A loja volta sozinha.',
      confirmar: 'Pausar',
      perguntaOpcoes: 'Por quanto tempo?',
      opcoes: const <(String, int)>[
        ('15 minutos', 15),
        ('30 minutos', 30),
        ('60 minutos', 60),
        ('Até fechar hoje', -1),
      ],
    );
    if (r == null) return;
    final minutos = r.opcao ?? 15;
    await _correr('pausa', () async {
      final res = await _api.pausarLoja(id, minutos);
      if (res['ok'] == true) {
        await _registar(AcoesAreaParceiro.pausar, <String, dynamic>{
          'motivo': r.motivo,
          'minutos': minutos,
          'volta_as': res['volta_as'],
        });
        _msg('Loja em pausa até às ${res['volta_as'] ?? '—'}. Volta sozinha.');
        await _recarregarLojaEHistorico();
      } else {
        _msg(respostaLojaEmPalavras(res), erro: true);
      }
    });
  }

  Future<void> _tirarPausa() async {
    final id = _lojaId;
    if (id == null) return;
    final r = await _pedirMotivo(
      titulo: 'Tirar a pausa',
      explicacao: 'A loja volta já a receber pedidos (dentro do horário).',
      confirmar: 'Tirar a pausa',
    );
    if (r == null) return;
    await _correr('pausa', () async {
      final res = await _api.pausarLoja(id, 0);
      if (res['ok'] == true) {
        await _registar(AcoesAreaParceiro.tirarPausa,
            <String, dynamic>{'motivo': r.motivo});
        _msg('A loja voltou a receber pedidos.');
        await _recarregarLojaEHistorico();
      } else {
        _msg(respostaLojaEmPalavras(res), erro: true);
      }
    });
  }

  Future<void> _ligarOcupado() async {
    final id = _lojaId;
    if (id == null) return;
    final r = await _pedirMotivo(
      titulo: 'Ligar modo ocupado',
      explicacao: 'Durante 2 horas os clientes veem um tempo de entrega maior '
          'nesta loja. Não muda nenhum preço.',
      confirmar: 'Ligar',
      perguntaOpcoes: 'Quantos minutos a mais?',
      opcoes: <(String, int)>[for (final m in kMinutosOcupado) ('+$m min', m)],
    );
    if (r == null) return;
    final minutos = r.opcao ?? kMinutosOcupado.first;
    await _correr('ocupado', () async {
      final res = await _api.ligarModoOcupado(id, minutos);
      if (res['ok'] == true) {
        await _registar(AcoesAreaParceiro.ligarModoOcupado, <String, dynamic>{
          'motivo': r.motivo,
          'minutos': minutos,
          'ate_as': res['ate_as'],
        });
        _msg('Modo ocupado ligado: +$minutos min até às ${res['ate_as'] ?? '—'}.');
        await _recarregarLojaEHistorico();
      } else {
        _msg(respostaLojaEmPalavras(res), erro: true);
      }
    });
  }

  Future<void> _desligarOcupado() async {
    final id = _lojaId;
    if (id == null) return;
    final antes = _loja?.ocupadoMinutos;
    final r = await _pedirMotivo(
      titulo: 'Desligar modo ocupado',
      explicacao: 'Os clientes voltam a ver o tempo de entrega normal desta loja.',
      confirmar: 'Desligar',
    );
    if (r == null) return;
    await _correr('ocupado', () async {
      final res = await _api.desligarModoOcupado(id);
      if (res['ok'] == true) {
        // O servidor grava partner_busy_desligado sem o motivo: grava-se aqui.
        await _registar(AcoesAreaParceiro.desligarModoOcupado, <String, dynamic>{
          'motivo': r.motivo,
          'minutos_antes': antes,
        });
        _msg('Modo ocupado desligado.');
        await _recarregarLojaEHistorico();
      } else {
        _msg(respostaLojaEmPalavras(res), erro: true);
      }
    });
  }

  Future<void> _mudarDisponivel(ProdutoDoMenu p, bool disponivel) async {
    final r = await _pedirMotivo(
      titulo: disponivel
          ? 'Deixar "${p.nome}" disponível'
          : 'Marcar "${p.nome}" como esgotado',
      explicacao: disponivel
          ? 'O produto volta a aparecer para os clientes.'
          : 'Os clientes deixam de poder pedir este produto até alguém o ligar '
              'de novo.',
      confirmar: disponivel ? 'Deixar disponível' : 'Marcar esgotado',
    );
    if (r == null) return;
    await _correr('produto:${p.id}', () async {
      final res = await _api.definirDisponivel(p.id,
          disponivel: disponivel, motivo: r.motivo);
      if (res['success'] == true || res['ok'] == true) {
        // O servidor já grava product_activate/product_deactivate com o motivo
        // e a loja (details.restaurant_id): não se grava outra linha aqui.
        if (!mounted) return;
        setState(() {
          _menu = <ProdutoDoMenu>[
            for (final x in _menu) x.id == p.id ? x.comDisponivel(disponivel) : x,
          ];
        });
        _msg(disponivel
            ? 'Produto disponível de novo.'
            : 'Produto marcado como esgotado.');
        unawaited(_recarregar(_carregarHistorico));
      } else {
        _msg('Não foi possível: ${res['error'] ?? 'resposta inesperada do servidor'}.',
            erro: true);
      }
    });
  }

  Future<void> _escolherEntregador(PedidoDaLoja p) async {
    final r = await _pedirMotivo(
      titulo: 'Escolher entregador para ${p.codigo}',
      explicacao: 'A seguir escolha o entregador. Se o pedido ainda não estiver '
          'pronto, fica reservado para ele.',
      confirmar: 'Continuar',
    );
    if (r == null) return;
    await _correr('pedido:escolher:${p.id}', () async {
      if (!mounted) return;
      final feito = await escolherEstafetaParaPedido(context,
          orderId: p.id, status: p.status);
      if (!feito) return;
      await _registar(AcoesAreaParceiro.escolherEntregador, <String, dynamic>{
        'motivo': r.motivo,
        'order_id': p.id,
      });
      await _recarregarPedidosEHistorico();
    });
  }

  Future<void> _chamarJa(PedidoDaLoja p) async {
    final r = await _pedirMotivo(
      titulo: 'Chamar entregador já: ${p.codigo}',
      explicacao: 'Encomenda feita por telefone: o pedido passa já a chamar '
          'entregador, sem esperar pela loja.',
      confirmar: 'Chamar já',
    );
    if (r == null) return;
    await _correr('pedido:chamar:${p.id}', () async {
      final res = await _api.chamarEntregadorJa(p.id);
      if (res['ok'] == true) {
        await _registar(AcoesAreaParceiro.chamarEntregadorJa, <String, dynamic>{
          'motivo': r.motivo,
          'order_id': p.id,
        });
        _msg(chamarJaEmPalavras(res));
        await _recarregarPedidosEHistorico();
      } else {
        _msg(chamarJaEmPalavras(res), erro: true);
      }
    });
  }

  Future<void> _forcarChamada(PedidoDaLoja p) async {
    final r = await _pedirMotivo(
      titulo: 'Forçar chamada: ${p.codigo}',
      explicacao: 'Toca já no celular do próximo entregador da lista de reforço '
          '(quem aceitou chamadas de reforço).',
      confirmar: 'Forçar chamada',
    );
    if (r == null) return;
    await _correr('pedido:forcar:${p.id}', () async {
      final res = await _api.forcarChamada(p.id);
      final ok = res['ok'] == true;
      if (ok) {
        await _registar(AcoesAreaParceiro.forcarChamada, <String, dynamic>{
          'motivo': r.motivo,
          'order_id': p.id,
          'entregador': res['nome'],
        });
      }
      _msg(forcarChamadaEmPalavras(res), erro: !ok);
      if (ok) await _recarregarPedidosEHistorico();
    });
  }

  Future<void> _horaPronto(PedidoDaLoja p) async {
    final r = await _pedirMotivo(
      titulo: 'Prometer hora de pronto: ${p.codigo}',
      explicacao: 'O cliente e o entregador passam a ver a hora em que a loja '
          'diz que o pedido fica pronto.',
      confirmar: 'Gravar',
      perguntaOpcoes: 'Fica pronto daqui a:',
      opcoes: const <(String, int)>[
        ('10 min', 10),
        ('20 min', 20),
        ('30 min', 30),
        ('45 min', 45),
        ('Tirar a hora', 0),
      ],
    );
    if (r == null) return;
    await _correr('pedido:pronto:${p.id}', () async {
      final minutos = r.opcao ?? 0;
      final hora = minutos > 0 ? _agora().add(Duration(minutes: minutos)) : null;
      final res = await _api.prometerHoraPronto(p.id, hora);
      if (res['ok'] == true) {
        await _registar(AcoesAreaParceiro.horaPronto, <String, dynamic>{
          'motivo': r.motivo,
          'order_id': p.id,
          'pronto_as': res['pronto_as'],
        });
        _msg(res['pronto_as'] == null
            ? 'Hora de pronto retirada.'
            : 'Fica pronto às ${res['pronto_as']}.');
        await _recarregarPedidosEHistorico();
      } else {
        _msg(respostaLojaEmPalavras(res), erro: true);
      }
    });
  }

  Future<void> _cancelar(PedidoDaLoja p) async {
    await _correr('pedido:cancelar:${p.id}', () async {
      if (!mounted) return;
      // O diálogo do painel pede a categoria e o motivo (mínimo 10 letras) e
      // cancela pelo caminho de sempre (admin_cancel_order, auditado no pedido).
      final res = await showDialog<AdminCancelOrderResult>(
        context: context,
        builder: (_) => AdminCancelOrderDialog(order: p.paraCancelar()),
      );
      if (res == null) return;
      await _registar(AcoesAreaParceiro.cancelarPedido, <String, dynamic>{
        'order_id': p.id,
        'resultado': res.summary,
        'estado_antes': res.previousStatus,
      });
      await _recarregarPedidosEHistorico();
    });
  }

  /// "Entregue sem código": o botão do painel pede o motivo (mínimo 5 letras);
  /// a chamada passa pelo serviço e fica também no histórico da loja.
  Future<Map<String, dynamic>> _entregueSemCodigo(
      String pedidoId, String motivo) async {
    final res = await _api.marcarEntregueSemCodigo(pedidoId, motivo);
    if (res['ok'] == true && res['ja_entregue'] != true) {
      await _registar(AcoesAreaParceiro.entregueSemCodigo, <String, dynamic>{
        'motivo': motivo,
        'order_id': pedidoId,
        'estado_antes': res['status_antes'],
      });
    }
    return res;
  }

  void _depoisDeEntregue() {
    unawaited(_recarregarPedidosEHistorico());
  }

  Future<void> _chamarComoLoja() async {
    final id = _lojaId;
    if (id == null) return;
    final r = await _pedirMotivo(
      titulo: 'Chamar entregador como a loja',
      explicacao: 'Abre a tela "Chamar estafeta" do app da loja, para um cliente '
          'que pediu no balcão ou por telefone. O pedido nasce já chamando '
          'entregador e o cliente paga em dinheiro na entrega.',
      confirmar: 'Abrir',
    );
    if (r == null) return;
    await _correr('balcao', () async {
      if (!mounted) return;
      final store = context.read<RestaurantStore>();
      var loja = store.restaurantById(id);
      if (loja == null) {
        await store.loadRestaurantsFromSupabase();
        loja = store.restaurantById(id);
      }
      if (!mounted) return;
      final encontrada = loja;
      if (encontrada == null) {
        _msg('Não consegui abrir: a loja não está carregada nesta sessão. '
            'Atualize a página e tente de novo.', erro: true);
        return;
      }
      final criado = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => PartnerCallDriverScreen(restaurant: encontrada),
        ),
      );
      if (criado != true) return;
      await _registar(AcoesAreaParceiro.chamarEntregadorBalcao,
          <String, dynamic>{'motivo': r.motivo});
      _msg('Pedido criado pela loja: já está chamando entregador.');
      await _recarregarPedidosEHistorico();
    });
  }

  void _abrirFicha({int aba = 0}) {
    final id = _lojaId;
    if (id == null) return;
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
          builder: (_) => AdminPartnerDetailScreen(
            restaurantId: id,
            initialName: _loja?.nome ?? id,
            abaInicial: aba,
          ),
        ))
        .then((_) {
      // A ficha pode ter mudado horário, preços ou fotos: lê-se tudo de novo.
      if (mounted && _lojaId == id) unawaited(_carregarTudo());
    });
  }

  void _abrirReservas() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const AdminReservationsScreen(),
    ));
  }

  // ─── Ecrã ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Área do parceiro',
        actions: [
          IconButton(
            key: const Key('area_atualizar_tudo'),
            tooltip: 'Atualizar tudo',
            onPressed: _lojaId == null ? null : _carregarTudo,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _lojaId == null ? _escolha() : _conteudo(),
    );
  }

  Widget _escolha() {
    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        const Text(
          kAreaParceiroEscolhaLoja,
          key: Key('area_escolha_texto'),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: Spacing.md),
        AdminEscolherLoja(onEscolhida: _escolherLoja),
      ],
    );
  }

  Widget _conteudo() {
    return RefreshIndicator(
      onRefresh: _carregarTudo,
      child: SingleChildScrollView(
        key: const Key('area_rolagem'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xxxl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _cabecalho(),
                _secaoLoja(),
                _secaoPedidos(),
                _secaoMenu(),
                _secaoDinheiro(),
                _secaoReservas(),
                _secaoHistorico(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cabecalho() {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _loja?.nome ?? _lojaId ?? '',
                  key: const Key('area_nome_loja'),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: Spacing.xxs),
                const Text(
                  'Você está agindo por esta loja. Cada mudança pede um motivo e '
                  'fica no log de auditoria.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          TextButton.icon(
            key: const Key('area_trocar_loja'),
            onPressed: _trocarLoja,
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Trocar loja'),
          ),
        ],
      ),
    );
  }

  // 1 ─ Loja agora
  Widget _secaoLoja() {
    final l = _loja;
    final Widget corpo;
    if (l == null) {
      corpo = _aCarregarLoja
          ? const _Carregando()
          : _Erro(_erroLoja ?? 'Não consegui ler a loja.',
              aoTentar: () => _recarregar(_carregarLoja));
    } else {
      final agora = _agora();
      corpo = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _estadoGrande(l),
          const SizedBox(height: Spacing.xs),
          ..._linhasDaLoja(l, agora),
          const SizedBox(height: Spacing.md),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              FilledButton.icon(
                key: const Key('area_forcar_abrir'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                onPressed:
                    _aCorrer.contains('forcar') ? null : () => _forcar(abrir: true),
                icon: const Icon(Icons.lock_open),
                label: const Text('Forçar ABRIR'),
              ),
              FilledButton.icon(
                key: const Key('area_forcar_fechar'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed:
                    _aCorrer.contains('forcar') ? null : () => _forcar(abrir: false),
                icon: const Icon(Icons.lock_outline),
                label: const Text('Forçar FECHAR'),
              ),
              OutlinedButton.icon(
                key: const Key('area_voltar_horario'),
                onPressed: (!l.forcada || _aCorrer.contains('horario'))
                    ? null
                    : _voltarAoHorario,
                icon: const Icon(Icons.schedule),
                label: const Text('Voltar ao horário normal'),
              ),
              if (l.pausadaEm(agora))
                OutlinedButton.icon(
                  key: const Key('area_tirar_pausa'),
                  onPressed: _aCorrer.contains('pausa') ? null : _tirarPausa,
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Tirar a pausa'),
                )
              else
                OutlinedButton.icon(
                  key: const Key('area_pausar'),
                  onPressed: _aCorrer.contains('pausa') ? null : _pausar,
                  icon: const Icon(Icons.pause_circle_outline),
                  label: const Text('Pausar a loja'),
                ),
              if (l.ocupadaEm(agora))
                OutlinedButton.icon(
                  key: const Key('area_desligar_ocupado'),
                  onPressed: _aCorrer.contains('ocupado') ? null : _desligarOcupado,
                  icon: const Icon(Icons.timer_off_outlined),
                  label: const Text('Desligar modo ocupado'),
                )
              else
                OutlinedButton.icon(
                  key: const Key('area_ligar_ocupado'),
                  onPressed: _aCorrer.contains('ocupado') ? null : _ligarOcupado,
                  icon: const Icon(Icons.more_time),
                  label: const Text('Ligar modo ocupado'),
                ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          OutlinedButton.icon(
            key: const Key('area_abrir_ficha'),
            onPressed: () => _abrirFicha(),
            icon: const Icon(Icons.storefront_outlined),
            label: const Text('Abrir a ficha da loja (horário, dados, fotos, preços)'),
          ),
        ],
      );
    }
    return _Secao(chave: 'loja', icone: Icons.store_outlined, filho: corpo);
  }

  Widget _estadoGrande(LojaAgora l) {
    final (String texto, Color cor, IconData icone) = !l.estadoLido
        ? ('Não deu para ler se está aberta', AppColors.textSecondary, Icons.help_outline)
        : l.aberta
            ? (
                l.forcada ? 'ABERTA (forçada pelo admin)' : 'ABERTA agora',
                AppColors.success,
                Icons.check_circle,
              )
            : (
                l.forcada ? 'FECHADA (forçada pelo admin)' : 'FECHADA agora',
                AppColors.error,
                Icons.cancel,
              );
    return Row(
      children: [
        Icon(icone, color: cor, size: 28),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: Text(
            texto,
            key: const Key('area_estado_loja'),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cor),
          ),
        ),
      ],
    );
  }

  List<Widget> _linhasDaLoja(LojaAgora l, DateTime agora) {
    const pequeno = TextStyle(fontSize: 13, color: AppColors.textSecondary);
    Widget linha(String s, {Key? key, TextStyle estilo = pequeno}) => Padding(
          padding: const EdgeInsets.only(top: Spacing.xxs),
          child: Text(s, key: key, style: estilo),
        );
    final forcadaAte = l.forcadaAte;
    final abreDia = l.abreDia;
    return <Widget>[
      linha(l.parceira
          ? 'Loja parceira (tem o app do parceiro).'
          : 'Loja não parceira (não tem app de parceiro).'),
      if (!l.aprovada) linha('Cadastro: ${aprovacaoLojaPtBr(l.aprovacao)}.'),
      if (l.emBreve) linha('Aparece como "em breve" para os clientes.'),
      if (!l.online)
        linha(
          'A loja está desligada (offline): os clientes não conseguem pedir.',
          estilo: const TextStyle(
              fontSize: 13, color: AppColors.error, fontWeight: FontWeight.w600),
        ),
      if (l.forcada) ...[
        linha('Motivo do admin: ${l.motivoForcada ?? '—'}'),
        linha(forcadaAte == null
            ? 'Sem hora para acabar.'
            : 'Até ${dataHoraLisboa(forcadaAte.toIso8601String())}.'),
      ] else if (!l.aberta && l.abreAs != null)
        linha('Abre ${abreDia == null ? '' : '$abreDia '}às ${l.abreAs}.')
      else if (l.aberta && l.fechaEmMinutos != null)
        linha('Fecha daqui a ${l.fechaEmMinutos} min.'),
      if (l.pausadaEm(agora))
        linha('Em pausa até às ${_hora(l.pausadaAte)} (volta sozinha).',
            key: const Key('area_loja_pausada')),
      if (l.ocupadaEm(agora))
        linha(
          'Modo ocupado: +${l.ocupadoMinutos} min até às ${_hora(l.ocupadoAte)}.',
          key: const Key('area_loja_ocupada'),
          estilo: const TextStyle(
              fontSize: 13, color: AppColors.accent, fontWeight: FontWeight.w700),
        ),
      linha('Retirada no balcão ${l.retirada ? 'ligada' : 'desligada'} · reservas '
          'de mesa ${l.reservas ? 'ligadas' : 'desligadas'}.'),
    ];
  }

  // 2 ─ Pedidos da loja agora
  Widget _secaoPedidos() {
    final Widget corpo;
    if (_aCarregarPedidos && _pedidos.isEmpty) {
      corpo = const _Carregando();
    } else if (_erroPedidos != null && _pedidos.isEmpty) {
      corpo = _Erro(_erroPedidos!, aoTentar: () => _recarregar(_carregarPedidos));
    } else {
      corpo = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _pedidos.isEmpty
                ? 'Nenhum pedido em curso nesta loja agora.'
                : '${_pedidos.length} pedido(s) em curso.',
            key: const Key('area_pedidos_resumo'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: Spacing.xxs),
          const Text(
            'Lista tirada dos pedidos ao vivo do painel, pelo nome da loja. '
            'Pedidos de retirada já prontos, à espera do cliente, não aparecem.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          for (final p in _pedidos) _cartaoPedido(p),
          const SizedBox(height: Spacing.md),
          _chamarComoLojaBotao(),
        ],
      );
    }
    return _Secao(
      chave: 'pedidos',
      icone: Icons.receipt_long_outlined,
      filho: corpo,
      acoes: [
        IconButton(
          key: const Key('area_pedidos_atualizar'),
          tooltip: 'Atualizar pedidos',
          onPressed: () => _recarregar(_carregarPedidos),
          icon: const Icon(Icons.refresh, color: AppColors.primary),
        ),
      ],
    );
  }

  List<(String, String)> _pendentesDoPedido(PedidoDaLoja p) {
    switch (p.status) {
      case 'created':
        return <(String, String)>[
          ('area_pendente_aceitar_${p.id}', 'Aceitar pedido'),
          ('area_pendente_recusar_${p.id}', 'Recusar pedido'),
        ];
      case 'preparing':
        return <(String, String)>[
          (
            'area_pendente_pronto_${p.id}',
            p.retirada ? 'Pronto para retirada' : 'Marcar pronto',
          ),
          ('area_pendente_falta_${p.id}', 'Avisar falta de item'),
        ];
    }
    return const <(String, String)>[];
  }

  Widget _cartaoPedido(PedidoDaLoja p) {
    final recebe = _recebeCents[p.id];
    final ocupado = _pedidoOcupado(p.id);
    final pendentes = _pendentesDoPedido(p);
    final detalhe = <String>[
      if (p.cliente != null) 'Cliente: ${p.cliente}',
      'total ${euros.eur(p.total)}',
      if (recebe != null) 'a loja recebe ${euros.eurCents(recebe)}',
      if (p.criadoEm != null) 'feito às ${_hora(p.criadoEm)}',
      if (p.retirada)
        'retirada no balcão'
      else if (p.temEntregador)
        'com entregador'
      else
        'sem entregador',
    ].join(' · ');
    return Container(
      key: Key('area_pedido_${p.id}'),
      margin: const EdgeInsets.only(top: Spacing.sm),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${p.codigo} · ${estadoPedidoLojaPtBr(p.status)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (p.teste) const _Etiqueta('TESTE'),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          Text(detalhe,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.xs,
            children: [
              if (!p.retirada && _kEstadosEscolher.contains(p.status))
                OutlinedButton.icon(
                  key: Key('area_escolher_${p.id}'),
                  onPressed: ocupado ? null : () => _escolherEntregador(p),
                  icon: const Icon(Icons.person_search_outlined),
                  label: const Text('Escolher entregador'),
                ),
              if (p.status == 'preparing' && _telefone.contains(p.id))
                OutlinedButton.icon(
                  key: Key('area_chamar_ja_${p.id}'),
                  onPressed: ocupado ? null : () => _chamarJa(p),
                  icon: const Icon(Icons.campaign_outlined),
                  label: const Text('Chamar entregador já'),
                ),
              if (p.status == 'preparing' && !p.retirada)
                OutlinedButton.icon(
                  key: Key('area_hora_pronto_${p.id}'),
                  onPressed: ocupado ? null : () => _horaPronto(p),
                  icon: const Icon(Icons.alarm),
                  label: const Text('Prometer hora de pronto'),
                ),
              if (p.status == 'callingDriver' && !p.temEntregador)
                OutlinedButton.icon(
                  key: Key('area_forcar_chamada_${p.id}'),
                  onPressed: ocupado ? null : () => _forcarChamada(p),
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Forçar chamada'),
                ),
              OutlinedButton.icon(
                key: Key('area_cancelar_${p.id}'),
                onPressed: ocupado ? null : () => _cancelar(p),
                icon: const Icon(Icons.cancel_outlined, color: AppColors.error),
                label: const Text('Cancelar pedido'),
              ),
            ],
          ),
          AdminEntregueSemCodigoButton(
            orderId: p.id,
            status: p.status,
            onDone: _depoisDeEntregue,
            marcar: _entregueSemCodigo,
          ),
          if (pendentes.isNotEmpty) ...[
            const SizedBox(height: Spacing.sm),
            _Pendentes(itens: pendentes),
          ],
        ],
      ),
    );
  }

  Widget _chamarComoLojaBotao() {
    final l = _loja;
    final pode = l != null && l.parceira && l.aprovada;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          key: const Key('area_chamar_balcao'),
          onPressed: (!pode || _aCorrer.contains('balcao')) ? null : _chamarComoLoja,
          icon: const Icon(Icons.delivery_dining_outlined),
          label: const Text('Chamar entregador para um pedido feito na loja'),
        ),
        const SizedBox(height: Spacing.xxs),
        Text(
          pode
              ? 'Abre a tela "Chamar estafeta" do app da loja: o cliente pediu no '
                  'balcão ou por telefone e a loja quer entrega.'
              : 'Só para lojas parceiras aprovadas.',
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  // 3 ─ Menu
  Widget _secaoMenu() {
    return _Secao(
      chave: 'menu',
      icone: Icons.restaurant_menu,
      filho: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('area_menu_procurar'),
                  controller: _procurar,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _recarregar(_carregarMenu),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Procurar produto',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              IconButton(
                key: const Key('area_menu_procurar_botao'),
                tooltip: 'Procurar',
                onPressed: () => _recarregar(_carregarMenu),
                icon: const Icon(Icons.search, color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          if (_aCarregarMenu && _menu.isEmpty)
            const _Carregando()
          else if (_erroMenu != null && _menu.isEmpty)
            _Erro(_erroMenu!, aoTentar: () => _recarregar(_carregarMenu))
          else if (_menu.isEmpty)
            const Text('Nenhum produto encontrado.')
          else ...[
            Text(
              _menu.length >= kAreaParceiroMaxProdutos
                  ? '${_menu.length} produtos (mostra até $kAreaParceiroMaxProdutos; '
                      'use a pesquisa).'
                  : '${_menu.length} produto(s).',
              key: const Key('area_menu_resumo'),
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            for (final p in _menu) _linhaProduto(p),
          ],
          const SizedBox(height: Spacing.md),
          OutlinedButton.icon(
            key: const Key('area_menu_ficha'),
            onPressed: () => _abrirFicha(aba: 5),
            icon: const Icon(Icons.sell_outlined),
            label: const Text('Preços, categorias e fotos: abrir na ficha da loja'),
          ),
        ],
      ),
    );
  }

  Widget _linhaProduto(ProdutoDoMenu p) {
    final ocupado = _aCorrer.contains('produto:${p.id}');
    final preco = p.preco;
    final categoria = p.categoria;
    final detalhe = <String>[
      if (preco != null) euros.eur(preco),
      if (p.aoPeso) 'ao peso',
      if (categoria != null) categoria,
    ].join(' · ');
    return Padding(
      key: Key('area_produto_${p.id}'),
      padding: const EdgeInsets.only(top: Spacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (detalhe.isNotEmpty)
                  Text(detalhe,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Text(
            p.disponivel ? 'Disponível' : 'Esgotado',
            key: Key('area_menu_estado_${p.id}'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: p.disponivel ? AppColors.success : AppColors.error,
            ),
          ),
          Switch(
            key: Key('area_menu_switch_${p.id}'),
            value: p.disponivel,
            onChanged: ocupado ? null : (v) => _mudarDisponivel(p, v),
          ),
        ],
      ),
    );
  }

  // 4 ─ Dinheiro da semana (só leitura)
  Widget _secaoDinheiro() {
    final d = _dinheiro;
    final Widget corpo;
    if (d == null) {
      corpo = _aCarregarDinheiro
          ? const _Carregando()
          : _Erro(_erroDinheiro ?? 'Não consegui ler o dinheiro da loja.',
              aoTentar: () => _recarregar(_carregarDinheiro));
    } else {
      const negrito = TextStyle(fontWeight: FontWeight.w700);
      const pequeno = TextStyle(fontSize: 12, color: AppColors.textSecondary);
      corpo = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (d.semanaLida) ...[
            Text(
              d.inicio == null
                  ? 'Esta semana'
                  : 'Esta semana (${_dia(d.inicio)} a ${_dia(d.fim)})',
              style: negrito,
            ),
            _Valor('Pedidos', '${d.pedidos}'),
            _Valor('Vendas', euros.eur(d.vendas)),
            _Valor('Parte da Bora', euros.eur(d.parteBora)),
            _Valor('Fica para a loja', euros.eur(d.ficaParaLoja),
                destaque: true, chave: const Key('area_dinheiro_fica')),
            _Valor('Acerto da semana', _saldoTexto(d)),
          ] else
            const Text('Sem fecho desta semana para a loja.'),
          if (d.extratoLido) ...[
            const Divider(height: Spacing.xl),
            const Text(
              'Últimos $kAreaParceiroDiasExtrato dias, pedido a pedido',
              style: negrito,
            ),
            if (d.transferidoCents != null || d.porTransferirCents != null)
              Text(
                'Já transferido: ${_cents(d.transferidoCents)} · por transferir: '
                '${_cents(d.porTransferirCents)}',
                style: pequeno,
              ),
            if (d.linhas.isEmpty)
              const Text('Nenhum pedido nestes dias.')
            else
              for (final linha in d.linhas.take(_kMaxLinhasExtrato))
                _linhaExtrato(linha),
            if (d.linhas.length > _kMaxLinhasExtrato)
              Text(
                'E mais ${d.linhas.length - _kMaxLinhasExtrato} pedido(s): o '
                'extrato completo está no menu Extratos.',
                style: pequeno,
              ),
          ],
          if (d.aviso != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(d.aviso!,
                style: const TextStyle(fontSize: 12, color: AppColors.warning)),
          ],
          const SizedBox(height: Spacing.sm),
          const Text(
            'Só leitura: aqui não se paga nem se acerta nada.',
            key: Key('area_dinheiro_so_leitura'),
            style: pequeno,
          ),
          const SizedBox(height: Spacing.xs),
          OutlinedButton.icon(
            key: const Key('area_dinheiro_ficha'),
            onPressed: () => _abrirFicha(aba: 4),
            icon: const Icon(Icons.bar_chart),
            label: const Text('Ver vendas na ficha da loja'),
          ),
        ],
      );
    }
    return _Secao(chave: 'dinheiro', icone: Icons.payments_outlined, filho: corpo);
  }

  String _saldoTexto(DinheiroDaSemana d) {
    if (d.boraPagaALoja) return 'a Bora paga à loja ${euros.eur(d.saldo.abs())}';
    if (d.lojaPagaABora) return 'a loja entrega à Bora ${euros.eur(d.saldo.abs())}';
    return 'sem saldo esta semana';
  }

  Widget _linhaExtrato(LinhaDoExtrato l) {
    final partes = <String>[
      l.quando,
      if (l.cliente != null) l.cliente!,
      if (l.pagamento != null) l.pagamento!,
      if (l.clientePagouCents != null) 'cliente pagou ${_cents(l.clientePagouCents)}',
      if (l.parteBoraCents != null) 'parte da Bora ${_cents(l.parteBoraCents)}',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(partes.join(' · '),
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
          Text(_cents(l.ficaCents),
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: AppColors.primary)),
        ],
      ),
    );
  }

  // 5 ─ Reservas e marcações
  Widget _secaoReservas() {
    final r = _reservas;
    final l = _loja;
    return _Secao(
      chave: 'reservas',
      icone: Icons.event_seat_outlined,
      filho: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (l != null)
            Text(l.reservas
                ? 'Reservas de mesa ligadas nesta loja.'
                : 'Reservas de mesa desligadas nesta loja (liga-se na ficha, aba '
                    'Estado).'),
          const SizedBox(height: Spacing.xs),
          if (r == null && _aCarregarReservas)
            const _Carregando()
          else if (r == null)
            _Erro(_erroReservas ?? 'Não consegui ler as reservas.',
                aoTentar: () => _recarregar(_carregarReservas))
          else
            Text(
              'Hoje: ${r.hoje} · próximas: ${r.proximas} · por decidir: '
              '${r.porDecidir}',
              key: const Key('area_reservas_resumo'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          const SizedBox(height: Spacing.sm),
          OutlinedButton.icon(
            key: const Key('area_reservas_abrir'),
            onPressed: _abrirReservas,
            icon: const Icon(Icons.list_alt),
            label: const Text('Abrir a lista de reservas (todas as lojas)'),
          ),
          const SizedBox(height: Spacing.sm),
          const _Pendentes(itens: <(String, String)>[
            ('area_pendente_reserva', 'Aceitar ou recusar reserva como a loja'),
            ('area_pendente_chegada', 'Marcar chegada do cliente'),
          ]),
          const SizedBox(height: Spacing.sm),
          const Text(
            'Marcações (barbearias e serviços) são de prestadores, não de lojas: '
            'ficam no menu de Serviços.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  // 6 ─ Histórico do admin nesta loja
  Widget _secaoHistorico() {
    final Widget corpo;
    if (_aCarregarHistorico && _historico.isEmpty) {
      corpo = const _Carregando();
    } else if (_erroHistorico != null && _historico.isEmpty) {
      corpo = _Erro(_erroHistorico!,
          aoTentar: () => _recarregar(_carregarHistorico));
    } else if (_historico.isEmpty) {
      corpo = const Text('Ainda não há nada registrado nesta loja.',
          key: Key('area_historico_vazio'));
    } else {
      corpo = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final a in _historico)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.admin_panel_settings_outlined,
                  color: AppColors.primary),
              title: Text(rotuloAcaoNaLoja(a)),
              subtitle: Text(detalheAcaoNaLoja(a)),
            ),
        ],
      );
    }
    return _Secao(
      chave: 'historico',
      icone: Icons.history,
      filho: corpo,
      acoes: [
        IconButton(
          key: const Key('area_historico_atualizar'),
          tooltip: 'Atualizar histórico',
          onPressed: () => _recarregar(_carregarHistorico),
          icon: const Icon(Icons.refresh, color: AppColors.primary),
        ),
      ],
    );
  }
}

// ─── Peças pequenas ─────────────────────────────────────────────────────────

/// Um cartão de secção: título, a frase do que serve e o conteúdo.
class _Secao extends StatelessWidget {
  const _Secao({
    required this.chave,
    required this.icone,
    required this.filho,
    this.acoes = const <Widget>[],
  });

  final String chave;
  final IconData icone;
  final Widget filho;
  final List<Widget> acoes;

  @override
  Widget build(BuildContext context) {
    final s = kAreaParceiroSecoes.firstWhere((e) => e.$1 == chave);
    return Card(
      key: Key('area_secao_$chave'),
      elevation: 0,
      color: AppColors.card,
      margin: const EdgeInsets.only(bottom: Spacing.md),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone, color: AppColors.primary),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    s.$2,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                ...acoes,
              ],
            ),
            const SizedBox(height: Spacing.xxs),
            Text(s.$3,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: Spacing.md),
            filho,
          ],
        ),
      ),
    );
  }
}

/// Botões do parceiro que o servidor ainda não deixa o admin usar.
class _Pendentes extends StatelessWidget {
  const _Pendentes({required this.itens});

  /// (chave, rótulo) de cada botão desligado.
  final List<(String, String)> itens;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.xs,
          children: [
            for (final i in itens)
              OutlinedButton(
                key: Key(i.$1),
                onPressed: null,
                child: Text(i.$2),
              ),
          ],
        ),
        const SizedBox(height: Spacing.xxs),
        const Text(
          kAreaParceiroFraseFuncaoNova,
          style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _Valor extends StatelessWidget {
  const _Valor(this.rotulo, this.valor, {this.destaque = false, this.chave});

  final String rotulo;
  final String valor;
  final bool destaque;
  final Key? chave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.xxs),
      child: Row(
        children: [
          Expanded(
            child: Text(rotulo,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: destaque ? FontWeight.w700 : FontWeight.w400)),
          ),
          Text(
            valor,
            key: chave,
            style: TextStyle(
              fontSize: destaque ? 15 : 13,
              fontWeight: destaque ? FontWeight.w800 : FontWeight.w600,
              color: destaque ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(texto,
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.info)),
    );
  }
}

class _Carregando extends StatelessWidget {
  const _Carregando();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: Spacing.md),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}

class _Erro extends StatelessWidget {
  const _Erro(this.texto, {required this.aoTentar});

  final String texto;
  final VoidCallback aoTentar;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.error_outline, color: AppColors.error),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: Text(texto, style: const TextStyle(color: AppColors.error)),
        ),
        TextButton(onPressed: aoTentar, child: const Text('Tentar de novo')),
      ],
    );
  }
}

/// Resposta da janela do motivo: o motivo escrito e a opção escolhida.
class _RespostaMotivo {
  const _RespostaMotivo(this.motivo, this.opcao);

  final String motivo;
  final int? opcao;
}

/// Janela de confirmação com motivo (mínimo 3 letras) e, quando há, opções
/// (tempo, minutos). Dona do seu campo de texto: só o liberta ao sair do ecrã.
class _MotivoDialog extends StatefulWidget {
  const _MotivoDialog({
    required this.titulo,
    required this.explicacao,
    required this.confirmar,
    required this.opcoes,
    this.perguntaOpcoes,
  });

  final String titulo;
  final String explicacao;
  final String confirmar;
  final List<(String, int)> opcoes;
  final String? perguntaOpcoes;

  @override
  State<_MotivoDialog> createState() => _MotivoDialogState();
}

class _MotivoDialogState extends State<_MotivoDialog> {
  final TextEditingController _ctrl = TextEditingController();
  int? _opcao;

  @override
  void initState() {
    super.initState();
    if (widget.opcoes.isNotEmpty) _opcao = widget.opcoes.first.$2;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = motivoAreaParceiroOk(_ctrl.text);
    return AlertDialog(
      title: Text(widget.titulo),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.explicacao),
            if (widget.opcoes.isNotEmpty) ...[
              const SizedBox(height: Spacing.md),
              Text(widget.perguntaOpcoes ?? 'Escolha:',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: Spacing.xs),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.xs,
                children: [
                  for (final o in widget.opcoes)
                    ChoiceChip(
                      key: Key('area_opcao_${o.$2}'),
                      label: Text(o.$1),
                      selected: _opcao == o.$2,
                      onSelected: (_) => setState(() => _opcao = o.$2),
                    ),
                ],
              ),
            ],
            const SizedBox(height: Spacing.md),
            TextField(
              key: const Key('area_motivo_campo'),
              controller: _ctrl,
              maxLines: 2,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Motivo (obrigatório)',
                helperText: 'Mínimo 3 letras. Fica no log de auditoria com o seu nome.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('area_motivo_cancelar'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Voltar'),
        ),
        FilledButton(
          key: const Key('area_motivo_confirmar'),
          onPressed: ok
              ? () => Navigator.of(context)
                  .pop(_RespostaMotivo(_ctrl.text.trim(), _opcao))
              : null,
          child: Text(widget.confirmar),
        ),
      ],
    );
  }
}
