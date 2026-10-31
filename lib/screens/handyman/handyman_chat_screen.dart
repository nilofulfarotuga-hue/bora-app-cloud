import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../l10n/tr.dart';
import '../../stores/handyman_store.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/bora/bora.dart';

/// CASA — mensagens com o cliente (`casa_mensagens` / `casa_enviar_mensagem`).
/// Só existe com `pode_contactar` (aceite e pago); o servidor recusa antes.
/// Relê de 6 em 6 segundos enquanto o ecrã está aberto.
class HandymanChatScreen extends StatefulWidget {
  const HandymanChatScreen({super.key, required this.pedidoId, this.titulo = ''});

  final String pedidoId;
  final String titulo;

  @override
  State<HandymanChatScreen> createState() => _HandymanChatScreenState();
}

class _HandymanChatScreenState extends State<HandymanChatScreen> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _msgs = const [];
  bool _carregou = false;
  String? _erro;
  bool _aEnviar = false;
  Timer? _relogio;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ler());
    _relogio = Timer.periodic(const Duration(seconds: 6), (_) => _ler());
  }

  @override
  void dispose() {
    _relogio?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _ler() async {
    if (!mounted) return;
    final store = context.read<HandymanStore>();
    try {
      final m = await store.mensagens(widget.pedidoId);
      if (!mounted) return;
      setState(() {
        _msgs = m;
        _carregou = true;
        _erro = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregou = true;
        _erro = casaErroTexto(e);
      });
    }
  }

  Future<void> _enviar() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty || _aEnviar) return;
    setState(() => _aEnviar = true);
    final store = context.read<HandymanStore>();
    final ok = await store.enviarMensagem(widget.pedidoId, t);
    if (!mounted) return;
    setState(() => _aEnviar = false);
    if (ok) {
      _ctrl.clear();
      await _ler();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(store.lastError ?? casaErroTexto(''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BoraScreenAppBar(
          title: widget.titulo.isEmpty ? 'Mensagens'.tr : widget.titulo),
      body: Column(
        children: [
          Expanded(
            child: !_carregou
                ? const Center(child: CircularProgressIndicator())
                : (_erro != null && _msgs.isEmpty)
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(Spacing.xl),
                          child: Text(_erro!, textAlign: TextAlign.center),
                        ),
                      )
                    : _msgs.isEmpty
                        ? Center(
                            child: Text('Ainda não há mensagens.'.tr,
                                style: const TextStyle(
                                    color: AppColors.textSecondary)))
                        : ListView.builder(
                            reverse: true,
                            padding: const EdgeInsets.all(Spacing.md),
                            itemCount: _msgs.length,
                            itemBuilder: (context, i) {
                              final m = _msgs[_msgs.length - 1 - i];
                              final meu =
                                  (m['sender_role'] ?? '').toString() == 'handyman';
                              final admin =
                                  (m['sender_role'] ?? '').toString() == 'admin';
                              return Align(
                                alignment: meu
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: Spacing.sm),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: Spacing.md, vertical: Spacing.sm),
                                  constraints: const BoxConstraints(maxWidth: 300),
                                  decoration: BoxDecoration(
                                    color: meu
                                        ? AppColors.primary
                                        : AppColors.surface2,
                                    borderRadius: BorderRadius.circular(Radii.lg),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (admin)
                                        Text('Equipa Bora'.tr,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.textSecondary)),
                                      Text(
                                        (m['message'] ?? '').toString(),
                                        style: TextStyle(
                                            color: meu
                                                ? Colors.white
                                                : AppColors.textPrimary),
                                      ),
                                      Text(
                                        dataHoraLisboa(m['created_at']),
                                        style: TextStyle(
                                            fontSize: 10.5,
                                            color: meu
                                                ? Colors.white70
                                                : AppColors.textSubtle),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.md, Spacing.xs, Spacing.md, Spacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Escreve uma mensagem'.tr,
                        counterText: '',
                      ),
                      onSubmitted: (_) => _enviar(),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  IconButton.filled(
                    onPressed: _aEnviar ? null : _enviar,
                    icon: _aEnviar
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send),
                    tooltip: 'Enviar'.tr,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
