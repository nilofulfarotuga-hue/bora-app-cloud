import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../l10n/tr.dart';
import '../../../services/bloqueio_service.dart';
import '../../../stores/casa_store.dart';
import '../../../widgets/bora/bora.dart';
import '../../../widgets/bora_denunciar.dart';

/// CASA — chat do cliente com o profissional (31/10/2026).
///
/// Molde: CleaningChatScreen. Só se abre com `pode_contactar` (aceite e pago —
/// decisão 4 do Danilo); o servidor recusa ler ou escrever antes disso.
/// [telefone] (só vem com pode_contactar) liga o botão de LIGAR no topo.
class CasaChatScreen extends StatefulWidget {
  const CasaChatScreen({
    super.key,
    required this.pedidoId,
    required this.titulo,
    this.telefone,
  });

  final String pedidoId;
  final String titulo;
  final String? telefone;

  @override
  State<CasaChatScreen> createState() => _CasaChatScreenState();
}

class _CasaChatScreenState extends State<CasaChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _aEnviar = false;

  // Guardado no initState: ler o Provider dentro do dispose rebenta quando o
  // ecrã sai da árvore (mesmo defeito corrigido no chat da limpeza a 07/10).
  late final CasaStore _store;

  /// Rede de segurança do tempo real: relê de 15 em 15 s enquanto o chat
  /// está aberto (o canal pode cair com a app em fundo).
  Timer? _releitura;
  int _vistas = 0;

  static const _meuPapel = 'client';

  @override
  void initState() {
    super.initState();
    _store = context.read<CasaStore>();
    _store.ouvirMensagens(widget.pedidoId);
    _releitura = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _store.carregarMensagens(widget.pedidoId);
    });
  }

  @override
  void dispose() {
    _releitura?.cancel();
    _store.pararMensagens(widget.pedidoId);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final texto = _controller.text.trim();
    if (texto.isEmpty || _aEnviar) return;
    setState(() => _aEnviar = true);
    try {
      await _store.enviarMensagem(widget.pedidoId, texto);
      _controller.clear();
      _irAoFim();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Não foi possível enviar. Tenta de novo.'.tr)));
      }
    } finally {
      if (mounted) setState(() => _aEnviar = false);
    }
  }

  void _irAoFim() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _ligar() async {
    final telefone = widget.telefone;
    if (telefone == null || telefone.isEmpty) return;
    final uri = Uri.parse('tel:$telefone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CasaStore>();
    // Directriz 1.2 da App Store: quem bloqueia deixa de ver o outro lado.
    final refDoOutro = 'casa:${widget.pedidoId}:$_meuPapel';
    final bloqueado = BloqueioService.estaBloqueado(refDoOutro);
    final mensagens = store
        .mensagensDe(widget.pedidoId)
        .where((m) => !bloqueado || m.senderRole == _meuPapel)
        .toList();
    if (mensagens.length != _vistas) {
      _vistas = mensagens.length;
      _irAoFim();
    }
    final telefone = widget.telefone;

    return Scaffold(
      appBar: BoraScreenAppBar(
        title: widget.titulo,
        actions: [
          BotaoDenunciar(
            sobreQuem: widget.titulo,
            refDoOutro: refDoOutro,
            onMudou: () => setState(() {}),
          ),
          if (telefone != null && telefone.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.call),
              tooltip: 'Ligar'.tr,
              onPressed: _ligar,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: mensagens.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(Spacing.xl),
                      child: Text(
                        store.mensagensFalharam
                            ? 'Não foi possível carregar as mensagens. Verifica a ligação.'.tr
                            : 'Ainda sem mensagens. Combina aqui os pormenores do trabalho.'.tr,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textSubtle),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(Spacing.md),
                    itemCount: mensagens.length,
                    itemBuilder: (_, i) {
                      final m = mensagens[i];
                      final minha = m.senderRole == _meuPapel;
                      return Align(
                        alignment:
                            minha ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: Spacing.md, vertical: Spacing.sm),
                          constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.72),
                          decoration: BoxDecoration(
                            color: minha ? AppColors.primary : AppColors.surface,
                            borderRadius: BorderRadius.circular(Radii.md + 2),
                            border: minha
                                ? null
                                : Border.all(color: AppColors.divider),
                          ),
                          child: m.senderRole == 'admin'
                              // A equipa do Bora também escreve aqui (painel).
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('Bora',
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.primary)),
                                    Text(m.texto,
                                        style: const TextStyle(
                                            color: AppColors.textPrimary)),
                                  ],
                                )
                              : Text(
                                  m.texto,
                                  style: TextStyle(
                                      color: minha
                                          ? Colors.white
                                          : AppColors.textPrimary),
                                ),
                        ),
                      );
                    },
                  ),
          ),
          if (bloqueado)
            BarraBloqueado(
              refDoOutro: refDoOutro,
              onMudou: () => setState(() {}),
            )
          else
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(Spacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 2000,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _enviar(),
                        decoration: InputDecoration(
                          hintText: 'Escreve uma mensagem…'.tr,
                          counterText: '',
                          filled: true,
                          fillColor: AppColors.surface,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: Spacing.md, vertical: Spacing.sm),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(Radii.lg),
                            borderSide:
                                const BorderSide(color: AppColors.divider),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    IconButton.filled(
                      tooltip: 'Enviar'.tr,
                      onPressed: _aEnviar ? null : _enviar,
                      icon: const Icon(Icons.send),
                      style: IconButton.styleFrom(
                          backgroundColor: AppColors.primary),
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
