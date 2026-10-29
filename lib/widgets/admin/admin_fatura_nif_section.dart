import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/fatura_nif_service.dart';
import '../../utils/nif_pt.dart';

/// Fatura com NIF no painel admin (28/10/2026) — PT-BR, ver e editar.
///
/// Dois usos, o mesmo cartão:
///  * detalhe do PEDIDO: o NIF e o nome que o cliente pediu para esta fatura
///    (`admin_order_invoice_set`);
///  * detalhe do CLIENTE: o NIF e o nome guardados no perfil dele
///    (`admin_client_billing_set`).
/// NIF vazio apaga. As duas funções do servidor validam o NIF e registram a
/// ação no log de auditoria (`log_admin_action`).
class AdminFaturaNifSection extends StatefulWidget {
  const AdminFaturaNifSection({
    super.key,
    required this.titulo,
    required this.carregar,
    required this.guardar,
  });

  /// NIF e nome do PEDIDO [orderId].
  factory AdminFaturaNifSection.pedido({
    Key? key,
    required String orderId,
    Future<DadosFatura?> Function()? carregar,
    Future<void> Function(String nif, String nome)? guardar,
  }) {
    return AdminFaturaNifSection(
      key: key,
      titulo: 'Fatura com NIF deste pedido',
      carregar: carregar ??
          () async => DadosFatura.deMapa(await Supabase.instance.client
              .from('order_invoice_requests')
              .select('nif, nome')
              .eq('order_id', orderId)
              .maybeSingle()),
      guardar: guardar ??
          (nif, nome) async {
            await Supabase.instance.client.rpc('admin_order_invoice_set',
                params: {'p_order_id': orderId, 'p_nif': nif, 'p_nome': nome});
          },
    );
  }

  /// NIF e nome guardados no perfil do CLIENTE [userId].
  factory AdminFaturaNifSection.cliente({
    Key? key,
    required String userId,
    Future<DadosFatura?> Function()? carregar,
    Future<void> Function(String nif, String nome)? guardar,
  }) {
    return AdminFaturaNifSection(
      key: key,
      titulo: 'Dados de faturação do cliente',
      carregar: carregar ??
          () async => DadosFatura.deMapa(await Supabase.instance.client
              .from('client_billing_profile')
              .select('nif, nome')
              .eq('user_id', userId)
              .maybeSingle()),
      guardar: guardar ??
          (nif, nome) async {
            await Supabase.instance.client.rpc('admin_client_billing_set',
                params: {'p_user_id': userId, 'p_nif': nif, 'p_nome': nome});
          },
    );
  }

  final String titulo;
  final Future<DadosFatura?> Function() carregar;
  final Future<void> Function(String nif, String nome) guardar;

  @override
  State<AdminFaturaNifSection> createState() => _AdminFaturaNifSectionState();
}

class _AdminFaturaNifSectionState extends State<AdminFaturaNifSection> {
  DadosFatura? _dados;
  bool _aCarregar = true;
  bool _falhou = false;

  @override
  void initState() {
    super.initState();
    _ler();
  }

  Future<void> _ler() async {
    setState(() {
      _aCarregar = true;
      _falhou = false;
    });
    try {
      final d = await widget.carregar();
      if (!mounted) return;
      setState(() {
        _dados = d;
        _aCarregar = false;
      });
    } catch (e) {
      debugPrint('[AdminFaturaNif] leitura falhou: $e');
      if (!mounted) return;
      setState(() {
        _aCarregar = false;
        _falhou = true;
      });
    }
  }

  Future<void> _editar() async {
    final nifCtrl =
        TextEditingController(text: soDigitosNif(_dados?.nif));
    final nomeCtrl = TextEditingController(text: _dados?.nome ?? '');
    String? erro;
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('NIF (número de contribuinte)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('admin_fatura_nif_campo'),
                controller: nifCtrl,
                keyboardType: TextInputType.number,
                maxLength: 9,
                decoration: InputDecoration(
                  labelText: 'NIF (9 dígitos)',
                  helperText: 'Deixe vazio para apagar.',
                  errorText: erro,
                  counterText: '',
                ),
              ),
              TextField(
                key: const Key('admin_fatura_nome_campo'),
                controller: nomeCtrl,
                maxLength: 120,
                decoration: const InputDecoration(
                    labelText: 'Nome na fatura (opcional)', counterText: ''),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const Key('admin_fatura_salvar'),
              onPressed: () {
                final nif = soDigitosNif(nifCtrl.text);
                if (nif.isNotEmpty && !nifPtValido(nif)) {
                  setD(() => erro =
                      'NIF inválido (o dígito de controle não bate).');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    // Os controladores não se libertam aqui: a janela ainda está a fechar (a
    // animação de saída continua a ler os campos). Não têm ouvintes.
    final nif = soDigitosNif(nifCtrl.text);
    final nome = nomeCtrl.text.trim();
    if (confirmou != true || !mounted) return;
    try {
      await widget.guardar(nif, nome);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(nif.isEmpty ? 'NIF apagado.' : 'NIF salvo.')));
      await _ler();
    } catch (e) {
      debugPrint('[AdminFaturaNif] gravação falhou: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().contains('PEDIDO_SEM_CLIENTE')
              ? 'Este pedido não tem cliente: não dá para registrar o NIF.'
              : 'Erro ao salvar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _dados;
    return Card(
      key: const Key('admin_fatura_nif_cartao'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_outlined,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(widget.titulo,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (_aCarregar)
              const LinearProgressIndicator()
            else if (_falhou)
              Row(
                children: [
                  const Expanded(
                      child: Text('Não foi possível ler.',
                          style: TextStyle(color: AppColors.error))),
                  TextButton(onPressed: _ler, child: const Text('Tentar de novo')),
                ],
              )
            else
              Text(
                d == null
                    ? 'Sem NIF (consumidor final).'
                    : d.nome == null
                        ? 'NIF ${formatarNif(d.nif)}'
                        : 'NIF ${formatarNif(d.nif)} · ${d.nome}',
                key: const Key('admin_fatura_nif_texto'),
                style: const TextStyle(fontSize: 13),
              ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('admin_fatura_nif_editar'),
                onPressed: _aCarregar || _falhou ? null : _editar,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Editar NIF e nome'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Abre o cartão do CLIENTE numa janela (menu do cliente no painel).
Future<void> mostrarFaturacaoDoCliente(
  BuildContext context, {
  required String userId,
  required String rotulo,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(rotulo, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 420,
        child: AdminFaturaNifSection.cliente(userId: userId),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}
