import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../l10n/tr.dart';
import '../../models/chat_message.dart';
import '../../models/order_edit.dart';
import '../../models/order_model.dart';
import '../../screens/chat_screen.dart';
import '../../services/interruptores_app.dart';

/// Contas da janela de troca (adendo 4 · item 4, 29/10/2026). Funções puras.
///
/// Quando a loja marca um produto em falta num pedido já aceite, o cliente
/// tem [minutos] para pedir uma troca à loja. É só aviso e contagem no ecrã:
/// o total do pedido e o dinheiro continuam a mudar pelo caminho do servidor
/// que já existia (`partner_propose_order_edit`), sem reembolso novo.
class JanelaTroca {
  JanelaTroca._();

  /// Minutos de recurso quando o painel não responde.
  static const int minutosPorDefeito = 10;

  /// Tempo que falta (nunca negativo).
  static Duration restante({
    required DateTime desde,
    required DateTime agora,
    required int minutos,
  }) {
    final fim = desde.add(Duration(minutes: minutos));
    final falta = fim.difference(agora);
    return falta.isNegative ? Duration.zero : falta;
  }

  static bool aberta({
    required DateTime desde,
    required DateTime agora,
    required int minutos,
  }) =>
      restante(desde: desde, agora: agora, minutos: minutos) > Duration.zero;

  /// "9:42".
  static String contagem(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds - m * 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Quando a janela abriu: a altura em que a loja aplicou a mudança.
  static DateTime desdeDoGrupo(OrderEditGrupo g) =>
      g.linhas.first.aplicadoEm ?? g.criadoEm;
}

/// Pedidos cujo aviso o cliente já fechou ("Está bem, fico sem").
final Set<String> _gruposDispensados = <String>{};

/// O que o CLIENTE vê por baixo do aviso "Produto em falta": a contagem e dois
/// botões (pedir troca à loja pelo chat, ou ficar sem o produto). Passada a
/// janela, desaparece.
class JanelaTrocaCliente extends StatefulWidget {
  const JanelaTrocaCliente({
    super.key,
    required this.grupo,
    required this.order,
    this.agora,
  });

  final OrderEditGrupo grupo;
  final OrderModel order;

  /// Só para testes: relógio fixo.
  final DateTime Function()? agora;

  @override
  State<JanelaTrocaCliente> createState() => _JanelaTrocaClienteState();
}

class _JanelaTrocaClienteState extends State<JanelaTrocaCliente> {
  bool _ligado = true;
  int _minutos = JanelaTroca.minutosPorDefeito;
  Timer? _relogio;

  DateTime _agora() => (widget.agora ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _ler();
    _relogio = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _ler() async {
    final cfg = InterruptoresApp.instance;
    final ligado = await cfg.ligado(InterruptoresApp.esgotadoAviso);
    final min = await cfg.inteiro(InterruptoresApp.esgotadoMinutos);
    if (!mounted) return;
    setState(() {
      _ligado = ligado;
      if (min > 0) _minutos = min;
    });
  }

  @override
  void dispose() {
    _relogio?.cancel();
    super.dispose();
  }

  void _pedirTroca() {
    final o = widget.order;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          order: o,
          senderType: ChatSenderType.client,
          chatTarget: ChatTarget.partner,
          conversationType: resolveConversationType(
              ChatSenderType.client, o.status, ChatTarget.partner),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.grupo.grupoId;
    if (!_ligado || _gruposDispensados.contains(id)) {
      return const SizedBox.shrink();
    }
    final falta = JanelaTroca.restante(
      desde: JanelaTroca.desdeDoGrupo(widget.grupo),
      agora: _agora(),
      minutos: _minutos,
    );
    if (falta == Duration.zero) return const SizedBox.shrink();
    return Padding(
      key: const Key('janela_troca_cliente'),
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tens {0} min para pedir uma troca à loja. Se preferires ficar sem ele, não precisas de fazer nada.'
                .trArgs([_minutos]),
            style: const TextStyle(fontSize: 16, height: 1.3),
          ),
          const SizedBox(height: 4),
          Text(
            'Faltam {0}'.trArgs([JanelaTroca.contagem(falta)]),
            key: const Key('janela_troca_contagem'),
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.primary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const Key('btn_pedir_troca'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size(0, 48),
                ),
                onPressed: _pedirTroca,
                icon: const Icon(Icons.chat_bubble_outline, size: 20),
                label: Text('Pedir troca'.tr),
              ),
              OutlinedButton(
                key: const Key('btn_ficar_sem'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () => setState(() => _gruposDispensados.add(id)),
                child: Text('Ficar sem ele'.tr),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// O que o PARCEIRO vê por baixo do "Em falta": que o cliente foi avisado e
/// quanto tempo tem para pedir a troca (para a loja saber que ainda pode
/// receber um pedido de troca pelo chat).
class AvisoTrocaParceiro extends StatefulWidget {
  const AvisoTrocaParceiro({super.key, required this.grupo, this.agora});

  final OrderEditGrupo grupo;
  final DateTime Function()? agora;

  @override
  State<AvisoTrocaParceiro> createState() => _AvisoTrocaParceiroState();
}

class _AvisoTrocaParceiroState extends State<AvisoTrocaParceiro> {
  bool _ligado = true;
  int _minutos = JanelaTroca.minutosPorDefeito;
  Timer? _relogio;

  DateTime _agora() => (widget.agora ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _ler();
    _relogio = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _ler() async {
    final cfg = InterruptoresApp.instance;
    final ligado = await cfg.ligado(InterruptoresApp.esgotadoAviso);
    final min = await cfg.inteiro(InterruptoresApp.esgotadoMinutos);
    if (!mounted) return;
    setState(() {
      _ligado = ligado;
      if (min > 0) _minutos = min;
    });
  }

  @override
  void dispose() {
    _relogio?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ligado) return const SizedBox.shrink();
    final falta = JanelaTroca.restante(
      desde: JanelaTroca.desdeDoGrupo(widget.grupo),
      agora: _agora(),
      minutos: _minutos,
    );
    final texto = falta == Duration.zero
        ? 'O prazo do cliente para pedir troca já terminou.'
        : 'O cliente foi avisado e ainda tem ${JanelaTroca.contagem(falta)} para pedir uma troca pelo chat.';
    return Padding(
      key: const Key('aviso_troca_parceiro'),
      padding: const EdgeInsets.only(top: 4, left: 2),
      child: Text(texto,
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
    );
  }
}

/// Push ao cliente (pelo `notify-client` que já existe) a dizer que um produto
/// ficou em falta e que pode pedir troca. Melhor esforço: se falhar, o aviso
/// no ecrã do pedido (tempo real) continua lá.
Future<void> avisarClienteDeProdutoEmFalta({
  required OrderModel order,
  required String resumo,
  required int minutos,
}) async {
  final cliente = order.userId;
  if (cliente == null || cliente.isEmpty) return;
  try {
    await Supabase.instance.client.functions.invoke('notify-client', body: {
      'clientId': cliente,
      'orderId': order.id,
      'title': 'Produto em falta no teu pedido',
      'body': '$resumo. Tens $minutos min para pedir uma troca à loja.',
    });
  } catch (e) {
    debugPrint('[JanelaTroca] push ao cliente falhou (não é grave): $e');
  }
}
