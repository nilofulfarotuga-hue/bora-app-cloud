import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../stores/reservation_store.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';

import '../../../l10n/tr.dart';

/// Reservas PRO F3.C — pedir aviso "se vagar mesa".
/// Form: data, hora, pessoas, flexibilidade.
/// Submit chama RPC client_join_notify via store.joinNotify.
class ReservationNotifyJoinScreen extends StatefulWidget {
  const ReservationNotifyJoinScreen({
    super.key,
    required this.restaurantId,
    required this.restaurantName,
    this.prefilledDate,
    this.prefilledTime,
    this.prefilledPartySize,
  });

  final String restaurantId;
  final String restaurantName;
  final DateTime? prefilledDate;
  final TimeOfDay? prefilledTime;
  final int? prefilledPartySize;

  @override
  State<ReservationNotifyJoinScreen> createState() =>
      _ReservationNotifyJoinScreenState();
}

class _ReservationNotifyJoinScreenState
    extends State<ReservationNotifyJoinScreen> {
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  late int _selectedPartySize;
  int _flexibilityMinutes = 30;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.prefilledDate ??
        DateTime.now().add(const Duration(days: 1));
    _selectedTime = widget.prefilledTime ??
        const TimeOfDay(hour: 20, minute: 0);
    _selectedPartySize = widget.prefilledPartySize ?? 2;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isBefore(now) ? now : _selectedDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
      locale: const Locale('pt', 'PT'),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null && mounted) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _showLargePartyDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Grupos grandes'.tr),
        content: Text(
          'Para grupos com mais de 12 pessoas, contacta o restaurante directamente.'.tr,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _onSubmit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<ReservationStore>().joinNotify(
            restaurantId: widget.restaurantId,
            targetDate: _selectedDate,
            targetTime: _selectedTime,
            people: _selectedPartySize,
            flexibilityMinutes: _flexibilityMinutes,
          );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Aviso activado! Avisamos-te se vagar.'.tr),
          backgroundColor: AppColors.primary,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      messenger.showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(title: 'Avisar-me se vagar'.tr),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      elevation: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Notificação para {0}'.trArgs([widget.restaurantName]),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Avisamos-te se uma mesa ficar disponível.'.tr,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildInputsCard(),
                    const SizedBox(height: 12),
                    _buildExplainerCard(),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _onSubmit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.notifications_active),
                  label: Text(
                    'Activar aviso'.tr,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputsCard() {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionLabel('Data'.tr),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(_formatDatePt(_selectedDate)),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            _SectionLabel('Hora'.tr),
            OutlinedButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.access_time, size: 18),
              label: Text(_formatTimePt(_selectedTime)),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            _SectionLabel('Pessoas'.tr),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 1; i <= 12; i++)
                  ChoiceChip(
                    label: Text('$i'),
                    selected: _selectedPartySize == i,
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                      color: _selectedPartySize == i
                          ? Colors.white
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) =>
                        setState(() => _selectedPartySize = i),
                  ),
                ActionChip(
                  label: const Text('13+'),
                  onPressed: _showLargePartyDialog,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SectionLabel('Flexibilidade: {0} min'.trArgs([_flexibilityMinutes])),
            Slider(
              value: _flexibilityMinutes.toDouble(),
              min: 0,
              max: 180,
              divisions: 12,
              activeColor: AppColors.primary,
              label: '{0} min'.trArgs([_flexibilityMinutes]),
              onChanged: (v) =>
                  setState(() => _flexibilityMinutes = v.round()),
            ),
            Text(
              _flexibilityMinutes == 0
                  ? 'Apenas no horário exacto.'.tr
                  : 'Aceitas até $_flexibilityMinutes min antes ou depois.',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExplainerCard() {
    return Card(
      elevation: 0,
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Como funciona "Avisar-me se vagar"'.tr,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            _Bullet(text: 'Avisamos-te se uma mesa ficar disponível.'.tr),
            _Bullet(text: 'Tens 15 minutos para confirmar a reserva.'.tr),
            _Bullet(text: 'Sem pré-pagamento até confirmares.'.tr),
            _Bullet(text: 'Aviso expira 24h antes do horário escolhido.'.tr),
          ],
        ),
      ),
    );
  }

  static String _formatDatePt(DateTime d) {
    const weekdays = [
      'Segunda',
      'Terça',
      'Quarta',
      'Quinta',
      'Sexta',
      'Sábado',
      'Domingo',
    ];
    const months = [
      'Janeiro',
      'Fevereiro',
      'Março',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
    ];
    final wd = weekdays[(d.weekday - 1).clamp(0, 6)];
    final mo = months[(d.month - 1).clamp(0, 11)];
    return '$wd, ${d.day} de $mo';
  }

  static String _formatTimePt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
