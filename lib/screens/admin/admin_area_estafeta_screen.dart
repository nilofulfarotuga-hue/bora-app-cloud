// ÁREA DO ESTAFETA (15/11/2026, missão app-15-11 — ordem do Danilo): o admin
// escolhe um entregador e faz por ele o que ele faz no app. Cada ação pede
// confirmação (as que mudam alguma coisa, com motivo) e fica no log de
// auditoria com o nome de quem fez.
//
// Um ecrã só, de cima para baixo, uma secção por cartão:
//   1. Agora ............ presença ("Ligado, GPS há 12 s"), posição no Google
//                         Maps, avisos para o celular (GPS / sem sinal)
//   2. Pedidos dele ..... passar para outro, devolver à fila, entregue sem código
//   3. Dar um pedido .... pedidos esperando entregador → "Dar este pedido a ele"
//   4. Ganhos ........... Hoje / Esta semana / Semana passada / Este mês
//   5. Conta e documentos semáforo da conta, robô dos documentos, lembrete,
//                         modo de trabalho
//   6. O que o admin já fez por ele (log de auditoria + histórico de atribuições)
//
// Ainda sem função no servidor (botões desligados, com a frase
// [kFrasePrecisaFuncaoNova]): ligar/desligar por ele, "Recolhi"/"A caminho",
// fatura do mês, enviar documento por ele.
//
// Todas as chamadas ao servidor estão em AdminAreaEstafetaService. Textos em
// PT-BR (painel). Dinheiro com eurCents; horas de Lisboa.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/admin_area_estafeta_service.dart';
import '../../services/minha_conta.dart';
import '../../services/robo_documentos.dart';
import '../../utils/euros.dart';
import '../../utils/periodo_entregas.dart';
import '../../widgets/admin/admin_entregue_sem_codigo_button.dart';
import '../../widgets/admin/escolher_estafeta_sheet.dart'
    show EstafetaParaAtribuir, plataformaLabel;
import '../../widgets/bora/bora_screen_app_bar.dart';
import '_admin_rpc_errors.dart';

const TextStyle _estiloPequeno =
    TextStyle(fontSize: 12, color: AppColors.textSecondary);

class AdminAreaEstafetaScreen extends StatefulWidget {
  const AdminAreaEstafetaScreen({
    super.key,
    required this.driverId,
    required this.userId,
    this.nome,
    this.servico,
  });

  /// `drivers.id` (uuid).
  final String driverId;

  /// `drivers.user_id` — o id de login; os pedidos usam este.
  final String userId;

  final String? nome;

  /// Os testes passam um serviço falso; por defeito, o Supabase da app.
  final AdminAreaEstafetaService? servico;

  @override
  State<AdminAreaEstafetaScreen> createState() => _AdminAreaEstafetaScreenState();
}

class _DadosAgora {
  const _DadosAgora({this.presenca, this.posicao});
  final PresencaEstafeta? presenca;
  final PosicaoEstafeta? posicao;
}

class _DadosConta {
  const _DadosConta({required this.conta, this.documentos = const [], this.modo});
  final ContaDoEstafeta conta;
  final List<VereditoRobo> documentos;
  final ModoTrabalho? modo;
}

class _AdminAreaEstafetaScreenState extends State<AdminAreaEstafetaScreen> {
  late final AdminAreaEstafetaService _servico =
      widget.servico ?? const AdminAreaEstafetaSupabase();

  late Future<_DadosAgora> _fAgora;
  late Future<List<PedidoAberto>> _fPedidos;
  late Future<ExtratoGanhos> _fGanhos;
  late Future<_DadosConta> _fConta;
  late Future<List<RegistoAdmin>> _fHistorico;

  PeriodoEntregas _periodo = PeriodoEntregas.estaSemana;

  /// A ação que está a correr: enquanto houver uma, os botões ficam desligados.
  String? _acaoEmCurso;

  /// A última presença lida (para avisar antes de lhe dar um pedido).
  PresencaEstafeta? _presencaAtual;

  /// Pedidos que ficaram reservados para ele nesta visita (o servidor ainda
  /// não lhes pôs entregador, por isso continuam na lista de espera).
  final Set<String> _reservadosAgora = <String>{};

  bool get _livre => _acaoEmCurso == null;

  String get _nome {
    final n = (widget.nome ?? '').trim();
    return n.isEmpty ? 'o entregador' : n;
  }

  Set<String> get _idsDele =>
      <String>{widget.userId, widget.driverId}..removeWhere((s) => s.isEmpty);

  @override
  void initState() {
    super.initState();
    // `ignore()`: o erro fica para o FutureBuilder mostrar, nunca "solto".
    _fAgora = _lerAgora()..ignore();
    _fPedidos = _servico.pedidosAbertos()..ignore();
    _fGanhos = _servico.ganhos(widget.userId)..ignore();
    _fConta = _lerConta()..ignore();
    _fHistorico =
        _servico.historico(userId: widget.userId, driverId: widget.driverId)..ignore();
  }

  // ── Leituras ───────────────────────────────────────────────────────────────

  Future<_DadosAgora> _lerAgora() async {
    final presenca = await _servico.presenca(widget.driverId);
    _presencaAtual = presenca;
    PosicaoEstafeta? posicao;
    try {
      posicao = await _servico.posicao(userId: widget.userId, driverId: widget.driverId);
    } catch (e) {
      debugPrint('[AreaEstafeta] posição: $e');
    }
    return _DadosAgora(presenca: presenca, posicao: posicao);
  }

  Future<_DadosConta> _lerConta() async {
    final conta = await _servico.conta(widget.userId);
    var documentos = <VereditoRobo>[];
    ModoTrabalho? modo;
    try {
      documentos = await _servico.documentos(widget.userId);
    } catch (e) {
      debugPrint('[AreaEstafeta] documentos: $e');
    }
    try {
      modo = await _servico.modoTrabalho(widget.driverId);
    } catch (e) {
      debugPrint('[AreaEstafeta] modo de trabalho: $e');
    }
    return _DadosConta(conta: conta, documentos: documentos, modo: modo);
  }

  void _recarregarAgora() {
    if (!mounted) return;
    setState(() {
      _fAgora = _lerAgora()..ignore();
    });
  }

  void _recarregarPedidos() {
    if (!mounted) return;
    setState(() {
      _fPedidos = _servico.pedidosAbertos()..ignore();
    });
  }

  void _recarregarGanhos() {
    if (!mounted) return;
    setState(() {
      _fGanhos = _servico.ganhos(widget.userId)..ignore();
    });
  }

  void _recarregarConta() {
    if (!mounted) return;
    setState(() {
      _fConta = _lerConta()..ignore();
    });
  }

  void _recarregarHistorico() {
    if (!mounted) return;
    setState(() {
      _fHistorico = _servico
          .historico(userId: widget.userId, driverId: widget.driverId)
        ..ignore();
    });
  }

  /// Depois de mexer num pedido: presença, pedidos e histórico.
  void _recarregarDepoisDeAcao() {
    _recarregarAgora();
    _recarregarPedidos();
    _recarregarHistorico();
  }

  void _recarregarTudo() {
    _recarregarDepoisDeAcao();
    _recarregarGanhos();
    _recarregarConta();
  }

  // ── Ajudas das ações ───────────────────────────────────────────────────────

  String _erroLegivel(Object e) =>
      e is AreaEstafetaErro ? e.mensagem : humanizeAdminRpcError(e);

  void _avisar(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: erro ? AppColors.error : null,
    ));
  }

  /// Corre uma ação com os botões desligados; erro vira aviso em palavras.
  Future<void> _executar(String chave, Future<void> Function() corpo) async {
    if (!_livre || !mounted) return;
    setState(() {
      _acaoEmCurso = chave;
    });
    try {
      await corpo();
    } catch (e) {
      _avisar('Não foi possível: ${_erroLegivel(e)}', erro: true);
    } finally {
      if (mounted) {
        setState(() {
          _acaoEmCurso = null;
        });
      }
    }
  }

  /// Confirmação com motivo obrigatório. null = desistiu.
  Future<String?> _pedirMotivo({
    required String titulo,
    required String explicacao,
    required String botao,
    String? aviso,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => _MotivoDialog(
        titulo: titulo,
        explicacao: explicacao,
        botao: botao,
        aviso: aviso,
      ),
    );
  }

  /// Confirmação simples (avisos para o celular, que não mudam nada nele).
  Future<bool> _confirmar({
    required String titulo,
    required String explicacao,
    required String botao,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(explicacao),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            key: const Key('area_confirmar'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(botao),
          ),
        ],
      ),
    );
    return ok == true;
  }

  // ── Ações ──────────────────────────────────────────────────────────────────

  Future<void> _abrirMapa(PosicaoEstafeta pos) async {
    var abriu = false;
    try {
      abriu = await launchUrl(pos.linkMaps, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[AreaEstafeta] mapa: $e');
    }
    if (!abriu) _avisar('Não consegui abrir o Google Maps.', erro: true);
  }

  Future<void> _avisarGps() async {
    if (!_livre) return;
    final ok = await _confirmar(
      titulo: 'Mandar o aviso de GPS?',
      explicacao: 'Ele recebe no celular que a Bora não está recebendo a '
          'localização dele e que precisa abrir o app. Fica registrado.',
      botao: 'Mandar aviso',
    );
    if (!ok || !mounted) return;
    await _executar('aviso_gps', () async {
      final r = await _servico.avisarGps(widget.driverId);
      if (r['ok'] == true) {
        _avisar('Aviso de GPS enviado para o celular de $_nome.');
        _recarregarHistorico();
      } else {
        _avisar('Não foi possível: ${mensagemDoServidor(r)}', erro: true);
      }
    });
  }

  Future<void> _avisarSemSinal() async {
    if (!_livre) return;
    final ok = await _confirmar(
      titulo: 'Mandar o aviso "sem sinal"?',
      explicacao: 'Ele recebe no celular que está ligado mas a Bora não '
          'recebe sinal dele, para abrir o app. Fica registrado.',
      botao: 'Mandar aviso',
    );
    if (!ok || !mounted) return;
    await _executar('aviso_sem_sinal', () async {
      final r = await _servico.avisarSemSinal(widget.userId);
      if (r['ok'] == true) {
        _avisar('Aviso "sem sinal" enviado para o celular de $_nome.');
        _recarregarHistorico();
      } else {
        _avisar('Não foi possível: ${mensagemDoServidor(r)}', erro: true);
      }
    });
  }

  Future<void> _darAEle(PedidoAberto p) async {
    if (!_livre) return;
    final motivo = await _pedirMotivo(
      titulo: 'Dar o pedido ${p.codigo} a $_nome?',
      explicacao: 'É o mesmo que ele aceitar o pedido no app. Ele recebe um '
          'aviso no celular e fica registrado com o seu nome.',
      botao: 'Dar a ele',
      aviso: avisoAntesDeDar(p, presenca: _presencaAtual, agora: DateTime.now()),
    );
    if (motivo == null || !mounted) return;
    await _executar('dar:${p.id}', () async {
      final r = await _servico.atribuirPedido(
        orderId: p.id,
        novoEntregador: widget.userId,
        motivo: motivo,
      );
      if (r['ok'] != true) {
        _avisar('Não foi possível: ${mensagemDoServidor(r)}', erro: true);
        return;
      }
      final reservado = r['pre_atribuicao'] == true;
      if (reservado && mounted) {
        setState(() {
          _reservadosAgora.add(p.id);
        });
      }
      _avisar(reservado
          ? 'Pedido ${p.codigo} reservado para $_nome. Ele recebe a oferta '
              'quando a loja marcar pronto.'
          : 'Pedido ${p.codigo} dado a $_nome. Aviso enviado para o celular dele.');
      _recarregarDepoisDeAcao();
    });
  }

  /// A lista de outros entregadores (sem ele). null = não deu.
  Future<List<EstafetaParaAtribuir>?> _carregarOutros(PedidoAberto p) async {
    setState(() {
      _acaoEmCurso = 'lista:${p.id}';
    });
    try {
      final todos = await _servico.outrosEntregadores(p.id);
      final dele = _idsDele;
      return todos
          .where((e) => !dele.contains(e.userId) && !dele.contains(e.driverId))
          .toList();
    } catch (e) {
      _avisar('Não consegui carregar os entregadores: ${_erroLegivel(e)}', erro: true);
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _acaoEmCurso = null;
        });
      }
    }
  }

  Future<void> _passar(PedidoAberto p) async {
    if (!_livre) return;
    final outros = await _carregarOutros(p);
    if (outros == null || !mounted) return;
    final escolhido = await showDialog<EstafetaParaAtribuir>(
      context: context,
      builder: (_) => _EscolherOutroDialog(codigo: p.codigo, entregadores: outros),
    );
    if (escolhido == null || !mounted) return;
    final avisos = <String>[
      if (!escolhido.vaiReceber)
        'Atenção: ${escolhido.nome} não vai receber o aviso agora '
            '(${escolhido.motivoNaoRecebe}).',
      if (kEstadosComEncomenda.contains(p.status))
        'A encomenda já está com $_nome: ${escolhido.nome} vai precisar '
            'buscá-la com ele.',
    ];
    final motivo = await _pedirMotivo(
      titulo: 'Passar o pedido ${p.codigo} para ${escolhido.nome}?',
      explicacao: 'Ele sai deste pedido e ${escolhido.nome} recebe um aviso no '
          'celular. Fica registrado com o seu nome.',
      botao: 'Passar o pedido',
      aviso: avisos.isEmpty ? null : avisos.join('\n'),
    );
    if (motivo == null || !mounted) return;
    await _executar('passar:${p.id}', () async {
      final r = await _servico.atribuirPedido(
        orderId: p.id,
        novoEntregador: escolhido.userId,
        motivo: motivo,
      );
      if (r['ok'] == true) {
        _avisar('Pedido ${p.codigo} passado para ${r['estafeta'] ?? escolhido.nome}.');
        _recarregarDepoisDeAcao();
      } else {
        _avisar('Não foi possível: ${mensagemDoServidor(r)}', erro: true);
      }
    });
  }

  Future<void> _devolver(PedidoAberto p) async {
    if (!_livre) return;
    final motivo = await _pedirMotivo(
      titulo: 'Devolver o pedido ${p.codigo} à fila?',
      explicacao: 'É o mesmo que ele largar o pedido no app: ele sai do pedido, '
          'recebe um aviso e o pedido volta a tocar para os entregadores '
          'disponíveis. Fica registrado com o seu nome.',
      botao: 'Devolver à fila',
    );
    if (motivo == null || !mounted) return;
    await _executar('devolver:${p.id}', () async {
      final r = await _servico.devolverAFila(orderId: p.id, motivo: motivo);
      if (r['ok'] == true) {
        _avisar('Pedido ${p.codigo} devolvido à fila.');
        _recarregarDepoisDeAcao();
      } else {
        _avisar('Não foi possível: ${mensagemDoServidor(r)}', erro: true);
      }
    });
  }

  /// O botão "Marcar entregue sem código" (que já existe) chama isto: o
  /// servidor grava pelo pedido; aqui grava-se também ligado a ele.
  Future<Map<String, dynamic>> _marcarSemCodigo(String orderId, String motivo) async {
    if (mounted) {
      setState(() {
        _acaoEmCurso = 'sem_codigo:$orderId';
      });
    }
    try {
      final r = await _servico.marcarEntregueSemCodigo(orderId, motivo);
      if (r['ok'] == true && r['ja_entregue'] != true) {
        final gravou = await _servico.registarAuditoria(
          acao: 'entregue_sem_codigo',
          driverId: widget.driverId,
          detalhes: <String, dynamic>{
            'user_id': widget.userId,
            'pedido': orderId,
            'motivo': motivo,
          },
        );
        if (!gravou) {
          _avisar('A entrega foi fechada, mas o registro ligado a ele falhou.',
              erro: true);
        }
      }
      return r;
    } finally {
      if (mounted) {
        setState(() {
          _acaoEmCurso = null;
        });
      }
    }
  }

  Future<void> _lembrarDocumentos() async {
    if (!_livre) return;
    final ok = await _confirmar(
      titulo: 'Lembrar os documentos que faltam?',
      explicacao: 'Ele recebe um aviso no app e um email com a lista do que '
          'falta. Fica registrado.',
      botao: 'Mandar lembrete',
    );
    if (!ok || !mounted) return;
    await _executar('lembrar_documentos', () async {
      final r = await _servico.lembrarDocumentos(widget.userId);
      if (r['ok'] == true) {
        final faltas = r['faltas'];
        final lista = faltas is List ? faltas.map((e) => '$e').join(', ') : '';
        _avisar(lista.isEmpty
            ? 'Lembrete enviado para $_nome.'
            : 'Lembrete enviado para $_nome (faltam: $lista).');
        _recarregarHistorico();
      } else {
        _avisar('Não foi possível: ${mensagemDoServidor(r)}', erro: true);
      }
    });
  }

  Future<void> _mudarModo(ModoTrabalho atual, String novo) async {
    if (!_livre) return;
    final motivo = await _pedirMotivo(
      titulo: 'Mudar o modo de trabalho para "${rotuloModoTrabalho(novo)}"?',
      explicacao: 'Muda o que $_nome recebe no app. Fica registrado com o seu '
          'nome e o motivo.',
      botao: 'Mudar',
    );
    if (motivo == null || !mounted) return;
    await _executar('modo_trabalho', () async {
      final r = await _servico.definirModoTrabalho(driverId: widget.driverId, modo: novo);
      if (r['ok'] != true) {
        _avisar('Não foi possível: ${mensagemDoServidor(r)}', erro: true);
        return;
      }
      // O servidor grava a mudança sem o motivo: o motivo fica aqui.
      final gravou = await _servico.registarAuditoria(
        acao: 'modo_trabalho',
        driverId: widget.driverId,
        detalhes: <String, dynamic>{
          'user_id': widget.userId,
          'motivo': motivo,
          'antes': atual.modoEfetivo,
          'depois': novo,
        },
      );
      _avisar(
        gravou
            ? 'Modo de trabalho mudado para "${rotuloModoTrabalho(novo)}".'
            : 'Modo de trabalho mudado, mas o registro do motivo falhou.',
        erro: !gravou,
      );
      _recarregarConta();
      _recarregarHistorico();
    });
  }

  void _escolherPeriodo(PeriodoEntregas p) {
    if (p == _periodo) return;
    setState(() {
      _periodo = p;
    });
  }

  // ── Ecrã ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Área do estafeta',
        actions: [
          IconButton(
            tooltip: 'Atualizar tudo',
            icon: const Icon(Icons.refresh),
            onPressed: _recarregarTudo,
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_livre) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _cabecalho(),
                      _secaoAgora(),
                      _secaoPedidosDele(),
                      _secaoDarPedido(),
                      _secaoGanhos(),
                      _secaoConta(),
                      _secaoHistorico(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cabecalho() {
    final nome = (widget.nome ?? '').trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            nome.isEmpty ? 'Entregador' : nome,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: Spacing.xs),
          const Text(
            'Aqui você faz por ele o que ele faz no app. Tudo o que fizer fica '
            'registrado no log de auditoria com o seu nome e o motivo.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  // 1 ─ Agora
  Widget _secaoAgora() {
    return _Secao(
      titulo: 'Agora',
      paraQue: 'Mostra se ele está ligado e com sinal neste momento, e deixa '
          'você mandar avisos para o celular dele.',
      aoAtualizar: _recarregarAgora,
      child: FutureBuilder<_DadosAgora>(
        future: _fAgora,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const _Carregando();
          final dados = snap.data;
          if (snap.hasError || dados == null) {
            return _ErroSecao(
              texto: _erroLegivel(snap.error ?? 'sem resposta'),
              aoTentar: _recarregarAgora,
            );
          }
          return _conteudoAgora(dados);
        },
      ),
    );
  }

  Widget _conteudoAgora(_DadosAgora d) {
    final p = d.presenca;
    final pos = d.posicao;
    final agora = DateTime.now();
    final cor = switch (nivelPresenca(p)) {
      NivelPresenca.ligado => AppColors.primary,
      NivelPresenca.semSinal => AppColors.warning,
      NivelPresenca.desligado => AppColors.textSecondary,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.circle, size: 14, color: cor),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                textoPresenca(p, agora),
                key: const Key('area_presenca'),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: cor),
              ),
            ),
          ],
        ),
        if (p != null) ...[
          const SizedBox(height: Spacing.sm),
          _LinhaInfo(
            icone: Icons.wifi_tethering,
            rotulo: 'Último sinal',
            valor: textoUltimoSinal(p.ultimoSinal, agora),
          ),
          _LinhaInfo(
            icone: p.temNotificacoes ? Icons.notifications_active : Icons.notifications_off,
            rotulo: 'Notificações',
            valor: p.temNotificacoes
                ? 'Sim (${p.aparelhos} aparelho(s))'
                : 'Não: assim não recebe pedidos',
          ),
          _LinhaInfo(
            icone: Icons.devices,
            rotulo: 'Como usa a Bora',
            valor: plataformaLabel(p.plataforma),
          ),
          _LinhaInfo(
            icone: Icons.delivery_dining,
            rotulo: 'Pedidos em curso',
            valor: '${p.pedidosEmCurso}',
          ),
        ],
        const SizedBox(height: Spacing.md),
        if (pos != null) ...[
          OutlinedButton.icon(
            key: const Key('area_ver_mapa'),
            onPressed: () => _abrirMapa(pos),
            icon: const Icon(Icons.map_outlined),
            label: const Text('Ver onde ele está (Google Maps)'),
          ),
          Padding(
            padding: const EdgeInsets.only(top: Spacing.xs),
            child: Text(
              'Posição de ${dataHoraLisboaDe(pos.quando)} (hora de Lisboa).',
              style: _estiloPequeno,
            ),
          ),
        ] else
          const Text(
            'Sem posição recente: ela só aparece com o GPS dele ligado nos '
            'últimos 5 minutos.',
            style: _estiloPequeno,
          ),
        const SizedBox(height: Spacing.md),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            OutlinedButton.icon(
              key: const Key('area_aviso_gps'),
              onPressed: _livre ? _avisarGps : null,
              icon: const Icon(Icons.gps_not_fixed),
              label: const Text('Mandar aviso de GPS'),
            ),
            OutlinedButton.icon(
              key: const Key('area_aviso_sem_sinal'),
              onPressed: _livre && (p?.ligado ?? false) ? _avisarSemSinal : null,
              icon: const Icon(Icons.signal_wifi_off),
              label: const Text('Mandar aviso "sem sinal"'),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        const _PendentesDoServidor(botoes: [
          _BotaoPendente('area_ligar_por_ele', Icons.power_settings_new, 'Ligar por ele'),
          _BotaoPendente('area_desligar_por_ele', Icons.power_off, 'Desligar por ele'),
        ]),
      ],
    );
  }

  // 2 ─ Pedidos dele agora
  Widget _secaoPedidosDele() {
    return _Secao(
      titulo: 'Pedidos dele agora',
      paraQue: 'Os pedidos que estão com ele neste momento: você pode passar '
          'para outro, devolver à fila ou fechar a entrega por ele.',
      aoAtualizar: _recarregarPedidos,
      child: FutureBuilder<List<PedidoAberto>>(
        future: _fPedidos,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const _Carregando();
          final todos = snap.data;
          if (snap.hasError || todos == null) {
            return _ErroSecao(
              texto: _erroLegivel(snap.error ?? 'sem resposta'),
              aoTentar: _recarregarPedidos,
            );
          }
          final meus = pedidosDele(todos, userId: widget.userId, driverId: widget.driverId);
          if (meus.isEmpty) {
            return const Text('Ele não tem pedidos neste momento.', style: _estiloPequeno);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final p in meus) _cartaoPedidoDele(p)],
          );
        },
      ),
    );
  }

  Widget _cartaoPedidoDele(PedidoAberto p) {
    final semDevolver = motivoSemDevolverAFila(p);
    return _CaixaPedido(
      pedido: p,
      children: [
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            OutlinedButton.icon(
              key: Key('area_passar_${p.id}'),
              onPressed: _livre ? () => _passar(p) : null,
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Passar para outro entregador'),
            ),
            OutlinedButton.icon(
              key: Key('area_devolver_${p.id}'),
              onPressed: _livre && semDevolver == null ? () => _devolver(p) : null,
              icon: const Icon(Icons.undo),
              label: const Text('Devolver à fila'),
            ),
          ],
        ),
        if (semDevolver != null)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.xs),
            child: Text(semDevolver, style: _estiloPequeno),
          ),
        IgnorePointer(
          ignoring: !_livre,
          child: AdminEntregueSemCodigoButton(
            orderId: p.id,
            status: p.status,
            onDone: _recarregarDepoisDeAcao,
            marcar: _marcarSemCodigo,
          ),
        ),
        const SizedBox(height: Spacing.md),
        _PendentesDoServidor(botoes: [
          _BotaoPendente('area_recolhi_${p.id}', Icons.inventory_2_outlined, 'Recolhi'),
          _BotaoPendente('area_a_caminho_${p.id}', Icons.directions_bike, 'A caminho'),
        ]),
      ],
    );
  }

  // 3 ─ Dar um pedido a ele
  Widget _secaoDarPedido() {
    return _Secao(
      titulo: 'Dar um pedido a ele',
      paraQue: 'Pedidos esperando entregador: dar um a ele é o mesmo que ele '
          'aceitar no app.',
      aoAtualizar: _recarregarPedidos,
      child: FutureBuilder<List<PedidoAberto>>(
        future: _fPedidos,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const _Carregando();
          final todos = snap.data;
          if (snap.hasError || todos == null) {
            return _ErroSecao(
              texto: _erroLegivel(snap.error ?? 'sem resposta'),
              aoTentar: _recarregarPedidos,
            );
          }
          final espera = pedidosEsperandoEntregador(todos);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _AvisoAgendado(),
              const SizedBox(height: Spacing.sm),
              if (espera.isEmpty)
                const Text('Nenhum pedido esperando entregador agora.', style: _estiloPequeno)
              else
                for (final p in espera) _cartaoParaDar(p),
            ],
          );
        },
      ),
    );
  }

  Widget _cartaoParaDar(PedidoAberto p) {
    final agendado = p.agendadoPara;
    return _CaixaPedido(
      pedido: p,
      extras: [
        Text('Feito em ${dataHoraLisboaDe(p.criadoEm)}', style: _estiloPequeno),
        if (agendado != null)
          Text(
            'Agendado para ${dataHoraLisboaDe(agendado)} (hora de Lisboa)',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
      ],
      children: [
        if (_reservadosAgora.contains(p.id))
          const _Etiqueta(texto: 'Reservado para ele agora')
        else
          FilledButton.icon(
            key: Key('area_dar_${p.id}'),
            onPressed: _livre ? () => _darAEle(p) : null,
            icon: const Icon(Icons.assignment_ind),
            label: const Text('Dar este pedido a ele'),
          ),
      ],
    );
  }

  // 4 ─ Ganhos
  Widget _secaoGanhos() {
    return _Secao(
      titulo: 'Ganhos',
      paraQue: 'Quanto ele ganhou no período, trabalho a trabalho, como ele vê no app.',
      aoAtualizar: _recarregarGanhos,
      child: FutureBuilder<ExtratoGanhos>(
        future: _fGanhos,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const _Carregando();
          final extrato = snap.data;
          if (snap.hasError || extrato == null) {
            return _ErroSecao(
              texto: _erroLegivel(snap.error ?? 'sem resposta'),
              aoTentar: _recarregarGanhos,
            );
          }
          final lista = trabalhosDoPeriodo(extrato.trabalhos, _periodo, DateTime.now());
          final semValor = trabalhosSemValor(lista);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  for (final per in PeriodoEntregas.values)
                    ChoiceChip(
                      key: Key('area_periodo_${per.name}'),
                      label: Text(per.rotulo),
                      selected: per == _periodo,
                      onSelected: (_) => _escolherPeriodo(per),
                    ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              Text(
                eurCents(totalGanhoCents(lista)),
                key: const Key('area_total_ganhos'),
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
              Text(
                '${lista.length} trabalho(s) em "${_periodo.rotulo}"',
                style: _estiloPequeno,
              ),
              if (semValor > 0)
                Text(
                  '$semValor trabalho(s) sem valor conhecido ficaram fora do total.',
                  style: _estiloPequeno,
                ),
              const SizedBox(height: Spacing.sm),
              for (final t in lista.take(kMaxTrabalhosVisiveis)) _LinhaTrabalho(trabalho: t),
              if (lista.length > kMaxTrabalhosVisiveis)
                const Text(
                  'Mostrando os $kMaxTrabalhosVisiveis mais recentes.',
                  style: _estiloPequeno,
                ),
              const SizedBox(height: Spacing.md),
              const _PendentesDoServidor(botoes: [
                _BotaoPendente('area_fatura_mes', Icons.receipt_long, 'Fatura do mês'),
              ]),
            ],
          );
        },
      ),
    );
  }

  // 5 ─ Conta e documentos
  Widget _secaoConta() {
    return _Secao(
      titulo: 'Conta e documentos',
      paraQue: 'O que falta na conta dele, os documentos e o modo de trabalho.',
      aoAtualizar: _recarregarConta,
      child: FutureBuilder<_DadosConta>(
        future: _fConta,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const _Carregando();
          final dados = snap.data;
          if (snap.hasError || dados == null) {
            return _ErroSecao(
              texto: _erroLegivel(snap.error ?? 'sem resposta'),
              aoTentar: _recarregarConta,
            );
          }
          final conta = dados.conta;
          final modo = dados.modo;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LinhaInfo(
                icone: Icons.verified_user,
                rotulo: 'Cadastro',
                valor: aprovacaoPtBr(conta.aprovacao),
              ),
              if (conta.estado.itens.isEmpty)
                const Text('O servidor não devolveu o estado da conta.', style: _estiloPequeno)
              else
                for (final item in conta.estado.itens) _LinhaItemConta(item: item),
              const SizedBox(height: Spacing.md),
              const Text(
                'Últimas verificações do robô dos documentos',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: Spacing.xs),
              if (dados.documentos.isEmpty)
                const Text('Nenhuma verificação registrada.', style: _estiloPequeno)
              else
                for (final v in dados.documentos)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '${rotuloDoCampo(v.campo)}: ${textoDoVeredito(v)} · '
                      '${dataHoraLisboaDe(v.criadoEm)}',
                      style: _estiloPequeno,
                    ),
                  ),
              const SizedBox(height: Spacing.sm),
              OutlinedButton.icon(
                key: const Key('area_lembrar_documentos'),
                onPressed: _livre ? _lembrarDocumentos : null,
                icon: const Icon(Icons.mark_email_unread),
                label: const Text('Lembrar os documentos que faltam'),
              ),
              const SizedBox(height: Spacing.md),
              const _PendentesDoServidor(botoes: [
                _BotaoPendente('area_enviar_documento', Icons.upload_file, 'Enviar documento por ele'),
              ]),
              const SizedBox(height: Spacing.md),
              const Divider(height: 1),
              const SizedBox(height: Spacing.md),
              if (modo == null)
                const Text('Não consegui ler o modo de trabalho.', style: _estiloPequeno)
              else
                _blocoModoTrabalho(modo),
            ],
          );
        },
      ),
    );
  }

  Widget _blocoModoTrabalho(ModoTrabalho modo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Modo de trabalho: ${rotuloModoTrabalho(modo.modoEfetivo)}',
          key: const Key('area_modo_atual'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: Spacing.xs),
        if (!modo.fazCorridasDePassageiros)
          const Text(
            'Só se muda para quem faz corridas de passageiros (TVDE); ele '
            'trabalha com entregas.',
            style: _estiloPequeno,
          )
        else
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              for (final m in kModosTrabalho)
                OutlinedButton(
                  key: Key('area_modo_$m'),
                  onPressed: _livre && modo.modoEfetivo != m ? () => _mudarModo(modo, m) : null,
                  child: Text(rotuloModoTrabalho(m)),
                ),
            ],
          ),
      ],
    );
  }

  // 6 ─ O que o admin já fez por ele
  Widget _secaoHistorico() {
    return _Secao(
      titulo: 'O que o admin já fez por ele',
      paraQue: 'Tudo o que o painel fez por ele fica registrado aqui, com quem '
          'fez e o motivo.',
      aoAtualizar: _recarregarHistorico,
      child: FutureBuilder<List<RegistoAdmin>>(
        future: _fHistorico,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const _Carregando();
          final lista = snap.data;
          if (snap.hasError || lista == null) {
            return _ErroSecao(
              texto: _erroLegivel(snap.error ?? 'sem resposta'),
              aoTentar: _recarregarHistorico,
            );
          }
          if (lista.isEmpty) {
            return const Text('Nada registrado ainda.', style: _estiloPequeno);
          }
          final ids = _idsDele;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final r in lista)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.history, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: Spacing.sm),
                      Expanded(
                        child: Text(
                          linhaDoHistorico(r, idsDele: ids),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ── Peças do ecrã ────────────────────────────────────────────────────────────

/// Um cartão de secção: título, uma frase a dizer para que serve, conteúdo.
class _Secao extends StatelessWidget {
  const _Secao({
    required this.titulo,
    required this.paraQue,
    required this.child,
    this.aoAtualizar,
  });

  final String titulo;
  final String paraQue;
  final VoidCallback? aoAtualizar;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.lg),
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              if (aoAtualizar != null)
                IconButton(
                  tooltip: 'Atualizar',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: aoAtualizar,
                ),
            ],
          ),
          Text(paraQue, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: Spacing.md),
          child,
        ],
      ),
    );
  }
}

class _Carregando extends StatelessWidget {
  const _Carregando();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: Spacing.md),
      child: LinearProgressIndicator(minHeight: 2),
    );
  }
}

class _ErroSecao extends StatelessWidget {
  const _ErroSecao({required this.texto, required this.aoTentar});

  final String texto;
  final VoidCallback aoTentar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(texto, style: const TextStyle(color: AppColors.error)),
        TextButton.icon(
          onPressed: aoTentar,
          icon: const Icon(Icons.refresh),
          label: const Text('Tentar de novo'),
        ),
      ],
    );
  }
}

class _LinhaInfo extends StatelessWidget {
  const _LinhaInfo({required this.icone, required this.rotulo, required this.valor});

  final IconData icone;
  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: '$rotulo: ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: valor),
              ]),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Etiqueta pequena (status do pedido, reservado).
class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 3),
        child: Text(
          texto,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryDark,
          ),
        ),
      ),
    );
  }
}

/// O único elemento laranja do ecrã.
class _AvisoAgendado extends StatelessWidget {
  const _AvisoAgendado();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.schedule, size: 18, color: AppColors.textSecondary),
        SizedBox(width: Spacing.xs),
        Expanded(
          child: Text(
            'Pedido agendado? Confira a hora antes.',
            style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// Um pedido: código, status, loja e endereço; por baixo, o que se pode fazer.
class _CaixaPedido extends StatelessWidget {
  const _CaixaPedido({
    required this.pedido,
    required this.children,
    this.extras = const [],
  });

  final PedidoAberto pedido;
  final List<Widget> extras;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final loja = pedido.loja;
    final entrega = pedido.entrega;
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.md),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                pedido.codigo,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              _Etiqueta(texto: estadoPedidoPtBr(pedido.status)),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          if (loja != null) Text('Loja: $loja'),
          if (entrega != null) Text('Entrega: $entrega', style: _estiloPequeno),
          ...extras,
          const SizedBox(height: Spacing.sm),
          ...children,
        ],
      ),
    );
  }
}

class _LinhaTrabalho extends StatelessWidget {
  const _LinhaTrabalho({required this.trabalho});

  final TrabalhoGanho trabalho;

  @override
  Widget build(BuildContext context) {
    final t = trabalho;
    final titulo = t.descricao.isEmpty ? tipoTrabalhoPtBr(t.tipo) : t.descricao;
    final pagamento = pagamentoPtBr(t.pagamento);
    final ganhou = t.ganhouCents;
    final cliente = t.clientePagouCents;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(
                  '${t.quandoTxt} · ${tipoTrabalhoPtBr(t.tipo)}'
                  '${pagamento.isEmpty ? '' : ' · $pagamento'}',
                  style: _estiloPequeno,
                ),
                // Regra do ganho em número grande: o valor do cliente só em
                // pequeno e só quando pagou em dinheiro.
                if (t.emDinheiro && cliente != null)
                  Text('Cliente pagou em dinheiro: ${eurCents(cliente)}', style: _estiloPequeno),
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Text(
            ganhou == null ? '—' : eurCents(ganhou),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinhaItemConta extends StatelessWidget {
  const _LinhaItemConta({required this.item});

  final ItemConta item;

  @override
  Widget build(BuildContext context) {
    final (icone, cor) = switch (item.estado) {
      EstadoItemConta.ok => (Icons.check_circle, AppColors.primary),
      EstadoItemConta.emAnalise => (Icons.hourglass_top, AppColors.warning),
      EstadoItemConta.falta => (Icons.error, AppColors.error),
    };
    final detalhe = item.detalhe;
    final bloqueia = item.emFalta && item.bloqueiaOnline ? ' (impede de ficar ligado)' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 16, color: cor),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${item.rotulo}$bloqueia', style: const TextStyle(fontSize: 13)),
                if (detalhe != null) Text(detalhe, style: _estiloPequeno),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Um botão que ainda não tem função no servidor.
class _BotaoPendente {
  const _BotaoPendente(this.chave, this.icone, this.rotulo);

  final String chave;
  final IconData icone;
  final String rotulo;
}

/// Botões desligados + a frase [kFrasePrecisaFuncaoNova].
class _PendentesDoServidor extends StatelessWidget {
  const _PendentesDoServidor({required this.botoes});

  final List<_BotaoPendente> botoes;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            for (final b in botoes)
              OutlinedButton.icon(
                key: Key(b.chave),
                onPressed: null,
                icon: Icon(b.icone, size: 18),
                label: Text(b.rotulo),
              ),
          ],
        ),
        const SizedBox(height: Spacing.xs),
        const Text(
          kFrasePrecisaFuncaoNova,
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

/// A janela do motivo é dona do seu campo de texto (só é libertado quando a
/// janela sai do ecrã). O botão de confirmar só liga com o motivo mínimo.
class _MotivoDialog extends StatefulWidget {
  const _MotivoDialog({
    required this.titulo,
    required this.explicacao,
    required this.botao,
    this.aviso,
  });

  final String titulo;
  final String explicacao;
  final String botao;
  final String? aviso;

  @override
  State<_MotivoDialog> createState() => _MotivoDialogState();
}

class _MotivoDialogState extends State<_MotivoDialog> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aviso = widget.aviso;
    final valido = motivoSuficiente(_ctrl.text);
    return AlertDialog(
      title: Text(widget.titulo),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.explicacao),
            if (aviso != null) ...[
              const SizedBox(height: Spacing.md),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0x14DC2626),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.sm),
                  child: Text(
                    aviso,
                    key: const Key('area_motivo_aviso'),
                    style: const TextStyle(
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: Spacing.md),
            TextField(
              key: const Key('area_motivo'),
              controller: _ctrl,
              autofocus: true,
              maxLines: 2,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Motivo (obrigatório)',
                helperText: 'Mínimo $kMotivoMinimo letras. Fica no registro de auditoria.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Voltar'),
        ),
        FilledButton(
          key: const Key('area_motivo_confirmar'),
          onPressed: valido ? () => Navigator.pop(context, _ctrl.text.trim()) : null,
          child: Text(widget.botao),
        ),
      ],
    );
  }
}

/// Escolher o entregador que fica com o pedido (os disponíveis primeiro, como
/// o servidor os ordena).
class _EscolherOutroDialog extends StatefulWidget {
  const _EscolherOutroDialog({required this.codigo, required this.entregadores});

  final String codigo;
  final List<EstafetaParaAtribuir> entregadores;

  @override
  State<_EscolherOutroDialog> createState() => _EscolherOutroDialogState();
}

class _EscolherOutroDialogState extends State<_EscolherOutroDialog> {
  String _pesquisa = '';

  @override
  Widget build(BuildContext context) {
    final q = _pesquisa.trim().toLowerCase();
    final lista = q.isEmpty
        ? widget.entregadores
        : widget.entregadores
            .where((e) => e.nome.toLowerCase().contains(q) || e.telefone.contains(q))
            .toList();
    return AlertDialog(
      title: Text('Passar o pedido ${widget.codigo} para quem?'),
      content: SizedBox(
        width: 440,
        height: 420,
        child: Column(
          children: [
            TextField(
              key: const Key('area_pesquisa_entregador'),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Pesquisar por nome ou celular',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() {
                _pesquisa = v;
              }),
            ),
            const SizedBox(height: Spacing.sm),
            Expanded(
              child: lista.isEmpty
                  ? const Center(child: Text('Nenhum entregador encontrado.'))
                  : ListView.separated(
                      itemCount: lista.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final e = lista[i];
                        final distancia = e.distanciaKm;
                        final onde = distancia == null
                            ? ''
                            : ' · ${distancia.toStringAsFixed(1).replaceAll('.', ',')} km da loja';
                        return ListTile(
                          key: Key('area_outro_${e.userId}'),
                          dense: true,
                          leading: Icon(
                            Icons.circle,
                            size: 12,
                            color: e.vaiReceber ? AppColors.primary : AppColors.textSecondary,
                          ),
                          title: Text(e.nome),
                          subtitle: Text(e.vaiReceber
                              ? 'Ligado agora · ${e.pedidosEmCurso} pedido(s) em curso$onde'
                              : 'Não vai receber agora: ${e.motivoNaoRecebe}$onde'),
                          onTap: () => Navigator.pop(context, e),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Voltar'),
        ),
      ],
    );
  }
}
