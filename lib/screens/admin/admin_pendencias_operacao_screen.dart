// lib/screens/admin/admin_pendencias_operacao_screen.dart
//
// [ronda-fecho-2026-09-22 · BLOCO E] "Pendências de operação" — painel admin
// (PT-BR, só o Danilo usa).
//
// Por que esta tela existe: em 21–23/09 havia talões à espera de reembolso,
// corridas mortas no pagamento, vales de volta sem volta, voltas retidas por
// distância suspeita, taxas cobradas sem estafeta, reservas sem motorista, um
// estafeta "online" com o GPS parado há 19 h e outro sem notificações — cada
// coisa numa tela diferente, e o Danilo só sabia das que lhe contavam. Esta
// caixa junta tudo o que precisa de mão humana hoje numa lista só, com o
// botão certo ao lado de cada linha.
//
// Lê `admin_pendencias_operacao()` (RPC só de leitura, devolve jsonb) e chama
// os RPCs de ação que já existem: `admin_driver_avisar_gps`,
// `admin_tvde_ride_release_hold`, `tvde_cancel_ride`,
// `admin_tvde_reservation_force_search` e `admin_release_stuck_reservation`.
// NADA aqui mexe em dinheiro: onde a ação é dinheiro (perdoar taxa, devolver
// um vale expirado, decidir um talão) a tela mostra só a nota do RPC.
//
// `carregar` e `chamarRpc` são injetáveis para a tela se testar sem Supabase
// (`test/admin_pendencias_operacao_test.dart`).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../utils/gps_parado.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '_admin_rpc_errors.dart';

/// Lê o mapa inteiro das pendências (por omissão `admin_pendencias_operacao`).
typedef CarregarPendencias = Future<Map<String, dynamic>> Function();

/// Chama um RPC de ação (por omissão `Supabase.instance.client.rpc`).
typedef ChamarRpcAdmin = Future<dynamic> Function(
    String fn, Map<String, dynamic> params);

/// Uma das oito caixas da tela, pela ordem em que aparecem.
class SecaoPendencias {
  const SecaoPendencias({
    required this.chave,
    required this.titulo,
    required this.chip,
    required this.explicacao,
    required this.icone,
  });

  /// Chave no jsonb do RPC (`taloes`, `pagamentos_falhados`, …).
  final String chave;
  final String titulo;

  /// Rótulo curto do chip de totais no cabeçalho.
  final String chip;

  /// Uma linha em PT-BR a dizer o que é (termo técnico entre parênteses).
  final String explicacao;
  final IconData icone;
}

const List<SecaoPendencias> kSecoesPendencias = [
  SecaoPendencias(
    chave: 'taloes',
    titulo: 'Talões por reembolsar',
    chip: 'Talões',
    explicacao: 'Talões de compras (recibos) que o estafeta entregou e ainda '
        'esperam a decisão de reembolso.',
    icone: Icons.receipt_long,
  ),
  SecaoPendencias(
    chave: 'pagamentos_falhados',
    titulo: 'Pagamentos falhados (TVDE)',
    chip: 'Pagamentos',
    explicacao: 'Corridas do Bora Motorista em que o cartão ou o MB Way não '
        'fechou, nos últimos 14 dias. Ninguém foi cobrado; vale a pena ligar.',
    icone: Icons.credit_card_off,
  ),
  SecaoPendencias(
    chave: 'pacotes_sem_volta',
    titulo: 'Pacotes ida-e-volta sem volta',
    chip: 'Sem volta',
    explicacao: 'Vales de volta (pacote ida-e-volta de € 8) ainda sem corrida '
        'de volta.',
    icone: Icons.swap_horiz,
  ),
  SecaoPendencias(
    chave: 'voltas_retidas',
    titulo: 'Voltas retidas para correção manual',
    chip: 'Voltas retidas',
    explicacao: 'Voltas que o sistema segurou (dispatch hold) por distância '
        'suspeita: corrigir os km e libertar, ou cancelar e devolver o vale.',
    icone: Icons.pan_tool_alt_outlined,
  ),
  SecaoPendencias(
    chave: 'cancelamentos_taxa_sem_estafeta',
    titulo: 'Cancelamentos com taxa sem estafeta',
    chip: 'Taxas s/ estafeta',
    explicacao: 'Cancelamentos com taxa cobrada sem nenhum estafeta envolvido '
        '(30 dias). Perdoar a taxa é dinheiro real: só com o vai do Danilo.',
    icone: Icons.money_off,
  ),
  SecaoPendencias(
    chave: 'reservas_falhadas',
    titulo: 'Reservas falhadas',
    chip: 'Reservas',
    explicacao: 'Corridas marcadas sem motorista ou por pagar, e reservas de '
        'mesa presas há mais de 60 min.',
    icone: Icons.event_busy,
  ),
  SecaoPendencias(
    chave: 'motoristas_gps_parado',
    titulo: 'Motoristas/estafetas com GPS parado',
    chip: 'GPS parado',
    explicacao: 'Ligados e com sinal (heartbeat) vivo, mas sem posição '
        'recente: o sistema não lhes manda pedidos.',
    icone: Icons.gps_off,
  ),
  SecaoPendencias(
    chave: 'estafetas_sem_push',
    titulo: 'Estafetas online sem notificações',
    chip: 'Sem push',
    explicacao: 'Ligados mas sem aparelho registrado para avisos (push): não '
        'vão receber ofertas.',
    icone: Icons.notifications_off_outlined,
  ),
];

/// Rotas nomeadas do painel que existem em `lib/main.dart` (`routes:` mais os
/// prefixos tratados em `onGenerateRoute`), confirmadas por grep a 23/09/2026.
///
/// O RPC devolve `accao.rota` também para rotas que ainda NÃO existem
/// (`/admin/reembolsos`, `/admin/tvde/ida-e-volta`, `/admin/drivers`,
/// `/admin/tvde/cancelamentos`, `/admin/reservas/presas`). Para essas a tela
/// não mostra "Abrir" — só "Copiar id" — porque um `pushNamed` a uma rota
/// desconhecida cai em "Página não encontrada". Ao registrar uma rota nova em
/// `main.dart`, acrescenta-a aqui.
const Set<String> kRotasAdminRegistadas = {
  '/admin',
  '/admin/pendencias',
  '/admin/conformidade',
  '/admin/reembolsos',
  '/admin/tvde/ida-e-volta',
  '/admin/drivers',
  '/admin/tvde/cancelamentos',
  '/admin/reservas/presas',
  '/admin/configuracoes',
  '/admin/parceiros',
  '/admin/notificacoes',
  '/admin/acertos-semana',
  '/admin/cleaning/cleaners',
  '/admin/crosstalk',
  '/admin/dinheiro-retido-falta',
  '/admin/drivers/approval',
  '/admin/ledger',
  '/admin/marcacoes-por-confirmar',
  '/admin/motores',
  '/admin/orders',
  '/admin/partners/pending',
  '/admin/ratings',
  '/admin/robot',
  '/admin/robot-suggestions',
  '/admin/settlements',
  '/admin/suggestions/metrics',
  '/admin/tvde',
  '/admin/tvde/access-requests',
  '/admin/tvde/noshows',
  '/admin/tvde/pagamentos',
  '/admin/tvde/reservas',
  '/admin/users',
  '/admin/whatsapp',
};

/// Prefixos com argumento no caminho, tratados em `onGenerateRoute`.
const List<String> _prefixosComId = ['/admin/orders/', '/admin/limpeza/'];

/// Verdadeiro só para rotas que a app sabe abrir (ver [kRotasAdminRegistadas]).
bool rotaAdminRegistada(String? rota) {
  if (rota == null) return false;
  final r = rota.trim();
  if (r.isEmpty) return false;
  if (kRotasAdminRegistadas.contains(r)) return true;
  for (final p in _prefixosComId) {
    if (r.startsWith(p) && r.length > p.length) return true;
  }
  return false;
}

// ── Texto (puro, testável sem Flutter) ─────────────────────────────────────

String eurosDeCents(num? cents) =>
    '€ ${((cents ?? 0) / 100).toStringAsFixed(2)}';

/// "2.1", "3", "2.43" — sem zeros a mais.
String numeroCurto(num v) {
  var s = v.toStringAsFixed(2);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}

String kmTexto(num? km) => km == null ? '? km' : '${numeroCurto(km)} km';

/// Aceita vírgula ou ponto; só distâncias positivas.
double? kmDeTexto(String texto) {
  final v = double.tryParse(texto.trim().replaceAll(',', '.'));
  if (v == null || v <= 0 || v.isNaN || v.isInfinite) return null;
  return v;
}

DateTime? dataLocal(Object? v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString())?.toLocal();
}

String _dd(int n) => n.toString().padLeft(2, '0');
String horaMinuto(DateTime t) => '${_dd(t.hour)}:${_dd(t.minute)}';
String diaHora(DateTime t) => '${_dd(t.day)}/${_dd(t.month)} ${horaMinuto(t)}';

/// "há 5 min", "há 2 h", "há 3 dias"; no futuro "daqui a 40 min"; vazio se
/// não houver data.
String haQuantoTexto(DateTime? t, {DateTime? agora}) {
  if (t == null) return '';
  final d = (agora ?? DateTime.now()).difference(t);
  final abs = d.abs();
  if (abs.inMinutes < 1) return 'agora mesmo';
  final String corpo;
  if (abs.inMinutes < 60) {
    corpo = '${abs.inMinutes} min';
  } else if (abs.inHours < 48) {
    corpo = '${abs.inHours} h';
  } else {
    corpo = '${abs.inDays} dias';
  }
  return d.isNegative ? 'daqui a $corpo' : 'há $corpo';
}

const Map<String, String> _errosConhecidos = {
  'not_admin': 'Sem permissões de admin para esta ação.',
  'ride_not_found': 'Esta corrida já não existe. Atualiza a lista.',
  'ride_not_on_hold': 'Esta corrida já não está retida. Atualiza a lista.',
  'invalid_status': 'A corrida já mudou de estado. Atualiza a lista.',
  'distancia_invalida': 'Distância inválida: tem de ser maior que 0 km.',
  'estafeta_nao_encontrado': 'Estafeta não encontrado. Atualiza a lista.',
  'requires_refund_manual_review': 'Esta reserva tem pagamento associado: '
      'libertar é dinheiro, só com o vai do Danilo.',
  'reservation_not_found': 'Esta reserva já não existe. Atualiza a lista.',
};

/// Erro do RPC em palavras simples; o resto cai no helper partilhado.
String mensagemErroPendencias(Object erro) {
  final msg = erro is PostgrestException ? erro.message : erro.toString();
  for (final e in _errosConhecidos.entries) {
    if (msg.contains(e.key)) return e.value;
  }
  return humanizeAdminRpcError(erro);
}

String _metodoPagamento(String m) => switch (m) {
      'card' => 'Cartão',
      'mbway' => 'MB Way',
      'cash' => 'Dinheiro',
      'wallet' => 'Carteira',
      '' => '—',
      _ => m,
    };

/// PT-BR com o termo técnico entre parênteses (mesmo vocabulário da tela
/// "Pagamentos das corridas").
String _estadoPagamento(String estado) => switch (estado) {
      'succeeded' => 'Pago',
      'processing' => 'Processando (a Stripe ainda está confirmando)',
      'refunded' => 'Estornado por inteiro',
      'partial_refund' => 'Estornado em parte',
      'kept_cancel_fee' => 'Ficou só a taxa de cancelamento',
      'requires_payment_method' => 'Cliente não chegou a pôr o cartão',
      'requires_confirmation' => 'Pagamento por confirmar',
      'requires_action' =>
        'Banco pediu confirmação e ela não veio (3-D Secure)',
      '' => 'sem estado de pagamento',
      _ => estado,
    };

String _motivoCancelamento(String motivo) => switch (motivo) {
      'payment_failed' => 'Pagamento não concluído',
      'payment_abandoned' => 'Cliente fechou a tela de pagamento',
      'payment_timeout' => 'Expirou (limpeza automática do sistema)',
      'admin_stuck_payment' => 'Cancelada pelo admin (pagamento preso)',
      _ => motivo.replaceAll('_', ' '),
    };

String _estadoCorrida(String s) => switch (s) {
      'solicitada' => 'à procura de motorista',
      'agendada' => 'agendada',
      'aceite' => 'aceite pelo motorista',
      'a_caminho' => 'motorista a caminho',
      'chegou' => 'motorista chegou',
      'em_curso' => 'em curso',
      'concluida' => 'concluída',
      'sem_motorista' => 'sem motorista',
      '' => '—',
      _ => s.replaceAll('_', ' '),
    };

String _motivoRetencao(String r) => switch (r) {
      'distancia_suspeita' =>
        'distância suspeita (volta muito diferente da ida)',
      _ => r.replaceAll('_', ' '),
    };

String _veiculo(String v) => switch (v) {
      'car' => 'carro',
      'carro_passageiros' => 'Bora Motorista (passageiros)',
      'motorcycle' => 'mota',
      'bicycle' => 'bicicleta',
      '' => '',
      _ => v.replaceAll('_', ' '),
    };

String _plataforma(String p) => switch (p) {
      'android' || 'android_app' => 'app Android',
      'ios' || 'ios_app' => 'app iPhone',
      'web' || 'web_app' || 'browser' => 'navegador (web)',
      '' => 'plataforma desconhecida',
      _ => p.replaceAll('_', ' '),
    };

// ── Leitura do jsonb ───────────────────────────────────────────────────────

String _s(Map<String, dynamic> m, String k, [String vazio = '']) {
  final v = m[k];
  if (v == null) return vazio;
  final t = v.toString().trim();
  return t.isEmpty ? vazio : t;
}

num? _n(Map<String, dynamic> m, String k) {
  final v = m[k];
  if (v is num) return v;
  return num.tryParse('${v ?? ''}');
}

bool _b(Map<String, dynamic> m, String k) => m[k] == true;

Map<String, dynamic> _accao(Map<String, dynamic> m) {
  final a = m['accao'];
  return a is Map ? Map<String, dynamic>.from(a) : const {};
}

class _Pendencias {
  _Pendencias(this.raw);

  final Map<String, dynamic> raw;

  DateTime? get geradoEm => dataLocal(raw['gerado_em']);

  int get gpsLimiteS =>
      (raw['gps_limite_s'] as num?)?.toInt() ?? kGpsFrescoSegundosPadrao;

  List<Map<String, dynamic>> lista(String chave) {
    final v = raw[chave];
    if (v is! List) return const [];
    return v
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  int total(String chave) {
    final t = raw['totais'];
    if (t is Map && t[chave] is num) return (t[chave] as num).toInt();
    return lista(chave).length;
  }

  int get totalGeral =>
      kSecoesPendencias.fold(0, (soma, s) => soma + total(s.chave));
}

// ── Tela ───────────────────────────────────────────────────────────────────

class AdminPendenciasOperacaoScreen extends StatefulWidget {
  const AdminPendenciasOperacaoScreen({
    super.key,
    this.carregar,
    this.chamarRpc,
  });

  /// Substitui a leitura do RPC (testes). Nulo = Supabase.
  final CarregarPendencias? carregar;

  /// Substitui as chamadas de ação (testes). Nulo = Supabase.
  final ChamarRpcAdmin? chamarRpc;

  @override
  State<AdminPendenciasOperacaoScreen> createState() =>
      _AdminPendenciasOperacaoScreenState();
}

class _AdminPendenciasOperacaoScreenState
    extends State<AdminPendenciasOperacaoScreen> {
  _Pendencias? _dados;
  bool _carregando = true;
  String? _erro;

  /// Chave da linha com ação em curso. Nunca um "ocupado" global: um botão
  /// trava-se pelo SEU pedido (PADRÃO BORA 3.13).
  String? _ocupado;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<Map<String, dynamic>> _carregarPadrao() async {
    final res = await Supabase.instance.client.rpc('admin_pendencias_operacao');
    if (res is Map) return Map<String, dynamic>.from(res);
    throw StateError('Resposta inesperada do servidor.');
  }

  Future<dynamic> _rpcPadrao(String fn, Map<String, dynamic> params) =>
      Supabase.instance.client.rpc(fn, params: params);

  /// `silencioso` = recarregar por baixo da lista que já está no ecrã (depois
  /// de uma ação ou do puxar-para-atualizar), sem esconder nada.
  Future<void> _carregar({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }
    try {
      final m = await (widget.carregar ?? _carregarPadrao)();
      if (!mounted) return;
      setState(() {
        _dados = _Pendencias(m);
        _carregando = false;
        _erro = null;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = mensagemErroPendencias(e);
      setState(() {
        _carregando = false;
        if (_dados == null) _erro = msg;
      });
      if (_dados != null) _aviso('Não deu para atualizar: $msg', erro: true);
    }
  }

  void _aviso(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: erro ? AppColors.error : null,
    ));
  }

  /// Chama um RPC de ação, mostra o resultado e recarrega a lista.
  Future<void> _executar({
    required String chave,
    required String fn,
    required Map<String, dynamic> params,
    required String Function(dynamic res) sucesso,
  }) async {
    setState(() => _ocupado = chave);
    try {
      final res = await (widget.chamarRpc ?? _rpcPadrao)(fn, params);
      if (!mounted) return;
      if (res is Map && res['ok'] == false) {
        final codigo = '${res['error'] ?? ''}';
        _aviso(_errosConhecidos[codigo] ?? 'Não deu certo: $codigo',
            erro: true);
      } else {
        _aviso(sucesso(res));
      }
    } catch (e) {
      if (!mounted) return;
      _aviso(mensagemErroPendencias(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = null);
    }
    if (mounted) await _carregar(silencioso: true);
  }

  Future<bool> _confirmar({
    required String titulo,
    required String corpo,
    required String acao,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(titulo),
        content: Text(corpo),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(d, true),
            child: Text(acao),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _copiar(String texto) async {
    await Clipboard.setData(ClipboardData(text: texto));
    _aviso('Id copiado: $texto');
  }

  /// Abre o marcador do telefone; se não der (web sem app de telefone),
  /// copia o número para não deixar o Danilo sem saída.
  Future<void> _ligar(String tel) async {
    final uri = Uri(scheme: 'tel', path: tel);
    try {
      if (await launchUrl(uri)) return;
    } catch (_) {
      // cai no recurso abaixo
    }
    await Clipboard.setData(ClipboardData(text: tel));
    _aviso('Não deu para abrir o telefone aqui. Número copiado: $tel');
  }

  void _abrir(String rota) => Navigator.of(context).pushNamed(rota);

  // ── Ações ────────────────────────────────────────────────────────────────

  Future<void> _avisarGps(Map<String, dynamic> m) async {
    final a = _accao(m);
    final driver =
        _s(a, 'p_driver').isNotEmpty ? _s(a, 'p_driver') : _s(m, 'user_id');
    await _executar(
      chave: 'gps:${_s(m, 'user_id')}',
      fn: 'admin_driver_avisar_gps',
      params: {'p_driver': driver},
      sucesso: (res) {
        final nome = res is Map && res['driver'] != null
            ? '${res['driver']}'
            : _s(m, 'name', 'estafeta');
        return 'Aviso enviado a $nome: "Sem sinal de GPS".';
      },
    );
  }

  Future<void> _cancelarCorridaPresa(Map<String, dynamic> m) async {
    final id = _s(m, 'ride_id');
    final ok = await _confirmar(
      titulo: 'Cancelar esta corrida presa?',
      corpo: 'A corrida de ${_s(m, 'client_name', 'cliente sem nome')} fica '
          'cancelada pelo cliente (motivo: pagamento preso). Nenhum motorista '
          'foi envolvido, por isso a taxa de cancelamento é € 0,00. '
          'Não tem desfazer.',
      acao: 'Sim, cancelar',
    );
    if (!ok) return;
    await _executar(
      chave: 'pag:$id',
      fn: 'tvde_cancel_ride',
      params: {
        'p_ride_id': id,
        'p_actor': 'cliente',
        'p_reason': 'admin_stuck_payment',
      },
      sucesso: (_) => 'Corrida cancelada.',
    );
  }

  Future<void> _corrigirKmELibertar(Map<String, dynamic> m) async {
    final id = _s(m, 'ride_id');
    final idaKm = _n(m, 'ida_km') ?? _n(m, 'est_distance_km');
    final r = await showDialog<_CorrecaoKm>(
      context: context,
      builder: (_) => _DialogoCorrigirKm(
        idaKm: idaKm,
        kmPedido: _n(m, 'est_distance_km'),
      ),
    );
    if (r == null || !mounted) return;
    await _executar(
      chave: 'volta:$id',
      fn: 'admin_tvde_ride_release_hold',
      params: {
        'p_ride_id': id,
        'p_est_distance_km': r.km,
        if (r.nota.isNotEmpty) 'p_nota': r.nota,
        'p_cancelar': false,
      },
      sucesso: (res) {
        final ganho = res is Map ? res['driver_earn_cents'] as num? : null;
        return 'Volta libertada com ${kmTexto(r.km)}'
            '${ganho == null ? '' : ' · ganho do motorista ${eurosDeCents(ganho)}'}.';
      },
    );
  }

  Future<void> _cancelarVolta(Map<String, dynamic> m) async {
    final id = _s(m, 'ride_id');
    final ok = await _confirmar(
      titulo: 'Cancelar a volta e devolver o vale?',
      corpo: 'A volta de ${_s(m, 'client_name', 'cliente sem nome')} é '
          'cancelada e o vale (pacote ida-e-volta) volta ao cliente, que pode '
          'chamar a volta de novo na app. Não tem desfazer.',
      acao: 'Sim, cancelar e devolver',
    );
    if (!ok) return;
    await _executar(
      chave: 'volta:$id',
      fn: 'admin_tvde_ride_release_hold',
      params: {
        'p_ride_id': id,
        'p_nota': 'Pendências de operação: volta cancelada e vale devolvido',
        'p_cancelar': true,
      },
      sucesso: (_) => 'Volta cancelada e vale devolvido ao cliente.',
    );
  }

  Future<void> _voltarAProcurar(Map<String, dynamic> m) async {
    final a = _accao(m);
    final id = _s(a, 'p_ride_id').isNotEmpty ? _s(a, 'p_ride_id') : _s(m, 'id');
    await _executar(
      chave: 'res:$id',
      fn: 'admin_tvde_reservation_force_search',
      params: {'p_ride_id': id},
      sucesso: (res) => res == false
          ? 'Não deu para voltar a procurar: a reserva já mudou de estado.'
          : 'Nova procura de motorista disparada.',
    );
  }

  Future<void> _libertarReserva(Map<String, dynamic> m) async {
    final a = _accao(m);
    final id = _s(a, 'p_reservation_id').isNotEmpty
        ? _s(a, 'p_reservation_id')
        : _s(m, 'id');
    final ok = await _confirmar(
      titulo: 'Libertar esta reserva de mesa?',
      corpo: 'A reserva presa de ${_s(m, 'client_name', 'cliente sem nome')} '
          'fica cancelada pelo admin e a mesa volta a ficar livre. Se houver '
          'pagamento associado, o servidor recusa (isso é dinheiro: só com o '
          'vai do Danilo). Não tem desfazer.',
      acao: 'Sim, libertar',
    );
    if (!ok) return;
    await _executar(
      chave: 'res:$id',
      fn: 'admin_release_stuck_reservation',
      params: {'p_reservation_id': id, 'p_reason': 'admin_pendencias'},
      sucesso: (_) => 'Reserva libertada.',
    );
  }

  // ── Botões ───────────────────────────────────────────────────────────────

  Widget _botao({
    required String texto,
    required IconData icone,
    required VoidCallback onPressed,
    bool primario = false,
    bool perigo = false,
    bool ocupado = false,
  }) {
    final Widget icon = ocupado
        ? const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icone, size: 16);
    final label = Text(texto);
    final VoidCallback? cb = ocupado ? null : onPressed;
    if (primario) {
      return FilledButton.icon(onPressed: cb, icon: icon, label: label);
    }
    return OutlinedButton.icon(
      style: perigo
          ? OutlinedButton.styleFrom(foregroundColor: AppColors.error)
          : null,
      onPressed: cb,
      icon: icon,
      label: label,
    );
  }

  Widget _botaoCopiar(String id) => _botao(
      texto: 'Copiar id', icone: Icons.copy, onPressed: () => _copiar(id));

  Widget _botaoLigar(String tel) =>
      _botao(texto: 'Ligar', icone: Icons.phone, onPressed: () => _ligar(tel));

  Widget? _botaoAbrir(String rota, String texto) => rotaAdminRegistada(rota)
      ? _botao(
          texto: texto, icone: Icons.open_in_new, onPressed: () => _abrir(rota))
      : null;

  String _telefone(Map<String, dynamic> m, Map<String, dynamic> a) {
    final t = _s(a, 'tel');
    if (t.isNotEmpty) return t;
    final c = _s(m, 'client_phone');
    return c.isNotEmpty ? c : _s(m, 'phone');
  }

  // ── Cartões, um por secção ───────────────────────────────────────────────

  Widget _cartao(SecaoPendencias s, Map<String, dynamic> m) =>
      switch (s.chave) {
        'taloes' => _cartaoTalao(m),
        'pagamentos_falhados' => _cartaoPagamento(m),
        'pacotes_sem_volta' => _cartaoPacote(m),
        'voltas_retidas' => _cartaoVolta(m),
        'cancelamentos_taxa_sem_estafeta' => _cartaoCancelamento(m),
        'reservas_falhadas' => _cartaoReserva(m),
        'motoristas_gps_parado' => _cartaoGps(m),
        _ => _cartaoSemPush(m),
      };

  Widget _cartaoTalao(Map<String, dynamic> m) {
    final a = _accao(m);
    final id = _s(m, 'receipt_id');
    final estafeta = _s(m, 'driver_name', 'Estafeta sem nome');
    final loja = _s(m, 'vendor_name');
    final abrir = _botaoAbrir(_s(a, 'rota'), 'Abrir reembolsos');
    return _Caixa(children: [
      _Titulo(
        texto: loja.isEmpty ? estafeta : '$estafeta · $loja',
        valor: eurosDeCents(_n(m, 'valor_cents')),
      ),
      _Linha(
        icone: Icons.shopping_bag_outlined,
        texto: 'Pedido ${_s(m, 'order_id', '—')} · talão entregue '
            '${haQuantoTexto(dataLocal(m['created_at']))}',
      ),
      if (_b(m, 'is_test_order'))
        const _Linha(icone: Icons.science_outlined, texto: 'Pedido de teste'),
      const _Nota('A decisão (pagar, pagar por fora ou rejeitar) faz-se na '
          'tela Reembolsos de estafetas.'),
      _Botoes(children: [if (abrir != null) abrir, _botaoCopiar(id)]),
    ]);
  }

  Widget _cartaoPagamento(Map<String, dynamic> m) {
    final a = _accao(m);
    final id = _s(m, 'ride_id');
    final preso = _b(m, 'preso');
    final tel = _telefone(m, a);
    final abrir = _botaoAbrir(_s(a, 'rota'), 'Abrir pagamentos');
    return _Caixa(
      borda: preso ? AppColors.error : AppColors.warning,
      children: [
        _Titulo(
          texto: '${_s(m, 'client_name', 'Sem nome')} · '
              '${haQuantoTexto(dataLocal(m['created_at']))}',
          valor: eurosDeCents(_n(m, 'est_fare_cents')),
          etiqueta: preso ? 'PRESA' : null,
          corEtiqueta: AppColors.error,
        ),
        _Linha(
          icone: Icons.payment,
          texto: '${_metodoPagamento(_s(m, 'payment_method'))} · '
              '${_estadoPagamento(_s(m, 'payment_status'))}',
        ),
        if (_s(m, 'cancel_reason').isNotEmpty)
          _Linha(
            icone: Icons.info_outline,
            texto: _motivoCancelamento(_s(m, 'cancel_reason')),
          ),
        _Linha(
          icone: Icons.route,
          texto: '${_s(m, 'origin_label', '?')} → ${_s(m, 'dest_label', '?')}',
        ),
        if (tel.isNotEmpty) _Linha(icone: Icons.phone, texto: tel),
        if (preso)
          const _Nota('Presa em "solicitada" com o pagamento por fechar: o '
              'motorista nunca vai ser chamado. Cancelar não cobra nada ao '
              'cliente.'),
        _Botoes(children: [
          if (tel.isNotEmpty) _botaoLigar(tel),
          _botaoCopiar(id),
          if (abrir != null) abrir,
          if (preso)
            _botao(
              texto: 'Cancelar corrida presa',
              icone: Icons.cancel_outlined,
              perigo: true,
              ocupado: _ocupado == 'pag:$id',
              onPressed: () => _cancelarCorridaPresa(m),
            ),
        ]),
      ],
    );
  }

  Widget _cartaoPacote(Map<String, dynamic> m) {
    final a = _accao(m);
    final id = _s(m, 'credit_id');
    final ativo = _s(m, 'status') == 'ativo';
    final expira = dataLocal(m['expires_at']);
    final tel = _telefone(m, a);
    final nota = _s(a, 'nota');
    final abrir = _botaoAbrir(_s(a, 'rota'), 'Abrir ida e volta');
    return _Caixa(
      borda: ativo ? null : AppColors.warning,
      children: [
        _Titulo(
          texto: _s(m, 'client_name', 'Sem nome'),
          valor: eurosDeCents(_n(m, 'paid_cents')),
          etiqueta: ativo ? 'VALE ATIVO' : 'VALE EXPIRADO',
          corEtiqueta: ativo ? AppColors.success : AppColors.warning,
        ),
        _Linha(
          icone: Icons.route,
          texto: 'Ida: ${_s(m, 'origin_label', '?')} → '
              '${_s(m, 'dest_label', '?')} '
              '(${_estadoCorrida(_s(m, 'ida_status'))})',
        ),
        _Linha(
          icone: Icons.schedule,
          texto: 'Comprado ${haQuantoTexto(dataLocal(m['created_at']))}'
              '${expira == null ? '' : ' · ${ativo ? 'expira' : 'expirou'} ${haQuantoTexto(expira)}'}'
              ' · ${_b(m, 'pago_online') ? 'pago online' : 'pago em dinheiro'}',
        ),
        if (tel.isNotEmpty) _Linha(icone: Icons.phone, texto: tel),
        if (nota.isNotEmpty) _Nota(nota),
        _Botoes(children: [
          if (tel.isNotEmpty) _botaoLigar(tel),
          _botaoCopiar(id),
          if (abrir != null) abrir,
        ]),
      ],
    );
  }

  Widget _cartaoVolta(Map<String, dynamic> m) {
    final a = _accao(m);
    final id = _s(m, 'ride_id');
    final tel = _telefone(m, a);
    final nota = _s(a, 'nota');
    final ocupado = _ocupado == 'volta:$id';
    return _Caixa(
      borda: AppColors.warning,
      children: [
        _Titulo(
          texto: '${_s(m, 'client_name', 'Sem nome')} · retida '
              '${haQuantoTexto(dataLocal(m['hold_at'] ?? m['created_at']))}',
          valor: 'motorista ${eurosDeCents(_n(m, 'driver_earn_cents'))}',
        ),
        _Linha(
          icone: Icons.route,
          texto: '${_s(m, 'origin_label', '?')} → ${_s(m, 'dest_label', '?')}',
        ),
        _Linha(
          icone: Icons.straighten,
          texto: 'Volta pedida com ${kmTexto(_n(m, 'est_distance_km'))} · '
              'a ida teve ${kmTexto(_n(m, 'ida_km'))}',
        ),
        if (_s(m, 'hold_reason').isNotEmpty)
          _Linha(
            icone: Icons.info_outline,
            texto: 'Motivo: ${_motivoRetencao(_s(m, 'hold_reason'))}',
          ),
        if (_s(m, 'detalhe').isNotEmpty)
          _Linha(icone: Icons.notes, texto: _s(m, 'detalhe')),
        if (tel.isNotEmpty) _Linha(icone: Icons.phone, texto: tel),
        if (nota.isNotEmpty) _Nota(nota),
        _Botoes(children: [
          _botao(
            texto: 'Corrigir km e libertar',
            icone: Icons.straighten,
            primario: true,
            ocupado: ocupado,
            onPressed: () => _corrigirKmELibertar(m),
          ),
          _botao(
            texto: 'Cancelar volta e devolver vale',
            icone: Icons.cancel_outlined,
            perigo: true,
            ocupado: ocupado,
            onPressed: () => _cancelarVolta(m),
          ),
          if (tel.isNotEmpty) _botaoLigar(tel),
          _botaoCopiar(id),
        ]),
      ],
    );
  }

  Widget _cartaoCancelamento(Map<String, dynamic> m) {
    final a = _accao(m);
    final id = _s(m, 'id');
    final pedido = _s(m, 'kind') == 'pedido';
    final loja = _s(m, 'vendor_name');
    final motivo = _s(m, 'cancel_reason');
    final nota = _s(a, 'nota');
    final abrir = _botaoAbrir(_s(a, 'rota'), pedido ? 'Abrir pedido' : 'Abrir');
    return _Caixa(children: [
      _Titulo(
        texto: '${pedido ? 'Pedido' : 'Corrida'} · '
            '${_s(m, 'customer_name', 'Sem nome')}',
        valor: '${eurosDeCents(_n(m, 'fee_cents'))} de taxa',
      ),
      if (loja.isNotEmpty) _Linha(icone: Icons.storefront, texto: loja),
      _Linha(
        icone: Icons.schedule,
        texto: 'Cancelado ${haQuantoTexto(dataLocal(m['cancelled_at']))}'
            '${motivo.isEmpty ? '' : ' · ${_motivoCancelamento(motivo)}'}',
      ),
      _Linha(
        icone: Icons.payment,
        texto: '${_metodoPagamento(_s(m, 'payment_method'))} · reembolso: '
            '${_s(m, 'refund_status', 'nenhum')}',
      ),
      if (nota.isNotEmpty) _Nota(nota),
      _Botoes(children: [_botaoCopiar(id), if (abrir != null) abrir]),
    ]);
  }

  Widget _cartaoReserva(Map<String, dynamic> m) {
    final a = _accao(m);
    final id = _s(m, 'id');
    final mesa = _s(m, 'kind') == 'mesa';
    final quando = dataLocal(m['quando']);
    final tel = _telefone(m, a);
    final rpc = _s(a, 'rpc');
    final ocupado = _ocupado == 'res:$id';
    final abrir = _botaoAbrir(_s(a, 'rota'), 'Abrir reservas');
    return _Caixa(
      borda: AppColors.warning,
      children: [
        _Titulo(
          texto: '${mesa ? 'Mesa' : 'Corrida marcada'} · '
              '${_s(m, 'client_name', 'Sem nome')}',
          valor: quando == null ? null : diaHora(quando),
        ),
        _Linha(
          icone: Icons.info_outline,
          texto: _s(m, 'motivo', _estadoCorrida(_s(m, 'status'))),
          cor: AppColors.error,
        ),
        _Linha(
          icone: mesa ? Icons.restaurant : Icons.route,
          texto: mesa
              ? _s(m, 'origin_label', 'Restaurante sem nome')
              : '${_s(m, 'origin_label', '?')} → ${_s(m, 'dest_label', '?')}',
        ),
        _Linha(
          icone: Icons.schedule,
          texto: 'Para ${quando == null ? '?' : diaHora(quando)} '
              '(${haQuantoTexto(quando)}) · '
              '${_metodoPagamento(_s(m, 'payment_method'))}',
        ),
        if (tel.isNotEmpty) _Linha(icone: Icons.phone, texto: tel),
        _Botoes(children: [
          if (!mesa && rpc.contains('admin_tvde_reservation_force_search'))
            _botao(
              texto: 'Voltar a procurar',
              icone: Icons.search,
              primario: true,
              ocupado: ocupado,
              onPressed: () => _voltarAProcurar(m),
            ),
          if (mesa && rpc.contains('admin_release_stuck_reservation'))
            _botao(
              texto: 'Libertar reserva',
              icone: Icons.lock_open,
              perigo: true,
              ocupado: ocupado,
              onPressed: () => _libertarReserva(m),
            ),
          if (tel.isNotEmpty) _botaoLigar(tel),
          _botaoCopiar(id),
          if (abrir != null) abrir,
        ]),
      ],
    );
  }

  Widget _cartaoGps(Map<String, dynamic> m) {
    final a = _accao(m);
    final id = _s(m, 'user_id');
    final tel = _telefone(m, a);
    final veiculo = _veiculo(_s(m, 'vehicle_type'));
    final gpsAge = _n(m, 'gps_age_s')?.toInt();
    final hb = _n(m, 'heartbeat_age_s')?.toInt();
    final abrir = _botaoAbrir(_s(a, 'rota'), 'Abrir estafetas');
    return _Caixa(
      borda: AppColors.error,
      children: [
        _Titulo(
          texto: '${_s(m, 'name', 'Sem nome')}'
              '${veiculo.isEmpty ? '' : ' · $veiculo'}',
          etiqueta: 'ONLINE',
          corEtiqueta: AppColors.success,
        ),
        _Linha(
          icone: Icons.gps_off,
          texto: gpsParadoTexto(gpsAge),
          cor: AppColors.error,
        ),
        _Linha(
          icone: Icons.favorite_border,
          texto: 'Sinal (heartbeat) ${gpsIdadeTexto(hb)} · '
              '${_plataforma(_s(m, 'last_platform'))}',
        ),
        if (!_b(m, 'tem_notificacoes'))
          const _Linha(
            icone: Icons.notifications_off_outlined,
            texto: 'Sem notificações registradas: o push não chega',
            cor: AppColors.warning,
          ),
        if (tel.isNotEmpty) _Linha(icone: Icons.phone, texto: tel),
        _Botoes(children: [
          _botao(
            texto: 'Avisar por push',
            icone: Icons.notifications_active_outlined,
            primario: true,
            ocupado: _ocupado == 'gps:$id',
            onPressed: () => _avisarGps(m),
          ),
          if (tel.isNotEmpty) _botaoLigar(tel),
          _botaoCopiar(id),
          if (abrir != null) abrir,
        ]),
      ],
    );
  }

  Widget _cartaoSemPush(Map<String, dynamic> m) {
    final a = _accao(m);
    final id = _s(m, 'user_id');
    final tel = _telefone(m, a);
    final hb = _n(m, 'heartbeat_age_s')?.toInt();
    final nota = _s(a, 'nota');
    final abrir = _botaoAbrir(_s(a, 'rota'), 'Abrir estafetas');
    return _Caixa(
      borda: AppColors.warning,
      children: [
        _Titulo(
          texto: _s(m, 'name', 'Sem nome'),
          etiqueta: 'SEM PUSH',
          corEtiqueta: AppColors.warning,
        ),
        _Linha(
          icone: Icons.favorite_border,
          texto: 'Sinal (heartbeat) ${gpsIdadeTexto(hb)} · '
              '${_plataforma(_s(m, 'last_platform'))}',
        ),
        if (tel.isNotEmpty) _Linha(icone: Icons.phone, texto: tel),
        if (nota.isNotEmpty) _Nota(nota),
        _Botoes(children: [
          if (tel.isNotEmpty) _botaoLigar(tel),
          _botaoCopiar(id),
          if (abrir != null) abrir,
        ]),
      ],
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final d = _dados;
    final Widget corpo;
    if (d == null) {
      corpo = _carregando
          ? const Center(child: CircularProgressIndicator())
          : _Falha(erro: _erro ?? '', aoTentar: _carregar);
    } else {
      corpo = RefreshIndicator(
        onRefresh: () => _carregar(silencioso: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
              Spacing.md, Spacing.md, Spacing.md, Spacing.xxxl),
          children: [
            _Cabecalho(
              geradoEm: d.geradoEm,
              gpsLimiteS: d.gpsLimiteS,
              totais: [
                for (final s in kSecoesPendencias) (s, d.total(s.chave))
              ],
            ),
            if (d.totalGeral == 0) const _NadaPendente(),
            for (final s in kSecoesPendencias)
              _SecaoTile(
                secao: s,
                itens: d.lista(s.chave),
                cartao: (m) => _cartao(s, m),
              ),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Pendências de operação',
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed:
                _carregando ? null : () => _carregar(silencioso: d != null),
          ),
        ],
      ),
      body: corpo,
    );
  }
}

// ── Widgets de apoio ───────────────────────────────────────────────────────

/// Resultado do diálogo "Corrigir distância e libertar".
typedef _CorrecaoKm = ({double km, String nota});

/// Diálogo com campo de km (pré-preenchido com a distância da ida) e nota.
/// Widget próprio para os controladores viverem e morrerem com ele — dispor
/// logo a seguir ao `showDialog` rebenta durante a animação de saída.
class _DialogoCorrigirKm extends StatefulWidget {
  const _DialogoCorrigirKm({required this.idaKm, required this.kmPedido});

  final num? idaKm;
  final num? kmPedido;

  @override
  State<_DialogoCorrigirKm> createState() => _DialogoCorrigirKmState();
}

class _DialogoCorrigirKmState extends State<_DialogoCorrigirKm> {
  late final TextEditingController _km = TextEditingController(
      text: widget.idaKm == null ? '' : numeroCurto(widget.idaKm!));
  final TextEditingController _nota = TextEditingController();
  String? _erroKm;

  @override
  void dispose() {
    _km.dispose();
    _nota.dispose();
    super.dispose();
  }

  void _libertar() {
    final km = kmDeTexto(_km.text);
    if (km == null) {
      setState(() => _erroKm = 'Escreve uma distância maior que 0.');
      return;
    }
    Navigator.pop<_CorrecaoKm>(context, (km: km, nota: _nota.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Corrigir distância e libertar'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A volta fica com os km certos e volta a ser oferecida aos '
            'motoristas (o ganho do motorista é recalculado). '
            'A ida teve ${kmTexto(widget.idaKm)}; a volta pediu '
            '${kmTexto(widget.kmPedido)}.',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: Spacing.md),
          TextField(
            key: const Key('pendencias_km'),
            controller: _km,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Distância da volta (km)',
              errorText: _erroKm,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          TextField(
            key: const Key('pendencias_nota'),
            controller: _nota,
            decoration: const InputDecoration(
              labelText: 'Nota (opcional)',
              hintText: 'fica no histórico da corrida',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Voltar'),
        ),
        FilledButton(onPressed: _libertar, child: const Text('Libertar')),
      ],
    );
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({
    required this.geradoEm,
    required this.gpsLimiteS,
    required this.totais,
  });

  final DateTime? geradoEm;
  final int gpsLimiteS;
  final List<(SecaoPendencias, int)> totais;

  @override
  Widget build(BuildContext context) {
    return _Caixa(children: [
      Text(
        geradoEm == null
            ? 'Gerado agora'
            : 'Gerado às ${horaMinuto(geradoEm!)}',
        style: const TextStyle(
            fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      ),
      const SizedBox(height: Spacing.xs),
      Text(
        'GPS parado = sem posição há mais de $gpsLimiteS s '
        '(limite dispatch_gps_fresh_seconds).',
        style: const TextStyle(fontSize: 12, color: AppColors.textSubtle),
      ),
      const SizedBox(height: Spacing.sm),
      Wrap(
        spacing: Spacing.sm,
        runSpacing: Spacing.sm,
        children: [
          for (final t in totais) _ChipTotal(rotulo: t.$1.chip, n: t.$2),
        ],
      ),
    ]);
  }
}

/// Verde quando está a zero, laranja quando há trabalho.
class _ChipTotal extends StatelessWidget {
  const _ChipTotal({required this.rotulo, required this.n});

  final String rotulo;
  final int n;

  @override
  Widget build(BuildContext context) {
    final cor = n == 0 ? AppColors.success : AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.xs),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: cor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$n',
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 13, color: cor)),
          const SizedBox(width: Spacing.xs),
          Text(rotulo, style: TextStyle(fontSize: 12.5, color: cor)),
        ],
      ),
    );
  }
}

class _Contador extends StatelessWidget {
  const _Contador(this.n);

  final int n;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm, vertical: Spacing.xxs),
        decoration: BoxDecoration(
          color: n == 0 ? AppColors.success : AppColors.accent,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Text('$n',
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12)),
      );
}

class _NadaPendente extends StatelessWidget {
  const _NadaPendente();

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: Spacing.sm),
        padding: const EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(Radii.md + 2),
          border: Border.all(color: AppColors.success),
        ),
        child: const Column(
          children: [
            Text('Nada pendente 🎉',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.success)),
            SizedBox(height: Spacing.xs),
            Text(
                'As oito caixas estão a zero. Puxa para baixo para conferir '
                'de novo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
}

class _SecaoTile extends StatelessWidget {
  const _SecaoTile({
    required this.secao,
    required this.itens,
    required this.cartao,
  });

  final SecaoPendencias secao;
  final List<Map<String, dynamic>> itens;
  final Widget Function(Map<String, dynamic>) cartao;

  @override
  Widget build(BuildContext context) {
    final vazio = itens.isEmpty;
    return Container(
      margin: const EdgeInsets.only(top: Spacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.md + 2),
        border: Border.all(color: AppColors.divider),
      ),
      child: ExpansionTile(
        key: PageStorageKey<String>('pendencias_${secao.chave}'),
        initiallyExpanded: !vazio,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: Spacing.md),
        childrenPadding:
            const EdgeInsets.fromLTRB(Spacing.md, 0, Spacing.md, Spacing.md),
        leading: Icon(secao.icone,
            color: vazio ? AppColors.success : AppColors.accent),
        title: Row(
          children: [
            Expanded(
              child: Text(secao.titulo,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: AppColors.textPrimary)),
            ),
            const SizedBox(width: Spacing.sm),
            _Contador(itens.length),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: Spacing.xxs),
          child: Text(secao.explicacao,
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSubtle)),
        ),
        children: [
          if (vazio)
            const Padding(
              padding: EdgeInsets.only(bottom: Spacing.xs),
              child: Text('Nada aqui.',
                  style: TextStyle(color: AppColors.textSubtle)),
            ),
          for (final m in itens)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: cartao(m),
            ),
        ],
      ),
    );
  }
}

class _Caixa extends StatelessWidget {
  const _Caixa({required this.children, this.borda});

  final List<Widget> children;
  final Color? borda;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.md + 2),
          border: Border.all(color: borda ?? AppColors.divider),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}

class _Titulo extends StatelessWidget {
  const _Titulo({
    required this.texto,
    this.valor,
    this.etiqueta,
    this.corEtiqueta = AppColors.accent,
  });

  final String texto;
  final String? valor;
  final String? etiqueta;
  final Color corEtiqueta;

  @override
  Widget build(BuildContext context) {
    final v = valor;
    final e = etiqueta;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(texto,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ),
        if (e != null) ...[
          const SizedBox(width: Spacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Spacing.sm, vertical: Spacing.xxs),
            decoration: BoxDecoration(
              color: corEtiqueta.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Radii.pill),
              border: Border.all(color: corEtiqueta),
            ),
            child: Text(e,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: corEtiqueta)),
          ),
        ],
        if (v != null && v.isNotEmpty) ...[
          const SizedBox(width: Spacing.sm),
          Text(v,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        ],
      ],
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha({required this.icone, required this.texto, this.cor});

  final IconData icone;
  final String texto;
  final Color? cor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Spacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icone, size: 14, color: cor ?? AppColors.textSubtle),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(texto,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: cor ?? AppColors.textSecondary,
                      fontWeight: cor == null ? null : FontWeight.w600)),
            ),
          ],
        ),
      );
}

/// Nota do RPC (onde a ação é dinheiro, é só isto que aparece).
class _Nota extends StatelessWidget {
  const _Nota(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: Spacing.sm),
        padding: const EdgeInsets.all(Spacing.sm),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 14, color: AppColors.warning),
            const SizedBox(width: 6),
            Expanded(
              child: Text(texto,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textPrimary)),
            ),
          ],
        ),
      );
}

class _Botoes extends StatelessWidget {
  const _Botoes({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Spacing.sm),
        child: Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.xs,
          children: children,
        ),
      );
}

class _Falha extends StatelessWidget {
  const _Falha({required this.erro, required this.aoTentar});

  final String erro;
  final VoidCallback aoTentar;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: AppColors.error),
              const SizedBox(height: Spacing.md),
              Text('Não deu para carregar.\n$erro',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: Spacing.md),
              FilledButton(
                  onPressed: aoTentar, child: const Text('Tentar de novo')),
            ],
          ),
        ),
      );
}
