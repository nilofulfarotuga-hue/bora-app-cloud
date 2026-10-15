import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../models/cleaning_models.dart';

/// GUIA DA LIMPEZA — o que a profissional tem de fazer e de levar.
///
/// Pedido do Danilo (15/10/2026): uma cliente perguntou no suporte "como é a
/// limpeza standard?" e a profissional que aceita a limpeza não tinha em lado
/// nenhum o que cada tipo inclui nem o que tem de levar. Agora, em cada oferta
/// e em cada limpeza da agenda, aparece o que levar e um botão "O que tens de
/// fazer" com a lista do tipo (Standard, Profunda, Pós-obras).
///
/// A verdade vive em `platform_settings` (chaves `limpeza_guia_*`, migration
/// 20261015060000) e o Danilo edita-a no painel admin. Aqui só se lê.
class GuiaLimpezaService {
  static Future<Map<String, String>>? _cache;

  static Future<Map<String, String>> carregar() {
    return _cache ??= _ler().then((m) {
      // Falhou (sem rede, por exemplo): não guardar o vazio, tentar de novo
      // na próxima vez que o ecrã pedir.
      if (m.isEmpty) _cache = null;
      return m;
    });
  }

  static Future<Map<String, String>> _ler() async {
    try {
      final rows = await Supabase.instance.client
          .from('platform_settings')
          .select('key, value')
          .like('key', 'limpeza_guia_%');
      final out = <String, String>{};
      for (final r in rows as List) {
        final m = (r as Map).cast<String, dynamic>();
        final v = m['value'];
        if (v is String && v.trim().isNotEmpty) out[m['key'] as String] = v;
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  static String chaveDoTipo(String cleaningType) => switch (cleaningType) {
        'deep' => 'limpeza_guia_profunda',
        'post_works' => 'limpeza_guia_pos_obras',
        _ => 'limpeza_guia_standard',
      };
}

/// Caixa curta com o que levar + botão que abre a lista completa.
class GuiaLimpezaCaixa extends StatelessWidget {
  const GuiaLimpezaCaixa({super.key, required this.booking});
  final CleaningBooking booking;

  bool get _levaProdutos => booking.productsBy == 'cleaner';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _levaProdutos ? Icons.shopping_bag_outlined : Icons.home_outlined,
                size: 18,
                color: _levaProdutos ? AppColors.accent : AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _levaProdutos
                      ? 'Levas tu os produtos de limpeza (o cliente pagou)'
                      : 'Produtos de limpeza: usa os do cliente',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => abrirGuiaLimpeza(context, booking),
              icon: const Icon(Icons.checklist, size: 18),
              label: const Text('O que tens de fazer e levar'),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> abrirGuiaLimpeza(BuildContext context, CleaningBooking b) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, scroll) => FutureBuilder<Map<String, String>>(
        future: GuiaLimpezaService.carregar(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final g = snap.data ?? const {};
          if (g.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                  'Não foi possível carregar o guia. Verifica a internet e abre de novo.'),
            );
          }
          final tipo = CleaningLabels.types[b.cleaningType] ?? 'Limpeza';
          final levar = b.productsBy == 'cleaner'
              ? g['limpeza_guia_levar_produtos_profissional']
              : g['limpeza_guia_levar_produtos_cliente'];
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: [
              Text('Limpeza $tipo · ${b.sizeLabel}',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
              if (b.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                _Bloco(
                  titulo: 'Nota do cliente',
                  texto: b.notes,
                  primeiraLinhaIntro: false,
                ),
              ],
              _Bloco(
                titulo: 'O que tens de fazer',
                texto: g[GuiaLimpezaService.chaveDoTipo(b.cleaningType)],
              ),
              _Bloco(titulo: 'O que levar', texto: levar),
              _Bloco(
                titulo: 'Aspirador, balde e esfregona',
                texto: g['limpeza_guia_equipamento'],
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _Bloco extends StatelessWidget {
  const _Bloco({
    required this.titulo,
    required this.texto,
    this.primeiraLinhaIntro = true,
  });
  final String titulo;
  final String? texto;
  final bool primeiraLinhaIntro;

  @override
  Widget build(BuildContext context) {
    final linhas = (texto ?? '')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (linhas.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary)),
          const SizedBox(height: 8),
          for (var i = 0; i < linhas.length; i++)
            if (i == 0 && primeiraLinhaIntro)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(linhas[i],
                    style: const TextStyle(
                        color: AppColors.textSecondary, height: 1.4)),
              )
            else
              _Linha(linhas[i]),
        ],
      ),
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) {
    final nao = texto.toUpperCase().startsWith('NÃO');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(nao ? Icons.block : Icons.check_circle_outline,
                size: 18, color: nao ? AppColors.error : AppColors.primary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto,
                style: TextStyle(
                    height: 1.4,
                    color: nao ? AppColors.error : AppColors.textPrimary,
                    fontWeight: nao ? FontWeight.w600 : FontWeight.w400)),
          ),
        ],
      ),
    );
  }
}
