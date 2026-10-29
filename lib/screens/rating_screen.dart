import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../models/order_model.dart';
import '../models/rating_model.dart';
import '../services/foto_avaliacao_service.dart';
import '../services/interruptores_app.dart';
import '../services/tip_service.dart';
import '../utils/safe_image_picker.dart';
import '../widgets/bora/bora_accent_button.dart';
import '../widgets/bora/bora_screen_app_bar.dart';
import '../widgets/tip_selector.dart';

import '../l10n/tr.dart';

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

  /// Gorjeta ligada no servidor (`tips_enabled`)? Até sabermos, não se mostra.
  bool _gorjetaLigada = false;

  /// Foto do prato (adendo 4 · item 7): interruptor `feature_avaliacao_com_foto`,
  /// só ao avaliar a loja. Sem prémio nenhum por enviar foto.
  bool _fotoLigada = false;
  Uint8List? _fotoBytes;

  bool get _avaliaLoja =>
      widget.subjectType == RatingSubjectType.partner ||
      widget.subjectType == RatingSubjectType.restaurant;

  @override
  void initState() {
    super.initState();
    TipService.ligada().then((v) {
      if (mounted) setState(() => _gorjetaLigada = v);
    });
    InterruptoresApp.instance
        .ligado(InterruptoresApp.avaliacaoComFoto)
        .then((v) {
      if (mounted && v != _fotoLigada) setState(() => _fotoLigada = v);
    });
  }

  Future<void> _escolherFoto(ImageSource origem) async {
    try {
      final f = await SafeImagePicker.pickImage(
        source: origem,
        imageQuality: 80,
        maxWidth: 1400,
      );
      if (f == null) return;
      final bytes = await f.readAsBytes();
      if (mounted) setState(() => _fotoBytes = bytes);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir a foto.'.tr)),
      );
    }
  }

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
          SnackBar(content: Text('Sessão expirou.'.tr)),
        );
        return;
      }

      final isDriverSubject =
          widget.subjectType == RatingSubjectType.driver;
      // Sessão 6: server-side RPC valida order ownership + status='delivered'
      // + idempotência (UNIQUE INDEX parcial em order_id+subject_type+rater).
      final resposta = await client.rpc('submit_rating', params: {
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

      // Foto do prato (adendo 4 · item 7): depois de a avaliação estar
      // gravada. Se a foto falhar, a avaliação fica e avisa-se.
      String? avisoFoto;
      final fotoParaEnviar = _fotoBytes;
      if (fotoParaEnviar != null && _fotoLigada && _avaliaLoja) {
        final ratingId = FotoAvaliacaoService.idDaAvaliacao(resposta);
        final ok = ratingId != null &&
            await FotoAvaliacaoService.enviar(
              orderId: widget.order.id,
              ratingId: ratingId,
              bytes: fotoParaEnviar,
            );
        if (!ok) {
          avisoFoto = 'Avaliação gravada, mas a foto não seguiu.'.tr;
        }
      }

      // Gorjeta (missão 03/10 · bloco 3): até 04/10 aqui só se escrevia um
      // número no pedido, sem cobrar nada — e nunca ficou nenhuma gravada.
      // Agora é cobrada à parte (charge-tip, 100% para o estafeta). A
      // avaliação já está gravada; a gorjeta falhar não a desfaz.
      String? avisoGorjeta;
      if (_tipCents > 0 && isDriverSubject && _gorjetaLigada) {
        final r = await TipService.cobrar(
          target: 'order',
          id: widget.order.id,
          cents: _tipCents,
          moment: 'after',
        );
        avisoGorjeta = r.ok ? null : 'Avaliação gravada. ${r.mensagem}';
      }

      if (!mounted) return;
      messenger.showSnackBar(
        avisoGorjeta != null || avisoFoto != null
            ? SnackBar(content: Text(avisoGorjeta ?? avisoFoto!))
            : SnackBar(content: Text('Obrigado pela tua avaliação!'.tr)),
      );
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Erro a gravar avaliação: {0}'.trArgs([e]))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tagsToShow = _suggestedTags;
    return Scaffold(
      appBar: BoraScreenAppBar(title: 'Avaliar'.tr),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Como correu?'.tr,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
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
                Text('Etiquetas rápidas'.tr,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
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
                decoration: InputDecoration(
                  labelText: 'Comentário (opcional)'.tr,
                  border: const OutlineInputBorder(),
                ),
              ),
              // Foto do prato (opcional).
              if (_fotoLigada && _avaliaLoja) ...[
                const SizedBox(height: 16),
                _FotoDoPrato(
                  bytes: _fotoBytes,
                  desativada: _submitting,
                  aoEscolher: _escolherFoto,
                  aoRemover: () => setState(() => _fotoBytes = null),
                ),
              ],
              // BUG 9 — esconder gorjeta em CASH. Em CASH não há como cobrar
              // gorjeta extra (cliente já entregou dinheiro exacto no balcão).
              if (_gorjetaLigada &&
                  widget.subjectType == RatingSubjectType.driver &&
                  widget.order.paymentMethod != PaymentMethod.cash &&
                  widget.order.tipCents == 0) ...[
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
                title: Text(
                  'Avaliação privada'.tr,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Apenas a equipa Bora vê. Não aparece no perfil público.'.tr,
                  style: const TextStyle(fontSize: 12),
                ),
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppColors.primary,
              ),
              const SizedBox(height: 12),
              BoraAccentButton(
                label: 'Enviar avaliação'.tr,
                loading: _submitting,
                onPressed: _canSubmit ? _submit : null,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _submitting ? null : () => Navigator.pop(context),
                child: Text('Saltar'.tr),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Foto do prato (opcional)": tirar ou escolher, ver e tirar. Sem prémio.
class _FotoDoPrato extends StatelessWidget {
  const _FotoDoPrato({
    required this.bytes,
    required this.desativada,
    required this.aoEscolher,
    required this.aoRemover,
  });

  final Uint8List? bytes;
  final bool desativada;
  final void Function(ImageSource origem) aoEscolher;
  final VoidCallback aoRemover;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('avaliacao_foto_do_prato'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Foto do prato (opcional)'.tr,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (bytes != null)
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(bytes!,
                    height: 160, width: double.infinity, fit: BoxFit.cover),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton.filled(
                  key: const Key('avaliacao_foto_remover'),
                  tooltip: 'Tirar a foto'.tr,
                  onPressed: desativada ? null : aoRemover,
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('avaliacao_foto_camara'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed:
                      desativada ? null : () => aoEscolher(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text('Tirar foto'.tr),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('avaliacao_foto_galeria'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed:
                      desativada ? null : () => aoEscolher(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text('Galeria'.tr),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
