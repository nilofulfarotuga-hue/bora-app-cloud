import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../models/order_model.dart';
import '../stores/order_store.dart';
import '../stores/session_store.dart';
import '../utils/euros.dart';
import '../utils/hora_lisboa.dart';
import '../utils/mensagem_online_recusado.dart' show mostraInterruptorOnline;
import '../utils/periodo_entregas.dart';
import '../widgets/atalho_trabalho_em_curso.dart';
import '../widgets/bora/bora_barra_separadores.dart';
import '../widgets/bora/bora_screen_app_bar.dart';
import '../widgets/trocar_de_papel.dart';
import 'driver/minha_conta_screen.dart';
import 'driver_home_screen.dart';
import 'ganhos_screen.dart';
import 'profile_screen.dart';

export '../utils/periodo_entregas.dart';

/// Casa do estafeta com a barra de baixo (missão fechar-tudo, bloco F,
/// 10/11/2026 — pedido do Danilo: "igual ao padrão Uber/Glovo").
///
/// Início (o mapa, o Online e as ofertas — o [DriverHomeScreen] de sempre,
/// intacto: GPS, batimento, serviço de fundo e ofertas continuam lá dentro),
/// Ganhos, Pedidos (em curso + histórico) e Conta.
///
/// Os quatro botões redondos só com ícone que viviam no topo do mapa
/// (Perfil, Ganhos, Trabalhar noutra coisa, Mudar modo) saíram de lá:
/// Ganhos é separador e os outros três são linhas com texto em "Conta".
///
/// O Início fica SEMPRE montado (IndexedStack): trocar de separador não
/// desliga o GPS nem perde ofertas. Os outros só se montam na 1.ª visita.
/// Conta por aprovar/recusada: sem barra, só o ecrã de espera de sempre.
class DriverMainScreen extends StatefulWidget {
  const DriverMainScreen({super.key});

  /// Os 4 separadores, por esta ordem (lidos também pelos testes).
  static const List<BoraSeparador> separadores = [
    BoraSeparador(
      rotulo: 'Início',
      icone: Icons.map_outlined,
      iconeAtivo: Icons.map,
    ),
    BoraSeparador(
      rotulo: 'Ganhos',
      icone: Icons.bar_chart_outlined,
      iconeAtivo: Icons.bar_chart,
    ),
    BoraSeparador(
      rotulo: 'Pedidos',
      icone: Icons.receipt_long_outlined,
      iconeAtivo: Icons.receipt_long,
    ),
    BoraSeparador(
      rotulo: 'Conta',
      icone: Icons.person_outline,
      iconeAtivo: Icons.person,
    ),
  ];

  static const int inicio = 0;
  static const int ganhos = 1;
  static const int pedidos = 2;
  static const int conta = 3;

  @override
  State<DriverMainScreen> createState() => _DriverMainScreenState();
}

class _DriverMainScreenState extends State<DriverMainScreen> {
  int _separador = DriverMainScreen.inicio;
  final Set<int> _abertos = <int>{DriverMainScreen.inicio};

  /// Ganhos volta a ler o servidor de cada vez que se abre o separador — como
  /// quando era um ecrã empurrado por cima do mapa.
  int _aberturasGanhos = 0;

  OrderStore? _orderStore;
  final Set<String> _ofertasVistas = <String>{};

  @override
  void initState() {
    super.initState();
    _orderStore = context.read<OrderStore>();
    _ofertasVistas.addAll(_orderStore!.availableOrders.map((o) => o.id));
    _orderStore!.addListener(_aoMudarPedidos);
  }

  @override
  void dispose() {
    _orderStore?.removeListener(_aoMudarPedidos);
    super.dispose();
  }

  /// Oferta nova (por ID — o realtime troca os objetos) com o estafeta noutro
  /// separador: volta ao Início, onde está o cartão Aceitar/Recusar. O som e
  /// a vibração continuam a ser do [DriverHomeScreen], como sempre.
  void _aoMudarPedidos() {
    final store = _orderStore;
    if (store == null || !mounted) return;
    final ids = store.availableOrders.map((o) => o.id).toSet();
    final novas = ids.difference(_ofertasVistas);
    _ofertasVistas
      ..clear()
      ..addAll(ids);
    if (novas.isNotEmpty && _separador != DriverMainScreen.inicio) {
      // Depois do frame: o aviso do OrderStore pode chegar a meio de um build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _separador != DriverMainScreen.inicio) {
          setState(() => _separador = DriverMainScreen.inicio);
        }
      });
      WidgetsBinding.instance.scheduleFrame();
    }
  }

  void _mudar(int i) {
    if (i == _separador) return;
    setState(() {
      _separador = i;
      _abertos.add(i);
      if (i == DriverMainScreen.ganhos) _aberturasGanhos++;
    });
  }

  /// O "Mudar modo" que vivia no botão redondo do mapa, tal e qual:
  /// TROCA DE MODO NAO E SAIR (2026-08-29) — a sessão FICA; o ecrã de
  /// escolha é que decide (com sessão troca por dentro, sem sessão manda
  /// entrar). Sai só a conta ACTIVA em memória.
  Future<void> _mudarModo() async {
    final authStore = context.read<AuthStore>();
    final sessionStore = context.read<SessionStore>();
    authStore.clearActiveAccountsKeepingSession();
    await sessionStore.clearRole();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final aprovado = context.select<AuthStore, bool>(
      (a) => mostraInterruptorOnline(a.currentDriverStatus),
    );
    final indice = aprovado ? _separador : DriverMainScreen.inicio;

    return Scaffold(
      body: IndexedStack(
        index: indice,
        children: [
          // Sempre na mesma posição da árvore: nunca se desmonta ao trocar de
          // separador nem quando a conta passa de "em análise" a aprovada.
          DriverHomeScreen(
            dentroDaBarra: true,
            aoAbrirGanhos: () => _mudar(DriverMainScreen.ganhos),
          ),
          _abertos.contains(DriverMainScreen.ganhos)
              ? GanhosScreen(key: ValueKey('ganhos_$_aberturasGanhos'))
              : const SizedBox.shrink(),
          _abertos.contains(DriverMainScreen.pedidos)
              ? PedidosEstafetaScreen(
                  aoAbrirInicio: () => _mudar(DriverMainScreen.inicio))
              : const SizedBox.shrink(),
          _abertos.contains(DriverMainScreen.conta)
              ? ContaEstafetaScreen(aoMudarModo: _mudarModo)
              : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: aprovado
          // A faixa "voltar ao trabalho" (limpeza/lavagem/casa) desenha-se no
          // fundo do ecrã por cima de tudo: a barra sobe a altura dela para
          // os separadores nunca ficarem tapados.
          ? ValueListenableBuilder<double>(
              valueListenable: AtalhoTrabalhoEmCurso.alturaOcupada,
              builder: (context, faixa, barra) => Padding(
                padding: EdgeInsets.only(bottom: faixa),
                child: barra,
              ),
              child: BoraBarraSeparadores(
                separadores: DriverMainScreen.separadores,
                atual: indice,
                aoMudar: _mudar,
              ),
            )
          : null,
    );
  }
}

/// As linhas do separador "Conta" do estafeta. Tudo o que antes estava em
/// botões redondos só com ícone no topo do mapa, agora com texto.
List<BoraLigacao> ligacoesDaContaEstafeta({
  required VoidCallback aoAbrirPerfil,
  required VoidCallback aoAbrirMinhaConta,
  required VoidCallback aoTrabalharNoutraCoisa,
  required VoidCallback aoMudarModo,
}) =>
    [
      BoraLigacao(
        chave: 'perfil',
        icone: Icons.person_outline,
        titulo: 'Perfil',
        subtitulo: 'Nome, telemóvel, veículo e terminar sessão',
        aoTocar: aoAbrirPerfil,
      ),
      BoraLigacao(
        chave: 'minha_conta',
        icone: Icons.fact_check_outlined,
        titulo: 'A minha conta',
        subtitulo: 'Documentos, NIF, IBAN e o que falta tratar',
        aoTocar: aoAbrirMinhaConta,
      ),
      BoraLigacao(
        chave: 'trabalhar_noutra_coisa',
        icone: Icons.work_outline,
        titulo: 'Trabalhar noutra coisa',
        subtitulo: 'Limpeza, lavagem ou casa, se também fazes',
        aoTocar: aoTrabalharNoutraCoisa,
      ),
      BoraLigacao(
        chave: 'mudar_modo',
        icone: Icons.swap_horiz,
        titulo: 'Mudar modo',
        subtitulo: 'Voltar a escolher: cliente, estafeta ou parceiro',
        aoTocar: aoMudarModo,
      ),
    ];

/// Separador "Conta" do estafeta.
class ContaEstafetaScreen extends StatelessWidget {
  const ContaEstafetaScreen({super.key, required this.aoMudarModo});

  final VoidCallback aoMudarModo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Conta'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          BoraListaLigacoes(
            ligacoes: ligacoesDaContaEstafeta(
              aoAbrirPerfil: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
              ),
              aoAbrirMinhaConta: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const MinhaContaScreen()),
              ),
              aoTrabalharNoutraCoisa: () => abrirTrocaDePapel(context),
              aoMudarModo: aoMudarModo,
            ),
          ),
        ],
      ),
    );
  }
}

/// Separador "Pedidos" do estafeta: lê o [OrderStore] (só leitura) e mostra
/// o [PedidosEstafetaCorpo].
class PedidosEstafetaScreen extends StatelessWidget {
  const PedidosEstafetaScreen({super.key, required this.aoAbrirInicio});

  final VoidCallback aoAbrirInicio;

  @override
  Widget build(BuildContext context) {
    final orderStore = context.watch<OrderStore>();
    final feitos = [...orderStore.completedOrders]
      ..sort((a, b) => (b.deliveredAt ?? b.createdAt)
          .compareTo(a.deliveredAt ?? a.createdAt));
    return PedidosEstafetaCorpo(
      emCurso: orderStore.myOrders.length,
      ofertas: orderStore.availableOrders.length,
      historico: feitos,
      aoAbrirInicio: aoAbrirInicio,
    );
  }
}

/// O que se vê no separador "Pedidos": o que está em curso (os cartões com
/// os botões continuam no Início, onde sempre estiveram — daqui só se salta
/// para lá) e as entregas feitas no período escolhido, da mais recente para a
/// mais antiga, com o total ganho no período em número grande.
class PedidosEstafetaCorpo extends StatefulWidget {
  const PedidosEstafetaCorpo({
    super.key,
    required this.emCurso,
    required this.ofertas,
    required this.historico,
    required this.aoAbrirInicio,
    this.haMaisNoServidor = false,
    this.aCarregarMais = false,
    this.aoPedirMaisAntigas,
    this.agora,
  });

  /// fechar-app-15-11 (Bloco 2): o histórico mostra-se às páginas de 20.
  static const int porPagina = 20;

  final int emCurso;
  final int ofertas;
  final List<OrderModel> historico;
  final VoidCallback aoAbrirInicio;

  /// Há entregas mais antigas que ainda não vieram do servidor.
  final bool haMaisNoServidor;

  /// Está a chegar mais uma página do servidor.
  final bool aCarregarMais;

  /// Pedir ao servidor a página seguinte (quando as que cá estão acabam).
  final VoidCallback? aoPedirMaisAntigas;

  /// Relógio do ecrã (só os testes o fixam). Vazio = agora.
  final DateTime Function()? agora;

  @override
  State<PedidosEstafetaCorpo> createState() => _PedidosEstafetaCorpoState();
}

class _PedidosEstafetaCorpoState extends State<PedidosEstafetaCorpo> {
  int _visiveis = PedidosEstafetaCorpo.porPagina;
  PeriodoEntregas _periodo = PeriodoEntregas.estaSemana;
  bool _aberto = true;

  void _verMais(int noPeriodo, bool podeHaverMaisNoServidor) {
    setState(() => _visiveis += PedidosEstafetaCorpo.porPagina);
    if (_visiveis > noPeriodo && podeHaverMaisNoServidor) {
      widget.aoPedirMaisAntigas?.call();
    }
  }

  void _escolher(PeriodoEntregas p) {
    if (p == _periodo) return;
    setState(() {
      _periodo = p;
      _visiveis = PedidosEstafetaCorpo.porPagina;
      _aberto = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final emCurso = widget.emCurso;
    final ofertas = widget.ofertas;
    final aoAbrirInicio = widget.aoAbrirInicio;
    final agora = (widget.agora ?? DateTime.now)();
    // Conta a hora da entrega; pedidos antigos sem ela usam a hora do pedido.
    DateTime quando(OrderModel o) => o.deliveredAt ?? o.createdAt;
    final doPeriodo = widget.historico
        .where((o) => entregaNoPeriodo(quando(o), _periodo, agora))
        .toList();
    final ganho = doPeriodo.fold<double>(0, (s, o) => s + o.driverEarnings);
    final historico = doPeriodo.take(_visiveis).toList();
    // O servidor manda as entregas da mais recente para a mais antiga: se a
    // mais antiga que cá está ainda não é anterior ao período, pode haver
    // mais do período lá.
    final podeHaverMaisNoServidor = widget.haMaisNoServidor &&
        (widget.historico.isEmpty ||
            !diaLisboa(quando(widget.historico.last))
                .isBefore(inicioDoPeriodo(_periodo, agora)));
    final haMais = doPeriodo.length > _visiveis || podeHaverMaisNoServidor;
    const titulo = TextStyle(fontWeight: FontWeight.bold, fontSize: 16);
    final String? resumo = emCurso > 0
        ? (emCurso == 1 ? '1 pedido em curso' : '$emCurso pedidos em curso')
        : ofertas > 0
            ? (ofertas == 1
                ? '1 oferta à espera de resposta'
                : '$ofertas ofertas à espera de resposta')
            : null;
    final n = doPeriodo.length;
    // Total honesto: se ainda faltam entregas do período no servidor, diz-se.
    final contagem = (n == 1 ? '1 entrega' : '$n entregas') +
        (podeHaverMaisNoServidor ? ' (há mais por carregar)' : '');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Pedidos'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Em curso', style: titulo),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: resumo == null
                ? const ListTile(
                    key: Key('pedidos_estafeta_sem_curso'),
                    leading: Icon(Icons.delivery_dining_outlined),
                    title: Text('Nenhum pedido em curso'),
                    subtitle: Text(
                        'Fica Online no Início para receberes ofertas.'),
                  )
                : ListTile(
                    key: const Key('pedidos_estafeta_em_curso'),
                    leading: const Icon(Icons.delivery_dining,
                        color: AppColors.primary),
                    title: Text(resumo),
                    subtitle: const Text('Os botões estão no Início.'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: aoAbrirInicio,
                  ),
          ),
          const SizedBox(height: 24),
          const Text('Histórico', style: titulo),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final p in PeriodoEntregas.values) ...[
                  ChoiceChip(
                    key: ValueKey('pedidos_estafeta_periodo_${p.name}'),
                    label: Text(p.rotulo),
                    selected: p == _periodo,
                    selectedColor: AppColors.primary.withValues(alpha: 0.15),
                    onSelected: (_) => _escolher(p),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                InkWell(
                  key: const Key('pedidos_estafeta_total'),
                  onTap: () => setState(() => _aberto = !_aberto),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ganhaste — ${_periodo.rotulo.toLowerCase()}',
                                style: TextStyle(
                                    color: Colors.grey.shade700, fontSize: 13),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                eur(ganho),
                                key: const Key('pedidos_estafeta_total_valor'),
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                              Text(
                                contagem,
                                key: const Key(
                                    'pedidos_estafeta_total_contagem'),
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          _aberto ? Icons.expand_less : Icons.expand_more,
                          semanticLabel: _aberto
                              ? 'Fechar a lista'
                              : 'Abrir a lista',
                        ),
                      ],
                    ),
                  ),
                ),
                if (_aberto) ...[
                  const Divider(height: 1),
                  if (historico.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        widget.historico.isEmpty
                            ? 'Ainda não há entregas concluídas.'
                            : 'Sem entregas neste período.',
                        key: const Key('pedidos_estafeta_historico_vazio'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    )
                  else
                    for (var i = 0; i < historico.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        key: ValueKey('pedido_feito_${historico[i].id}'),
                        title: Text(historico[i].serviceType.label),
                        // Regra do ganho grande: o valor do cliente só em
                        // pequeno e só quando ele pagou em dinheiro.
                        subtitle: Text(
                          '${dataHoraLisboa(quando(historico[i]).toIso8601String())}'
                          ' • ${historico[i].distanceKm.toStringAsFixed(1)} km'
                          '${historico[i].paymentMethod == PaymentMethod.cash ? ' • dinheiro ${eur(historico[i].total)}' : ''}'
                          // Caixa 71 B3.4 (15/11): a gorjeta do cliente aparece no pedido entregue.
                          '${historico[i].tipCents > 0 ? ' • gorjeta +${eur(historico[i].tipCents / 100)}' : ''}',
                        ),
                        trailing: Text(
                          '+${eur(historico[i].driverEarnings)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ],
                ],
              ],
            ),
          ),
          if (_aberto && haMais) ...[
            const SizedBox(height: 8),
            Center(
              child: widget.aCarregarMais
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : TextButton(
                      key: const Key('pedidos_estafeta_ver_mais'),
                      onPressed: () => _verMais(n, podeHaverMaisNoServidor),
                      child: const Text('Ver entregas mais antigas'),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
