import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../l10n/tr.dart';
import '../../models/casa_models.dart';
import '../../services/papeis_de_trabalho.dart';
import '../../services/push_token_service.dart';
import '../../services/roles_service.dart';
import '../../stores/handyman_store.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/aviso_atividade_banner.dart';
import '../../widgets/aviso_toque_banner.dart';
import '../../widgets/bora/bora.dart';
import '../../widgets/bora_support_sheet.dart';
import '../../widgets/caixa_de_papeis.dart';
import '../../widgets/portao_do_prestador.dart';
import '../../widgets/profile_switcher_button.dart';
import '../shared/comprovativo_atividade_screen.dart';
import 'casa_profissional_ui.dart';
import 'handyman_apply_screen.dart';
import 'handyman_disponibilidade_screen.dart';
import 'handyman_documentos_screen.dart';
import 'handyman_ganhos_screen.dart';
import 'handyman_orcamento_screen.dart';
import 'handyman_trabalho_screen.dart';

/// CASA E MANUTENÇÃO — o painel do PROFISSIONAL (papel técnico `handyman`).
///
/// Sem perfil → convite para se candidatar. Pendente → "Em análise" com o
/// que falta e um botão por documento (sem refazer a candidatura). Aprovado →
/// interruptor por ofício (só os aprovados ligam), ofertas e convites, o
/// trabalho em curso a mandar no ecrã até terminar (regra 1.24), histórico,
/// ganhos e documentos com aviso de caducidade.
///
/// Desligar o papel inteiro é na caixa de papéis (que já não deixa desligar o
/// último) — aqui só há o atalho para ela.
class HandymanHomeScreen extends StatefulWidget {
  const HandymanHomeScreen({
    super.key,
    this.comoEntrada = false,
    this.abrirPedidoId,
  });

  /// true quando este ecrã é a entrada da pessoa na app (ver
  /// `PortaoDoPrestador`).
  final bool comoEntrada;

  /// Toque num aviso: abre logo este trabalho (ou o convite para orçar).
  final String? abrirPedidoId;

  @override
  State<HandymanHomeScreen> createState() => _HandymanHomeScreenState();
}

class _HandymanHomeScreenState extends State<HandymanHomeScreen> {
  RolesSummary _roles = RolesSummary.empty();
  List<PapelDeTrabalho> _papeis = const [];

  /// Regra 1.24: o trabalho em curso abre sozinho UMA vez por ecrã (ao voltar
  /// para trás a pessoa fica no painel, com o cartão "Trabalho em curso").
  final Set<String> _abertosSozinhos = <String>{};
  bool _pedidoDoAvisoTratado = false;

  /// Trava de toque duplo das ofertas (aceitar/recusar).
  bool _aAgir = false;

  @override
  void initState() {
    super.initState();
    // Quem é aprovado com a app já aberta fica com o aparelho registado
    // (o mesmo que a limpeza e a lavagem fazem).
    PushTokenService.registerForRole('handyman').ignore();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final s = context.read<HandymanStore>();
      await s.loadProfile();
      if (!mounted) return;
      if (s.isApproved) {
        s.carregarGanhos().ignore();
        if (!s.configCarregada) s.loadConfig().ignore();
      }
      _depoisDeCarregar();
    });
    RolesService.mySummary().then((r) {
      if (mounted) setState(() => _roles = r);
    });
    PapeisDeTrabalhoService.meus().then((p) {
      if (mounted) setState(() => _papeis = p);
    });
  }

  void _depoisDeCarregar() {
    if (!mounted) return;
    final s = context.read<HandymanStore>();
    final id = widget.abrirPedidoId;
    if (!_pedidoDoAvisoTratado && id != null && id.isNotEmpty) {
      _pedidoDoAvisoTratado = true;
      final t = s.trabalhoPorId(id);
      if (t != null) {
        _abertosSozinhos.add(t.id);
        _abrirTrabalho(t);
        return;
      }
      final o = s.ofertaPorId(id);
      if (o != null && o.convite) {
        _abrirOrcamento(o);
        return;
      }
    }
    final ativo = s.trabalhoAtivo;
    if (ativo != null && _abertosSozinhos.add(ativo.id)) _abrirTrabalho(ativo);
  }

  Future<void> _recarregar() async {
    final s = context.read<HandymanStore>();
    await s.loadProfile();
    if (s.isApproved) await s.carregarGanhos();
  }

  void _abrirTrabalho(CasaPedido p) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => HandymanTrabalhoScreen(pedidoId: p.id, inicial: p),
      ),
    ).then((_) {
      if (mounted) context.read<HandymanStore>().refreshAll();
    });
  }

  void _abrirOrcamento(CasaOferta o) {
    Navigator.push(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => HandymanOrcamentoScreen(oferta: o),
      ),
    ).then((_) {
      if (mounted) context.read<HandymanStore>().loadOffers();
    });
  }

  void _abrir(Widget ecra) => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => ecra),
      );

  void _openApply() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => HandymanApplyScreen(
          prefill: _roles.driverProfile ??
              _roles.cleanerProfile ??
              _roles.washerProfile,
        ),
      ),
    ).then((_) {
      if (mounted) context.read<HandymanStore>().loadProfile();
    });
  }

  Future<void> _aceitar(CasaOferta o) async {
    if (_aAgir) return;
    setState(() => _aAgir = true);
    final s = context.read<HandymanStore>();
    final ok = await s.accept(o.pedidoId);
    if (!mounted) return;
    setState(() => _aAgir = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.lastError ?? casaErroTexto(''))));
      return;
    }
    final t = s.trabalhoPorId(o.pedidoId) ?? await s.pedido(o.pedidoId);
    if (!mounted) return;
    if (t != null) {
      _abertosSozinhos.add(t.id);
      _abrirTrabalho(t);
    }
  }

  Future<void> _recusar(CasaOferta o) async {
    if (_aAgir) return;
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Recusar este trabalho?'.tr),
        content: Text('Passa ao profissional seguinte.'.tr),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Voltar'.tr)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Recusar'.tr)),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;
    setState(() => _aAgir = true);
    await context.read<HandymanStore>().reject(o.pedidoId);
    if (mounted) setState(() => _aAgir = false);
  }

  void _abrirPapeis() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CaixaDePapeis(iniciais: _papeis),
    ).then((_) {
      PapeisDeTrabalhoService.meus().then((p) {
        if (mounted) setState(() => _papeis = p);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HandymanStore>();
    final perfil = store.perfil;
    // Regra 1.24 também quando o trabalho chega depois (aceite noutro sítio).
    final ativo = store.trabalhoAtivo;
    if (ativo != null && !_abertosSozinhos.contains(ativo.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final a = context.read<HandymanStore>().trabalhoAtivo;
        if (a != null && _abertosSozinhos.add(a.id)) _abrirTrabalho(a);
      });
    }

    return Scaffold(
      appBar: BoraScreenAppBar(
        title: 'Casa e manutenção'.tr,
        actions: widget.comoEntrada
            ? acoesDaEntradaDoPrestador(context, modoAtual: 'handyman')
            : const [ProfileSwitcherButton(modoAtual: 'handyman', comTexto: true)],
      ),
      body: !store.profileLoaded
          ? const Center(child: CircularProgressIndicator())
          : (perfil == null && store.perfilFalhou)
              ? _SemLigacao(onTentar: _recarregar)
              : perfil == null
              ? _Convite(onApply: _openApply)
              : switch (perfil.approvalStatus) {
                  'approved' => _Painel(
                      store: store,
                      papeis: _papeis,
                      aAgir: _aAgir,
                      onRefresh: _recarregar,
                      onAbrirTrabalho: _abrirTrabalho,
                      onAceitar: _aceitar,
                      onRecusar: _recusar,
                      onOrcar: _abrirOrcamento,
                      onAbrir: _abrir,
                      onPapeis: _abrirPapeis,
                    ),
                  'pending' => _EmAnalise(perfil: perfil, onRefresh: _recarregar),
                  'suspended' || 'banned' => _Estado(
                      icone: Icons.pause_circle_outline,
                      cor: AppColors.error,
                      titulo: perfil.approvalStatus == 'banned'
                          ? 'Conta desativada'.tr
                          : 'Conta suspensa para revisão'.tr,
                      texto:
                          'A tua conta da Casa está em revisão pela equipa Bora. Contacta o suporte para saberes mais.'.tr,
                    ),
                  _ => _Recusada(
                      motivo: perfil.motivoRecusa,
                      onReapply: _openApply,
                    ),
                },
    );
  }
}

// ─── sem painel ─────────────────────────────────────────────────────────────

/// Não se conseguiu ler o perfil (sem rede): nunca fica a rodar para sempre
/// nem mostra o convite a quem já é profissional (PADRAO_BORA 1.26).
class _SemLigacao extends StatelessWidget {
  const _SemLigacao({required this.onTentar});
  final Future<void> Function() onTentar;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 56, color: AppColors.textSubtle),
              const SizedBox(height: Spacing.md),
              Text('Não conseguimos ligar ao Bora. Verifica a rede.'.tr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: Spacing.lg),
              BoraPrimaryButton(
                label: 'Tentar de novo'.tr,
                icon: Icons.refresh,
                expanded: false,
                onPressed: onTentar,
              ),
            ],
          ),
        ),
      );
}

class _Convite extends StatelessWidget {
  const _Convite({required this.onApply});
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Spacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                  color: AppColors.primaryWash, shape: BoxShape.circle),
              child: const Icon(Icons.handyman, size: 48, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          Text(
            'Ganha com trabalhos de casa'.tr,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'Montar móveis, pendurar e fixar, pequenas reparações, jardim e pequenas mudanças. Tu escolhes os ofícios, os dias e a zona.'.tr,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: Spacing.xl),
          BoraPrimaryButton(
            label: 'Quero candidatar-me'.tr,
            icon: Icons.arrow_forward,
            onPressed: onApply,
          ),
        ],
      ),
    );
  }
}

class _Estado extends StatelessWidget {
  const _Estado({
    required this.icone,
    required this.cor,
    required this.titulo,
    required this.texto,
  });
  final IconData icone;
  final Color cor;
  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone, size: 64, color: cor),
              const SizedBox(height: Spacing.lg),
              Text(titulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: Spacing.sm),
              Text(texto,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textSecondary, height: 1.4)),
            ],
          ),
        ),
      );
}

class _Recusada extends StatelessWidget {
  const _Recusada({required this.motivo, required this.onReapply});
  final String? motivo;
  final VoidCallback onReapply;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Spacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.cancel_outlined, size: 64, color: AppColors.error),
          const SizedBox(height: Spacing.lg),
          Text('Candidatura recusada'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          if ((motivo ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: Spacing.sm),
            Text('Motivo: {0}'.trArgs([motivo!.trim()]),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
          ],
          const SizedBox(height: Spacing.xl),
          BoraPrimaryButton(
            label: 'Candidatar de novo'.tr,
            icon: Icons.refresh,
            onPressed: onReapply,
          ),
        ],
      ),
    );
  }
}

/// Pendente: o que falta, com envio aqui mesmo (sem refazer a candidatura).
class _EmAnalise extends StatelessWidget {
  const _EmAnalise({required this.perfil, required this.onRefresh});
  final CasaPerfil perfil;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(Spacing.xl),
        children: [
          const AvisoAtividadeBanner(
              margem: EdgeInsets.only(bottom: Spacing.lg), emCandidatura: true),
          const Icon(Icons.hourglass_top, size: 64, color: AppColors.warning),
          const SizedBox(height: Spacing.lg),
          Text('Candidatura em análise'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: Spacing.sm),
          Text(
            'A equipa Bora está a rever os teus dados e cada ofício. Avisamos-te assim que estiver aprovado.'.tr,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: Spacing.xl),
          if (perfil.oficios.isNotEmpty) ...[
            CasaSeccao('Os teus ofícios'.tr),
            for (final o in perfil.oficios)
              CasaCaixa(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(o.nome,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                    ),
                    Flexible(
                      child: Text(casaEstadoOficioTexto(o),
                          textAlign: TextAlign.end,
                          style: TextStyle(
                              fontSize: 12.5,
                              color: o.aprovado
                                  ? AppColors.primary
                                  : AppColors.textSecondary)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: Spacing.md),
          ],
          CasaDocumentosPainel(perfil: perfil),
        ],
      ),
    );
  }
}

/// Estado de um ofício do profissional em PT-PT.
String casaEstadoOficioTexto(CasaOficioDoProfissional o) => switch (o.estado) {
      'approved' => 'Aprovado'.tr,
      'rejected' => (o.motivo ?? '').trim().isEmpty
          ? 'Recusado'.tr
          : 'Recusado: {0}'.trArgs([o.motivo!.trim()]),
      'suspended' => 'Suspenso'.tr,
      _ => (o.documentoExigido ?? '').isNotEmpty
          ? 'Em análise (precisa de documento DGEG/IMPIC)'.tr
          : 'Em análise'.tr,
    };

// ─── painel aprovado ────────────────────────────────────────────────────────

class _Painel extends StatelessWidget {
  const _Painel({
    required this.store,
    required this.papeis,
    required this.aAgir,
    required this.onRefresh,
    required this.onAbrirTrabalho,
    required this.onAceitar,
    required this.onRecusar,
    required this.onOrcar,
    required this.onAbrir,
    required this.onPapeis,
  });

  final HandymanStore store;
  final List<PapelDeTrabalho> papeis;
  final bool aAgir;
  final Future<void> Function() onRefresh;
  final void Function(CasaPedido) onAbrirTrabalho;
  final void Function(CasaOferta) onAceitar;
  final void Function(CasaOferta) onRecusar;
  final void Function(CasaOferta) onOrcar;
  final void Function(Widget) onAbrir;
  final VoidCallback onPapeis;

  @override
  Widget build(BuildContext context) {
    final perfil = store.perfil!;
    final ativo = store.trabalhoAtivo;
    final algumLigado = perfil.oficios.any((o) => o.aprovado && o.ligado);
    final faltas = casaDocumentosEmFalta(perfil);
    final aCaducar = casaDocumentosAtuais(perfil.documentos)
        .where((d) => casaAvisoCaducidade(d.validade) != null)
        .toList();
    final ofertas = [
      ...store.ofertasVivas(),
      ...store.convitesAbertos(),
    ];
    final historico = store.historico.take(20).toList();

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg,
            BoraBottomActionBar.folgaInferior(context)),
        children: [
          if (ativo != null)
            InkWell(
              key: const Key('casa_trabalho_em_curso'),
              onTap: () => onAbrirTrabalho(ativo),
              borderRadius: BorderRadius.circular(Radii.lg),
              child: CasaCaixa(
                destaque: true,
                child: Row(
                  children: [
                    const Icon(Icons.handyman, color: AppColors.primary),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Trabalho em curso'.tr,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primaryDark)),
                          Text(
                            [
                              ativo.servicoNome.isNotEmpty
                                  ? ativo.servicoNome
                                  : ativo.oficioNome,
                              casaEstadoParaProfissional(ativo.estado),
                            ].join(' · '),
                            style: const TextStyle(color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                    Text('Continuar'.tr,
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          AvisoToqueBanner(
            ativo: algumLigado,
            margem: const EdgeInsets.only(bottom: Spacing.md),
          ),
          const AvisoAtividadeBanner(margem: EdgeInsets.only(bottom: Spacing.md)),
          if (faltas.isNotEmpty || aCaducar.isNotEmpty)
            InkWell(
              key: const Key('casa_aviso_documentos'),
              onTap: () => onAbrir(const HandymanDocumentosScreen()),
              borderRadius: BorderRadius.circular(Radii.lg),
              child: Container(
                margin: const EdgeInsets.only(bottom: Spacing.md),
                padding: const EdgeInsets.all(Spacing.md),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(Radii.lg),
                  border:
                      Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: AppColors.warning),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: Text(
                        faltas.isNotEmpty
                            ? 'Tens documentos em falta ou recusados. Toca para enviar.'.tr
                            : 'Tens documentos a caducar. Toca para enviar os novos.'.tr,
                        style: const TextStyle(color: AppColors.textPrimary),
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.warning),
                  ],
                ),
              ),
            ),
          InkWell(
            onTap: () => onAbrir(const HandymanGanhosScreen()),
            borderRadius: BorderRadius.circular(Radii.lg),
            child: CasaCaixa(
              child: Row(
                children: [
                  Expanded(
                    child: CasaGanhoGrande(
                      cents: store.ganhos.ganhoCents,
                      legenda: 'Ganhaste esta semana'.tr,
                      tamanho: 28,
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.textSubtle),
                ],
              ),
            ),
          ),
          _OficiosCard(store: store),
          if (store.slots.isEmpty)
            InkWell(
              onTap: () => onAbrir(const HandymanDisponibilidadeScreen()),
              borderRadius: BorderRadius.circular(Radii.lg),
              child: Container(
                margin: const EdgeInsets.only(bottom: Spacing.md),
                padding: const EdgeInsets.all(Spacing.md),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(Radii.lg),
                  border:
                      Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.warning),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: Text(
                        'Ainda não marcaste a tua disponibilidade — sem ela não recebes ofertas. Toca aqui.'.tr,
                        style: const TextStyle(color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              _Atalho(
                icone: Icons.event_available,
                texto: 'Disponibilidade'.tr,
                onTap: () => onAbrir(const HandymanDisponibilidadeScreen()),
              ),
              _Atalho(
                icone: Icons.payments_outlined,
                texto: 'Ganhos'.tr,
                onTap: () => onAbrir(const HandymanGanhosScreen()),
              ),
              _Atalho(
                icone: Icons.badge_outlined,
                texto: 'Documentos'.tr,
                onTap: () => onAbrir(const HandymanDocumentosScreen()),
              ),
              // O ecrã único do comprovativo de atividade (não se duplica).
              _Atalho(
                icone: Icons.receipt_long_outlined,
                texto: 'Comprovativo de atividade'.tr,
                onTap: () => onAbrir(const ComprovativoAtividadeScreen()),
              ),
              _Atalho(
                icone: Icons.support_agent_outlined,
                texto: 'Suporte'.tr,
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const BoraSupportSheet(),
                ),
              ),
              if (mostrarCaixaDePapeis(papeis))
                _Atalho(
                  icone: Icons.swap_horiz,
                  texto: 'Os meus papéis'.tr,
                  onTap: onPapeis,
                ),
            ],
          ),
          CasaSeccao('Ofertas para ti'.tr),
          if (ofertas.isEmpty)
            Text(
              algumLigado
                  ? 'Sem ofertas agora. Quando houver, tocamos e aparecem aqui.'.tr
                  : 'Liga pelo menos um ofício para receberes ofertas.'.tr,
              style: const TextStyle(color: AppColors.textSecondary),
            )
          else
            for (final o in ofertas)
              CasaOfertaCartao(
                key: ValueKey('casa_oferta_${o.pedidoId}'),
                oferta: o,
                ocupado: aAgir,
                maxOrcamentos: store.config.quoteMaxPros,
                urlDaFoto: store.urlDaFoto,
                onAceitar: () => onAceitar(o),
                onRecusar: () => onRecusar(o),
                onOrcar: () => onOrcar(o),
              ),
          CasaSeccao('Os meus trabalhos'.tr),
          if (store.trabalhosAtivos.isEmpty)
            Text('Sem trabalhos marcados.'.tr,
                style: const TextStyle(color: AppColors.textSecondary))
          else
            for (final p in store.trabalhosAtivos)
              _TrabalhoLinha(pedido: p, onTap: () => onAbrirTrabalho(p)),
          if (historico.isNotEmpty) ...[
            CasaSeccao('Histórico'.tr),
            for (final p in historico)
              _TrabalhoLinha(pedido: p, onTap: () => onAbrirTrabalho(p)),
          ],
        ],
      ),
    );
  }
}

/// Interruptor por ofício: só os aprovados ligam. Guarda local por ofício.
class _OficiosCard extends StatefulWidget {
  const _OficiosCard({required this.store});
  final HandymanStore store;

  @override
  State<_OficiosCard> createState() => _OficiosCardState();
}

class _OficiosCardState extends State<_OficiosCard> {
  final Set<String> _aMudar = {};

  Future<void> _mudar(CasaOficioDoProfissional o, bool v) async {
    if (_aMudar.contains(o.codigo)) return;
    setState(() => _aMudar.add(o.codigo));
    final ok = await widget.store.ligarOficio(o.codigo, v);
    if (!mounted) return;
    setState(() => _aMudar.remove(o.codigo));
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.store.lastError ?? casaErroTexto(''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final oficios = widget.store.perfil?.oficios ?? const [];
    return CasaCaixa(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Os meus ofícios'.tr,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          if (oficios.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.sm),
              child: Text('Ainda não tens ofícios.'.tr,
                  style: const TextStyle(color: AppColors.textSecondary)),
            ),
          for (final o in oficios)
            SwitchListTile(
              key: ValueKey('casa_oficio_switch_${o.codigo}'),
              value: o.aprovado && o.ligado,
              onChanged: (!o.aprovado || _aMudar.contains(o.codigo))
                  ? null
                  : (v) => _mudar(o, v),
              title: Text(o.nome,
                  style: const TextStyle(color: AppColors.textPrimary)),
              subtitle: Text(
                o.aprovado
                    ? (o.ligado
                        ? 'A receber ofertas'.tr
                        : 'Desligado — sem ofertas'.tr)
                    : casaEstadoOficioTexto(o),
                style: const TextStyle(fontSize: 12.5),
              ),
              activeThumbColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
        ],
      ),
    );
  }
}

class _Atalho extends StatelessWidget {
  const _Atalho({required this.icone, required this.texto, required this.onTap});
  final IconData icone;
  final String texto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ActionChip(
        avatar: Icon(icone, size: 18, color: AppColors.primary),
        label: Text(texto),
        onPressed: onTap,
        backgroundColor: AppColors.surface,
        side: const BorderSide(color: AppColors.divider),
      );
}

class _TrabalhoLinha extends StatelessWidget {
  const _TrabalhoLinha({required this.pedido, required this.onTap});
  final CasaPedido pedido;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = pedido;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.lg),
      child: CasaCaixa(
        destaque: p.estado.ativo,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.servicoNome.isNotEmpty ? p.servicoNome : p.oficioNome,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  Text(
                    [
                      casaEstadoParaProfissional(p.estado),
                      casaJanelaTexto(p.scheduledAt, p.duracaoMin),
                      if (p.moradaCidade.isNotEmpty) p.moradaCidade,
                    ].join(' · '),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            if (p.ganhoCents != null)
              Text(casaEuro(p.ganhoCents!),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: AppColors.primaryDark)),
          ],
        ),
      ),
    );
  }
}

/// O cartão de uma oferta (preço fixo/hora) ou de um convite para orçar. Mostra
/// a zona e a distância (nunca a porta). O número GRANDE é o que o
/// profissional ganha.
class CasaOfertaCartao extends StatelessWidget {
  const CasaOfertaCartao({
    super.key,
    required this.oferta,
    this.onAceitar,
    this.onRecusar,
    this.onOrcar,
    this.urlDaFoto,
    this.ocupado = false,
    this.maxOrcamentos = 3,
  });

  final CasaOferta oferta;
  final VoidCallback? onAceitar;
  final VoidCallback? onRecusar;
  final VoidCallback? onOrcar;
  final Future<String?> Function(String path)? urlDaFoto;
  final bool ocupado;
  final int maxOrcamentos;

  @override
  Widget build(BuildContext context) {
    final o = oferta;
    final zona = [
      if (o.localidade.trim().isNotEmpty) o.localidade.trim(),
      if (o.distanciaKm != null) casaDistanciaTexto(o.distanciaKm),
    ].join(' · ');
    final modo = switch (o.modo) {
      CasaModo.orcamento => 'Orçamento'.tr,
      CasaModo.hora => 'À hora'.tr,
      CasaModo.fixo => 'Preço fixo'.tr,
    };
    return CasaCaixa(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.handyman, color: AppColors.primary),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.servicoNome.isNotEmpty ? o.servicoNome : o.oficioNome,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15.5,
                          color: AppColors.textPrimary),
                    ),
                    if (o.oficioNome.isNotEmpty && o.servicoNome.isNotEmpty)
                      Text(o.oficioNome,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12.5)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryWash,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Text(modo,
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryDark)),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          if (!o.convite && o.ganhoCents != null) ...[
            CasaGanhoGrande(
              key: const Key('casa_oferta_ganho'),
              cents: o.ganhoCents!,
              legenda: o.modo == CasaModo.hora
                  ? 'Ganhas (estimado para {0})'.trArgs([casaDuracaoTexto(o.duracaoMin)])
                  : 'Ganhas'.tr,
            ),
            const SizedBox(height: Spacing.sm),
          ],
          if (o.convite)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: Text(
                maxOrcamentos > 0
                    ? 'Pedido de orçamento — {0} de {1} já orçaram'.trArgs([o.orcamentosRecebidos, maxOrcamentos])
                    : 'Pedido de orçamento — {0} já orçaram'.trArgs([o.orcamentosRecebidos]),
                key: const Key('casa_oferta_convite'),
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.primaryDark),
              ),
            ),
          if (zona.isNotEmpty)
            _Info(Icons.place_outlined, zona, chave: const Key('casa_oferta_zona')),
          _Info(Icons.event, casaJanelaTexto(o.scheduledAt, o.duracaoMin)),
          if (o.expiraEm != null)
            _Info(Icons.timer_outlined,
                'Responde até {0}'.trArgs([dataHoraLisboa(o.expiraEm!.toUtc().toIso8601String())])),
          if (o.descricao.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.xs),
              child: Text(o.descricao.trim(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textPrimary)),
            ),
          if (o.fotos.isNotEmpty) ...[
            const SizedBox(height: Spacing.sm),
            CasaFotosFila(paths: o.fotos, urlDe: urlDaFoto),
          ],
          const SizedBox(height: Spacing.md),
          if (o.convite)
            (o.jaOrcei
                ? Row(
                    children: [
                      const Icon(Icons.check_circle, color: AppColors.primary),
                      const SizedBox(width: Spacing.xs),
                      Expanded(child: Text('Já enviaste o teu orçamento.'.tr)),
                      TextButton(
                        key: const Key('casa_oferta_orcar'),
                        onPressed: ocupado ? null : onOrcar,
                        child: Text('Ver'.tr),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          key: const Key('casa_oferta_recusar'),
                          onPressed: ocupado ? null : onRecusar,
                          child: Text('Não me interessa'.tr),
                        ),
                      ),
                      const SizedBox(width: Spacing.sm),
                      Expanded(
                        child: FilledButton(
                          key: const Key('casa_oferta_orcar'),
                          onPressed: ocupado ? null : onOrcar,
                          child: Text('Enviar orçamento'.tr),
                        ),
                      ),
                    ],
                  ))
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('casa_oferta_recusar'),
                    onPressed: ocupado ? null : onRecusar,
                    child: Text('Recusar'.tr),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: FilledButton(
                    key: const Key('casa_oferta_aceitar'),
                    onPressed: ocupado ? null : onAceitar,
                    child: Text('Aceitar'.tr),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.icone, this.texto, {this.chave});
  final IconData icone;
  final String texto;
  final Key? chave;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(children: [
          Icon(icone, size: 17, color: AppColors.textSecondary),
          const SizedBox(width: Spacing.xs),
          Expanded(
              child: Text(texto,
                  key: chave,
                  style: const TextStyle(color: AppColors.textPrimary))),
        ]),
      );
}
