import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../l10n/tr.dart';
import '../../models/casa_models.dart';
import '../../stores/handyman_store.dart';
import '../../widgets/bora/bora.dart';
import '../../widgets/botao_rota.dart';
import 'casa_camara.dart';
import 'casa_profissional_ui.dart';
import 'handyman_chat_screen.dart';

/// CASA — o trabalho aceite, do lado do profissional. Morada completa e rota
/// (a mesma `BotaoRota` da limpeza), botões a caminho → cheguei → iniciar →
/// concluir, fotos de antes e depois (concluir exige pelo menos uma de
/// depois), valor extra com consentimento do cliente, chat e ligar só com
/// `pode_contactar`, avaliar o cliente no fim e desistir com confirmação.
/// Regra 1.24: ao acabar, volta sozinho.
class HandymanTrabalhoScreen extends StatefulWidget {
  const HandymanTrabalhoScreen({super.key, required this.pedidoId, this.inicial});

  final String pedidoId;

  /// O pedido já conhecido (lista), para desenhar sem esperar pela rede.
  final CasaPedido? inicial;

  @override
  State<HandymanTrabalhoScreen> createState() => _HandymanTrabalhoScreenState();
}

class _HandymanTrabalhoScreenState extends State<HandymanTrabalhoScreen> {
  /// Trava de toque duplo LOCAL (PADRAO_BORA 3.13).
  bool _aAgir = false;
  String? _fotoAEnviar;
  bool _carregou = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final s = context.read<HandymanStore>();
      if (!s.configCarregada) s.loadConfig().ignore();
      await s.pedido(widget.pedidoId);
      if (mounted) setState(() => _carregou = true);
    });
  }

  void _snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _avancar(CasaPedido p, String para) async {
    if (_aAgir) return;
    final store = context.read<HandymanStore>();
    if (para == 'concluido') {
      final dinheiro = p.paymentMethod == 'cash';
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Concluir o trabalho?'.tr),
          content: Text(dinheiro
              ? 'O cliente confirma na app. Recebe agora em dinheiro: {0}.'.trArgs([casaEuro(p.totalCents)])
              : 'O cliente confirma na app. O pagamento entra no acerto da semana.'.tr),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Ainda não'.tr)),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Concluir'.tr)),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _aAgir = true);
    final ok = await store.avancar(p.id, para);
    if (!mounted) return;
    setState(() => _aAgir = false);
    if (!ok) {
      _snack(store.lastError ?? casaErroTexto(''));
      return;
    }
    if (para == 'concluido') {
      await _avaliar(p.id, depoisDeConcluir: true);
      if (!mounted) return;
      // FIM DO TRABALHO — volta sozinho ao ecrã de onde veio (regra 1.24).
      if (Navigator.canPop(context)) Navigator.pop(context);
    }
  }

  Future<void> _tirarFoto(CasaPedido p, String tipo) async {
    if (_fotoAEnviar != null) return;
    final store = context.read<HandymanStore>();
    final f = await casaTirarFoto(context);
    if (f == null || !mounted) return;
    setState(() => _fotoAEnviar = tipo);
    final ok = await store.adicionarFoto(p.id, tipo, f);
    if (!mounted) return;
    setState(() => _fotoAEnviar = null);
    if (!ok) _snack(store.lastError ?? casaErroTexto(''));
  }

  Future<void> _pedirExtra(CasaPedido p) async {
    final valorCtrl = TextEditingController();
    final motivoCtrl = TextEditingController();
    final r = await showDialog<({int cents, String motivo})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Pedir valor extra'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'O cliente tem de aceitar na app. Só faças o trabalho extra depois de ele aceitar.'.tr,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              key: const Key('casa_extra_valor'),
              controller: valorCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Valor'.tr, suffixText: '€'),
            ),
            TextField(
              key: const Key('casa_extra_motivo'),
              controller: motivoCtrl,
              maxLength: 300,
              decoration: InputDecoration(
                labelText: 'Motivo'.tr,
                hintText: 'Ex.: o sifão estava partido, tive de pôr um novo.'.tr,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancelar'.tr)),
          FilledButton(
            onPressed: () {
              final c = casaEurosParaCents(valorCtrl.text);
              final m = motivoCtrl.text.trim();
              if (c == null || m.length < 3) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Indica o valor e o motivo.'.tr)));
                return;
              }
              Navigator.pop(ctx, (cents: c, motivo: m));
            },
            child: Text('Pedir ao cliente'.tr),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      valorCtrl.dispose();
      motivoCtrl.dispose();
    });
    if (r == null || !mounted) return;
    final store = context.read<HandymanStore>();
    setState(() => _aAgir = true);
    final ok = await store.pedirExtra(p.id, r.cents, r.motivo);
    if (!mounted) return;
    setState(() => _aAgir = false);
    _snack(ok
        ? 'Pedido enviado ao cliente. Espera que ele aceite.'.tr
        : (store.lastError ?? casaErroTexto('')));
  }

  /// Avaliar o cliente (1 a 5). Depois de concluir pode deixar para mais tarde.
  Future<void> _avaliar(String pedidoId, {bool depoisDeConcluir = false}) async {
    final nota = await showDialog<int>(
      context: context,
      builder: (ctx) => _AvaliarClienteDialogo(podeAdiar: depoisDeConcluir),
    );
    if (nota == null || !mounted) return;
    final store = context.read<HandymanStore>();
    final ok = await store.avaliarCliente(pedidoId, nota);
    if (!mounted) return;
    _snack(ok
        ? 'Obrigado pela avaliação.'.tr
        : (store.lastError ?? casaErroTexto('')));
  }

  Future<void> _desistir(CasaPedido p) async {
    final motivoCtrl = TextEditingController();
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Desistir deste trabalho?'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'O pedido volta a ser oferecido a outro profissional. Desistir muitas vezes conta na tua avaliação.'.tr,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              controller: motivoCtrl,
              decoration: InputDecoration(labelText: 'Motivo'.tr),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Voltar'.tr)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Desistir'.tr),
          ),
        ],
      ),
    );
    final motivo = motivoCtrl.text;
    Future<void>.delayed(
        const Duration(milliseconds: 600), motivoCtrl.dispose);
    if (confirmou != true || !mounted) return;
    final store = context.read<HandymanStore>();
    setState(() => _aAgir = true);
    final ok = await store.desistir(p.id, motivo);
    if (!mounted) return;
    setState(() => _aAgir = false);
    if (!ok) {
      _snack(store.lastError ?? casaErroTexto(''));
      return;
    }
    _snack('Desististe do trabalho.'.tr);
    if (Navigator.canPop(context)) Navigator.pop(context);
  }

  Future<void> _ligar(String phone) async {
    final uri = Uri.parse('tel:$phone');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      _snack('Não foi possível abrir o telefone.'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HandymanStore>();
    final p = store.trabalhoPorId(widget.pedidoId) ?? widget.inicial;
    if (p == null) {
      return Scaffold(
        appBar: BoraScreenAppBar(title: 'Trabalho'.tr),
        body: Center(
          child: _carregou
              ? Text('Este trabalho já não está disponível.'.tr)
              : const CircularProgressIndicator(),
        ),
      );
    }
    final servico =
        casaServicoDe(store.config, id: p.servicoId, nome: p.servicoNome);
    final respostas = casaRespostasLegiveis(p.respostas, servico);
    final moradaCompleta = [
      p.moradaRua,
      [p.moradaPostal, p.moradaCidade].where((s) => s.trim().isNotEmpty).join(' '),
    ].where((s) => s.trim().isNotEmpty).join(', ');
    final podeFotoAntes =
        p.estado == CasaEstado.chegou || p.estado == CasaEstado.emCurso;
    final podeFotoDepois = p.estado == CasaEstado.emCurso;
    final maxFotos = store.config.maxFotos;
    final podeExtra =
        p.estado == CasaEstado.chegou || p.estado == CasaEstado.emCurso;
    final terminado = p.estado == CasaEstado.concluido ||
        p.estado == CasaEstado.confirmado ||
        p.estado == CasaEstado.disputa;

    return Scaffold(
      appBar: BoraScreenAppBar(
          title: p.servicoNome.isNotEmpty ? p.servicoNome : 'Trabalho'.tr),
      body: RefreshIndicator(
        onRefresh: () async {
          await store.pedido(p.id);
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg,
              BoraBottomActionBar.folgaInferior(context)),
          children: [
            // ── Estado + ganho ───────────────────────────────────────────
            CasaCaixa(
              destaque: p.estado.ativo,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(casaEstadoParaProfissional(p.estado),
                      key: const Key('casa_trabalho_estado'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryDark)),
                  const SizedBox(height: Spacing.sm),
                  CasaGanhoGrande(cents: p.ganhoCents ?? 0),
                  if (p.paymentMethod == 'cash' && p.totalCents > 0)
                    Text(
                      'A cobrar ao cliente em dinheiro: {0}'.trArgs([casaEuro(p.totalCents)]),
                      key: const Key('casa_trabalho_cobrar'),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12.5),
                    ),
                  const SizedBox(height: Spacing.sm),
                  Row(children: [
                    const Icon(Icons.event, size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: Spacing.xs),
                    Expanded(
                        child: Text(casaJanelaTexto(p.scheduledAt, p.duracaoMin))),
                  ]),
                ],
              ),
            ),

            // ── Morada e rota ────────────────────────────────────────────
            CasaSeccao('Morada'.tr),
            CasaCaixa(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(moradaCompleta.isEmpty ? '—' : moradaCompleta,
                      key: const Key('casa_trabalho_morada'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: Spacing.sm),
                  BotaoRota(morada: moradaCompleta, lat: p.lat, lng: p.lng),
                ],
              ),
            ),

            // ── Cliente e contacto ───────────────────────────────────────
            CasaSeccao('Cliente'.tr),
            CasaCaixa(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (p.cliente?.nome ?? '').isEmpty ? 'Cliente'.tr : p.cliente!.nome,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: Spacing.sm),
                  if (p.podeContactar)
                    Wrap(
                      spacing: Spacing.sm,
                      runSpacing: Spacing.sm,
                      children: [
                        OutlinedButton.icon(
                          key: const Key('casa_trabalho_chat'),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => HandymanChatScreen(
                                pedidoId: p.id,
                                titulo: p.cliente?.nome ?? '',
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: Text('Mensagens'.tr),
                        ),
                        if ((p.cliente?.phone ?? '').isNotEmpty)
                          OutlinedButton.icon(
                            key: const Key('casa_trabalho_ligar'),
                            onPressed: () => _ligar(p.cliente!.phone!),
                            icon: const Icon(Icons.phone_outlined),
                            label: Text('Ligar'.tr),
                          ),
                      ],
                    )
                  else
                    Text(
                      'O contacto do cliente aparece quando o pedido estiver confirmado e pago.'.tr,
                      key: const Key('casa_trabalho_sem_contacto'),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                ],
              ),
            ),

            // ── O pedido ─────────────────────────────────────────────────
            CasaSeccao('O que o cliente pediu'.tr),
            CasaCaixa(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      if (p.oficioNome.isNotEmpty) p.oficioNome,
                      if (p.quantidade != 1)
                        '× ${p.quantidade.toStringAsFixed(p.quantidade % 1 == 0 ? 0 : 1)}',
                    ].join(' '),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  if (p.descricao.trim().isNotEmpty) ...[
                    const SizedBox(height: Spacing.xs),
                    Text(p.descricao.trim(),
                        style: const TextStyle(
                            color: AppColors.textPrimary, height: 1.4)),
                  ],
                  for (final r in respostas)
                    Padding(
                      padding: const EdgeInsets.only(top: Spacing.xs),
                      child: Text('${r.$1}: ${r.$2}',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 13)),
                    ),
                  if (p.fotosDe('problema').isNotEmpty) ...[
                    const SizedBox(height: Spacing.sm),
                    CasaFotosFila(
                      paths: p.fotosDe('problema').map((f) => f.storagePath).toList(),
                      urlDe: store.urlDaFoto,
                    ),
                  ],
                ],
              ),
            ),

            // ── Fotos de antes e depois ──────────────────────────────────
            if (p.estado.ativo || terminado) ...[
              CasaSeccao('Fotos do trabalho'.tr),
              _FotosDoTipo(
                titulo: 'Antes'.tr,
                fotos: p.fotosDe('antes'),
                urlDe: store.urlDaFoto,
                aEnviar: _fotoAEnviar == 'antes',
                podeTirar: podeFotoAntes && p.fotosDe('antes').length < maxFotos,
                onTirar: () => _tirarFoto(p, 'antes'),
              ),
              _FotosDoTipo(
                titulo: 'Depois'.tr,
                fotos: p.fotosDe('depois'),
                urlDe: store.urlDaFoto,
                aEnviar: _fotoAEnviar == 'depois',
                podeTirar: podeFotoDepois && p.fotosDe('depois').length < maxFotos,
                onTirar: () => _tirarFoto(p, 'depois'),
              ),
            ],

            // ── Valores extra ────────────────────────────────────────────
            if (p.extras.isNotEmpty || podeExtra) ...[
              CasaSeccao('Valor extra'.tr),
              for (final e in p.extras)
                CasaCaixa(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(casaEuro(e.valorCents),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary)),
                            Text(e.motivo,
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13)),
                          ],
                        ),
                      ),
                      Text(casaEstadoExtraTexto(e.estado),
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: e.estado == 'aceite'
                                  ? AppColors.primary
                                  : (e.estado == 'recusado'
                                      ? AppColors.error
                                      : AppColors.warning))),
                    ],
                  ),
                ),
              if (podeExtra)
                OutlinedButton.icon(
                  key: const Key('casa_trabalho_pedir_extra'),
                  onPressed: _aAgir ? null : () => _pedirExtra(p),
                  icon: const Icon(Icons.add_circle_outline),
                  label: Text('Pedir valor extra'.tr),
                ),
            ],

            // ── Disputa ──────────────────────────────────────────────────
            if (p.estado == CasaEstado.disputa)
              CasaCaixa(
                child: Text(
                  'O cliente pediu para refazer. Combina com ele pelas mensagens o dia para voltar.'.tr,
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
              ),

            const SizedBox(height: Spacing.lg),
            CasaAcaoPrincipal(
              pedido: p,
              aAgir: _aAgir,
              onAvancar: (para) => _avancar(p, para),
            ),

            // ── Avaliar o cliente ────────────────────────────────────────
            if (terminado && p.ratingProfissional == null) ...[
              const SizedBox(height: Spacing.md),
              OutlinedButton.icon(
                key: const Key('casa_trabalho_avaliar'),
                onPressed: () => _avaliar(p.id),
                icon: const Icon(Icons.star_outline),
                label: Text('Avaliar o cliente'.tr),
              ),
            ],

            // ── Desistir ─────────────────────────────────────────────────
            if (p.estado.ativo) ...[
              const SizedBox(height: Spacing.lg),
              TextButton(
                key: const Key('casa_trabalho_desistir'),
                onPressed: _aAgir ? null : () => _desistir(p),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                child: Text('Desistir deste trabalho'.tr),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// O botão principal do trabalho (a caminho → cheguei → iniciar → concluir).
/// Concluir fica desligado sem pelo menos uma foto de depois.
class CasaAcaoPrincipal extends StatelessWidget {
  const CasaAcaoPrincipal({
    super.key,
    required this.pedido,
    required this.onAvancar,
    this.aAgir = false,
  });

  final CasaPedido pedido;
  final void Function(String para) onAvancar;
  final bool aAgir;

  @override
  Widget build(BuildContext context) {
    final passo = casaProximoPasso(pedido.estado);
    if (passo == null) return const SizedBox.shrink();
    final bloqueado = passo.para == 'concluido' && !casaPodeConcluir(pedido);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BoraPrimaryButton(
          key: const Key('casa_trabalho_avancar'),
          label: passo.rotulo,
          icon: switch (passo.para) {
            'a_caminho' => Icons.directions_car_outlined,
            'chegou' => Icons.place,
            'em_curso' => Icons.handyman,
            _ => Icons.check_circle_outline,
          },
          loading: aAgir,
          onPressed: bloqueado ? null : () => onAvancar(passo.para),
        ),
        if (bloqueado)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.sm),
            child: Text(
              'Para concluir, tira pelo menos uma foto de como ficou (depois).'.tr,
              key: const Key('casa_concluir_bloqueado'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.warning, fontSize: 12.5),
            ),
          ),
      ],
    );
  }
}

class _FotosDoTipo extends StatelessWidget {
  const _FotosDoTipo({
    required this.titulo,
    required this.fotos,
    required this.urlDe,
    required this.aEnviar,
    required this.podeTirar,
    required this.onTirar,
  });

  final String titulo;
  final List<CasaFoto> fotos;
  final Future<String?> Function(String path) urlDe;
  final bool aEnviar;
  final bool podeTirar;
  final VoidCallback onTirar;

  @override
  Widget build(BuildContext context) {
    return CasaCaixa(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('$titulo (${fotos.length})',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              if (aEnviar)
                const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else if (podeTirar)
                TextButton.icon(
                  onPressed: onTirar,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text('Tirar foto'.tr),
                ),
            ],
          ),
          if (fotos.isNotEmpty) ...[
            const SizedBox(height: Spacing.sm),
            CasaFotosFila(
              paths: fotos.map((f) => f.storagePath).toList(),
              urlDe: urlDe,
            ),
          ],
        ],
      ),
    );
  }
}

class _AvaliarClienteDialogo extends StatefulWidget {
  const _AvaliarClienteDialogo({required this.podeAdiar});
  final bool podeAdiar;

  @override
  State<_AvaliarClienteDialogo> createState() => _AvaliarClienteDialogoState();
}

class _AvaliarClienteDialogoState extends State<_AvaliarClienteDialogo> {
  int _nota = 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Como correu com o cliente?'.tr),
      content: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              onPressed: () => setState(() => _nota = i),
              icon: Icon(i <= _nota ? Icons.star : Icons.star_border,
                  color: AppColors.primary, size: 32),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.podeAdiar ? 'Avaliar depois'.tr : 'Cancelar'.tr),
        ),
        FilledButton(
          onPressed: _nota == 0 ? null : () => Navigator.pop(context, _nota),
          child: Text('Avaliar'.tr),
        ),
      ],
    );
  }
}
