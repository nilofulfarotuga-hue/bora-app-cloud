import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/papeis_de_trabalho.dart';
import '../../widgets/bora/bora.dart';

/// OS MEUS GANHOS — um ecrã só para quem trabalha, seja no que for.
///
/// Antes de 2026-08-29 cada papel tinha o seu canto: o estafeta via o extrato
/// dele, a faxineira via o dela, e o lavador não via nada. Quem faz duas ou
/// três coisas tinha de somar de cabeça, e o acerto semanal — que já é um só
/// por pessoa — não aparecia em lado nenhum.
///
/// Aqui em cima está o que a pessoa ganhou hoje e esta semana, com o detalhe
/// por tipo de trabalho. Em baixo, o acerto de cada semana fechada, com **um
/// número final** e o sentido: ou a Bora paga, ou a pessoa deve.
///
/// Nada disto calcula dinheiro. Lê o que o servidor já apurou.
class MeusGanhosScreen extends StatefulWidget {
  const MeusGanhosScreen({super.key});

  @override
  State<MeusGanhosScreen> createState() => _MeusGanhosScreenState();
}

class _MeusGanhosScreenState extends State<MeusGanhosScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _erro;
  Map<String, dynamic> _ganho = const {};
  List<Map<String, dynamic>> _acertos = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final ganho = await _sb.rpc('meu_ganho_ao_vivo');
      final acertos = await _sb.rpc('meu_acerto_semanal', params: {
        'p_semanas': 8,
      });
      if (!mounted) return;
      setState(() {
        _ganho = (ganho as Map).cast<String, dynamic>();
        _acertos = ((acertos as List?) ?? [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Os meus ganhos',
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _carregar),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? _Erro(erro: _erro!, onRetry: _carregar)
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.all(Spacing.lg),
                    children: [
                      _CaixaDeHoje(ganho: _ganho),
                      const SizedBox(height: Spacing.lg),
                      const Text('Acerto por semana',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: Spacing.xs),
                      const Text(
                        'Cada semana dá um número só, com tudo o que fizeste '
                        'somado e o que deves já descontado.',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: Spacing.md),
                      if (_acertos.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: Spacing.xl),
                          child: Text(
                            'Ainda não há nenhuma semana fechada. O acerto '
                            'aparece aqui quando a semana fecha.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSubtle),
                          ),
                        )
                      else
                        for (final a in _acertos) ...[
                          _CartaoDeSemana(acerto: a),
                          const SizedBox(height: Spacing.md),
                        ],
                    ],
                  ),
                ),
    );
  }
}

String eur(num cents) =>
    '€${(cents.abs() / 100).toStringAsFixed(2).replaceAll('.', ',')}';

/// Data curta em português, sem depender de `intl` inicializado.
String diaCurto(String? iso) {
  if (iso == null || iso.length < 10) return '—';
  return '${iso.substring(8, 10)}/${iso.substring(5, 7)}';
}

class _CaixaDeHoje extends StatelessWidget {
  const _CaixaDeHoje({required this.ganho});
  final Map<String, dynamic> ganho;

  @override
  Widget build(BuildContext context) {
    final hoje = (ganho['hoje_cents'] as num?)?.toInt() ?? 0;
    final semana = (ganho['semana_cents'] as num?)?.toInt() ?? 0;
    final porPapel = ((ganho['por_papel'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();

    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _Numero(rotulo: 'Hoje', cents: hoje, grande: true)),
              Container(width: 1, height: 48, color: AppColors.divider),
              Expanded(
                  child: _Numero(
                      rotulo: 'Esta semana', cents: semana, grande: true)),
            ],
          ),
          if (porPapel.isNotEmpty) ...[
            const SizedBox(height: Spacing.md),
            const Divider(height: 1),
            const SizedBox(height: Spacing.sm),
            for (final l in porPapel)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        (l['titulo'] ?? '').toString(),
                        style: const TextStyle(color: AppColors.textPrimary),
                      ),
                    ),
                    Text(
                      eur((l['semana_cents'] as num?) ?? 0),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Numero extends StatelessWidget {
  const _Numero({required this.rotulo, required this.cents, this.grande = false});
  final String rotulo;
  final int cents;
  final bool grande;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(rotulo,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 4),
        Text(eur(cents),
            style: TextStyle(
                fontSize: grande ? 24 : 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
      ],
    );
  }
}

class _CartaoDeSemana extends StatelessWidget {
  const _CartaoDeSemana({required this.acerto});
  final Map<String, dynamic> acerto;

  @override
  Widget build(BuildContext context) {
    final total = (acerto['total_cents'] as num?)?.toInt() ?? 0;
    final sentido = (acerto['sentido'] ?? 'zero').toString();
    final divida = (acerto['divida_cents'] as num?)?.toInt() ?? 0;
    final porAbater = (acerto['divida_por_abater_cents'] as num?)?.toInt() ?? 0;
    final pago = acerto['tudo_pago'] == true;
    final detalhe = (acerto['detalhe'] as Map?)?.cast<String, dynamic>() ?? {};

    final (cor, frase) = switch (sentido) {
      'bora_paga' => (AppColors.primary, 'A Bora paga-te'),
      'pessoa_deve' => (AppColors.error, 'Deves à Bora'),
      _ => (AppColors.textSecondary, 'Semana a zero'),
    };

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Semana de ${diaCurto(acerto['semana']?.toString())}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
              ),
              if (pago)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryWash,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: const Text('Pago',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          // Cada tipo de trabalho, com o que rendeu.
          for (final e in detalhe.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      PapelDeTrabalho(papel: e.key, aceita: true).titulo,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ),
                  Text(
                    eur(((e.value as Map)['liquido_cents'] as num?) ?? 0),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
          if (divida > 0) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    porAbater > 0
                        ? 'Dinheiro da Bora que ficou contigo'
                        : 'Dinheiro da Bora que ficou contigo (já descontado)',
                    style: const TextStyle(
                        color: AppColors.error, fontSize: 13),
                  ),
                ),
                Text('− ${eur(divida)}',
                    style: const TextStyle(
                        color: AppColors.error, fontSize: 13)),
              ],
            ),
          ],
          const SizedBox(height: Spacing.sm),
          const Divider(height: 1),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(frase,
                    style: TextStyle(
                        color: cor, fontWeight: FontWeight.w700)),
              ),
              Text(eur(total),
                  style: TextStyle(
                      color: cor,
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Erro extends StatelessWidget {
  const _Erro({required this.erro, required this.onRetry});
  final String erro;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 40),
            const SizedBox(height: Spacing.md),
            const Text('Não foi possível carregar os teus ganhos.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textPrimary)),
            const SizedBox(height: Spacing.xs),
            Text(erro,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSubtle, fontSize: 12)),
            const SizedBox(height: Spacing.md),
            OutlinedButton(onPressed: onRetry, child: const Text('Tentar de novo')),
          ],
        ),
      ),
    );
  }
}
