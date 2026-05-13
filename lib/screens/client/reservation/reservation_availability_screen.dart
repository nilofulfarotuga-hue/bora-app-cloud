import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_theme.dart';
import '../../../stores/reservation_store.dart';
import 'reservation_checkout_screen.dart';
import 'reservation_notify_join_screen.dart';
import 'reservation_waitlist_join_screen.dart';

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

  // DIAG temporário (BUG #11) — remover após rollback pre-diag-2026-05-13
  String? _debugLastResponse;
  String? _debugLastError;

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
          const SnackBar(
            content: Text('Erro ao abrir calendário. Tenta de novo.'),
            duration: Duration(seconds: 3),
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
        title: const Text('Grupos grandes'),
        content: const Text(
          'Para grupos com mais de 12 pessoas, contacta o restaurante '
          'directamente para garantir disponibilidade.',
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
    setState(() {
      _searching = true;
      _availabilityResult = null;
      _debugLastResponse = null;
      _debugLastError = null;
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
      _debugLastResponse = result.toString();
      setState(() => _availabilityResult = result);
    } catch (e, st) {
      if (!mounted) return;
      final stackStr = st.toString().split('\n').take(5).join('\n');
      _debugLastError = '$e\n$stackStr';
      final msg = e.toString().replaceFirst('Exception: ', '');
      if (msg.contains('Não podes reservar')) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Bloqueado'),
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
      appBar: AppBar(
        title: Text('Reservar — ${widget.restaurantName}'),
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
                    backgroundColor: AppTheme.primary,
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
                  label: const Text(
                    'Procurar disponibilidade',
                    style: TextStyle(fontWeight: FontWeight.w700),
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
            const Text(
              'Data',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
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
            const Text(
              'Pessoas',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
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
                    selectedColor: AppTheme.primary,
                    labelStyle: TextStyle(
                      color: _selectedPartySize == i
                          ? Colors.white
                          : AppTheme.textPrimary,
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
            const Text(
              'Hora (opcional)',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
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
                          : 'Qualquer hora',
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
                    tooltip: 'Limpar hora',
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
              'Slots disponíveis (${slots.length})',
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
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(color: AppTheme.primary),
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
        ? 'Este restaurante pode não aceitar reservas a '
            '${dow == 6 ? "Sábado" : "Domingo"}'
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
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tenta outra data ou junta-te à fila.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary),
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
              label: const Text('Entrar fila de espera'),
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
              label: const Text('Avisar se vagar'),
            ),
            // DIAG temporário BUG #11 — remover após rollback pre-diag-2026-05-13
            if (_debugLastResponse != null || _debugLastError != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.yellow.shade100,
                  border: Border.all(color: Colors.orange),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🐛 DEBUG RESERVAS (temporário):',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                    const SizedBox(height: 4),
                    Text('Restaurant ID: ${widget.restaurantId}',
                        style: const TextStyle(fontSize: 10)),
                    Text('Date: ${_selectedDate.toIso8601String()}',
                        style: const TextStyle(fontSize: 10)),
                    Text('Party: $_selectedPartySize',
                        style: const TextStyle(fontSize: 10)),
                    Text(
                        'Time: ${_selectedTime?.format(context) ?? "null"}',
                        style: const TextStyle(fontSize: 10)),
                    const SizedBox(height: 8),
                    if (_debugLastError != null)
                      Text('❌ ERRO: $_debugLastError',
                          style: const TextStyle(
                              fontSize: 10, color: Colors.red)),
                    if (_debugLastResponse != null)
                      Text('✅ RESPOSTA: $_debugLastResponse',
                          style: const TextStyle(fontSize: 10)),
                  ],
                ),
              ),
            ],
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
        final t = item['time'] ?? item['slot'] ?? item['hhmm'];
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
