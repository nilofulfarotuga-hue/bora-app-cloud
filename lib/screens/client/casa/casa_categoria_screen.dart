import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../l10n/tr.dart';
import '../../../models/casa_models.dart';
import '../../../stores/casa_store.dart';
import '../../../widgets/bora/bora.dart';
import '../../../widgets/bora/lista_estado.dart';
import 'casa_meus_pedidos_screen.dart';
import 'casa_pedido_wizard_screen.dart';
import 'casa_regras.dart';
import 'casa_widgets.dart';

/// CASA — entrada do ladrilho "Casa" (31/10/2026).
///
/// Cartões por ofício (só os ativos da fase 1) e, dentro de cada um, os
/// serviços: preço fixo / à hora mostram "desde X €" (o número vem do servidor,
/// nunca do código); orçamento mostra "Pedir orçamento — grátis, até N
/// profissionais respondem".
///
/// Regra 1.27 (loja fechada): o cliente vê tudo; o travão só existe ao
/// confirmar, no servidor. Este ecrã nunca fica preso à espera: com a
/// configuração já em memória desenha logo e só refresca por trás.
class CasaCategoriaScreen extends StatefulWidget {
  const CasaCategoriaScreen({super.key});

  @override
  State<CasaCategoriaScreen> createState() => _CasaCategoriaScreenState();
}

class _CasaCategoriaScreenState extends State<CasaCategoriaScreen> {
  /// Ofício aberto (mostra os serviços por baixo). Só um de cada vez.
  String? _aberto;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = context.read<CasaStore>();
      store.refreshSettings();
      store.carregarMeusPedidos();
    });
  }

  List<CasaOficio> _oficios(CasaConfig c) => c.oficios
      .where((o) => o.ativo && o.fase == 1 && c.servicosDe(o.codigo).isNotEmpty)
      .toList();

  void _abrirServico(CasaServico s) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CasaPedidoWizardScreen(servico: s)),
    );
  }

  void _abrirMeusPedidos() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CasaMeusPedidosScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CasaStore>();
    final config = store.config;

    final Widget corpo;
    if (!store.configCarregada && !store.configFalhou) {
      corpo = const ListaACarregar();
    } else if (!store.configCarregada && store.configFalhou) {
      corpo = ListaComErro(onRetry: store.refreshSettings);
    } else if (!store.enabled) {
      corpo = const _Brevemente();
    } else {
      final oficios = _oficios(config);
      corpo = RefreshIndicator(
        onRefresh: store.refreshSettings,
        child: ListView(
          padding: EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg,
              BoraBottomActionBar.folgaInferior(context)),
          children: [
            Text(
              'Do que precisas em casa?'.tr,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              'Escolhe o trabalho. Nos de preço fixo vês já o valor; nos outros pedes orçamento grátis e escolhes o profissional.'.tr,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: Spacing.lg),
            _BotaoMeusPedidos(
              ativos: store.pedidosAtivos.length,
              onTap: _abrirMeusPedidos,
            ),
            const SizedBox(height: Spacing.lg),
            if (oficios.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
                child: Text(
                  'Ainda não há trabalhos disponíveis. Volta daqui a pouco.'.tr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            for (final o in oficios) ...[
              _CartaoOficio(
                oficio: o,
                servicos: config.servicosDe(o.codigo),
                quoteMaxPros: config.quoteMaxPros,
                aberto: _aberto == o.codigo,
                onAlternar: () => setState(
                    () => _aberto = _aberto == o.codigo ? null : o.codigo),
                onServico: _abrirServico,
              ),
              const SizedBox(height: Spacing.md),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(title: 'Casa e manutenção'.tr),
      body: corpo,
    );
  }
}

class _Brevemente extends StatelessWidget {
  const _Brevemente();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.home_repair_service_outlined,
                size: 64, color: AppColors.primary),
            const SizedBox(height: Spacing.lg),
            Text(
              'Brevemente'.tr,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Montagem de móveis, pequenas reparações, jardim e mais — feitos por profissionais da tua zona. Estamos quase a abrir.'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _BotaoMeusPedidos extends StatelessWidget {
  const _BotaoMeusPedidos({required this.ativos, required this.onTap});

  final int ativos;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CasaCartao(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg, vertical: Spacing.md),
      child: Row(
        children: [
          const Icon(Icons.list_alt_outlined, color: AppColors.primary),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              'Os meus pedidos'.tr,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (ativos > 0)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Text(
                '$ativos',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          const Icon(Icons.chevron_right, color: AppColors.textSubtle),
        ],
      ),
    );
  }
}

class _CartaoOficio extends StatelessWidget {
  const _CartaoOficio({
    required this.oficio,
    required this.servicos,
    required this.quoteMaxPros,
    required this.aberto,
    required this.onAlternar,
    required this.onServico,
  });

  final CasaOficio oficio;
  final List<CasaServico> servicos;
  final int quoteMaxPros;
  final bool aberto;
  final VoidCallback onAlternar;
  final ValueChanged<CasaServico> onServico;

  @override
  Widget build(BuildContext context) {
    return CasaCartao(
      destacado: aberto,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(Radii.lg),
            onTap: onAlternar,
            child: Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primaryWash,
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                    child: Icon(casaIconeOficio(oficio.codigo),
                        color: AppColors.primary),
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Nome e descrição vêm do catálogo (servidor): não
                        // levam .tr — não são texto da app.
                        Text(
                          oficio.nome,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (oficio.descricao.isNotEmpty)
                          Text(
                            oficio.descricao,
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  Icon(aberto ? Icons.expand_less : Icons.expand_more,
                      color: AppColors.textSubtle),
                ],
              ),
            ),
          ),
          if (aberto)
            for (final s in servicos) ...[
              const Divider(height: 1),
              _LinhaServico(
                servico: s,
                quoteMaxPros: quoteMaxPros,
                onTap: () => onServico(s),
              ),
            ],
        ],
      ),
    );
  }
}

class _LinhaServico extends StatelessWidget {
  const _LinhaServico({
    required this.servico,
    required this.quoteMaxPros,
    required this.onTap,
  });

  final CasaServico servico;
  final int quoteMaxPros;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final orc = servico.pedeOrcamento;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.md, Spacing.md, Spacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    servico.nome,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (servico.descricao.isNotEmpty)
                    Text(
                      servico.descricao,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    casaTextoPreco(servico, quoteMaxPros: quoteMaxPros),
                    style: TextStyle(
                      color: orc ? AppColors.textPrimary : AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSubtle),
          ],
        ),
      ),
    );
  }
}
