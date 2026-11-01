import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/auth_store.dart';
import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../config/legal_identity.dart';
import '../../services/prestador_suspensao_service.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import 'como_o_bora_decide_screen.dart';

/// "A minha conta foi suspensa" — o mesmo ecrã em todas as apps de prestador
/// (estafeta, motorista, limpeza, lavagem, Casa, parceiro).
///
/// Missão app-fechar-2026-11-01, bloco B8 (Diretiva (UE) 2024/2831, art. 11.º):
/// a pessoa vê o motivo por escrito, a data da decisão, até quando, quem
/// decidiu (uma pessoa da equipa Bora), pode pedir revisão aqui mesmo e vê a
/// resposta. Sem registo de suspensão (`{suspensa:false}`) mostra o texto
/// antigo do ecrã, com os contactos.
///
/// PT-PT, sem `.tr` (texto legal, como "Sobre / Informação legal").

typedef CarregarSuspensao = Future<SuspensaoInfo> Function();
typedef PedirRevisaoFn = Future<String> Function(String motivo);
typedef AbrirLigacaoSuspensao = Future<bool> Function(Uri uri);

/// Corpo do ecrã (sem Scaffold), para pôr dentro do ecrã de cada app.
class ContaSuspensaView extends StatefulWidget {
  const ContaSuspensaView({
    super.key,
    required this.textoSemRegisto,
    this.tituloSemRegisto = 'A tua conta não está ativa',
    this.tiposConta,
    this.carregar,
    this.pedirRevisao,
    this.abrirLigacao,
    this.rodape,
  });

  /// O texto que o ecrã mostrava antes (ex.: "Contacta o suporte…"), para
  /// quando não há suspensão registada por uma pessoa.
  final String textoSemRegisto;
  final String tituloSemRegisto;

  /// Só mostra o registo se for de um destes papéis (ex.: {'limpeza'}). O
  /// servidor devolve a ÚLTIMA suspensão da pessoa, que pode ser de outro
  /// papel. `null` = qualquer papel.
  final Set<String>? tiposConta;

  /// Injetáveis nos testes (por omissão chamam o servidor).
  final CarregarSuspensao? carregar;
  final PedirRevisaoFn? pedirRevisao;
  final AbrirLigacaoSuspensao? abrirLigacao;

  /// Botão de saída do ecrã de cada app (ex.: "Terminar sessão").
  final Widget? rodape;

  @override
  State<ContaSuspensaView> createState() => _ContaSuspensaViewState();
}

class _ContaSuspensaViewState extends State<ContaSuspensaView> {
  SuspensaoInfo? _info;
  bool _aCarregar = true;
  bool _falhouLeitura = false;

  bool _formAberto = false;
  bool _aEnviar = false;
  String? _erroPedido;
  String? _mensagemOk;
  final TextEditingController _texto = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _aCarregar = true;
      _falhouLeitura = false;
    });
    SuspensaoInfo? info;
    var falhou = false;
    try {
      info = await (widget.carregar ?? PrestadorSuspensaoService.minha)();
    } catch (e) {
      debugPrint('[ContaSuspensa] prestador_minha_suspensao falhou: $e');
      falhou = true;
    }
    if (!mounted) return;
    setState(() {
      _info = info;
      _falhouLeitura = falhou;
      _aCarregar = false;
    });
  }

  /// Registo a mostrar, já filtrado pelo papel deste ecrã.
  SuspensaoInfo? get _registo {
    final i = _info;
    if (i == null || !i.suspensa) return null;
    final tipos = widget.tiposConta;
    if (tipos != null && i.tipoConta != null && !tipos.contains(i.tipoConta)) {
      return null;
    }
    return i;
  }

  Future<void> _enviarPedido() async {
    final erro = validarPedidoRevisao(_texto.text);
    if (erro != null) {
      setState(() => _erroPedido = erro);
      return;
    }
    setState(() {
      _aEnviar = true;
      _erroPedido = null;
    });
    try {
      final msg = await (widget.pedirRevisao ??
          PrestadorSuspensaoService.pedirRevisao)(_texto.text.trim());
      if (!mounted) return;
      setState(() {
        _mensagemOk = msg;
        _formAberto = false;
        _texto.clear();
      });
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      setState(() => _erroPedido = traduzirErroSuspensao(e, painel: false));
    } finally {
      if (mounted) setState(() => _aEnviar = false);
    }
  }

  Future<void> _abrir(Uri uri) async {
    var ok = false;
    try {
      final abrir = widget.abrirLigacao;
      ok = abrir != null
          ? await abrir(uri)
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[ContaSuspensa] não abriu $uri: $e');
    }
    if (ok || !mounted) return;
    final alvo = uri.scheme == 'mailto' ? uri.path : uri.toString();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('Não foi possível abrir $alvo')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_aCarregar) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    final r = _registo;
    final whatsapp = r?.contactoWhatsapp ??
        _info?.contactoWhatsapp ??
        LegalIdentity.telefoneE164;
    final email =
        r?.contactoEmail ?? _info?.contactoEmail ?? LegalIdentity.email;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.pause_circle_outline,
              size: 64, color: AppColors.error),
          const SizedBox(height: Spacing.md),
          Text(
            r?.titulo ?? widget.tituloSemRegisto,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: Spacing.lg),
          if (r == null) ...[
            Text(
              widget.textoSemRegisto,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 15, color: AppColors.textSecondary, height: 1.45),
            ),
            if (_falhouLeitura) ...[
              const SizedBox(height: Spacing.md),
              const Text(
                'Não conseguimos ler os detalhes agora. Verifica a rede.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textSubtle),
              ),
              TextButton(
                onPressed: _carregar,
                child: const Text('Tentar de novo'),
              ),
            ],
          ] else
            ..._detalhes(r),
          const SizedBox(height: Spacing.xl),
          const Text(
            'Falar com uma pessoa da equipa Bora',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: Spacing.xs),
          _Contacto(
            icone: Icons.chat_outlined,
            titulo: 'WhatsApp da Bora',
            subtitulo: whatsapp,
            onTap: () => _abrir(Uri.parse(
                'https://wa.me/${whatsapp.replaceAll(RegExp(r'[^0-9]'), '')}')),
          ),
          _Contacto(
            icone: Icons.email_outlined,
            titulo: 'Email da Bora',
            subtitulo: email,
            onTap: () => _abrir(Uri(scheme: 'mailto', path: email)),
          ),
          const SizedBox(height: Spacing.md),
          const LigacaoComoOBoraDecide(),
          if (widget.rodape != null) ...[
            const SizedBox(height: Spacing.md),
            widget.rodape!,
          ],
        ],
      ),
    );
  }

  List<Widget> _detalhes(SuspensaoInfo r) {
    final ate = r.encerramento
        ? 'Não tem data de fim (conta encerrada).'
        : r.ate != null
            ? diaEHoraSuspensao(r.ate!)
            : 'Sem data de fim.';
    final estadoRevisao = r.estadoRevisao;
    return [
      _Caixa(
        children: [
          const _Rotulo('Motivo'),
          Text(r.motivo ?? '—',
              style: const TextStyle(
                  fontSize: 15, color: AppColors.textPrimary, height: 1.45)),
          const SizedBox(height: Spacing.md),
          _Linha('Data da decisão',
              r.decididoEm != null ? diaEHoraSuspensao(r.decididoEm!) : '—'),
          _Linha('Até quando', ate),
          _Linha(
              'Decidido por',
              (r.decididoPor ?? '').contains('Equipa Bora')
                  ? r.decididoPor!
                  : 'Equipa Bora'),
        ],
      ),
      const SizedBox(height: Spacing.md),
      const Text(
        'Esta decisão foi tomada por uma pessoa da equipa Bora, não pela app. '
        'Se não concordares, pede revisão: uma pessoa revê o teu caso e '
        'responde por escrito, com os motivos, em 7 dias.',
        style: TextStyle(
            fontSize: 13, color: AppColors.textSecondary, height: 1.45),
      ),
      if (_mensagemOk != null) ...[
        const SizedBox(height: Spacing.md),
        _Aviso(texto: _mensagemOk!, cor: AppColors.success),
      ],
      if (estadoRevisao != null) ...[
        const SizedBox(height: Spacing.md),
        _Aviso(texto: estadoRevisao, cor: AppColors.info),
      ],
      if (r.revisaoResposta != null) ...[
        const SizedBox(height: Spacing.md),
        _Caixa(
          children: [
            _Rotulo(r.revistoEm != null
                ? 'Resposta da equipa Bora (${diaSuspensao(r.revistoEm!)})'
                : 'Resposta da equipa Bora'),
            Text(r.revisaoResposta!,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textPrimary, height: 1.45)),
          ],
        ),
      ],
      if (r.podePedirRevisao) ...[
        const SizedBox(height: Spacing.lg),
        if (!_formAberto)
          FilledButton.icon(
            key: const ValueKey('pedir-revisao'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: Spacing.md),
            ),
            onPressed: () => setState(() {
              _formAberto = true;
              _mensagemOk = null;
            }),
            icon: const Icon(Icons.rate_review_outlined),
            label: const Text('Pedir revisão'),
          )
        else
          _Caixa(
            children: [
              const _Rotulo('Conta o teu lado'),
              TextField(
                key: const ValueKey('texto-revisao'),
                controller: _texto,
                minLines: 3,
                maxLines: 6,
                maxLength: 1000,
                enabled: !_aEnviar,
                decoration: InputDecoration(
                  hintText: 'O que aconteceu e porque achas que a decisão '
                      'deve mudar',
                  errorText: _erroPedido,
                  errorMaxLines: 3,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (_erroPedido != null) setState(() => _erroPedido = null);
                },
              ),
              const SizedBox(height: Spacing.sm),
              // OverflowBar: com letra grande os dois botões passam a linhas
              // separadas em vez de transbordar (ecrãs estreitos).
              OverflowBar(
                alignment: MainAxisAlignment.spaceBetween,
                overflowAlignment: OverflowBarAlignment.end,
                overflowSpacing: Spacing.xs,
                children: [
                  TextButton(
                    onPressed: _aEnviar
                        ? null
                        : () => setState(() {
                              _formAberto = false;
                              _erroPedido = null;
                            }),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    key: const ValueKey('enviar-revisao'),
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary),
                    onPressed: _aEnviar ? null : _enviarPedido,
                    child: _aEnviar
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Enviar pedido'),
                  ),
                ],
              ),
            ],
          ),
      ],
    ];
  }
}

/// Ecrã inteiro (com barra), para abrir por cima de qualquer app.
class ContaSuspensaScreen extends StatelessWidget {
  const ContaSuspensaScreen({
    super.key,
    required this.textoSemRegisto,
    this.tituloSemRegisto = 'A tua conta não está ativa',
    this.tiposConta,
    this.rotuloSair = 'Terminar sessão',
    this.onSair,
    this.carregar,
    this.pedirRevisao,
    this.abrirLigacao,
  });

  final String textoSemRegisto;
  final String tituloSemRegisto;
  final Set<String>? tiposConta;
  final String rotuloSair;

  /// Por omissão fecha o ecrã (quem o abriu decide o que vem a seguir).
  final VoidCallback? onSair;
  final CarregarSuspensao? carregar;
  final PedirRevisaoFn? pedirRevisao;
  final AbrirLigacaoSuspensao? abrirLigacao;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'A minha conta'),
      body: SafeArea(
        top: false,
        child: ContaSuspensaView(
          textoSemRegisto: textoSemRegisto,
          tituloSemRegisto: tituloSemRegisto,
          tiposConta: tiposConta,
          carregar: carregar,
          pedirRevisao: pedirRevisao,
          abrirLigacao: abrirLigacao,
          // Saída sempre viva (PADRAO_BORA 3.13): não depende de rede.
          rodape: OutlinedButton.icon(
            onPressed: onSair ??
                () {
                  Navigator.of(context).maybePop();
                },
            icon: const Icon(Icons.logout),
            label: Text(rotuloSair),
          ),
        ),
      ),
    );
  }
}

/// Abre [ContaSuspensaScreen] por cima e espera que a pessoa saia.
Future<void> abrirContaSuspensa(
  BuildContext context, {
  required String textoSemRegisto,
  String tituloSemRegisto = 'A tua conta não está ativa',
  Set<String>? tiposConta,
  String rotuloSair = 'Terminar sessão',
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ContaSuspensaScreen(
        textoSemRegisto: textoSemRegisto,
        tituloSemRegisto: tituloSemRegisto,
        tiposConta: tiposConta,
        rotuloSair: rotuloSair,
      ),
    ),
  );
}

/// Motorista de passageiros (TVDE): o ecrã dele não verificava se a conta
/// estava suspensa. Faz o mesmo que o ecrã do estafeta
/// (`driver_effective_status`): se estiver banido, suspenso ou removido,
/// mostra "A minha conta" e termina a sessão quando a pessoa sair.
/// Falha de rede = não faz nada (não tranca ninguém por um soluço).
Future<void> verificarContaDoMotorista(BuildContext context) async {
  final uid = Supabase.instance.client.auth.currentUser?.id;
  if (uid == null) return;
  String? status;
  DateTime? ate;
  try {
    status = await Supabase.instance.client.rpc('driver_effective_status',
        params: {'p_driver_id': uid}).timeout(kTempoSuspensao) as String?;
    if (status == 'suspended') {
      final row = await Supabase.instance.client
          .from('drivers')
          .select('banned_until')
          .eq('user_id', uid)
          .maybeSingle()
          .timeout(kTempoSuspensao);
      ate = DateTime.tryParse('${row?['banned_until'] ?? ''}');
    }
  } catch (e) {
    debugPrint('[verificarContaDoMotorista] falhou: $e');
    return;
  }
  if (status != 'banned' && status != 'suspended' && status != 'deleted') {
    return;
  }
  if (!context.mounted) return;
  final auth = context.read<AuthStore>();
  await abrirContaSuspensa(
    context,
    textoSemRegisto: textoContaEstafetaSemRegisto(status!, ate: ate),
    tiposConta: const {'estafeta', 'motorista'},
  );
  auth.logout();
}

/// O texto antigo do estafeta/motorista por estado (`driver_effective_status`),
/// agora com os contactos por baixo em vez de só "Contacta o suporte".
String textoContaEstafetaSemRegisto(String status, {DateTime? ate}) =>
    switch (status) {
      'deleted' => 'A tua conta foi removida. Fala connosco se precisares.',
      'suspended' => ate != null
          ? 'A tua conta está suspensa até ${diaEHoraSuspensao(ate)}. '
              'Fala connosco se tiveres dúvidas.'
          : 'A tua conta foi suspensa. Fala connosco se tiveres dúvidas.',
      'banned' => 'A tua conta foi suspensa. Fala connosco se tiveres dúvidas.',
      'rejected' =>
        'A tua candidatura foi rejeitada. Fala connosco se tiveres dúvidas.',
      _ => 'A tua conta não está ativa. Fala connosco se tiveres dúvidas.',
    };

/// Parceiro (loja ou barbearia): o painel nunca mostrava que a loja tinha
/// sido desligada pela equipa. Se estiver desligada ([desligado] ou
/// [lerDesligado]), mostra "A minha conta" com o motivo e um botão para
/// entrar no painel na mesma (o estado da loja muda o que ele vê, nunca se
/// ele entra — regra de 27/08/2026 do `PartnerEntryScreen`).
/// Enquanto lê, ou se a leitura falhar, mostra o painel (não tranca ninguém).
class PortaoContaSuspensa extends StatefulWidget {
  const PortaoContaSuspensa({
    super.key,
    required this.child,
    this.desligado,
    this.lerDesligado,
    this.tiposConta = const {'parceiro', 'servico'},
    this.textoSemRegisto =
        'A tua loja foi desligada pela equipa Bora e não aparece aos '
            'clientes. Fala connosco para saberes o motivo.',
    this.carregar,
  });

  final Widget child;
  final bool? desligado;
  final Future<bool> Function()? lerDesligado;
  final Set<String> tiposConta;
  final String textoSemRegisto;
  final CarregarSuspensao? carregar;

  /// `is_active_admin = false` na linha da loja/barbearia (RLS do dono).
  static Future<bool> Function() lerDe(String tabela, String id) => () async {
        final row = await Supabase.instance.client
            .from(tabela)
            .select('is_active_admin')
            .eq('id', id)
            .maybeSingle()
            .timeout(kTempoSuspensao);
        return row != null && row['is_active_admin'] == false;
      };

  @override
  State<PortaoContaSuspensa> createState() => _PortaoContaSuspensaState();
}

class _PortaoContaSuspensaState extends State<PortaoContaSuspensa> {
  bool _desligado = false;
  bool _entrarNaMesma = false;

  @override
  void initState() {
    super.initState();
    _desligado = widget.desligado ?? false;
    final ler = widget.lerDesligado;
    if (!_desligado && ler != null) {
      ler().then((v) {
        if (mounted && v) setState(() => _desligado = true);
      }).catchError((Object e) {
        debugPrint('[PortaoContaSuspensa] leitura falhou: $e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_desligado || _entrarNaMesma) return widget.child;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'A minha conta'),
      body: SafeArea(
        top: false,
        child: ContaSuspensaView(
          textoSemRegisto: widget.textoSemRegisto,
          tituloSemRegisto: 'A tua loja está desligada',
          tiposConta: widget.tiposConta,
          carregar: widget.carregar,
          rodape: OutlinedButton.icon(
            onPressed: () => setState(() => _entrarNaMesma = true),
            icon: const Icon(Icons.storefront_outlined),
            label: const Text('Entrar no painel na mesma'),
          ),
        ),
      ),
    );
  }
}

class _Caixa extends StatelessWidget {
  const _Caixa({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(Radii.lg),
          boxShadow: AppColors.shadowCard,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );
}

class _Rotulo extends StatelessWidget {
  const _Rotulo(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Spacing.xs),
        child: Text(
          texto,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.black54,
            letterSpacing: 0.3,
          ),
        ),
      );
}

class _Linha extends StatelessWidget {
  const _Linha(this.rotulo, this.valor);
  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Spacing.xs),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(
              text: '$rotulo: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: valor),
          ]),
          style: const TextStyle(
              fontSize: 14, color: AppColors.textPrimary, height: 1.4),
        ),
      );
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto, required this.cor});
  final String texto;
  final Color cor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: cor.withValues(alpha: 0.35)),
        ),
        child: Text(texto,
            style: const TextStyle(
                fontSize: 14, color: AppColors.textPrimary, height: 1.4)),
      );
}

class _Contacto extends StatelessWidget {
  const _Contacto({
    required this.icone,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
  });
  final IconData icone;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Radii.md),
        child: ListTile(
          leading: Icon(icone, color: AppColors.primary),
          title: Text(titulo,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          subtitle: Text(subtitulo,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          trailing: const Icon(Icons.open_in_new,
              size: 18, color: AppColors.textSubtle),
          onTap: onTap,
        ),
      );
}
