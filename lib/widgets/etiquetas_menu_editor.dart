import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../models/etiquetas_dieta.dart';
import '../services/interruptores_app.dart';

/// O que a Edge Function `etiquetas-menu-ia` respondeu, em palavras que o
/// parceiro lê. Função pura (testada sem rede).
({List<String>? etiquetas, String mensagem}) interpretarRespostaDaIa(Object? r) {
  if (r is! Map) {
    return (etiquetas: null, mensagem: 'Não foi possível pedir a sugestão. Tenta outra vez.');
  }
  if (r['ok'] == true) {
    final lista = r['resultados'];
    if (lista is List && lista.isNotEmpty && lista.first is Map) {
      final primeiro = lista.first as Map;
      if (primeiro['saltado'] == 'sem_descricao') {
        return (
          etiquetas: null,
          mensagem: 'O prato precisa de uma descrição guardada para a IA sugerir.',
        );
      }
      if (primeiro['saltado'] == 'escolhido_pelo_parceiro') {
        return (
          etiquetas: null,
          mensagem: 'Já escolheste as etiquetas deste prato. A IA não as muda.',
        );
      }
      if (primeiro['erro'] != null) {
        return (etiquetas: null, mensagem: 'A IA não respondeu. Tenta outra vez daqui a pouco.');
      }
      return (
        etiquetas: etiquetasDeLinha(primeiro['tags']),
        mensagem: 'Sugerido pela IA a partir da descrição. Confirma ou corrige.',
      );
    }
    return (etiquetas: null, mensagem: 'A IA não tem nada para sugerir.');
  }
  switch (r['reason']) {
    case 'desligado':
      return (etiquetas: null, mensagem: 'A sugestão por IA está desligada.');
    case 'gemini_nao_configurado':
      return (etiquetas: null, mensagem: 'A IA ainda não está configurada.');
  }
  return (etiquetas: null, mensagem: 'Não foi possível pedir a sugestão. Tenta outra vez.');
}

/// Editor das etiquetas do menu no ecrã do produto (adendo 4 · item 5): três
/// chips que o parceiro liga e desliga, e, se o painel admin deixar
/// (`feature_etiquetas_menu_ia`), um botão que pede à IA uma sugestão a partir
/// da descrição guardada. O parceiro tem sempre a última palavra.
class EtiquetasMenuEditor extends StatefulWidget {
  const EtiquetasMenuEditor({
    super.key,
    required this.inicial,
    required this.aoMudar,
    this.productId,
  });

  final List<String> inicial;
  final ValueChanged<List<String>> aoMudar;

  /// Só um prato já guardado pode pedir sugestão (a IA lê a descrição gravada).
  final String? productId;

  @override
  State<EtiquetasMenuEditor> createState() => _EtiquetasMenuEditorState();
}

class _EtiquetasMenuEditorState extends State<EtiquetasMenuEditor> {
  late Set<String> _escolhidas = normalizarEtiquetas(widget.inicial).toSet();
  bool _iaLigada = false;
  bool _aPedir = false;
  String? _mensagem;

  @override
  void initState() {
    super.initState();
    InterruptoresApp.instance.ligado(InterruptoresApp.etiquetasMenuIa).then((v) {
      if (mounted && v != _iaLigada) setState(() => _iaLigada = v);
    });
  }

  void _avisar() => widget.aoMudar(normalizarEtiquetas(_escolhidas));

  Future<void> _sugerir() async {
    final id = widget.productId;
    if (id == null || _aPedir) return;
    setState(() {
      _aPedir = true;
      _mensagem = null;
    });
    Object? resposta;
    try {
      final r = await Supabase.instance.client.functions
          .invoke('etiquetas-menu-ia', body: {'product_id': id});
      resposta = r.data;
    } catch (e) {
      debugPrint('[EtiquetasMenuEditor] $e');
    }
    if (!mounted) return;
    final res = interpretarRespostaDaIa(resposta);
    setState(() {
      _aPedir = false;
      _mensagem = res.mensagem;
      final novas = res.etiquetas;
      if (novas != null) _escolhidas = novas.toSet();
    });
    if (res.etiquetas != null) _avisar();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('editor_etiquetas_menu'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Etiquetas do menu',
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          'O cliente vê estas etiquetas no prato. Não substituem os alergénios.',
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSubtle),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in kEtiquetasDieta)
              FilterChip(
                key: Key('etiqueta_$t'),
                label: Text(kEtiquetasDietaTexto[t] ?? t,
                    style: const TextStyle(fontSize: 13)),
                selected: _escolhidas.contains(t),
                onSelected: (sel) {
                  setState(() {
                    if (sel) {
                      _escolhidas.add(t);
                    } else {
                      _escolhidas.remove(t);
                    }
                  });
                  _avisar();
                },
              ),
          ],
        ),
        if (_iaLigada && widget.productId != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('btn_sugerir_etiquetas_ia'),
            onPressed: _aPedir ? null : _sugerir,
            icon: _aPedir
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Sugerir com IA'),
          ),
        ],
        if (_mensagem != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_mensagem!,
                key: const Key('etiquetas_mensagem'),
                style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}
