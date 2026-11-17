import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/auth_store.dart';
import '../../config/app_colors.dart';
import '../../main.dart' show routeObserver;
import '../../stores/session_store.dart';
import '../../services/admin_push_service.dart';
import '../../services/auth_admin_service.dart';
import '../../widgets/admin/alerta_livro_reclamacoes_card.dart';
import '../../widgets/admin/encomendas_telefone_aguardar_card.dart';
import '../../widgets/admin_closed_partners_card.dart';
import '../../widgets/admin_realtime_metrics_card.dart';
import '../../widgets/bora/bora_primary_button.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import 'admin_dashboard_content.dart';
import 'admin_global_search_screen.dart';
import 'admin_menu_accordion.dart';
import 'admin_menu_registry.dart';
import 'admin_notifications_inbox_screen.dart';

/// Painel Admin (PT-BR, só o Danilo usa) — o que ele vê ao abrir.
///
/// 2026-09-14 (missão painel-admin-limpo). O que mudou e porquê:
///  · Os números de cima vêm do RPC `admin_dashboard_metrics_v2`: hora de
///    Lisboa em tudo (às 00:18 o painel mostrava "Pedidos hoje 1" — era um
///    pedido de demonstração e ainda era "ontem" em UTC), nada de demo nas
///    contas (interruptor `admin_show_demo_data` para quando ele quer testar),
///    uma linha por vertical (entregas, Bora Motorista, serviços, limpeza,
///    lavagem, reservas — zero é zero e aparece), dinheiro em três cartões
///    lidos das tabelas de acerto, e alertas que abrem o ecrã certo.
///  · O menu deixou de ser uma lista de 90 cartões: vive em
///    `admin_menu_registry.dart`, por secções fechadas, com busca, favoritos
///    e "Arquivado" no fim. O desenho vive em `admin_dashboard_content.dart`
///    (widget puro, fotografável em teste); este ficheiro só carrega e navega.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with RouteAware {
  static const _kFavoritos = 'bora_admin.favoritos';

  /// Favoritos com que o painel nasce; ele muda pelo alfinete de cada linha.
  static const _favoritosIniciais = [
    'dinheiro_dinheiro_e_acertos',
    'operacao_pedidos_ao_vivo',
    'servicos_marcacoes_por_confirmar_e_faltas',
  ];

  late Future<Map<String, dynamic>> _metricsFuture;
  int _pendingSuggestionsCount = 0;
  int _unreadNotificationsCount = 0;
  List<String> _favoritos = const [];
  bool _demoBusy = false;

  @override
  void initState() {
    super.initState();
    _metricsFuture = _loadMetrics();
    _loadPendingSuggestionsCount();
    _loadUnreadNotificationsCount();
    _loadFavoritos();
    // 5F-β — registar FCM token admin + ouvir taps em pushes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AdminPushService.registerForAdmin();
      AdminPushService.setupDeepLinks(context);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  // Refresh sempre que o admin volta para o dashboard.
  @override
  void didPopNext() {
    _refresh();
  }

  Future<Map<String, dynamic>> _loadMetrics() async {
    final response =
        await Supabase.instance.client.rpc('admin_dashboard_metrics_v2');
    if (response is Map<String, dynamic>) return response;
    if (response is Map) return Map<String, dynamic>.from(response);
    throw StateError('Unexpected RPC response type: ${response.runtimeType}');
  }

  Future<void> _loadPendingSuggestionsCount() async {
    try {
      final response = await Supabase.instance.client
          .rpc('admin_skill_suggestions_stats');
      if (!mounted) return;
      final stats = response is Map
          ? Map<String, dynamic>.from(response)
          : <String, dynamic>{};
      setState(() {
        _pendingSuggestionsCount = (stats['pending'] as num?)?.toInt() ?? 0;
      });
    } catch (_) {/* silent */}
  }

  /// app-15-11 (auditoria S5): o sininho baixava até 100 avisos por ler e
  /// mostrava sempre "9+" ("100 não lidas") — eram 1789, 948 deles do robô
  /// a dizer "(0 registos)" e 1462 com mais de 7 dias. Agora conta no
  /// servidor, ao número exato, só o que pede ação (ver [AdminSino]). A caixa
  /// de avisos continua a mostrar tudo.
  Future<void> _loadUnreadNotificationsCount() async {
    try {
      final desde = DateTime.now().toUtc().subtract(AdminSino.janela);
      final n = await Supabase.instance.client
          .from('admin_notifications')
          .count(CountOption.exact)
          .isFilter('read_at', null)
          .isFilter('archived_at', null)
          .inFilter('severity', AdminSino.severidades)
          .gte('created_at', desde.toIso8601String());
      if (!mounted) return;
      setState(() => _unreadNotificationsCount = n);
    } catch (_) {/* silent */}
  }

  Future<void> _loadFavoritos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getStringList(_kFavoritos);
      if (!mounted) return;
      setState(() => _favoritos = v ?? List.of(_favoritosIniciais));
    } catch (_) {
      if (mounted) setState(() => _favoritos = List.of(_favoritosIniciais));
    }
  }

  Future<void> _toggleFavorito(String id) async {
    final next = List.of(_favoritos);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    setState(() => _favoritos = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kFavoritos, next);
    } catch (_) {/* fica só em memória */}
  }

  Future<void> _refresh() async {
    setState(() {
      _metricsFuture = _loadMetrics();
    });
    try {
      await _metricsFuture;
    } catch (_) {/* o FutureBuilder mostra o erro */}
    await _loadPendingSuggestionsCount();
    await _loadUnreadNotificationsCount();
  }

  /// Interruptor "mostrar dados de demonstração" (platform_settings
  /// `admin_show_demo_data`). Por defeito desligado: demo fora das contas.
  Future<void> _setDemoVisivel(bool v) async {
    if (_demoBusy) return;
    setState(() => _demoBusy = true);
    try {
      await Supabase.instance.client.rpc('admin_update_setting',
          params: {'p_key': 'admin_show_demo_data', 'p_value': v});
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Não deu: $e')));
      }
    } finally {
      if (mounted) setState(() => _demoBusy = false);
    }
  }

  bool get _isAuthorized => AuthAdminService.isAdmin();

  void _abrir(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    if (!_isAuthorized) {
      return AdminAcessoNegado(
        emailAtual: Supabase.instance.client.auth.currentUser?.email,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Painel Admin',
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Buscar (clientes, entregadores, parceiros, pedidos)',
            onPressed: () => _abrir(const AdminGlobalSearchScreen()),
          ),
          Badge(
            isLabelVisible: _unreadNotificationsCount > 0,
            label: Text(AdminSino.rotulo(_unreadNotificationsCount)),
            backgroundColor: AppColors.error,
            child: IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: AdminSino.dica(_unreadNotificationsCount),
              onPressed: () => _abrir(const AdminNotificationsInboxScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _metricsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              // app-15-11 (S5): sessão expirada (401 / "JWT expired") não é
              // "erro ao carregar métricas" — diz o que fazer e dá o botão.
              if (AdminSessaoExpirada.detectar(snapshot.error)) {
                return const AdminSessaoExpirada();
              }
              // Sem números não se fica sem menu: o painel continua a servir
              // para chegar a qualquer ecrã.
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const EncomendasTelefoneAguardarCard(),
                  const SizedBox(height: 40),
                  const Icon(Icons.error_outline,
                      size: 48, color: AppColors.error),
                  const SizedBox(height: 12),
                  Text(
                    'Erro ao carregar métricas:\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: BoraPrimaryButton(
                      onPressed: _refresh,
                      icon: Icons.refresh,
                      label: 'Tentar de novo',
                      expanded: false,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Gestão',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  ValueListenableBuilder<int>(
                    valueListenable: EncomendasTelefoneAguardarCard.aguardar,
                    builder: (_, aguardar, __) => AdminMenuAccordion(
                      sections: adminMenuSections(),
                      favoritos: _favoritos,
                      onToggleFavorito: _toggleFavorito,
                      badges: {
                        'skills': _pendingSuggestionsCount,
                        'encomendas_telefone': aguardar,
                      },
                    ),
                  ),
                ],
              );
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 17/11: encomendas por telefone à espera — acima de tudo.
                const EncomendasTelefoneAguardarCard(),
                // [fechar-tudo-2026-11-10 · E2e] prazo de 15 dias úteis.
                const AlertaLivroReclamacoesCard(),
                const AdminRealtimeMetricsCard(),
                const AdminClosedPartnersCard(),
                const SizedBox(height: 8),
                AdminDashboardContent(
                  metrics: snapshot.data ?? const <String, dynamic>{},
                  favoritos: _favoritos,
                  onToggleFavorito: _toggleFavorito,
                  onOpen: _abrir,
                  pendingSuggestionsCount: _pendingSuggestionsCount,
                  demoBusy: _demoBusy,
                  onSetDemoVisivel: _setDemoVisivel,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// O que vê quem abre o painel sem ser administrador. Em PT-BR (o painel é
/// brasileiro). Fora do `build` do painel para se poder testar sem rede.
///
/// fechar-app-15-11 (Bloco 6): a mensagem antiga dizia "Seu e-mail não está na
/// lista de administradores", mas a app não tem lista nenhuma de e-mails — o
/// portão olha para o perfil de administrador da conta (`app_metadata.role`).
/// Agora diz com que conta a pessoa entrou e o que tem de fazer. O e-mail da
/// conta de administrador NÃO aparece aqui: este ecrã é visto por quem não é
/// administrador.
class AdminAcessoNegado extends StatelessWidget {
  const AdminAcessoNegado({super.key, this.emailAtual});

  /// E-mail da conta com sessão aberta (null = ninguém entrou).
  final String? emailAtual;

  /// Sair da conta: o mesmo que "Terminar sessão" do Perfil, e volta ao
  /// início, onde se entra com a conta de admin. Usado aqui e no aviso de
  /// sessão expirada ([AdminSessaoExpirada]).
  static Future<void> sair(BuildContext context) async {
    context.read<AuthStore>().logout();
    await context.read<SessionStore>().clearRole();
    if (!context.mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  /// Texto mostrado, fora do `build` para o teste o ler tal e qual.
  static String mensagem(String? emailAtual) {
    final email = emailAtual?.trim() ?? '';
    if (email.isEmpty) {
      return 'Acesso negado.\n'
          'Você ainda não entrou em nenhuma conta.\n'
          'Entre com a conta de administrador do Bora para abrir o painel.';
    }
    return 'Acesso negado.\n'
        'Você entrou com $email, e essa conta não tem perfil de administrador.\n'
        'Saia dessa conta e entre com a conta de administrador do Bora.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Painel Admin'),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                mensagem(emailAtual),
                key: const Key('admin_acesso_negado_texto'),
                textAlign: TextAlign.center,
              ),
              // app-15-11 (caixa 18, ponto 5): a mensagem manda sair da conta,
              // mas não havia botão. Faz o mesmo que "Terminar sessão" do
              // Perfil e volta ao início, onde se entra com a conta de admin.
              if ((emailAtual ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  key: const Key('admin_acesso_negado_sair'),
                  onPressed: () => sair(context),
                  icon: const Icon(Icons.logout),
                  label: const Text('Sair dessa conta'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// O que o painel mostra quando a sessão expirou (app-15-11, auditoria S5).
/// O RPC dos números falhava com 401 / "JWT expired" e o painel dizia só
/// "Erro ao carregar métricas" com o texto técnico, sem dizer o que fazer.
/// Agora diz a frase e tem o botão "Sair" (o mesmo de [AdminAcessoNegado]).
class AdminSessaoExpirada extends StatelessWidget {
  const AdminSessaoExpirada({super.key});

  static const String mensagem = 'Sua sessão expirou. Saia e entre de novo.';

  /// A falha é de sessão vencida? 401 do PostgREST (PGRST301/PGRST303 =
  /// token inválido ou vencido), 401 do login, ou o texto "JWT expired".
  static bool detectar(Object? erro) {
    if (erro == null) return false;
    if (erro is PostgrestException) {
      final c = (erro.code ?? '').toUpperCase();
      if (c == '401' || c == 'PGRST301' || c == 'PGRST303') return true;
    }
    if (erro is AuthException && erro.statusCode == '401') return true;
    final t = erro.toString().toLowerCase();
    return t.contains('jwt expired') ||
        t.contains('pgrst301') ||
        t.contains('pgrst303');
  }

  @override
  Widget build(BuildContext context) {
    // ListView para o "puxar para atualizar" do painel continuar a funcionar.
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 40),
        const Icon(Icons.lock_clock_outlined,
            size: 48, color: AppColors.warning),
        const SizedBox(height: 12),
        const Text(
          mensagem,
          key: Key('admin_sessao_expirada_texto'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        Center(
          child: FilledButton.icon(
            key: const Key('admin_sessao_expirada_sair'),
            onPressed: () => AdminAcessoNegado.sair(context),
            icon: const Icon(Icons.logout),
            label: const Text('Sair'),
          ),
        ),
      ],
    );
  }
}

/// Sininho do painel (app-15-11, auditoria S5): conta só o que pede ação —
/// por ler, não arquivado, nível alto ou crítico, criado nos últimos 7 dias.
/// Puro (sem rede) para o teste ler o número e a frase tal e qual.
class AdminSino {
  AdminSino._();

  /// Níveis que contam no sininho (`admin_notifications.severity`).
  static const List<String> severidades = ['high', 'critical'];

  /// Só os avisos desta janela contam.
  static const Duration janela = Duration(days: 7);

  /// O número no sininho: exato até 99, depois "99+".
  static String rotulo(int n) => n > 99 ? '99+' : '$n';

  /// A dica do sininho, com o número exato.
  static String dica(int n) => switch (n) {
        <= 0 => 'Nenhum aviso importante por ler (últimos 7 dias)',
        1 => '1 aviso importante por ler (últimos 7 dias)',
        _ => '$n avisos importantes por ler (últimos 7 dias)',
      };
}
