import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../l10n/tr.dart';
import '../../../models/cleaning_models.dart';
import '../../../models/cleaning_plan_models.dart';
import '../../../services/payment_service.dart';
import '../../../services/stripe_contas.dart';
import '../../../stores/cleaning_plan_store.dart';
import '../../../utils/hora_lisboa.dart';
import '../../../widgets/bora/bora.dart';
import 'cleaning_plan_wizard_screen.dart';

/// "O MEU PLANO" de limpeza (missão limpeza-planos-empresas-2026-11-28, Bloco C).
///
/// Próxima limpeza, profissional fixa, preço por hora, total do mês, histórico das cobranças
/// com recibo, Saltar uma limpeza, Mudar dia/hora (a partir da próxima), Mudar horas, Trocar
/// cartão e Cancelar o plano em 2 toques, sem taxa. Tudo decide-se no servidor.
class CleaningPlanScreen extends StatefulWidget {
  const CleaningPlanScreen({super.key, this.storeOverride});

  @visibleForTesting
  final CleaningPlanStore? storeOverride;

  @override
  State<CleaningPlanScreen> createState() => _CleaningPlanScreenState();
}

class _CleaningPlanScreenState extends State<CleaningPlanScreen> {
  late final CleaningPlanStore _store = widget.storeOverride ?? CleaningPlanStore();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
    WidgetsBinding.instance.addPostFrameCallback((_) => _store.loadMine());
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _correr(Future<bool> Function() acao, String okMsg) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await acao();
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(ok ? okMsg : (_store.erro ?? 'Não foi possível concluir.'.tr));
  }

  Future<void> _saltar(CleaningPlan p, CleaningPlanVisit v) async {
    final sim = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Saltar esta limpeza?'.tr),
        content: Text('A limpeza de {0} não se faz e não é cobrada. As outras continuam.'.trArgs([_quando(v.scheduledAt)])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Não'.tr)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Saltar'.tr)),
        ],
      ),
    );
    if (sim == true) await _correr(() => _store.skip(p.id, v.date), 'Limpeza saltada.'.tr);
  }

  Future<void> _mudarDiaHora(CleaningPlan p) async {
    final (min, max) = CleaningPlanLabels.diasPorSemana(p.frequency);
    final dias = {...p.daysOfWeek};
    final partes = p.horaCurta.split(':');
    var hora = TimeOfDay(hour: int.tryParse(partes.first) ?? 10, minute: int.tryParse(partes.length > 1 ? partes[1] : '0') ?? 0);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Mudar dia e hora'.tr),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Vale a partir da próxima limpeza (as das próximas 24 h ficam como estão).'.tr,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: Spacing.sm),
            Wrap(spacing: 4, children: [
              for (final d in CleaningPlanLabels.diasCurtos.entries)
                FilterChip(
                  label: Text(d.value.tr),
                  selected: dias.contains(d.key),
                  onSelected: (sel) => setD(() {
                    if (sel) {
                      if (max == 1) dias.clear();
                      if (dias.length < max) dias.add(d.key);
                    } else {
                      dias.remove(d.key);
                    }
                  }),
                ),
            ]),
            TextButton.icon(
              icon: const Icon(Icons.schedule),
              label: Text('Hora: {0}'.trArgs(['${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}'])),
              onPressed: () async {
                final t = await showTimePicker(context: ctx, initialTime: hora);
                if (t != null) setD(() => hora = t);
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancelar'.tr)),
            TextButton(
              onPressed: dias.length < min || dias.length > max ? null : () => Navigator.pop(ctx, true),
              child: Text('Guardar'.tr),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final hh = '${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}';
    await _correr(() => _store.changeSchedule(p.id, (dias.toList()..sort()), hh), 'Horário mudado.'.tr);
  }

  Future<void> _mudarHoras(CleaningPlan p) async {
    final minimo = p.isEmpresa ? 1 : 2;
    var horas = p.hours;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Horas por limpeza'.tr),
          content: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(onPressed: horas > minimo ? () => setD(() => horas--) : null, icon: const Icon(Icons.remove)),
            Text('$horas h', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            IconButton(onPressed: horas < 10 ? () => setD(() => horas++) : null, icon: const Icon(Icons.add)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancelar'.tr)),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Guardar'.tr)),
          ],
        ),
      ),
    );
    if (ok == true && horas != p.hours) {
      await _correr(() => _store.changeHours(p.id, horas), 'Horas mudadas. O preço por hora é o mesmo.'.tr);
    }
  }

  Future<void> _trocarCartao(CleaningPlan p) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await guardarCartaoDoPlano(context, _store, p.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) _snack('Cartão guardado.'.tr);
  }

  /// Cancelar em 2 toques: o botão e a confirmação, com a frase clara.
  Future<void> _cancelar(CleaningPlan p) async {
    final sim = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancelar o plano?'.tr),
        content: Text(
          'O plano acaba hoje. As limpezas já pagas que ainda não foram feitas voltam para a tua carteira. Não há taxa. Se a limpeza das próximas 24 h já tiver profissional confirmada, essa mantém-se.'.tr,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Manter o plano'.tr)),
          TextButton(
            key: const Key('plano-cancelar-confirmar'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cancelar o plano'.tr, style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (sim == true) await _correr(() => _store.cancel(p.id), 'Plano cancelado.'.tr);
  }

  /// O banco pediu para confirmar uma cobrança (3D Secure).
  Future<void> _confirmarPagamento(CleaningPlan p) async {
    final ch = p.charges.where((c) => c.needsAction).firstOrNull;
    if (ch == null || _busy) return;
    setState(() => _busy = true);
    try {
      final s = await _store.actionSecret(ch.id);
      if (s == null) {
        _snack(_store.erro ?? 'Não há pagamento por confirmar.'.tr);
        return;
      }
      final ok = await PaymentService().confirmSavedCardPayment(
        clientSecret: s['clientSecret'] as String,
        requiresAction: true,
        publishableKey: StripeContas.chaveDaResposta(s),
      );
      final estado = await _store.confirmAction(ch.id);
      if (!mounted) return;
      _snack(ok && estado == 'succeeded' ? 'Pagamento confirmado.'.tr : 'O pagamento não ficou confirmado. Podes trocar o cartão.'.tr);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _quando(DateTime utc) {
    final l = horaLisboa(utc);
    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')} às ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final p = _store.current;
    return Scaffold(
      appBar: BoraScreenAppBar(title: 'O meu plano'.tr),
      body: _store.loading && _store.plans.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : p == null
              ? _SemPlano(onCasa: () => _abrir('casa'), onEmpresa: () => _abrir('empresa'))
              : RefreshIndicator(
                  onRefresh: _store.loadMine,
                  child: ListView(
                    padding: const EdgeInsets.all(Spacing.lg),
                    children: [
                      if (p.status == 'pending_card') _AvisoCartao(onTap: () => _trocarCartao(p)),
                      if (p.charges.any((c) => c.needsAction))
                        _Aviso(
                          key: const Key('plano-aviso-confirmar'),
                          cor: AppColors.accent,
                          texto: 'O teu banco pede para confirmares um pagamento.'.tr,
                          botao: 'Confirmar pagamento'.tr,
                          onTap: () => _confirmarPagamento(p),
                        )
                      else if (p.charges.any((c) => c.status == 'failed'))
                        _Aviso(
                          cor: AppColors.error,
                          texto: 'Um pagamento não passou. Troca o cartão para não perderes a limpeza.'.tr,
                          botao: 'Trocar cartão'.tr,
                          onTap: () => _trocarCartao(p),
                        ),
                      _Cabecalho(plano: p),
                      const SizedBox(height: Spacing.lg),
                      Text('Próximas limpezas'.tr, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: Spacing.sm),
                      if (p.nextVisits.isEmpty)
                        Text('As próximas limpezas aparecem aqui logo que o plano comece.'.tr,
                            style: const TextStyle(color: AppColors.textSecondary)),
                      for (final v in p.nextVisits)
                        Card(
                          child: ListTile(
                            leading: Icon(v.confirmed ? Icons.check_circle : Icons.hourglass_top,
                                color: v.confirmed ? AppColors.primary : AppColors.warning),
                            title: Text(_quando(v.scheduledAt)),
                            subtitle: Text([
                              v.confirmed ? (v.cleanerName ?? 'Profissional confirmada'.tr) : 'À procura de profissional'.tr,
                              v.paid ? 'Pago'.tr : 'Cobramos 24 h antes'.tr,
                              CleaningLabels.euro(v.totalCents),
                            ].join(' · ')),
                            trailing: v.canSkip && p.isActive
                                ? TextButton(onPressed: _busy ? null : () => _saltar(p, v), child: Text('Saltar'.tr))
                                : null,
                          ),
                        ),
                      const SizedBox(height: Spacing.lg),
                      if (p.isActive) ...[
                        Wrap(spacing: Spacing.sm, runSpacing: Spacing.sm, children: [
                          if (p.frequency != 'once')
                            OutlinedButton.icon(
                              key: const Key('plano-mudar-dia'),
                              onPressed: _busy ? null : () => _mudarDiaHora(p),
                              icon: const Icon(Icons.event_repeat),
                              label: Text('Mudar dia/hora'.tr),
                            ),
                          OutlinedButton.icon(
                            key: const Key('plano-mudar-horas'),
                            onPressed: _busy ? null : () => _mudarHoras(p),
                            icon: const Icon(Icons.timelapse),
                            label: Text('Mudar horas'.tr),
                          ),
                          OutlinedButton.icon(
                            key: const Key('plano-trocar-cartao'),
                            onPressed: _busy ? null : () => _trocarCartao(p),
                            icon: const Icon(Icons.credit_card),
                            label: Text('Trocar cartão'.tr),
                          ),
                        ]),
                        const SizedBox(height: Spacing.lg),
                      ],
                      Text('Cobranças'.tr, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: Spacing.sm),
                      if (p.charges.isEmpty)
                        Text('Ainda não houve cobranças.'.tr, style: const TextStyle(color: AppColors.textSecondary)),
                      for (final c in p.charges)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            c.status == 'succeeded' ? Icons.receipt_long : (c.failed ? Icons.error_outline : Icons.schedule),
                            color: c.status == 'succeeded' ? AppColors.primary : (c.failed ? AppColors.error : AppColors.textSecondary),
                          ),
                          title: Text('${CleaningLabels.euro(c.amountCents)} · ${c.kind == 'month' ? 'Mês'.tr : 'Limpeza'.tr}'),
                          subtitle: Text([
                            c.statusLabel.tr,
                            if (c.paidAt != null) _quando(c.paidAt!),
                            if (c.cardLast4 != null) '•••• ${c.cardLast4}',
                          ].join(' · ')),
                          trailing: c.receiptUrl == null
                              ? null
                              : TextButton(
                                  onPressed: () => launchUrl(Uri.parse(c.receiptUrl!), mode: LaunchMode.externalApplication),
                                  child: Text('Recibo'.tr),
                                ),
                        ),
                      const SizedBox(height: Spacing.xl),
                      if (p.isOpen)
                        Center(
                          child: TextButton(
                            key: const Key('plano-cancelar'),
                            onPressed: _busy ? null : () => _cancelar(p),
                            child: Text('Cancelar o plano'.tr, style: const TextStyle(color: AppColors.error)),
                          ),
                        ),
                      const SizedBox(height: Spacing.xl),
                    ],
                  ),
                ),
    );
  }

  void _abrir(String segmento) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => CleaningPlanWizardScreen(segment: segmento)))
        .then((_) => _store.loadMine());
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.plano});
  final CleaningPlan plano;

  @override
  Widget build(BuildContext context) {
    final p = plano;
    final estado = switch (p.status) {
      'active' => 'Ativo'.tr,
      'paused' => 'Em pausa'.tr,
      'pending_card' => 'À espera do cartão'.tr,
      'cancelled' => 'Cancelado'.tr,
      _ => p.status,
    };
    return Container(
      key: const Key('plano-cabecalho'),
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(color: AppColors.primaryWash, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              p.isEmpresa ? '${'Bora Empresas'.tr}${p.companyName != null ? ' · ${p.companyName}' : ''}' : 'Plano de limpeza'.tr,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ),
          Chip(label: Text(estado), backgroundColor: Colors.white),
        ]),
        Text('${p.label.tr} · ${CleaningPlanLabels.dias(p.daysOfWeek)} · ${p.horaCurta} · ${p.hours} h'
            '${p.teamSize > 1 ? ' · ${p.teamSize} ${'profissionais'.tr}' : ''}'),
        const SizedBox(height: Spacing.sm),
        Text('{0} por limpeza · {1}'.trArgs([CleaningLabels.euro(p.totalPerVisitCents), CleaningPlanLabels.euroHora(p.clientCentsPerHour)]),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.primary)),
        if (p.frequency != 'once')
          Text('≈ {0} por mês · pago este mês: {1}'.trArgs([CleaningLabels.euro(p.approxMonthCents), CleaningLabels.euro(p.monthPaidCents)])),
        const SizedBox(height: Spacing.sm),
        Text(p.cleanerName != null
            ? 'A tua profissional: {0}. Se faltar, outra vem no lugar dela.'.trArgs([p.cleanerName!])
            : 'A profissional que aceitar a primeira limpeza fica a tua profissional fixa.'.tr),
        Text(p.cardLast4 != null
            ? 'Cartão {0} •••• {1} · {2}'.trArgs([p.cardBrand ?? '', p.cardLast4!, p.billingMode == 'monthly' ? 'O mês de uma vez'.tr : 'A cada limpeza (24 h antes)'.tr])
            : 'Sem cartão guardado.'.tr,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      ]),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({super.key, required this.cor, required this.texto, required this.botao, required this.onTap});
  final Color cor;
  final String texto;
  final String botao;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: Spacing.md),
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.10),
          border: Border.all(color: cor.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Expanded(child: Text(texto)),
          TextButton(onPressed: onTap, child: Text(botao)),
        ]),
      );
}

class _AvisoCartao extends StatelessWidget {
  const _AvisoCartao({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => _Aviso(
        cor: AppColors.accent,
        texto: 'Falta guardar o cartão para o plano começar. Não cobramos nada agora.'.tr,
        botao: 'Juntar cartão'.tr,
        onTap: onTap,
      );
}

class _SemPlano extends StatelessWidget {
  const _SemPlano({required this.onCasa, required this.onEmpresa});
  final VoidCallback onCasa;
  final VoidCallback onEmpresa;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.cleaning_services, size: 56, color: AppColors.primary),
          const SizedBox(height: Spacing.md),
          Text('Ainda não tens um plano de limpeza.'.tr, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: Spacing.lg),
          BoraPrimaryButton(label: 'Criar plano para a casa'.tr, onPressed: onCasa),
          const SizedBox(height: Spacing.sm),
          OutlinedButton(onPressed: onEmpresa, child: Text('Limpeza para empresas'.tr)),
        ]),
      );
}
