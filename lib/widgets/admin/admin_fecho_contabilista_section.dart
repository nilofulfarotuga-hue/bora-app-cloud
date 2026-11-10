// Painel admin (PT-BR) — "Para o contabilista" no ecrã /admin/fecho-mensal.
// Missão fecho-contabilista-2026-11-10 (Danilo, 10/11/2026: "O que vai pro
// estafeta, o que vai pro parceiro, o que vai pro contabilista... O sistema tem
// que estar ótimo, sem erro.").
//
// Mostra EXATAMENTE o conteúdo que vai ao contabilista no fecho do dia 1 (o
// texto da RPC admin_fecho_contabilista, que a Edge fecho-mensal-contabilista
// também manda como texto do email): receita da Bora por rubrica, faturação da
// parte da Bora (consumidor final; nunca às lojas), prestadores, tokens e
// promoções, cancelamentos, Stripe só da parte Bora, pedidos com prejuízo e
// dados em falta (DAC7). Autoridade total do Danilo: copiar o texto, exportar
// CSV, escrever/corrigir a nota que vai no fecho e reenviar.
//
// Servidor: admin_fecho_contabilista, admin_fecho_contabilista_nota e
// admin_fecho_contabilista_reenviar. Sem elas publicadas mostra
// "Função ainda não publicada no servidor".
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../utils/ofertas_em_palavras.dart' show servidorAindaSemIsto;
import 'admin_csv_button.dart';

const String kFechoContabilistaNaoPublicada =
    'Função ainda não publicada no servidor (migração do fecho do contabilista por aplicar).';

/// Linhas do CSV do contabilista a partir da resposta de admin_fecho_contabilista:
/// uma linha por número (secção, descrição, valor), na mesma ordem do texto.
List<Map<String, dynamic>> linhasCsvContabilista(Map<String, dynamic> d) {
  Map<String, dynamic> m(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  List<Map<String, dynamic>> l(Object? v) => v is List
      ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];
  final out = <Map<String, dynamic>>[];
  void add(String secao, String descricao, Object? valor, [String nota = '']) =>
      out.add({'secao': secao, 'descricao': descricao, 'valor': valor, 'nota': nota});

  final rec = m(d['receita']);
  for (final e in m(rec['rubricas']).entries) {
    add('1. Receita própria da Bora', e.key, e.value);
  }
  add('1. Receita própria da Bora', 'entregas_e_mercados', rec['entregas_e_mercados']);
  add('1. Receita própria da Bora', 'limpeza_taxa_bora', m(rec['limpeza'])['taxa_bora']);
  add('1. Receita própria da Bora', 'lavagem_taxa_bora', rec['lavagem_taxa_bora']);
  add('1. Receita própria da Bora', 'marcacoes', rec['marcacoes']);
  add('1. Receita própria da Bora', 'TOTAL', rec['total']);
  for (final f in l(d['faturacao'])) {
    add('2. Faturação da parte da Bora', '${f['destinatario'] ?? ''}', f['valor'], '${f['descricao'] ?? ''}');
  }
  final x = m(d['extras']);
  for (final p in l(x['pedidos_com_nif_do_cliente'])) {
    add('2. Pedidos com NIF do cliente', '${p['data']} ${p['loja'] ?? ''} NIF ${p['nif_cliente']}', p['parte_bora'], '${p['order_id']}');
  }
  final pr = m(d['prestadores']);
  for (final e in l(pr['estafetas'])) {
    add('3. Estafetas', '${e['nome']}${e['nif'] != null ? ' (NIF ${e['nif']})' : ' (sem NIF)'}', e['ganho'], '${e['entregas']} entregas');
  }
  for (final e in l(pr['limpeza'])) {
    add('3. Limpeza', '${e['nome']}${e['nif'] != null ? ' (NIF ${e['nif']})' : ' (sem NIF)'}', e['ganho'], '${e['servicos']} serviços; taxa Bora ${e['taxa_bora']}');
  }
  for (final e in l(pr['lavagem'])) {
    add('3. Lavagem', '${e['nome']}', e['ganho'], '${e['servicos']} serviços; taxa Bora ${e['taxa_bora']}');
  }
  for (final e in l(pr['lojas_parceiras'])) {
    add('3. Lojas parceiras', '${e['nome']}${e['nif'] != null ? ' (NIF ${e['nif']})' : ' (sem NIF)'}', e['parte_bora'] ?? e['comissao_bora'],
        'parte da Bora (faturada aos clientes); vendas ${e['vendas']}');
  }
  final tok = m(x['tokens_oferecidos']);
  add('4. Tokens', 'tokens oferecidos (valor)', tok['valor'], '${tok['tokens'] ?? 0} tokens');
  add('4. Tokens', 'tokens descontados em pedidos', m(x['tokens_descontados_em_pedidos'])['valor']);
  for (final c in l(x['codigos_promocionais'])) {
    add('4. Códigos promocionais', '${c['codigo']} (${c['usos']} usos)', c['valor'], '${c['nota'] ?? ''}');
  }
  final ck = m(x['premios_checkin']);
  add('4. Prémios do check-in', 'emitidos (custo previsto)', ck['emitidos_custo'], '${ck['emitidos'] ?? 0} vales');
  add('4. Prémios do check-in', 'usados (custo)', ck['usados_custo'], '${ck['usados'] ?? 0} vales');
  final cr = m(x['cancelados_e_reembolsos']);
  add('5. Cancelamentos', 'pedidos cancelados (valor)', cr['cancelados_valor'], '${cr['cancelados'] ?? 0} pedidos');
  add('5. Reembolsos', 'reembolsos (total)', cr['reembolsado_valor'], '${cr['reembolsados'] ?? 0} pedidos');
  final st = m(x['stripe_parte_bora']);
  add('6. Stripe (parte Bora)', 'taxas da Stripe', st['taxas_a_considerar'], '${st['fonte'] ?? ''}');
  for (final p in l(d['pedidos_no_prejuizo'])) {
    add('7. Pedidos com prejuízo', '${p['data']} ${p['loja'] ?? ''}', p['resultado'], '${p['motivo'] ?? ''} (${p['order_id']})');
  }
  for (final f in l(d['dados_em_falta'])) {
    final falta = f['falta'] is List ? (f['falta'] as List).join(', ') : '';
    add('8. Dados em falta (DAC7)', '${f['nome']} (${f['papel']})', null, 'falta $falta');
  }
  return out;
}

class AdminFechoContabilistaSection extends StatefulWidget {
  const AdminFechoContabilistaSection({
    super.key,
    required this.ano,
    required this.mes,
    this.carregar,
    this.guardarNota,
    this.reenviar,
  });

  final int ano;
  final int mes;

  /// Testes: em vez do Supabase.
  final Future<Object?> Function(int ano, int mes)? carregar;
  final Future<void> Function(int ano, int mes, String nota)? guardarNota;
  final Future<void> Function(int ano, int mes)? reenviar;

  static const List<(String, String)> colunasCsv = [
    ('secao', 'Secção'),
    ('descricao', 'Descrição'),
    ('valor', 'Valor (€)'),
    ('nota', 'Nota'),
  ];

  @override
  State<AdminFechoContabilistaSection> createState() =>
      _AdminFechoContabilistaSectionState();
}

class _AdminFechoContabilistaSectionState
    extends State<AdminFechoContabilistaSection> {
  Map<String, dynamic>? _dados;
  bool _aCarregar = true;
  String? _erro;
  bool _textoAberto = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _aCarregar = true;
      _erro = null;
    });
    try {
      final f = widget.carregar;
      final res = f != null
          ? await f(widget.ano, widget.mes)
          : await Supabase.instance.client.rpc('admin_fecho_contabilista',
              params: {'p_year': widget.ano, 'p_month': widget.mes});
      if (!mounted) return;
      setState(() {
        _dados = res is Map ? Map<String, dynamic>.from(res) : null;
        _aCarregar = false;
      });
    } catch (e) {
      debugPrint('[AdminFechoContabilista] $e');
      if (!mounted) return;
      setState(() {
        _aCarregar = false;
        _erro = servidorAindaSemIsto(e)
            ? kFechoContabilistaNaoPublicada
            : 'Não foi possível carregar: $e';
      });
    }
  }

  String get _texto => '${_dados?['texto'] ?? ''}';

  void _aviso(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _copiar() async {
    await Clipboard.setData(ClipboardData(text: _texto));
    if (mounted) _aviso('Texto do contabilista copiado.');
  }

  Future<void> _editarNota() async {
    final ctrl = TextEditingController(text: '${_dados?['nota_admin'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nota para o contabilista'),
        content: TextField(
          key: const Key('fecho_contab_nota_campo'),
          controller: ctrl,
          maxLines: 5,
          maxLength: 2000,
          decoration: const InputDecoration(
            hintText: 'Ex.: outubro foi no nome individual do Danilo.',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              key: const Key('fecho_contab_nota_salvar'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final f = widget.guardarNota;
      if (f != null) {
        await f(widget.ano, widget.mes, ctrl.text.trim());
      } else {
        await Supabase.instance.client.rpc('admin_fecho_contabilista_nota',
            params: {'p_year': widget.ano, 'p_month': widget.mes, 'p_nota': ctrl.text.trim()});
      }
      if (!mounted) return;
      _aviso('Nota salva: vai no próximo fecho ao contabilista.');
      await _carregar();
    } catch (e) {
      if (mounted) {
        _aviso(servidorAindaSemIsto(e) ? kFechoContabilistaNaoPublicada : 'Erro ao salvar: $e');
      }
    }
  }

  Future<void> _reenviar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reenviar o fecho ao contabilista?'),
        content: const Text(
            'Manda outra vez o email do fecho deste mês ao contabilista (com cópia '
            'ao Danilo), com o conteúdo que está aqui em cima.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              key: const Key('fecho_contab_reenviar_confirmar'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reenviar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final f = widget.reenviar;
      if (f != null) {
        await f(widget.ano, widget.mes);
      } else {
        await Supabase.instance.client.rpc('admin_fecho_contabilista_reenviar',
            params: {'p_year': widget.ano, 'p_month': widget.mes});
      }
      if (mounted) _aviso('Pedido de reenvio feito. O estado aparece aqui quando o email sair.');
    } catch (e) {
      if (mounted) {
        _aviso(servidorAindaSemIsto(e) ? kFechoContabilistaNaoPublicada : 'Erro ao reenviar: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _dados;
    final envio = d?['envio'] is Map ? Map<String, dynamic>.from(d!['envio']) : null;
    final falta = d?['dados_em_falta'] is List ? (d!['dados_em_falta'] as List) : const [];
    return Card(
      key: const Key('fecho_contabilista_secao'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Para o contabilista (o que vai no fecho do dia 1)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text(
              'As faturas da Bora são emitidas pelo escritório do contabilista. A parte da Bora '
              'fatura-se aos clientes (consumidor final ou NIF do cliente), nunca às lojas. Cada '
              'prestador fatura a sua parte; IVA e retenção de cada um confirmados pelo contabilista.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            if (_aCarregar)
              const LinearProgressIndicator()
            else if (_erro != null)
              Text(_erro!,
                  key: const Key('fecho_contab_erro'),
                  style: const TextStyle(color: AppColors.error))
            else if (d != null) ...[
              Text(
                'Envio: ${envio == null ? 'ainda não enviado' : '${envio['estado'] ?? '—'}${envio['enviado_em'] != null ? ' em ${envio['enviado_em']}' : ''}${envio['erro'] != null ? ' (${envio['erro']})' : ''}'}',
                key: const Key('fecho_contab_envio'),
                style: const TextStyle(fontSize: 13),
              ),
              if (falta.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${falta.length} prestador(es)/loja(s) com dados em falta (DAC7) — ver o fim do texto.',
                    key: const Key('fecho_contab_falta'),
                    style: const TextStyle(fontSize: 13, color: AppColors.error, fontWeight: FontWeight.w600),
                  ),
                ),
              if ('${d['nota_admin'] ?? ''}'.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Nota do Danilo: ${d['nota_admin']}',
                      key: const Key('fecho_contab_nota'),
                      style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  FilledButton.icon(
                    key: const Key('fecho_contab_copiar'),
                    onPressed: _texto.isEmpty ? null : _copiar,
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copiar texto para o contabilista'),
                  ),
                  AdminCsvButton(
                    nome: 'fecho_contabilista_${widget.ano}_${widget.mes.toString().padLeft(2, '0')}',
                    colunas: AdminFechoContabilistaSection.colunasCsv,
                    linhas: () => linhasCsvContabilista(d),
                  ),
                  OutlinedButton.icon(
                    key: const Key('fecho_contab_nota_editar'),
                    onPressed: _editarNota,
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: const Text('Nota para o contabilista'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('fecho_contab_reenviar'),
                    onPressed: _reenviar,
                    icon: const Icon(Icons.forward_to_inbox_outlined, size: 18),
                    label: const Text('Reenviar ao contabilista'),
                  ),
                ],
              ),
              TextButton.icon(
                key: const Key('fecho_contab_ver_texto'),
                onPressed: () => setState(() => _textoAberto = !_textoAberto),
                icon: Icon(_textoAberto ? Icons.expand_less : Icons.expand_more),
                label: Text(_textoAberto ? 'Esconder o texto' : 'Ver o texto completo'),
              ),
              if (_textoAberto)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(_texto,
                      key: const Key('fecho_contab_texto'),
                      style: const TextStyle(fontSize: 12.5, height: 1.4)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
