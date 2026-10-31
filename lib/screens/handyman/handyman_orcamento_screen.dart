import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../l10n/tr.dart';
import '../../models/casa_models.dart';
import '../../stores/handyman_store.dart';
import '../../widgets/bora/bora.dart';
import 'casa_profissional_ui.dart';

/// CASA — o orçamento para um convite (`casa_enviar_orcamento`): preço fechado
/// (euros → cêntimos), o que inclui, materiais (incluídos ou não), prazo e
/// duração estimada. Até `quote_max_pros` profissionais orçam; o cliente
/// escolhe. Vê-se a zona e a distância, nunca a porta.
class HandymanOrcamentoScreen extends StatefulWidget {
  const HandymanOrcamentoScreen({super.key, required this.oferta});

  final CasaOferta oferta;

  @override
  State<HandymanOrcamentoScreen> createState() =>
      _HandymanOrcamentoScreenState();
}

/// Durações que se podem escolher (minutos).
const List<int> kCasaDuracoes = [30, 60, 90, 120, 180, 240, 360, 480];

class _HandymanOrcamentoScreenState extends State<HandymanOrcamentoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _precoCtrl = TextEditingController();
  final _incluiCtrl = TextEditingController();
  final _materiaisCtrl = TextEditingController();
  final _prazoCtrl = TextEditingController();
  bool _materiaisIncluidos = false;
  int? _duracao;

  /// Guarda local do botão (PADRAO_BORA 3.13).
  bool _aEnviar = false;

  @override
  void initState() {
    super.initState();
    final d = widget.oferta.duracaoMin;
    _duracao = kCasaDuracoes.contains(d) ? d : null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = context.read<HandymanStore>();
      if (!s.configCarregada) s.loadConfig();
    });
  }

  @override
  void dispose() {
    _precoCtrl.dispose();
    _incluiCtrl.dispose();
    _materiaisCtrl.dispose();
    _prazoCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_aEnviar) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final cents = casaEurosParaCents(_precoCtrl.text);
    if (cents == null) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Enviar orçamento de {0}?'.trArgs([casaEuro(cents)])),
        content: Text(
            'É um preço fechado: se o cliente aceitar, o trabalho é teu por este valor.'.tr),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Rever'.tr)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Enviar'.tr)),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    setState(() => _aEnviar = true);
    final store = context.read<HandymanStore>();
    final ok = await store.enviarOrcamento(
      pedidoId: widget.oferta.pedidoId,
      precoCents: cents,
      inclui: _incluiCtrl.text,
      materiais: _materiaisCtrl.text,
      materiaisIncluidos: _materiaisIncluidos,
      prazo: _prazoCtrl.text,
      duracaoMin: _duracao,
    );
    if (!mounted) return;
    setState(() => _aEnviar = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Orçamento enviado. Avisamos-te se o cliente aceitar.'.tr)));
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(store.lastError ?? casaErroTexto(''))));
    }
  }

  Future<void> _recusar() async {
    if (_aEnviar) return;
    setState(() => _aEnviar = true);
    final store = context.read<HandymanStore>();
    await store.recusarOferta(widget.oferta.pedidoId);
    if (!mounted) return;
    setState(() => _aEnviar = false);
    Navigator.pop(context, false);
  }

  Future<void> _retirar(String orcamentoId) async {
    if (_aEnviar) return;
    setState(() => _aEnviar = true);
    final store = context.read<HandymanStore>();
    final ok = await store.retirarOrcamento(orcamentoId);
    if (!mounted) return;
    setState(() => _aEnviar = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? 'Orçamento retirado.'.tr
            : (store.lastError ?? casaErroTexto('')))));
    if (ok) Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HandymanStore>();
    final o = store.ofertaPorId(widget.oferta.pedidoId) ?? widget.oferta;
    final servico = casaServicoDe(store.config, nome: o.servicoNome);
    final respostas = casaRespostasLegiveis(o.respostas, servico);
    final perfil = store.perfil;
    final maxPros = store.config.quoteMaxPros;
    final meuOrcamento = store.orcamentoDe(o.pedidoId);

    return Scaffold(
      appBar: BoraScreenAppBar(title: 'Pedido de orçamento'.tr),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg,
              BoraBottomActionBar.folgaInferior(context)),
          children: [
            CasaCaixa(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    o.servicoNome.isNotEmpty ? o.servicoNome : o.oficioNome,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary),
                  ),
                  if (o.oficioNome.isNotEmpty && o.servicoNome.isNotEmpty)
                    Text(o.oficioNome,
                        style: const TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: Spacing.sm),
                  _Linha(Icons.place_outlined, [
                    if (o.localidade.isNotEmpty) o.localidade,
                    if (o.distanciaKm != null) casaDistanciaTexto(o.distanciaKm),
                  ].join(' · ')),
                  _Linha(Icons.event, casaJanelaTexto(o.scheduledAt, o.duracaoMin)),
                  _Linha(
                    Icons.groups_outlined,
                    maxPros > 0
                        ? '{0} de {1} orçamentos recebidos'.trArgs([o.orcamentosRecebidos, maxPros])
                        : '{0} orçamentos recebidos'.trArgs([o.orcamentosRecebidos]),
                  ),
                  if (o.descricao.trim().isNotEmpty) ...[
                    const SizedBox(height: Spacing.sm),
                    Text(o.descricao.trim(),
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
                  if (o.fotos.isNotEmpty) ...[
                    const SizedBox(height: Spacing.md),
                    CasaFotosFila(paths: o.fotos, urlDe: store.urlDaFoto),
                  ],
                ],
              ),
            ),
            if (o.jaOrcei) ...[
              CasaCaixa(
                destaque: true,
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: AppColors.primary),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: Text(
                          'Já enviaste o teu orçamento. Avisamos-te se o cliente o escolher.'.tr,
                          style: const TextStyle(color: AppColors.textPrimary)),
                    ),
                  ],
                ),
              ),
              if (meuOrcamento != null)
                OutlinedButton.icon(
                  onPressed: _aEnviar ? null : () => _retirar(meuOrcamento),
                  icon: const Icon(Icons.undo),
                  label: Text('Retirar orçamento'.tr),
                ),
            ] else ...[
              const SizedBox(height: Spacing.sm),
              TextFormField(
                key: const Key('casa_orcamento_preco'),
                controller: _precoCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Preço fechado *'.tr,
                  suffixText: '€',
                  helperText: 'O que o cliente paga pelo trabalho todo.'.tr,
                ),
                validator: (v) => casaEurosParaCents(v ?? '') == null
                    ? 'Indica um preço válido (ex.: 45 ou 45,50).'.tr
                    : null,
              ),
              if (perfil != null) ...[
                const SizedBox(height: Spacing.xs),
                Text(
                  casaTextoComissao(perfil.comissaoPct, perfil.semComissaoAte),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12.5),
                ),
              ],
              const SizedBox(height: Spacing.md),
              TextFormField(
                key: const Key('casa_orcamento_inclui'),
                controller: _incluiCtrl,
                maxLines: 3,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: 'O que inclui *'.tr,
                  hintText: 'Ex.: montar o roupeiro de 3 portas e fixar à parede.'.tr,
                ),
                validator: (v) => (v ?? '').trim().length < 5
                    ? 'Diz o que está incluído no preço.'.tr
                    : null,
              ),
              const SizedBox(height: Spacing.sm),
              TextFormField(
                controller: _materiaisCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Materiais'.tr,
                  hintText: 'Ex.: buchas e parafusos; o sifão novo é do cliente.'.tr,
                ),
              ),
              SwitchListTile(
                value: _materiaisIncluidos,
                onChanged: (v) => setState(() => _materiaisIncluidos = v),
                title: Text('Os materiais estão incluídos no preço'.tr),
                activeThumbColor: AppColors.primary,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: Spacing.sm),
              TextFormField(
                controller: _prazoCtrl,
                decoration: InputDecoration(
                  labelText: 'Prazo'.tr,
                  hintText: 'Ex.: posso ir no dia marcado de manhã.'.tr,
                ),
              ),
              const SizedBox(height: Spacing.md),
              DropdownButtonFormField<int>(
                initialValue: _duracao,
                decoration: InputDecoration(labelText: 'Duração estimada'.tr),
                items: [
                  for (final d in kCasaDuracoes)
                    DropdownMenuItem<int>(
                        value: d, child: Text(casaDuracaoTexto(d))),
                ],
                onChanged: (v) => setState(() => _duracao = v),
              ),
              const SizedBox(height: Spacing.xl),
              BoraPrimaryButton(
                key: const Key('casa_orcamento_enviar'),
                label: 'Enviar orçamento'.tr,
                icon: Icons.send,
                loading: _aEnviar,
                onPressed: _enviar,
              ),
              const SizedBox(height: Spacing.sm),
              TextButton(
                onPressed: _aEnviar ? null : _recusar,
                child: Text('Não me interessa'.tr),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha(this.icone, this.texto);
  final IconData icone;
  final String texto;

  @override
  Widget build(BuildContext context) {
    if (texto.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.xs),
      child: Row(children: [
        Icon(icone, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: Spacing.xs),
        Expanded(
            child: Text(texto,
                style: const TextStyle(color: AppColors.textPrimary))),
      ]),
    );
  }
}
