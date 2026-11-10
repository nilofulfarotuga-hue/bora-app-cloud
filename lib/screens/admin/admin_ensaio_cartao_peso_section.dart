// PAINEL ADMIN (PT-BR) — Ajustes de peso → "Ensaio do cartão (modo de teste da Stripe)".
// Missão fechar-tudo-2026-11-10, Bloco C.
//
// Quatro botões pedem à Edge `cobrar-diferenca-peso` um ENSAIO na Stripe da EMPRESA em MODO DE
// TESTE (cartões de teste da própria Stripe; nenhum pedido, nenhum cliente, nenhum dinheiro real):
//   • Melancia a mais     → tem de dar "cartão cobrado";
//   • Melancia a menos    → tem de dar "carteira" (o cartão não é mexido);
//   • Cartão recusado     → tem de dar "a Bora assume" (o pedido segue);
//   • Banco pede autenticação → tem de dar "a Bora assume".
// O botão chama a RPC `admin_ensaio_peso_cartao(p_caso)` (só admin), que manda o pedido à Edge com
// a chave de servidor do cofre. O resultado chega à tabela `ensaio_peso_cartao` em poucos segundos
// e aparece na lista. Só com os 4 a verde se liga `weight_adjust_card_charge_enabled`.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../utils/hora_lisboa.dart';
import '_admin_rpc_errors.dart';
import 'admin_ajustes_peso_screen.dart' show eurosAjustePeso;

/// Os casos do ensaio, pela ordem dos botões, com o texto do botão.
const List<(String, String)> kCasosEnsaioCartaoPeso = [
  ('a_mais', 'Melancia a mais (cobra 2,50 €)'),
  ('a_menos', 'Melancia a menos (1,80 € para a carteira)'),
  ('recusado', 'Cartão recusado (Bora assume)'),
  ('pede_autenticacao', 'Banco pede autenticação (Bora assume)'),
];

/// Nome curto do caso em PT-BR.
String textoCasoEnsaioPeso(Object? caso) {
  switch (caso?.toString()) {
    case 'a_mais':
      return 'Melancia a mais';
    case 'a_menos':
      return 'Melancia a menos';
    case 'recusado':
      return 'Cartão recusado';
    case 'pede_autenticacao':
      return 'Banco pede autenticação';
    default:
      return caso?.toString() ?? '—';
  }
}

/// O que o ensaio deu (ou devia dar), em PT-BR.
String textoResultadoEnsaioPeso(Object? resultado) {
  switch (resultado?.toString()) {
    case null:
    case '':
      return '—';
    case 'cartao_cobrado':
      return 'cartão cobrado';
    case 'carteira':
      return 'carteira Bora (cartão não mexido)';
    case 'bora_assume':
      return 'a Bora assume (pedido segue)';
    default:
      return resultado.toString();
  }
}

/// Erros conhecidos em PT-BR (o resto aparece como veio).
String textoErroEnsaioPeso(Object? erro) {
  final e = erro?.toString() ?? '';
  switch (e) {
    case 'falta_chave_teste':
      return 'Falta a chave de teste: STRIPE_TEST_SECRET_KEY_EMPRESA nos segredos das Edge Functions.';
    case 'chave_nao_e_de_teste':
      return 'A chave em STRIPE_TEST_SECRET_KEY_EMPRESA não é de teste (tem que começar com sk_test_). Não foi usada.';
    default:
      return e;
  }
}

class EnsaioCartaoPesoSection extends StatefulWidget {
  const EnsaioCartaoPesoSection({
    super.key,
    this.pedirEnsaio,
    this.carregar,
    this.esperaEntreLeituras = const Duration(seconds: 3),
    this.leiturasDepoisDoPedido = 8,
  });

  /// Só para testes: substitui a RPC `admin_ensaio_peso_cartao`.
  final Future<Map<String, dynamic>> Function(String caso)? pedirEnsaio;

  /// Só para testes: substitui a leitura de `ensaio_peso_cartao`.
  final Future<List<Map<String, dynamic>>> Function()? carregar;

  final Duration esperaEntreLeituras;
  final int leiturasDepoisDoPedido;

  @override
  State<EnsaioCartaoPesoSection> createState() => _EnsaioCartaoPesoSectionState();
}

class _EnsaioCartaoPesoSectionState extends State<EnsaioCartaoPesoSection> {
  List<Map<String, dynamic>> _linhas = const [];
  String? _aCorrer;
  String? _aviso;

  @override
  void initState() {
    super.initState();
    _ler();
  }

  Future<List<Map<String, dynamic>>> _doServidor() async {
    final rows = await Supabase.instance.client
        .from('ensaio_peso_cartao')
        .select('id, caso, estado, esperado, resultado, valor_original_cents, '
            'diferenca_cents, pi_original, pi_extra, erro, detalhe, criado_em')
        .order('criado_em', ascending: false)
        .limit(20);
    return [for (final r in rows) Map<String, dynamic>.from(r)];
  }

  Future<Map<String, dynamic>> _pedirAoServidor(String caso) async {
    final res = await Supabase.instance.client
        .rpc('admin_ensaio_peso_cartao', params: {'p_caso': caso});
    return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
  }

  Future<void> _ler() async {
    try {
      final l = await (widget.carregar ?? _doServidor)();
      if (!mounted) return;
      setState(() => _linhas = l);
    } catch (e) {
      debugPrint('[EnsaioCartaoPeso] leitura falhou: $e');
    }
  }

  Future<void> _correr(String caso) async {
    if (_aCorrer != null) return;
    final antes = _linhas.isEmpty ? null : _linhas.first['id']?.toString();
    setState(() {
      _aCorrer = caso;
      _aviso = null;
    });
    try {
      final r = await (widget.pedirEnsaio ?? _pedirAoServidor)(caso);
      if (r['ok'] != true) {
        if (mounted) setState(() => _aviso = 'Não deu para pedir o ensaio: ${r['erro'] ?? 'erro'}');
        return;
      }
      // O resultado chega à tabela em poucos segundos: lê-se até aparecer uma linha nova.
      for (var i = 0; i < widget.leiturasDepoisDoPedido; i++) {
        await Future<void>.delayed(widget.esperaEntreLeituras);
        await _ler();
        final agora = _linhas.isEmpty ? null : _linhas.first['id']?.toString();
        if (agora != null && agora != antes) break;
      }
    } catch (e) {
      if (mounted) setState(() => _aviso = humanizeAdminRpcError(e));
    } finally {
      if (mounted) setState(() => _aCorrer = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    const pequeno = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    return Card(
      key: const Key('ensaio_cartao_peso'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ensaio do cartão (modo de teste da Stripe)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: Spacing.xs),
            const Text(
              'Corre o mesmo código da cobrança da diferença de peso na Stripe da '
              'empresa em MODO DE TESTE, com cartões de teste da Stripe. Não usa '
              'pedidos, clientes nem dinheiro real. Só depois dos 4 ensaios verdes '
              'se liga a cobrança no cartão (weight_adjust_card_charge_enabled).',
              style: pequeno,
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              children: [
                for (final (caso, rotulo) in kCasosEnsaioCartaoPeso)
                  OutlinedButton(
                    key: Key('ensaio_cartao_peso_$caso'),
                    onPressed: _aCorrer == null ? () => _correr(caso) : null,
                    child: Text(_aCorrer == caso ? 'Executando…' : rotulo),
                  ),
              ],
            ),
            if (_aviso != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(_aviso!, style: const TextStyle(fontSize: 12, color: AppColors.error)),
            ],
            const SizedBox(height: Spacing.sm),
            if (_linhas.isEmpty)
              const Text('Ainda não houve nenhum ensaio.', style: pequeno)
            else
              for (final r in _linhas) _linha(r),
          ],
        ),
      ),
    );
  }

  Widget _linha(Map<String, dynamic> r) {
    final estado = r['estado']?.toString() ?? '';
    final (cor, selo) = switch (estado) {
      'ok' => (AppColors.success, 'OK'),
      'falhou' => (AppColors.error, 'FALHOU'),
      _ => (AppColors.warning, 'ERRO'),
    };
    final erro = textoErroEnsaioPeso(r['erro']);
    const pequeno = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Text(selo,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cor)),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(textoCasoEnsaioPeso(r['caso']),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              Text(dataHoraLisboa(r['criado_em']), style: pequeno),
            ],
          ),
          Text(
            'Esperado: ${textoResultadoEnsaioPeso(r['esperado'])} · '
            'Deu: ${textoResultadoEnsaioPeso(r['resultado'])}',
            style: const TextStyle(fontSize: 12),
          ),
          Text(
            'Pago no início: ${eurosAjustePeso(r['valor_original_cents'])} · '
            'Diferença: ${eurosAjustePeso(r['diferenca_cents'], comSinal: true)}',
            style: pequeno,
          ),
          if ((r['pi_original'] ?? r['pi_extra']) != null)
            Text(
              'Stripe (teste): ${r['pi_original'] ?? '—'}'
              '${r['pi_extra'] == null ? '' : ' → ${r['pi_extra']}'}',
              style: pequeno,
            ),
          if (erro.isNotEmpty)
            Text(erro, style: const TextStyle(fontSize: 12, color: AppColors.error)),
        ],
      ),
    );
  }
}
