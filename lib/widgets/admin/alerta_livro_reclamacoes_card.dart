import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../screens/admin/admin_livro_reclamacoes_screen.dart';
import '../../utils/dias_uteis.dart';

/// Aviso no topo do Painel Admin (PT-BR) quando há reclamações do Livro de
/// Reclamações com o prazo de 15 dias úteis a acabar (3 dias úteis ou menos)
/// ou já vencido (missão fechar-tudo-2026-11-10, E2e). Sem nada urgente — ou
/// sem a tabela ainda criada — não ocupa espaço.
class AlertaLivroReclamacoesCard extends StatefulWidget {
  const AlertaLivroReclamacoesCard({super.key, this.carregarPrazos});

  /// Testes: os prazos das reclamações abertas, sem servidor.
  final Future<List<DateTime>> Function()? carregarPrazos;

  @override
  State<AlertaLivroReclamacoesCard> createState() =>
      _AlertaLivroReclamacoesCardState();
}

class _AlertaLivroReclamacoesCardState
    extends State<AlertaLivroReclamacoesCard> {
  ({int vencidas, int aVencer}) _resumo = (vencidas: 0, aVencer: 0);

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  static Future<List<DateTime>> _doServidor() async {
    final res = await Supabase.instance.client
        .from('livro_reclamacoes_registo')
        .select('prazo')
        .eq('estado', 'aberta')
        .limit(500);
    return [
      for (final r in (res as List).whereType<Map>())
        if (DateTime.tryParse('${r['prazo']}') case final DateTime d) d,
    ];
  }

  Future<void> _carregar() async {
    try {
      final prazos = await (widget.carregarPrazos ?? _doServidor)();
      if (!mounted) return;
      setState(() => _resumo = resumoPrazos(prazos, hojeLisboa()));
    } catch (e) {
      // Migração por aplicar ou sem rede: o painel segue sem o aviso.
      debugPrint('[AlertaLivroReclamacoes] $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (:vencidas, :aVencer) = _resumo;
    if (vencidas == 0 && aVencer == 0) return const SizedBox.shrink();
    final cor = vencidas > 0 ? AppColors.error : AppColors.warning;
    final partes = [
      if (vencidas > 0)
        '$vencidas ${vencidas == 1 ? 'reclamação com prazo VENCIDO' : 'reclamações com prazo VENCIDO'}',
      if (aVencer > 0)
        '$aVencer ${aVencer == 1 ? 'reclamação vence' : 'reclamações vencem'} em 3 dias úteis ou menos',
    ];
    return Card(
      key: const ValueKey('alerta-livro-reclamacoes'),
      margin: const EdgeInsets.only(bottom: 8),
      color: cor.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cor.withValues(alpha: 0.6)),
      ),
      child: ListTile(
        leading: Icon(Icons.menu_book, color: cor),
        title: const Text('Livro de Reclamações — responder em 15 dias úteis',
            style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(partes.join(' · ')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const AdminLivroReclamacoesScreen()));
          _carregar();
        },
      ),
    );
  }
}
