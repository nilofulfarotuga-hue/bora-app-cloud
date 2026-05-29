import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../models/order_model.dart';
import '../models/rating_model.dart';
import '../widgets/bora/bora_accent_button.dart';
import '../widgets/bora/bora_screen_app_bar.dart';
import '../widgets/tip_selector.dart';

/// Rating screen shown to the client after an order is delivered (BR §13).
///
/// Posts a new row to public.ratings with:
///   • stars (1-5)
///   • tags[] (quick picks from RatingTags)
///   • comment (optional)
///   • is_private = false (client→driver is public, BR §13.3)
///
/// This screen is OPTIONAL — the user can dismiss without rating.
class RatingScreen extends StatefulWidget {
  const RatingScreen({
    super.key,
    required this.order,
    required this.subjectType,
    required this.subjectId,
  });

  final OrderModel order;
  final RatingSubjectType subjectType;
  final String subjectId;

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  int _stars = 0;
  final _commentController = TextEditingController();
  final Set<String> _selectedTags = <String>{};
  bool _submitting = false;
  bool _isPrivate = false;
  int _tipCents = 0;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  bool get _canSubmit => _stars >= 1 && _stars <= 5 && !_submitting;

  List<String> get _suggestedTags {
    if (_stars == 0) return const <String>[];
    if (_stars >= 4) return RatingTags.positive;
    if (_stars <= 2) return RatingTags.negative;
    return [...RatingTags.positive, ...RatingTags.negative];
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) {
        setState(() => _submitting = false);
        messenger.showSnackBar(
          const SnackBar(content: Text('Sessão expirou.')),
        );
        return;
      }

      final isDriverSubject =
          widget.subjectType == RatingSubjectType.driver;
      // Sessão 6: server-side RPC valida order ownership + status='delivered'
      // + idempotência (UNIQUE INDEX parcial em order_id+subject_type+rater).
      await client.rpc('submit_rating', params: {
        'p_order_id': widget.order.id,
        'p_subject_type':
            widget.subjectType == RatingSubjectType.driver ? 'driver' : 'partner',
        'p_subject_id': widget.subjectId,
        'p_stars': _stars,
        'p_comment': _commentController.text.trim().isEmpty
            ? null
            : _commentController.text.trim(),
        'p_tags': _selectedTags.toList(),
        'p_is_private': _isPrivate,
      });

      // Persist tip (BR §4.5) — best-effort, failure does not invalidate rating.
      if (_tipCents > 0 && isDriverSubject) {
        try {
          await client.from('orders').update({
            'tip_amount_cents': _tipCents,
            'tip_added_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', widget.order.id);
        } catch (e) {
          // ignore; rating already saved
        }
      }

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Obrigado pela tua avaliação!')),
      );
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Erro a gravar avaliação: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tagsToShow = _suggestedTags;
    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'Avaliar'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Como correu?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final filled = i < _stars;
                  return IconButton(
                    iconSize: 40,
                    onPressed: _submitting
                        ? null
                        : () => setState(() => _stars = i + 1),
                    icon: Icon(
                      filled ? Icons.star : Icons.star_border,
                      color: AppColors.warning,
                    ),
                  );
                }),
              ),
              if (tagsToShow.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Etiquetas rápidas',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: tagsToShow.map((tag) {
                    final selected = _selectedTags.contains(tag);
                    return FilterChip(
                      label: Text(tag),
                      selected: selected,
                      onSelected: _submitting
                          ? null
                          : (v) => setState(() {
                                if (v) {
                                  _selectedTags.add(tag);
                                } else {
                                  _selectedTags.remove(tag);
                                }
                              }),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _commentController,
                maxLines: 4,
                enabled: !_submitting,
                decoration: const InputDecoration(
                  labelText: 'Comentário (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              // BUG 9 — esconder gorjeta em CASH. Em CASH não há como cobrar
              // gorjeta extra (cliente já entregou dinheiro exacto no balcão).
              if (widget.subjectType == RatingSubjectType.driver &&
                  widget.order.paymentMethod != PaymentMethod.cash) ...[
                const SizedBox(height: 20),
                TipSelector(
                  initialCents: 0,
                  enabled: !_submitting,
                  onChanged: (cents) => _tipCents = cents,
                ),
              ],
              const SizedBox(height: 12),
              SwitchListTile(
                value: _isPrivate,
                onChanged: _submitting ? null : (v) => setState(() => _isPrivate = v),
                title: const Text(
                  'Avaliação privada',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Apenas a equipa Bora vê. Não aparece no perfil público.',
                  style: TextStyle(fontSize: 12),
                ),
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppColors.primary,
              ),
              const SizedBox(height: 12),
              BoraAccentButton(
                label: 'Enviar avaliação',
                loading: _submitting,
                onPressed: _canSubmit ? _submit : null,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _submitting ? null : () => Navigator.pop(context),
                child: const Text('Saltar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
