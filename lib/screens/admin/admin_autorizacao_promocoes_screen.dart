// PAINEL ADMIN (PT-BR) — Autorização de promoções (opt-in de marketing, RGPD).
// 03/11/2026, missão boom-hamburguer-mes, bloco H. Mostra quantos clientes
// aceitaram receber promoções, quantos recusaram, quantos nunca responderam, e
// a lista de quem aceitou com a data. Só leitura (RPC admin_marketing_opt_in_resumo).
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

class AdminAutorizacaoPromocoesScreen extends StatefulWidget {
  const AdminAutorizacaoPromocoesScreen({super.key, this.carregar});

  /// Só para testes: devolve o resumo sem ir ao servidor.
  final Future<Map<String, dynamic>> Function()? carregar;

  @override
  State<AdminAutorizacaoPromocoesScreen> createState() =>
      _AdminAutorizacaoPromocoesScreenState();
}

class _AdminAutorizacaoPromocoesScreenState
    extends State<AdminAutorizacaoPromocoesScreen> {
  Map<String, dynamic>? _r;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _ler();
  }

  Future<void> _ler() async {
    setState(() => _erro = null);
    try {
      final r = widget.carregar != null
          ? await widget.carregar!()
          : Map<String, dynamic>.from(await Supabase.instance.client
              .rpc('admin_marketing_opt_in_resumo') as Map);
      if (mounted) setState(() => _r = r);
    } catch (e) {
      if (mounted) setState(() => _erro = 'Não deu para carregar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    final lista = (r?['lista'] as List?) ?? const [];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Autorização de promoções'),
      body: _erro != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_erro!)))
          : r == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _ler,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text(
                        'O cliente responde UMA vez (logo após o cadastro, ou ao abrir o app se nunca respondeu). '
                        'Nada vem pré-marcado. Só quem aceitou pode receber promoções (RGPD — lei de proteção de dados).',
                        style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _Numero('Aceitaram', '${r['aceitaram'] ?? 0}', key: const Key('promo_aceitaram')),
                          _Numero('Recusaram', '${r['recusaram'] ?? 0}'),
                          _Numero('Nunca responderam', '${r['sem_resposta'] ?? 0}'),
                          _Numero('Clientes', '${r['clientes'] ?? 0}'),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text('Quem aceitou',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      if (lista.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('Ninguém aceitou ainda.'),
                        ),
                      for (final raw in lista)
                        Builder(builder: (_) {
                          final l = Map<String, dynamic>.from(raw as Map);
                          final nome = '${l['nome'] ?? ''}'.trim();
                          return Card(
                            child: ListTile(
                              title: Text(nome.isEmpty ? 'Cliente' : nome),
                              subtitle: Text([
                                if ('${l['email'] ?? ''}'.isNotEmpty) '${l['email']}',
                                if ('${l['telefone'] ?? ''}'.isNotEmpty) '${l['telefone']}',
                              ].join(' · ')),
                              trailing: Text(l['aceitou_em'] == null
                                  ? '—'
                                  : dataHoraLisboa(l['aceitou_em'])),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}

class _Numero extends StatelessWidget {
  const _Numero(this.titulo, this.valor, {super.key});

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppColors.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(valor, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(titulo, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
