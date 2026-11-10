// Missão fecho-contabilista-2026-11-10 (bloco C3): quem tem dados fiscais em
// falta para a lei DAC7 (nome legal, NIF, morada, data de nascimento, IBAN,
// comprovativo de atividade) vê na app uma barra "Faltam dados para as
// Finanças" e completa-os ali mesmo. O estafeta já tem isto em "A minha conta";
// aqui estende-se à limpeza, à Casa e Manutenção, à lavagem e às lojas
// parceiras. Sem mensagens a ninguém: é só a app.
//
// A regra do que falta é a do servidor (`meus_dados_fiscais_em_falta`, a mesma
// do painel "Dados fiscais (DAC7)" e da secção 8 do fecho ao contabilista).
// Falha aberta: sem rede, sem sessão ou com a função ainda fora do servidor,
// não mostra nada e não trava nada.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../screens/shared/comprovativo_atividade_screen.dart';
import 'prestador_documentos_em_falta.dart' show PrestadorDadosFiscaisScreen;

/// O que falta a este utilizador neste papel ('limpeza', 'casa', 'lavagem',
/// 'loja_parceira' ou 'estafeta'), a partir da resposta do servidor.
List<String> faltaDoPapel(Object? resposta, String papel) {
  if (resposta is! Map || resposta['ok'] != true) return const [];
  final lista = resposta['em_falta'];
  if (lista is! List) return const [];
  for (final e in lista) {
    if (e is Map && e['papel'] == papel && e['falta'] is List) {
      return (e['falta'] as List).map((x) => '$x').where((x) => x.isNotEmpty).toList();
    }
  }
  return const [];
}

/// "Faltam dados para as Finanças: IBAN e data de nascimento."
String textoFaltaDadosFiscais(List<String> falta) {
  if (falta.isEmpty) return '';
  final l = falta.length == 1
      ? falta.first
      : '${falta.sublist(0, falta.length - 1).join(', ')} e ${falta.last}';
  return 'Faltam dados para as Finanças: $l.';
}

class AvisoDadosFiscaisEmFalta extends StatefulWidget {
  const AvisoDadosFiscaisEmFalta({
    super.key,
    required this.papel,
    this.aoCompletar,
    this.carregar,
    this.margem,
    this.semComprovativo = false,
  });

  /// true quando o ecrã já mostra o aviso do comprovativo de atividade
  /// (AvisoAtividadeBanner): aqui só os outros dados, sem duplicar.
  final bool semComprovativo;

  /// 'limpeza', 'casa', 'lavagem' ou 'loja_parceira' (como no servidor).
  final String papel;

  /// Onde completar (ex.: a loja abre o ecrã "Dados fiscais" dela). Sem isto,
  /// abre o formulário dos dados fiscais do prestador e/ou o comprovativo.
  final Future<void> Function(BuildContext context)? aoCompletar;

  /// Só para testes: troca o servidor.
  final Future<Object?> Function()? carregar;

  final EdgeInsetsGeometry? margem;

  @override
  State<AvisoDadosFiscaisEmFalta> createState() => _AvisoDadosFiscaisEmFaltaState();
}

class _AvisoDadosFiscaisEmFaltaState extends State<AvisoDadosFiscaisEmFalta> {
  List<String> _falta = const [];

  static const _tabelaDoPapel = {
    'limpeza': ('cleaners', 'cleaner'),
    'casa': ('casa_profissionais', 'handyman'),
    'lavagem': ('washers', 'washer'),
  };

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final f = widget.carregar;
      final res = f != null
          ? await f()
          : await Supabase.instance.client.rpc('meus_dados_fiscais_em_falta');
      if (!mounted) return;
      final falta = faltaDoPapel(res, widget.papel);
      setState(() => _falta = widget.semComprovativo
          ? falta.where((f) => f != 'comprovativo de atividade').toList()
          : falta);
    } catch (e) {
      // Calado de propósito: sem isto o ecrã continua a funcionar.
      debugPrint('[dados-fiscais-em-falta] $e');
    }
  }

  bool get _faltaComprovativo => _falta.contains('comprovativo de atividade');
  bool get _faltaFormulario => _falta.any((f) => f != 'comprovativo de atividade');

  Future<void> _abrirFormulario() async {
    final t = _tabelaDoPapel[widget.papel];
    if (t == null) return;
    Map<String, dynamic> linha = const {};
    try {
      final sb = Supabase.instance.client;
      final uid = sb.auth.currentUser?.id;
      if (uid != null) {
        final r = await sb
            .from(t.$1)
            .select('legal_name, nif, address, iban, birth_date')
            .eq('user_id', uid)
            .maybeSingle();
        if (r != null) linha = Map<String, dynamic>.from(r);
      }
    } catch (e) {
      debugPrint('[dados-fiscais-em-falta] ler: $e');
    }
    if (!mounted) return;
    await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => PrestadorDadosFiscaisScreen(papel: t.$2, linha: linha),
    ));
  }

  Future<void> _abrir() async {
    final f = widget.aoCompletar;
    if (f != null) {
      await f(context);
    } else {
      await showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Dados para as Finanças',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  'A lei obriga a Bora a comunicar às Finanças os dados de quem trabalha pela '
                  'plataforma. ${textoFaltaDadosFiscais(_falta)}',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                if (_faltaFormulario)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('dados_fiscais_completar'),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _abrirFormulario();
                      },
                      icon: const Icon(Icons.badge_outlined),
                      label: const Text('Completar os dados fiscais'),
                    ),
                  ),
                if (_faltaComprovativo) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const Key('dados_fiscais_comprovativo'),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const ComprovativoAtividadeScreen()));
                      },
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Enviar o comprovativo de atividade'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    if (mounted) await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    if (_falta.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: widget.margem ?? const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: const Key('aviso_dados_fiscais_em_falta'),
          borderRadius: BorderRadius.circular(10),
          onTap: _abrir,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.error, color: AppColors.error, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${textoFaltaDadosFiscais(_falta)} Toque para completar.',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.error),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
