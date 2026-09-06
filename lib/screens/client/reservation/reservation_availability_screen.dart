import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../stores/reservation_store.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';
import 'reservation_checkout_screen.dart';
import 'reservation_notify_join_screen.dart';
import 'reservation_waitlist_join_screen.dart';

import '../../../l10n/tr.dart';

/// Reservas PRO F3.B — busca slots disponíveis no restaurante.
/// Date picker (locale pt_PT), party size, time picker opcional.
/// Empty state mostra placeholders F3.C (waitlist + notify).
class ReservationAvailabilityScreen extends StatefulWidget {
  const ReservationAvailabilityScreen({
    super.key,
    required this.restaurantId,
    required this.restaurantName,
    this.restaurantPhotoUrl,
  });

  final String restaurantId;
  final String restaurantName;
  final String? restaurantPhotoUrl;

  @override
  State<ReservationAvailabilityScreen> createState() =>
      _ReservationAvailabilityScreenState();
}

class _ReservationAvailabilityScreenState
    extends State<ReservationAvailabilityScreen> {
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  int _selectedPartySize = 2;
  TimeOfDay? _selectedTime;
  Map<String, dynamic>? _availabilityResult;
  bool _searching = false;

  Future<void> _pickDate() async {
    // BUG #12 (2026-05-13) — try/catch defensivo. Causa principal corrigida
    // em main.dart (flutter_localizations delegates). Este catch garante que
    // qualquer falha futura mostra snackbar em vez de tela em branco.
    try {
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
    } catch (e, st) {
      debugPrint('[ReservationAvailability] _pickDate error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao abrir calendário. Tenta de novo.'.tr),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? const TimeOfDay(hour: 20, minute: 0),
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
          'Para grupos com mais de 12 pessoas, contacta o restaurante directamente para garantir disponibilidade.'.tr,
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

  Future<void> _searchAvailability() async {
    if (_selectedTime != null) {
      final picked = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );
      if (picked.isBefore(DateTime.now())) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('A hora escolhida já passou. Escolhe outra.'.tr),
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }
    }
    setState(() {
      _searching = true;
      _availabilityResult = null;
    });
    try {
      final result =
          await context.read<ReservationStore>().searchAvailability(
                restaurantId: widget.restaurantId,
                date: _selectedDate,
                partySize: _selectedPartySize,
                targetTime: _selectedTime,
              );
      if (!mounted) return;
      setState(() => _availabilityResult = result);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      if (msg.contains('Não podes reservar')) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Bloqueado'.tr),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _openCheckout(DateTime slotDateTime) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReservationCheckoutScreen(
          restaurantId: widget.restaurantId,
          restaurantName: widget.restaurantName,
          restaurantPhotoUrl: widget.restaurantPhotoUrl,
          selectedDateTime: slotDateTime,
          partySize: _selectedPartySize,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Reservar — {0}'.trArgs([widget.restaurantName]),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildInputsCard(),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _searching ? null : _searchAvailability,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: _searching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.search),
                  label: Text(
                    'Procurar disponibilidade'.tr,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (_searching)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_availabilityResult != null)
                _buildResultsCard(_availabilityResult!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputsCard() {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Data ──
            Text(
              'Data'.tr,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(_formatDatePt(_selectedDate)),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            // ── Pessoas ──
            Text(
              'Pessoas'.tr,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
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
                    onSelected: (_) => setState(() => _selectedPartySize = i),
                  ),
                ActionChip(
                  label: const Text('13+'),
                  onPressed: _showLargePartyDialog,
                ),
              ],
            ),
            const SizedBox(height: 16),
            // ── Hora (opcional) ──
            Text(
              'Hora (opcional)'.tr,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.access_time, size: 18),
                    label: Text(
                      _selectedTime != null
                          ? _formatTimePt(_selectedTime!)
                          : 'Qualquer hora'.tr,
                    ),
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
                if (_selectedTime != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => setState(() => _selectedTime = null),
                    icon: const Icon(Icons.close),
                    tooltip: 'Limpar hora'.tr,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsCard(Map<String, dynamic> result) {
    final slots = _extractSlots(result);
    if (slots.isEmpty) {
      return _buildEmptyState();
    }
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Slots disponíveis ({0})'.trArgs([slots.length]),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final slot in slots)
                  OutlinedButton(
                    onPressed: () => _openCheckout(slot),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    child: Text(
                      _formatTimePt(TimeOfDay.fromDateTime(slot)),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    // BUG #11 Fase 1 (2026-05-13) — mensagem differenciada quando data
    // é fim-de-semana (sem pacing rules activas neste restaurante) vs
    // semana cheia (slots existem mas estão cheios/passados). DateTime
    // .weekday: 6=Sáb, 7=Dom. PostgreSQL EXTRACT(DOW): 0=Dom..6=Sáb.
    final dow = _selectedDate.weekday;
    final isWeekend = dow == 6 || dow == 7;
    final title = isWeekend
        ? 'Este restaurante pode não aceitar reservas a {0}'.trArgs([dow == 6 ? "Sábado" : "Domingo"])
        : 'Sem disponibilidade nesta data';
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.event_busy, size: 40, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tenta outra data ou junta-te à fila.'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReservationWaitlistJoinScreen(
                    restaurantId: widget.restaurantId,
                    restaurantName: widget.restaurantName,
                    prefilledDate: _selectedDate,
                    prefilledPartySize: _selectedPartySize,
                  ),
                ),
              ),
              icon: const Icon(Icons.schedule),
              label: Text('Entrar fila de espera'.tr),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReservationNotifyJoinScreen(
                    restaurantId: widget.restaurantId,
                    restaurantName: widget.restaurantName,
                    prefilledDate: _selectedDate,
                    prefilledTime: _selectedTime,
                    prefilledPartySize: _selectedPartySize,
                  ),
                ),
              ),
              icon: const Icon(Icons.notifications_active_outlined),
              label: Text('Avisar se vagar'.tr),
            ),
          ],
        ),
      ),
    );
  }

  /// Extrai slots da resposta da RPC client_search_availability.
  /// Defensivo: tenta múltiplas chaves possíveis (`slots`, `available_slots`)
  /// e formatos (HH:MM, ISO timestamp, objecto com `time`).
  List<DateTime> _extractSlots(Map<String, dynamic> result) {
    final raw = result['slots'] ?? result['available_slots'];
    if (raw is! List) return const [];
    final out = <DateTime>[];
    for (final item in raw) {
      DateTime? dt;
      if (item is String) {
        dt = _parseSlot(item);
      } else if (item is Map) {
        // BUG #11 (2026-05-13) — RPC client_search_availability devolve
        // slots como objectos com key `slot_time` (ISO timestamp). Os outros
        // fallbacks ficam para compatibilidade caso a RPC mude o shape.
        final t = item['slot_time'] ??
            item['time'] ??
            item['slot'] ??
            item['hhmm'];
        if (t is String) dt = _parseSlot(t);
      }
      if (dt != null) out.add(dt);
    }
    return out;
  }

  DateTime? _parseSlot(String raw) {
    // ISO timestamp.
    final iso = DateTime.tryParse(raw);
    if (iso != null) return iso.toLocal();
    // HH:MM ou HH:MM:SS.
    final parts = raw.split(':');
    if (parts.length >= 2) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) {
        return DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
          h,
          m,
        );
      }
    }
    return null;
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
