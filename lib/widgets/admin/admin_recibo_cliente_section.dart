// Painel admin (PT-BR) — "Recibo do cliente (e-mail)" (08/11/2026, missão
// m1-dinheiro-favores, bloco 4d). Em todo pedido entregue o servidor manda um
// recibo por e-mail ao cliente (tabela recibos_clientes). Aqui o admin vê o
// estado (enviado / falhou / sem e-mail / pendente / desligado), o e-mail, a
// hora do envio e o detalhe; pode pedir "Reenviar recibo" (RPC
// admin_recibo_reenviar, fica no log de auditoria) e abrir o PDF guardado
// ("Ver recibo": link assinado de 10 minutos do balde privado recibos-clientes).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../utils/hora_lisboa.dart';
import '../../utils/ofertas_em_palavras.dart' show servidorAindaSemIsto;

const String kReciboFuncaoNaoPublicada = 'Função ainda não publicada no servidor';

/// Estado do recibo em PT-BR (texto, cor).
(String, Color) estadoReciboTexto(String? estado) => switch (estado) {
      'enviado' => ('Enviado', AppColors.success),
      'falhou' => ('Falhou (o envio do e-mail deu erro — veja o detalhe)', AppColors.error),
      'sem_email' => ('Sem e-mail (o cliente não tem e-mail na conta)', AppColors.warning),
      'pendente' => ('Pendente (envio pedido, aguardando o servidor)', AppColors.info),
      'desligado' => (
          'Desligado (o recibo por e-mail está desligado em Configurações: recibo_cliente_email_enabled)',
          AppColors.textSecondary
        ),
      _ => ('Desconhecido (${estado ?? '—'})', AppColors.textSecondary),
    };

class AdminReciboClienteSection extends StatefulWidget {
  const AdminReciboClienteSection({
    super.key,
    required this.orderId,
    this.carregar,
    this.reenviar,
  });

  final String orderId;

  /// Só para testes.
  final Future<Map<String, dynamic>> Function(String orderId)? carregar;
  final Future<Map<String, dynamic>> Function(String orderId)? reenviar;

  static Future<Map<String, dynamic>> carregarDoServidor(String orderId) async {
    final r = await Supabase.instance.client
        .rpc('admin_recibo_pedido', params: {'p_order_id': orderId});
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> reenviarNoServidor(String orderId) async {
    final r = await Supabase.instance.client
        .rpc('admin_recibo_reenviar', params: {'p_order_id': orderId});
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  /// Mensagem PT-BR da resposta de admin_recibo_reenviar.
  static String mensagemReenvio(Map<String, dynamic> r) {
    if (r['ok'] == true) {
      return 'Reenvio pedido. O e-mail sai em alguns segundos — toque em atualizar para ver o estado.';
    }
    return switch (r['error']) {
      'pedido_nao_entregue' => 'Só dá para pedidos entregues (status atual: ${r['status'] ?? '—'}).',
      'servidor_sem_chave' =>
        'O servidor está sem a chave para chamar o envio (cofre/vault). Avise o suporte técnico.',
      'desligado' => 'O recibo por e-mail está desligado em Configurações.',
      _ => 'Não foi possível: ${r['error'] ?? 'erro desconhecido'}',
    };
  }

  @override
  State<AdminReciboClienteSection> createState() => _AdminReciboClienteSectionState();
}

class _AdminReciboClienteSectionState extends State<AdminReciboClienteSection> {
  bool _loading = true;
  bool _semServidor = false;
  bool _aEnviar = false;
  bool _aAbrir = false;
  String? _erro;
  Map<String, dynamic> _recibo = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _erro = null;
      _semServidor = false;
    });
    try {
      final r = await (widget.carregar ?? AdminReciboClienteSection.carregarDoServidor)(widget.orderId);
      if (!mounted) return;
      setState(() {
        _recibo = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _semServidor = servidorAindaSemIsto(e);
        _erro = _semServidor ? null : e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _reenviar() async {
    setState(() => _aEnviar = true);
    final messenger = ScaffoldMessenger.of(context);
    String msg;
    try {
      final r = await (widget.reenviar ?? AdminReciboClienteSection.reenviarNoServidor)(widget.orderId);
      msg = AdminReciboClienteSection.mensagemReenvio(r);
    } catch (e) {
      msg = servidorAindaSemIsto(e) ? kReciboFuncaoNaoPublicada : 'Erro ao reenviar: $e';
    }
    if (!mounted) return;
    setState(() => _aEnviar = false);
    messenger.showSnackBar(SnackBar(content: Text(msg)));
    await _load();
  }

  Future<void> _verRecibo(String caminho) async {
    final bucket = '${_recibo['bucket'] ?? 'recibos-clientes'}';
    // O caminho é relativo ao balde; se vier com o nome do balde à frente, tira-se.
    final path = caminho.startsWith('$bucket/') ? caminho.substring(bucket.length + 1) : caminho;
    setState(() => _aAbrir = true);
    final messenger = ScaffoldMessenger.of(context);
    String? url;
    try {
      url = await Supabase.instance.client.storage.from(bucket).createSignedUrl(path, 600);
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Não deu para abrir o recibo: $e')));
      }
    }
    if (!mounted) return;
    setState(() => _aAbrir = false);
    if (url == null) return;
    var abriu = false;
    try {
      abriu = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      abriu = false;
    }
    if (!abriu && mounted) _mostrarLink(url);
  }

  void _mostrarLink(String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Link do recibo (vale 10 minutos)'),
        content: SelectableText(url, style: const TextStyle(fontSize: 12)),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: url)),
            child: const Text('Copiar'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
        ],
      ),
    );
  }

  Widget _linha(String rotulo, String valor, {Color? cor}) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: '$rotulo: ', style: const TextStyle(color: AppColors.textSecondary)),
            TextSpan(text: valor, style: TextStyle(fontWeight: FontWeight.w600, color: cor)),
          ]),
          style: const TextStyle(fontSize: 13),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final existe = _recibo['existe'] == true;
    final caminho = '${_recibo['storage_path'] ?? ''}'.trim();
    final detalhe = '${_recibo['detalhe'] ?? ''}'.trim();
    final email = '${_recibo['email'] ?? ''}'.trim();
    final (estadoTxt, estadoCor) = estadoReciboTexto(_recibo['estado'] as String?);

    return Card(
      key: const Key('admin_recibo_cliente'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.receipt_long_outlined, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Recibo do cliente (e-mail)',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'Atualizar',
                onPressed: _loading ? null : _load,
              ),
            ]),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              )
            else if (_semServidor)
              const Text(
                '$kReciboFuncaoNaoPublicada. O recibo por e-mail começa a funcionar quando a migração '
                'do recibo do cliente for aplicada.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              )
            else if (_erro != null)
              Text('Não foi possível carregar: $_erro',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.error))
            else ...[
              if (!existe)
                const Text(
                  'Ainda não há registro de recibo para este pedido (pedido entregue antes de o recibo '
                  'por e-mail existir, ou pedido de teste). "Enviar recibo" manda agora.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                )
              else ...[
                _linha('Estado', estadoTxt, cor: estadoCor),
                _linha('E-mail', email.isEmpty ? '—' : email),
                _linha('Enviado em', dataHoraLisboa(_recibo['enviado_em'])),
                _linha('Tentativas', '${_recibo['tentativas'] ?? 0}'),
                if (detalhe.isNotEmpty) _linha('Detalhe', detalhe),
              ],
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, children: [
                OutlinedButton.icon(
                  key: const Key('btn_recibo_reenviar'),
                  onPressed: _aEnviar ? null : _reenviar,
                  icon: const Icon(Icons.forward_to_inbox_outlined, size: 18),
                  label: Text(_aEnviar
                      ? 'Enviando…'
                      : existe
                          ? 'Reenviar recibo'
                          : 'Enviar recibo'),
                ),
                if (caminho.isNotEmpty)
                  TextButton.icon(
                    key: const Key('btn_recibo_ver'),
                    onPressed: _aAbrir ? null : () => _verRecibo(caminho),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(_aAbrir ? 'Abrindo…' : 'Ver recibo'),
                  ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
