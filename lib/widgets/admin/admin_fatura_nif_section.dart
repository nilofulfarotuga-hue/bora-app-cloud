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
///
/// M10 09/11/2026: no detalhe do PEDIDO aparece também a linha "NIF na caixa"
/// (o NIF que o entregador tinha de dar no caixa da loja não parceira ou do
/// Favor com compra, e se deu), lida de `driver_order_invoice_nif`.
class AdminFaturaNifSection extends StatefulWidget {
  const AdminFaturaNifSection({
    super.key,
    required this.titulo,
    required this.carregar,
    required this.guardar,
    this.carregarCaixa,
  });

  /// NIF e nome do PEDIDO [orderId].
  factory AdminFaturaNifSection.pedido({
    Key? key,
    required String orderId,
    Future<DadosFatura?> Function()? carregar,
    Future<void> Function(String nif, String nome)? guardar,
    Future<Object?> Function()? carregarCaixa,
  }) {
    return AdminFaturaNifSection(
      key: key,
      titulo: 'Fatura com NIF deste pedido',
      carregarCaixa: carregarCaixa ??
          () => Supabase.instance.client.rpc('driver_order_invoice_nif',
              params: {'p_order_id': orderId}),
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

  /// Só no PEDIDO: a resposta de `driver_order_invoice_nif` (null = sem linha).
  final Future<Object?> Function()? carregarCaixa;

  /// O texto da linha "NIF na caixa" (PT-BR), ou null quando não se aplica.
  static String? textoNifNaCaixa(Object? r) {
    if (r is! Map || r['ok'] != true) return null;
    if (r['mostrar'] != true) {
      if (r['loja_parceira'] == true) {
        return 'NIF na caixa: não se aplica (loja parceira — quem emite a fatura é a loja).';
      }
      // 10/11/2026: sem NIF do cliente o talão é consumidor final (o NIF da Bora nunca vai na caixa).
      return r['motivo'] == 'cliente_sem_nif'
          ? 'NIF na caixa: o cliente não pediu fatura com NIF — talão consumidor final.'
          : null;
    }
    final nif = formatarNif(r['nif']?.toString());
    // Só o NIF do cliente vai na caixa; outro (servidor antigo) não se mostra.
    final doCliente = r['tipo'] == 'cliente' || r['pediu_fatura'] == true;
    if (nif.isEmpty || !doCliente) return null;
    final c = r['confirmado'];
    final String estado;
    if (c is Map && c['dado'] == true) {
      estado = 'dado ✓';
    } else if (c is Map && c['dado'] == false) {
      final m = (c['motivo'] as String? ?? '').trim();
      estado = m.isEmpty ? 'não dado' : 'não dado: $m';
    } else {
      estado = 'ainda não confirmado';
    }
    return 'NIF na caixa (o que o entregador deu no caixa): $nif — '
        'do cliente — $estado';
  }

  @override
  State<AdminFaturaNifSection> createState() => _AdminFaturaNifSectionState();
}

class _AdminFaturaNifSectionState extends State<AdminFaturaNifSection> {
  DadosFatura? _dados;
  bool _aCarregar = true;
  bool _falhou = false;
  String? _caixa;

  @override
  void initState() {
    super.initState();
    _ler();
  }

  Future<void> _lerCaixa() async {
    final f = widget.carregarCaixa;
    if (f == null) return;
    try {
      final texto = AdminFaturaNifSection.textoNifNaCaixa(await f());
      if (mounted) setState(() => _caixa = texto);
    } catch (e) {
      // Sem a função no servidor (ou sem rede): a linha simplesmente não aparece.
      debugPrint('[AdminFaturaNif] NIF na caixa: $e');
    }
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
      // O NIF do pedido pode ter mudado: a linha "NIF na caixa" relê também.
      await _lerCaixa();
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
            if (_caixa != null) ...[
              const SizedBox(height: 4),
              Text(
                _caixa!,
                key: const Key('admin_nif_caixa_linha'),
                style: const TextStyle(fontSize: 13),
              ),
            ],
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
