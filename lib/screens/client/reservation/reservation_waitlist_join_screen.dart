import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../stores/reservation_store.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';

/// Reservas PRO F3.C — entrar na fila de espera de um restaurante.
/// Form: data, pessoas, janela horária opcional, notas.
/// Submit chama RPC client_join_waitlist via store.joinWaitlist.
class ReservationWaitlistJoinScreen extends StatefulWidget {
  const ReservationWaitlistJoinScreen({
    super.key,
    required this.restaurantId,
    required this.restaurantName,
    this.prefilledDate,
    this.prefilledPartySize,
  });

  final String restaurantId;
  final String restaurantName;
  final DateTime? prefilledDate;
  final int? prefilledPartySize;

  @override
  State<ReservationWaitlistJoinScreen> createState() =>
      _ReservationWaitlistJoinScreenState();
}

class _ReservationWaitlistJoinScreenState
    extends State<ReservationWaitlistJoinScreen> {
  late DateTime _selectedDate;
  late int _selectedPartySize;
  TimeOfDay? _timeStart;
  TimeOfDay? _timeEnd;
  final _notesCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.prefilledDate ??
        DateTime.now().add(const Duration(hours: 1));
    _selectedPartySize = widget.prefilledPartySize ?? 2;
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
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

  Future<void> _pickTimeStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _timeStart ?? const TimeOfDay(hour: 19, minute: 0),
    );
    if (picked != null && mounted) {
      setState(() => _timeStart = picked);
    }
  }

  Future<void> _pickTimeEnd() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _timeEnd ?? const TimeOfDay(hour: 21, minute: 0),
    );
    if (picked != null && mounted) {
      setState(() => _timeEnd = picked);
    }
  }

  Future<void> _showLargePartyDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Grupos grandes'),
        content: const Text(
          'Para grupos com mais de 12 pessoas, contacta o restaurante '
          'directamente.',
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

  bool _validateTimeWindow() {
    if (_timeStart == null || _timeEnd == null) return true;
    final startMin = _timeStart!.hour * 60 + _timeStart!.minute;
    final endMin = _timeEnd!.hour * 60 + _timeEnd!.minute;
    return endMin > startMin;
  }

  Future<void> _onSubmit() async {
    if (_submitting) return;
    if (!_validateTimeWindow()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A hora final tem de ser depois da inicial.'),
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await context.read<ReservationStore>().joinWaitlist(
            restaurantId: widget.restaurantId,
            people: _selectedPartySize,
            targetDate: _selectedDate,
            timeStart: _timeStart,
            timeEnd: _timeEnd,
            notes: _notesCtrl.text.trim().isEmpty
                ? null
                : _notesCtrl.text.trim(),
          );
      if (!mounted) return;
      final position = result['position'] as int? ?? 0;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            position > 0
                ? 'Estás na fila! Posição #$position.'
                : 'Estás na fila!',
          ),
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
      appBar: const BoraScreenAppBar(title: 'Entrar na fila de espera'),
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
                              'Lista de espera em ${widget.restaurantName}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Sem pré-pagamento. Esta opção é gratuita.',
                              style: TextStyle(
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
                      : const Icon(Icons.schedule),
                  label: const Text(
                    'Entrar na fila',
                    style: TextStyle(
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
            const _SectionLabel('Data'),
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
            const _SectionLabel('Pessoas'),
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
            const _SectionLabel('Janela horária (opcional)'),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'A que horas preferes? Se deixares vazio, ficas na fila '
                'para o dia todo.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTimeStart,
                    icon: const Icon(Icons.access_time, size: 16),
                    label: Text(
                      _timeStart != null ? _formatTimePt(_timeStart!) : 'Das',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTimeEnd,
                    icon: const Icon(Icons.access_time, size: 16),
                    label: Text(
                      _timeEnd != null ? _formatTimePt(_timeEnd!) : 'Às',
                    ),
                  ),
                ),
                if (_timeStart != null || _timeEnd != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: () => setState(() {
                      _timeStart = null;
                      _timeEnd = null;
                    }),
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Limpar janela',
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            const _SectionLabel('Notas (opcional)'),
            TextField(
              controller: _notesCtrl,
              maxLength: 300,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Algo que o restaurante deva saber...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExplainerCard() {
    return const Card(
      elevation: 0,
      color: AppColors.surface,
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Como funciona a fila de espera',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 8),
            _Bullet(text: 'O restaurante chama-te quando houver mesa.'),
            _Bullet(text: 'A tua posição na fila é mostrada na app.'),
            _Bullet(text: 'Podes sair da fila a qualquer momento.'),
            _Bullet(text: 'Sem pré-pagamento — esta opção é gratuita.'),
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
