// CONVERSAS AO VIVO (15/11/2026, missão app-15-11) — pedido do Danilo de
// 12/11/2026 06:22: ver ao vivo o que os robôs falam com os clientes e entrar
// na conversa quando for preciso.
//
//   • /admin/conversas — as conversas dos 3 robôs numa lista só (suporte da
//     app, Amigo Bora, lojas no WhatsApp), as mais recentes primeiro, com quem
//     falou por último, o estado (robô, equipa, pediu uma pessoa, robô
//     desligado) e as não lidas. Atualiza sozinha: tempo real + de 10 em 10 s.
//   • /admin/conversas/<origem>/<id> — a conversa balão a balão (é o link dos
//     avisos e do push de cada mensagem de cliente), com "Assumir conversa",
//     "Devolver ao robô" e "Enviar como Equipa Bora". Relê de 5 em 5 s.
//
// Servidor: docs/propostas/app-15-11/conversas_ao_vivo.PROPOSTA.sql (ainda por
// aplicar). Sem as funções, o ecrã diz isso com calma, nunca o erro cru.
// O link antigo /admin/support/sessions/<id> continua a abrir o ecrã do suporte.
// Textos em PT-BR (painel).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../config/app_colors.dart';
import '../../services/admin_conversas_service.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import 'admin_suporte_conversas_screen.dart' show rotaConversaSuporte;

/// Rota da lista (menu e avisos).
const String kRotaConversasAoVivo = '/admin/conversas';

/// Prefixo das conversas: `/admin/conversas/<origem>/<id>`.
const String kPrefixoConversaAoVivo = '/admin/conversas/';

/// Link de uma conversa (o mesmo formato que os avisos e o push levam).
String rotaConversaAoVivo(String origem, String conversaId) =>
    '$kPrefixoConversaAoVivo$origem/${Uri.encodeComponent(conversaId)}';

final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

/// `%3A` → `:`; um link estragado (`%zz`) dá null em vez de rebentar.
String? _descodificar(String s) {
  try {
    return Uri.decodeComponent(s).trim();
  } catch (_) {
    return null;
  }
}

/// (origem, id) de um link `/admin/conversas/<origem>/<id>`; null se não for o
/// link de uma conversa (a lista `/admin/conversas` também dá null).
({String origem, String conversaId})? conversaDoLink(String? link) {
  if (link == null || !link.startsWith(kPrefixoConversaAoVivo)) return null;
  final resto = link
      .substring(kPrefixoConversaAoVivo.length)
      .split(RegExp(r'[?#]'))
      .first;
  final barra = resto.indexOf('/');
  if (barra <= 0) return null;
  final origem = resto.substring(0, barra);
  if (!kOrigensConversa.contains(origem)) return null;
  final id = _descodificar(resto.substring(barra + 1));
  if (id == null) return null;
  if (origem == kOrigemWhatsappLoja) {
    // <tenant_id>:<numero>
    final dois = id.indexOf(':');
    if (dois <= 0 || dois == id.length - 1) return null;
    if (!_uuid.hasMatch(id.substring(0, dois))) return null;
  } else if (!_uuid.hasMatch(id)) {
    return null;
  }
  return (origem: origem, conversaId: id);
}

/// "Suporte da app" / "Amigo Bora" / "Loja no WhatsApp".
String rotuloOrigemConversa(String origem) => switch (origem) {
      kOrigemSuporteApp => 'Suporte da app',
      kOrigemAmigo => 'Amigo Bora',
      kOrigemWhatsappLoja => 'Loja no WhatsApp',
      _ => 'Conversa',
    };

IconData iconeOrigemConversa(String origem) => switch (origem) {
      kOrigemSuporteApp => Icons.support_agent,
      kOrigemAmigo => Icons.auto_awesome,
      kOrigemWhatsappLoja => Icons.storefront_outlined,
      _ => Icons.forum_outlined,
    };

/// O estado em palavras (null = estado desconhecido, sem etiqueta).
String? rotuloEstadoConversa(String estado) => switch (estado) {
      'robo' => 'Robô a responder',
      'equipa' => 'Equipa assumiu',
      'pediu_pessoa' => 'Pediu uma pessoa',
      'desligado' => 'Robô desligado',
      _ => null,
    };

/// "Cliente: " / "Robô: " / "Equipa: " antes do resumo da última mensagem.
String prefixoAutorConversa(String autor) => switch (autor) {
      'cliente' => 'Cliente: ',
      'robo' => 'Robô: ',
      'equipa' => 'Equipa: ',
      _ => '',
    };

/// "agora · 15/11 14:05", "há 5 min · 15/11 14:05", "há 3 h · 15/11 11:05" ou
/// só "12/11 09:30" depois de um dia. Hora sempre de Lisboa. Puro ([agora]
/// vem dos testes).
String quandoConversa(DateTime? quando, {DateTime? agora}) {
  if (quando == null) return '—';
  final hora = dataHoraLisboa(quando.toUtc().toIso8601String());
  final d = (agora ?? DateTime.now()).difference(quando);
  if (d.inMinutes < 1) return 'agora · $hora';
  if (d.inMinutes < 60) return 'há ${d.inMinutes} min · $hora';
  if (d.inHours < 24) return 'há ${d.inHours} h · $hora';
  return hora;
}

/// O nome a mostrar: nunca só um número (regra do Danilo, 14/11). Sem nome,
/// "Cliente sem nome" — com o número entre parênteses, se for só isso que há.
/// Nas lojas o servidor manda "Nome · Loja": a loja fica.
String nomeClienteParaMostrar(String bruto) {
  final t = bruto.trim();
  if (t.isEmpty) return 'Cliente sem nome';
  final partes = t.split(' · ');
  final nome = partes.first.trim();
  final resto = partes.skip(1).map((p) => ' · ${p.trim()}').join();
  if (nome.isEmpty) return 'Cliente sem nome$resto';
  final semJid = nome.split('@').first;
  final soNumero = RegExp(r'^[+\d\s().-]+$').hasMatch(semJid) &&
      RegExp(r'\d').allMatches(semJid).length >= 3;
  if (soNumero) return 'Cliente sem nome ($nome)$resto';
  return t;
}

/// Erro de uma ação em palavras (nunca o erro cru).
String textoDoErroConversa(Object e, String seNaoSouber) {
  if (funcaoEmFalta(e)) return kConversasFuncaoEmFalta;
  if (e is PostgrestException) {
    if (e.message.contains('admin_required')) {
      return 'Sem permissão de admin para isto.';
    }
    if (e.message.contains('texto_vazio')) {
      return 'Escreva a mensagem antes de enviar.';
    }
  }
  return seNaoSouber;
}

// ─────────────────────────────────────────────────────────────────────────
// Lista
// ─────────────────────────────────────────────────────────────────────────

class AdminConversasAoVivoScreen extends StatefulWidget {
  const AdminConversasAoVivoScreen({
    super.key,
    this.servico = const AdminConversasService(),
    this.aoVivo = true,
  });

  final AdminConversasService servico;

  /// Tempo real + relógio de 10 s (os testes desligam).
  final bool aoVivo;

  @override
  State<AdminConversasAoVivoScreen> createState() =>
      _AdminConversasAoVivoScreenState();
}

class _AdminConversasAoVivoScreenState
    extends State<AdminConversasAoVivoScreen> {
  static const List<(String?, String)> _filtros = [
    (null, 'Todas'),
    (kOrigemSuporteApp, 'Suporte da app'),
    (kOrigemAmigo, 'Amigo Bora'),
    (kOrigemWhatsappLoja, 'Lojas no WhatsApp'),
  ];

  List<ConversaAoVivo> _linhas = const [];
  bool _carregando = true;
  bool _semFuncao = false;
  String? _erro;
  String? _origem;
  bool _soEspera = false;
  int _pedido = 0;
  Timer? _relogio;
  Timer? _folga;
  VoidCallback? _desligarTempoReal;

  @override
  void initState() {
    super.initState();
    unawaited(_carregar());
    if (widget.aoVivo) {
      _relogio = Timer.periodic(const Duration(seconds: 10), (_) {
        if (!_semFuncao) unawaited(_carregar());
      });
      // Mensagem nova em qualquer conversa → relê a lista (folga de 1 s).
      try {
        _desligarTempoReal = widget.servico.ouvirMensagensNovas(() {
          _folga?.cancel();
          _folga = Timer(const Duration(seconds: 1), () {
            if (mounted && !_semFuncao) unawaited(_carregar());
          });
        });
      } catch (e) {
        debugPrint('[AdminConversasAoVivo] tempo real: $e');
      }
    }
  }

  @override
  void dispose() {
    _relogio?.cancel();
    _folga?.cancel();
    _desligarTempoReal?.call();
    super.dispose();
  }

  /// Só a resposta do pedido mais recente conta (filtros trocados a meio,
  /// relógio e tempo real ao mesmo tempo).
  Future<void> _carregar() async {
    final pedido = ++_pedido;
    try {
      final linhas = await widget.servico
          .listar(soEsperaEquipa: _soEspera, origem: _origem);
      if (!mounted || pedido != _pedido) return;
      setState(() {
        _linhas = linhas;
        _carregando = false;
        _semFuncao = false;
        _erro = null;
      });
    } catch (e) {
      debugPrint('[AdminConversasAoVivo] $e');
      if (!mounted || pedido != _pedido) return;
      setState(() {
        _carregando = false;
        _semFuncao = funcaoEmFalta(e);
        _erro = _semFuncao ? null : 'Não consegui carregar as conversas agora.';
      });
    }
  }

  void _mudarFiltro({String? origem, bool? soEspera}) {
    setState(() {
      _origem = origem;
      if (soEspera != null) _soEspera = soEspera;
      _linhas = const [];
      _carregando = true;
      _erro = null;
    });
    unawaited(_carregar());
  }

  Future<void> _abrir(ConversaAoVivo c) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AdminConversaAoVivoScreen(
        origem: c.origem,
        conversaId: c.conversaId,
        titulo: nomeClienteParaMostrar(c.clienteNome),
        estado: c.estado,
        servico: widget.servico,
        aoVivo: widget.aoVivo,
      ),
    ));
    if (mounted) unawaited(_carregar());
  }

  @override
  Widget build(BuildContext context) {
    final aEsperar = _linhas
        .where((c) => c.naoLidas > 0 || c.estado == 'pediu_pessoa')
        .length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Conversas ao vivo',
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () => unawaited(_carregar()),
          ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                for (final f in _filtros)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: ValueKey('filtro_${f.$1 ?? 'todas'}'),
                      label: Text(f.$2),
                      selected: _origem == f.$1,
                      onSelected: (_) {
                        if (_origem != f.$1) _mudarFiltro(origem: f.$1);
                      },
                    ),
                  ),
              ],
            ),
          ),
          SwitchListTile(
            key: const ValueKey('filtro_so_espera'),
            dense: true,
            title: const Text('Só à espera da equipa'),
            subtitle: Text(_soEspera
                ? 'Mensagens não lidas ou cliente que pediu uma pessoa'
                : '${_linhas.length} conversas · $aEsperar à espera da equipa'),
            value: _soEspera,
            onChanged: (v) => _mudarFiltro(origem: _origem, soEspera: v),
          ),
          if (_erro != null && _linhas.isNotEmpty)
            _FaixaErro(texto: _erro!, onTentar: _carregar),
          const Divider(height: 1),
          Expanded(child: _corpo()),
        ],
      ),
    );
  }

  Widget _corpo() {
    if (_carregando && _linhas.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_semFuncao) return const _SemFuncao();
    if (_erro != null && _linhas.isEmpty) {
      return _ErroComTentar(texto: _erro!, onTentar: _carregar);
    }
    return RefreshIndicator(
      onRefresh: _carregar,
      child: _linhas.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Center(child: Text('Nenhuma conversa por aqui.')),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _linhas.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => ConversaAoVivoTile(
                conversa: _linhas[i],
                onTap: () => _abrir(_linhas[i]),
              ),
            ),
    );
  }
}

/// Uma linha da lista (pública para os testes).
class ConversaAoVivoTile extends StatelessWidget {
  const ConversaAoVivoTile({
    super.key,
    required this.conversa,
    this.onTap,
    this.agora,
  });

  final ConversaAoVivo conversa;
  final VoidCallback? onTap;

  /// Relógio dos testes ("há 5 min").
  final DateTime? agora;

  @override
  Widget build(BuildContext context) {
    final c = conversa;
    final porLer = c.naoLidas > 0;
    final estado = rotuloEstadoConversa(c.estado);
    return ListTile(
      key: ValueKey('conversa_${c.origem}_${c.conversaId}'),
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: porLer ? AppColors.primary : AppColors.primaryWash,
        foregroundColor: porLer ? Colors.white : AppColors.primaryDark,
        child: Icon(iconeOrigemConversa(c.origem)),
      ),
      title: Text(
        nomeClienteParaMostrar(c.clienteNome),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: porLer ? FontWeight.w700 : FontWeight.w500),
      ),
      subtitle: Text(
        '${rotuloOrigemConversa(c.origem)} · ${quandoConversa(c.ultimaMensagemEm, agora: agora)}\n'
        '${prefixoAutorConversa(c.ultimoAutor)}${c.ultimaMensagemResumo.trim()}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (estado != null) EtiquetaEstadoConversa(estado: c.estado),
          if (porLer)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                key: const ValueKey('conversa_nao_lidas'),
                constraints: const BoxConstraints(minWidth: 22),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  c.naoLidas > 99 ? '99+' : '${c.naoLidas}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A etiqueta do estado (robô / equipa / pediu uma pessoa / robô desligado).
class EtiquetaEstadoConversa extends StatelessWidget {
  const EtiquetaEstadoConversa({super.key, required this.estado});

  final String estado;

  @override
  Widget build(BuildContext context) {
    final texto = rotuloEstadoConversa(estado);
    if (texto == null) return const SizedBox.shrink();
    final (fundo, cor) = switch (estado) {
      'equipa' => (AppColors.primaryDark, Colors.white),
      'pediu_pessoa' => (AppColors.accent, Colors.white),
      'desligado' => (AppColors.divider, AppColors.textSecondary),
      _ => (AppColors.primaryLight, AppColors.primaryDark),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        texto,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cor),
      ),
    );
  }
}

class _SemFuncao extends StatelessWidget {
  const _SemFuncao();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          key: ValueKey('conversas_sem_funcao'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_empty, size: 36, color: AppColors.textSecondary),
            SizedBox(height: 12),
            Text(
              kConversasFuncaoEmFalta,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErroComTentar extends StatelessWidget {
  const _ErroComTentar({required this.texto, required this.onTentar});

  final String texto;
  final Future<void> Function() onTentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(texto, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => unawaited(onTentar()),
              child: const Text('Tentar de novo'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Faixa fina quando a atualização falha mas já há o que mostrar.
class _FaixaErro extends StatelessWidget {
  const _FaixaErro({required this.texto, required this.onTentar});

  final String texto;
  final Future<void> Function() onTentar;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF7ED),
      padding: const EdgeInsets.only(left: 12),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 12))),
          TextButton(
            onPressed: () => unawaited(onTentar()),
            child: const Text('Tentar de novo'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Conversa
// ─────────────────────────────────────────────────────────────────────────

class AdminConversaAoVivoScreen extends StatefulWidget {
  const AdminConversaAoVivoScreen({
    super.key,
    required this.origem,
    required this.conversaId,
    this.titulo,
    this.estado,
    this.servico = const AdminConversasService(),
    this.aoVivo = true,
  });

  /// 'suporte_app' | 'amigo' | 'whatsapp_loja'.
  final String origem;
  final String conversaId;

  /// Nome do cliente (vem da lista; pelo link do aviso não vem).
  final String? titulo;

  /// Estado que a lista mostrava, se veio da lista.
  final String? estado;

  final AdminConversasService servico;

  /// Relógio de 5 s (os testes desligam).
  final bool aoVivo;

  @override
  State<AdminConversaAoVivoScreen> createState() =>
      _AdminConversaAoVivoScreenState();
}

class _AdminConversaAoVivoScreenState extends State<AdminConversaAoVivoScreen> {
  final _texto = TextEditingController();
  final _scroll = ScrollController();
  List<MensagemConversa> _mensagens = const [];
  bool _carregando = true;
  bool _semFuncao = false;
  String? _erro;
  String? _estado;
  bool _verFerramentas = false;
  bool _aEnviar = false;
  bool _aAgir = false;
  int _pedido = 0;
  Timer? _relogio;

  @override
  void initState() {
    super.initState();
    _estado = widget.estado;
    unawaited(_carregar());
    if (widget.aoVivo) {
      _relogio = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!_semFuncao) unawaited(_carregar());
      });
    }
  }

  @override
  void dispose() {
    _relogio?.cancel();
    _texto.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final pedido = ++_pedido;
    final eraVazia = _mensagens.isEmpty;
    final pertoDoFim = !_scroll.hasClients || _scroll.position.extentAfter < 120;
    try {
      final lista =
          await widget.servico.mensagens(widget.origem, widget.conversaId);
      if (!mounted || pedido != _pedido) return;
      final mudou = !_iguais(_mensagens, lista);
      setState(() {
        if (mudou) _mensagens = lista;
        _carregando = false;
        _semFuncao = false;
        _erro = null;
      });
      if (mudou && (eraVazia || pertoDoFim)) _irAoFim();
    } catch (e) {
      debugPrint('[AdminConversaAoVivo] $e');
      if (!mounted || pedido != _pedido) return;
      setState(() {
        _carregando = false;
        _semFuncao = funcaoEmFalta(e);
        _erro = _semFuncao ? null : 'Não consegui abrir a conversa agora.';
      });
    }
  }

  static bool _iguais(List<MensagemConversa> a, List<MensagemConversa> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].texto != b[i].texto) return false;
    }
    return true;
  }

  void _irAoFim() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _aviso(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  static String _erroDoServidor(Map<String, dynamic> r, String seNaoSouber) {
    final e = (r['erro'] ?? '').toString().trim();
    return e.isEmpty ? seNaoSouber : 'Não deu certo: $e';
  }

  Future<void> _assumir() => _agir(
        () => widget.servico.assumir(widget.origem, widget.conversaId),
        novoEstado: 'equipa',
        ok: (_) => 'Você assumiu a conversa: o robô fica calado.',
        falhou: 'Não encontrei esta conversa para assumir.',
      );

  Future<void> _devolver() => _agir(
        () => widget.servico.devolver(widget.origem, widget.conversaId),
        novoEstado: 'robo',
        ok: (r) => r['mudou'] == false
            ? 'A conversa já estava com o robô.'
            : 'Conversa devolvida ao robô.',
        falhou: 'Não consegui devolver esta conversa ao robô.',
      );

  Future<void> _agir(
    Future<Map<String, dynamic>> Function() acao, {
    required String novoEstado,
    required String Function(Map<String, dynamic> r) ok,
    required String falhou,
  }) async {
    if (_aAgir) return;
    setState(() => _aAgir = true);
    try {
      final r = await acao();
      if (!mounted) return;
      if (r['ok'] == true) {
        setState(() => _estado = novoEstado);
        _aviso(ok(r));
        unawaited(_carregar());
      } else {
        _aviso(_erroDoServidor(r, falhou));
      }
    } catch (e) {
      debugPrint('[AdminConversaAoVivo] ação: $e');
      if (mounted) {
        _aviso(textoDoErroConversa(
            e, 'Não consegui fazer isso agora. Tente de novo.'));
      }
    } finally {
      if (mounted) setState(() => _aAgir = false);
    }
  }

  Future<void> _enviar() async {
    final t = _texto.text.trim();
    if (t.isEmpty || _aEnviar) return;
    setState(() => _aEnviar = true);
    try {
      final r =
          await widget.servico.responder(widget.origem, widget.conversaId, t);
      if (!mounted) return;
      if (r['ok'] == true) {
        _texto.clear();
        setState(() => _estado = 'equipa');
        await _carregar();
        _irAoFim();
      } else {
        _aviso(_erroDoServidor(r, 'Não enviei: o servidor não aceitou a mensagem.'));
      }
    } catch (e) {
      debugPrint('[AdminConversaAoVivo] enviar: $e');
      if (mounted) {
        _aviso(textoDoErroConversa(e, 'Não consegui enviar. Tente de novo.'));
      }
    } finally {
      if (mounted) setState(() => _aEnviar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titulo = (widget.titulo ?? '').trim();
    final ferramentas = _mensagens.where((m) => m.daFerramenta).length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: titulo.isEmpty ? rotuloOrigemConversa(widget.origem) : titulo,
        actions: [
          // O ecrã do suporte tem o telefone, o WhatsApp e os pedidos do cliente.
          if (widget.origem == kOrigemSuporteApp)
            IconButton(
              tooltip: 'Telefone e pedidos do cliente (tela do suporte)',
              icon: const Icon(Icons.phone_in_talk_outlined),
              onPressed: () => Navigator.of(context)
                  .pushNamed(rotaConversaSuporte(widget.conversaId)),
            ),
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () => unawaited(_carregar()),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _semFuncao
              ? const _SemFuncao()
              : _erro != null && _mensagens.isEmpty
                  ? _ErroComTentar(texto: _erro!, onTentar: _carregar)
                  : Column(
                      children: [
                        _Acoes(
                          origem: widget.origem,
                          estado: _estado,
                          aAgir: _aAgir,
                          onAssumir: _assumir,
                          onDevolver: _devolver,
                        ),
                        if (_erro != null)
                          _FaixaErro(texto: _erro!, onTentar: _carregar),
                        if (ferramentas > 0)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              key: const ValueKey('conversa_ver_ferramentas'),
                              onPressed: () => setState(
                                  () => _verFerramentas = !_verFerramentas),
                              icon: Icon(
                                  _verFerramentas
                                      ? Icons.expand_less
                                      : Icons.build_outlined,
                                  size: 16),
                              label: Text(_verFerramentas
                                  ? 'esconder ferramentas'
                                  : 'ver ferramentas ($ferramentas)'),
                            ),
                          ),
                        Expanded(child: _lista()),
                        _Caixa(
                          controller: _texto,
                          aEnviar: _aEnviar,
                          whatsapp: widget.origem == kOrigemWhatsappLoja,
                          onEnviar: _enviar,
                        ),
                      ],
                    ),
    );
  }

  Widget _lista() {
    // As linhas das ferramentas ficam recolhidas: "o robô usou N ferramentas".
    final itens = <Object>[];
    var escondidas = 0;
    for (final m in _mensagens) {
      if (m.daFerramenta && !_verFerramentas) {
        escondidas++;
        continue;
      }
      if (escondidas > 0) {
        itens.add(escondidas);
        escondidas = 0;
      }
      itens.add(m);
    }
    if (escondidas > 0) itens.add(escondidas);
    if (itens.isEmpty) {
      return const Center(child: Text('Sem mensagens nesta conversa.'));
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      itemCount: itens.length,
      itemBuilder: (_, i) {
        final item = itens[i];
        if (item is int) return _FerramentasEscondidas(n: item);
        return BalaoConversaAoVivo(mensagem: item as MensagemConversa);
      },
    );
  }
}

class _Acoes extends StatelessWidget {
  const _Acoes({
    required this.origem,
    required this.estado,
    required this.aAgir,
    required this.onAssumir,
    required this.onDevolver,
  });

  final String origem;
  final String? estado;
  final bool aAgir;
  final VoidCallback onAssumir;
  final VoidCallback onDevolver;

  @override
  Widget build(BuildContext context) {
    final e = estado == null ? null : rotuloEstadoConversa(estado!);
    return Material(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(iconeOrigemConversa(origem),
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(rotuloOrigemConversa(origem),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                if (e != null) ...[
                  const SizedBox(width: 8),
                  EtiquetaEstadoConversa(estado: estado!),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('conversa_assumir'),
                  onPressed: aAgir ? null : onAssumir,
                  icon: const Icon(Icons.pan_tool_alt_outlined, size: 18),
                  label: const Text('Assumir conversa'),
                ),
                TextButton.icon(
                  key: const ValueKey('conversa_devolver'),
                  onPressed: aAgir ? null : onDevolver,
                  icon: const Icon(Icons.smart_toy_outlined, size: 18),
                  label: const Text('Devolver ao robô'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FerramentasEscondidas extends StatelessWidget {
  const _FerramentasEscondidas({required this.n});

  final int n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Text(
          '· o robô usou $n ${n == 1 ? 'ferramenta' : 'ferramentas'} ·',
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

/// Um balão: Cliente à esquerda (cinza), Robô à direita (verde claro),
/// Equipa à direita (verde escuro, "Equipa Bora"). Ferramenta: linha pequena.
class BalaoConversaAoVivo extends StatelessWidget {
  const BalaoConversaAoVivo({super.key, required this.mensagem});

  final MensagemConversa mensagem;

  @override
  Widget build(BuildContext context) {
    final m = mensagem;
    final quando = m.criadoEm == null
        ? ''
        : ' · ${dataHoraLisboa(m.criadoEm!.toUtc().toIso8601String())}';
    if (m.daFerramenta) {
      final t = m.texto.trim();
      final curto = t.length > 160 ? '${t.substring(0, 160)}…' : t;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          '🔧 ${m.ferramenta ?? 'ferramenta'}${curto.isEmpty ? '' : ': $curto'}',
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      );
    }
    final cliente = m.autor == 'cliente';
    final equipa = m.autor == 'equipa';
    final fundo = cliente
        ? const Color(0xFFEEEEEE)
        : equipa
            ? AppColors.primaryDark
            : AppColors.primaryLight;
    final quem = cliente
        ? 'Cliente'
        : equipa
            ? 'Equipa Bora'
            : 'Robô';
    return Align(
      alignment: cliente ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: EdgeInsets.only(
            bottom: 8, left: cliente ? 0 : 40, right: cliente ? 40 : 0),
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: fundo,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(cliente ? 4 : 14),
            bottomRight: Radius.circular(cliente ? 14 : 4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$quem$quando',
              style: TextStyle(
                fontSize: 11,
                fontWeight: equipa ? FontWeight.w700 : FontWeight.w500,
                color: equipa ? Colors.white70 : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            SelectableText(
              m.texto,
              style: TextStyle(
                fontSize: 14,
                color: equipa ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Caixa extends StatelessWidget {
  const _Caixa({
    required this.controller,
    required this.aEnviar,
    required this.whatsapp,
    required this.onEnviar,
  });

  final TextEditingController controller;
  final bool aEnviar;
  final bool whatsapp;
  final VoidCallback onEnviar;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        color: AppColors.surface,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (whatsapp)
              const Padding(
                key: ValueKey('conversa_nota_whatsapp'),
                padding: EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.schedule, size: 14, color: AppColors.textSecondary),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'A resposta sai pelo WhatsApp da loja (fila da VPS, até 30 min)',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            TextField(
              key: const ValueKey('conversa_texto'),
              controller: controller,
              enabled: !aEnviar,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: 'Escreva a resposta (o cliente vê "Equipa Bora")',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const ValueKey('conversa_enviar'),
                onPressed: aEnviar ? null : onEnviar,
                icon: aEnviar
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send, size: 18),
                label: const Text('Enviar como Equipa Bora'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
