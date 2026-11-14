// Painel da farmácia (app do parceiro) — missão farmacias-loja-2026-11-14, bloco 2 e 3.
// Tudo aqui só se desenha em lojas com restaurants.category = 'pharmacy':
// - FarmaciaAbrirFecharCartao: botão grande "Abrir/Fechar a loja agora" + horário por dia.
// - FarmaciaCondicoesCartao: "3 meses sem comissão até DD/MM; depois 10 %; pagamento semanal".
// - BotaoWhatsAppCliente: abrir o WhatsApp do cliente do pedido.
// - FarmaciaChegadaParceiro: "um produto só chega às HH:MM" (bloco 3).
// Textos em PT-PT, direto (sem o dicionário .tr), como parceiro_prescricoes_screen.dart.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../models/farmacia_chegada.dart';
import '../../models/order_model.dart';
import '../../models/restaurant_model.dart';
import '../../services/farmacia_chegada_service.dart';
import '../../services/notification_service.dart';
import '../../utils/contact_validators.dart';
import '../../utils/hora_lisboa.dart';

/// true se a loja é uma farmácia.
bool eFarmacia(RestaurantModel r) => r.category == BusinessCategory.pharmacy;

String _dd(int n) => n.toString().padLeft(2, '0');

/// "14:30" em hora de Lisboa.
String hhmmFarmacia(DateTime instante) {
  final l = horaLisboa(instante);
  return '${_dd(l.hour)}:${_dd(l.minute)}';
}

/// "14/02" em hora de Lisboa.
String ddmmFarmacia(DateTime instante) {
  final l = horaLisboa(instante);
  return '${_dd(l.day)}/${_dd(l.month)}';
}

// ───────────────────────────────────────────────────────────── 1. abrir / fechar

/// Botão grande para abrir ou fechar a loja já (restaurants.is_online, o mesmo do
/// "Aberta/Fechada" da barra) e atalho para o horário de cada dia, domingo incluído.
class FarmaciaAbrirFecharCartao extends StatefulWidget {
  const FarmaciaAbrirFecharCartao({
    super.key,
    required this.restaurant,
    required this.aoMudar,
    required this.aoAbrirHorario,
  });

  final RestaurantModel restaurant;

  /// Muda restaurants.is_online. Devolve false se falhou (o ecrã avisa).
  final Future<bool> Function(bool abrir) aoMudar;
  final VoidCallback aoAbrirHorario;

  @override
  State<FarmaciaAbrirFecharCartao> createState() => _FarmaciaAbrirFecharCartaoState();
}

class _FarmaciaAbrirFecharCartaoState extends State<FarmaciaAbrirFecharCartao> {
  bool _aMudar = false;

  Future<void> _mudar(bool abrir) async {
    if (_aMudar) return;
    if (!abrir) {
      final confirmou = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Fechar a loja agora?'),
          content: const Text(
              'Os clientes deixam de poder fazer pedidos até voltar a abrir. Os pedidos que já tem continuam.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
      if (confirmou != true || !mounted) return;
    }
    setState(() => _aMudar = true);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await widget.aoMudar(abrir);
    if (!mounted) return;
    setState(() => _aMudar = false);
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? (abrir ? 'Loja aberta. Já pode receber pedidos.' : 'Loja fechada.')
          : 'Não foi possível mudar o estado da loja. Verifique a ligação e tente de novo.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.restaurant;
    if (!eFarmacia(r)) return const SizedBox.shrink();
    final ligada = r.isOnline;
    final abertaAgora = r.isOpenNow();
    final titulo = !ligada
        ? 'Loja fechada'
        : (abertaAgora ? 'Loja aberta' : 'Loja ligada, fora do horário');
    final subtitulo = !ligada
        ? 'Os clientes não conseguem fazer pedidos.'
        : (abertaAgora
            ? 'Os clientes podem fazer pedidos agora.'
            : 'Recebe pedidos quando chegar a hora de abrir.');
    final cor = ligada ? AppColors.primary : AppColors.error;
    return Card(
      key: const Key('farmacia_abrir_fechar'),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cor.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(ligada ? Icons.storefront : Icons.store_mall_directory_outlined, color: cor, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(titulo,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cor)),
                  const SizedBox(height: 2),
                  Text(subtitulo, style: const TextStyle(color: AppColors.textSecondary)),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: ligada
                  ? OutlinedButton.icon(
                      key: const Key('farmacia_fechar_loja'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      onPressed: _aMudar ? null : () => _mudar(false),
                      icon: const Icon(Icons.lock_outline),
                      label: const Text('Fechar a loja agora'),
                    )
                  : FilledButton.icon(
                      key: const Key('farmacia_abrir_loja'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      onPressed: _aMudar ? null : () => _mudar(true),
                      icon: const Icon(Icons.lock_open),
                      label: const Text('Abrir a loja agora'),
                    ),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              key: const Key('farmacia_horario'),
              onPressed: widget.aoAbrirHorario,
              icon: const Icon(Icons.schedule, size: 18),
              label: const Text('Horário de cada dia (domingo incluído)'),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────── 2. condições

/// Texto das condições da farmácia (puro, para testes).
///   início vazio → "3 meses sem comissão a contar do dia em que a loja abrir ao público. ..."
///   início no futuro → "3 meses sem comissão até 14/02. Depois, 10 % sobre as vendas. ..."
///   início já passou → "Comissão de 10 % sobre as vendas desde 14/02. ..."
String textoCondicoesFarmacia({
  required double? pct,
  required DateTime? inicio,
  int meses = 3,
  DateTime? agora,
}) {
  const pagamento = 'Pagamento semanal.';
  if (pct == null || pct <= 0) {
    return 'Sem comissão sobre as vendas. $pagamento';
  }
  // 0.10 * 100 dá 10.000000000000002: arredonda-se à décima antes de escrever.
  final p = (pct * 1000).round() / 10;
  final pctTxt = p == p.roundToDouble()
      ? '${p.round()} %'
      : '${p.toStringAsFixed(1).replaceAll('.', ',')} %';
  final m = meses > 0 ? meses : 3;
  final mesesTxt = m == 1 ? '1 mês' : '$m meses';
  if (inicio == null) {
    return '$mesesTxt sem comissão a contar do dia em que a loja abrir ao público. '
        'Depois, $pctTxt sobre as vendas. $pagamento';
  }
  final now = agora ?? DateTime.now();
  if (inicio.isAfter(now)) {
    return '$mesesTxt sem comissão até ${ddmmFarmacia(inicio)}. '
        'Depois, $pctTxt sobre as vendas. $pagamento';
  }
  return 'Comissão de $pctTxt sobre as vendas desde ${ddmmFarmacia(inicio)}. $pagamento';
}

class _Condicoes {
  const _Condicoes({required this.pct, required this.inicio, required this.meses});
  final double? pct;
  final DateTime? inicio;
  final int meses;
}

double? _numero(Object? v) => v == null ? null : double.tryParse(v.toString());

/// Condições da farmácia à vista no separador Ganhos (lê partner_extra_commission_pct e
/// partner_extra_commission_starts_at da loja e pharmacy_extra_commission_months).
class FarmaciaCondicoesCartao extends StatefulWidget {
  const FarmaciaCondicoesCartao({super.key, required this.restaurant, this.aoVerExtrato});

  final RestaurantModel restaurant;

  /// Abre o extrato pedido a pedido (o "Ver detalhe de ganhos" que já existe).
  final VoidCallback? aoVerExtrato;

  @override
  State<FarmaciaCondicoesCartao> createState() => _FarmaciaCondicoesCartaoState();
}

class _FarmaciaCondicoesCartaoState extends State<FarmaciaCondicoesCartao> {
  late final Future<_Condicoes?> _f = eFarmacia(widget.restaurant) ? _ler() : Future.value(null);

  Future<_Condicoes?> _ler() async {
    try {
      final sb = Supabase.instance.client;
      final r = await sb
          .from('restaurants')
          .select('partner_extra_commission_pct, partner_extra_commission_starts_at')
          .eq('id', widget.restaurant.id)
          .maybeSingle();
      var meses = 3;
      try {
        final s = await sb
            .from('platform_settings')
            .select('value')
            .eq('key', 'pharmacy_extra_commission_months')
            .maybeSingle();
        meses = _numero(s?['value'])?.round() ?? 3;
      } catch (_) {
        // sem a definição fica o valor do contrato (3 meses)
      }
      return _Condicoes(
        pct: _numero(r?['partner_extra_commission_pct']),
        inicio: DateTime.tryParse(r?['partner_extra_commission_starts_at']?.toString() ?? ''),
        meses: meses,
      );
    } catch (e) {
      debugPrint('[FarmaciaCondicoes] $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!eFarmacia(widget.restaurant)) return const SizedBox.shrink();
    return FutureBuilder<_Condicoes?>(
      future: _f,
      builder: (context, snap) {
        final c = snap.data;
        if (c == null) return const SizedBox.shrink();
        return Card(
          key: const Key('farmacia_condicoes'),
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.handshake_outlined, color: AppColors.primary),
                  SizedBox(width: 8),
                  Text('As suas condições',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 8),
                Text(
                  textoCondicoesFarmacia(pct: c.pct, inicio: c.inicio, meses: c.meses),
                  style: const TextStyle(fontSize: 15, height: 1.35),
                ),
                const SizedBox(height: 4),
                const Text(
                  'O cliente paga o preço do catálogo e a farmácia recebe o valor inteiro dos produtos.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                if (widget.aoVerExtrato != null) ...[
                  const SizedBox(height: 4),
                  TextButton.icon(
                    key: const Key('farmacia_ver_extrato'),
                    onPressed: widget.aoVerExtrato,
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: const Text('Ver extrato pedido a pedido'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// ───────────────────────────────────────────────────────────── 3. WhatsApp

/// Ligação do WhatsApp para o telefone do cliente (https://wa.me/<indicativo><número>).
/// Telemóvel português (com ou sem +351) → wa.me/351XXXXXXXXX. Número estrangeiro só
/// com indicativo (+ ou 00). Sem número utilizável → null (o botão não aparece).
Uri? linkWhatsAppDoCliente(String? telefone) {
  final bruto = (telefone ?? '').trim();
  if (bruto.isEmpty) return null;
  final pt = normalizarTelemovelPt(bruto);
  if (pt != null) return Uri.parse('https://wa.me/351$pt');
  var d = bruto.replaceAll(RegExp(r'[\s\-().]'), '');
  if (d.startsWith('+')) {
    d = d.substring(1);
  } else if (d.startsWith('00')) {
    d = d.substring(2);
  } else {
    return null;
  }
  if (!RegExp(r'^\d{8,15}$').hasMatch(d)) return null;
  return Uri.parse('https://wa.me/$d');
}

/// Botão do WhatsApp do cliente (ao lado do "Ligar cliente").
class BotaoWhatsAppCliente extends StatelessWidget {
  const BotaoWhatsAppCliente({super.key, required this.telefone});
  final String? telefone;

  @override
  Widget build(BuildContext context) {
    final uri = linkWhatsAppDoCliente(telefone);
    if (uri == null) return const SizedBox.shrink();
    return IconButton(
      key: const Key('farmacia_whatsapp_cliente'),
      icon: const Icon(Icons.chat_outlined, size: 20, color: AppColors.primary),
      tooltip: 'WhatsApp do cliente',
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!ok) {
          messenger.showSnackBar(const SnackBar(
              content: Text('Não foi possível abrir o WhatsApp neste telemóvel.')));
        }
      },
    );
  }
}

// ───────────────────────────────────────────────────────────── 4. chega mais tarde

/// "Um produto só chega às HH:MM" no cartão do pedido da farmácia.
/// Mostra o estado (à espera do cliente / espera / sem o produto / cancelou) e o botão
/// para marcar enquanto o pedido ainda não tem estafeta. Se o pedido ainda não foi aceite,
/// o servidor aceita-o ao marcar.
class FarmaciaChegadaParceiro extends StatefulWidget {
  const FarmaciaChegadaParceiro({super.key, required this.order});

  final OrderModel order;

  /// Igual ao servidor (farmacia_chegada_marcar): pedido da app com entrega, ainda na loja.
  static bool podeMarcar(OrderModel o) =>
      o.isPartnerStore &&
      o.serviceType == OrderServiceType.restaurant &&
      o.assignedDriverId == null &&
      (o.status == OrderStatus.created || o.status == OrderStatus.preparing);

  @override
  State<FarmaciaChegadaParceiro> createState() => _FarmaciaChegadaParceiroState();
}

class _FarmaciaChegadaParceiroState extends State<FarmaciaChegadaParceiro> {
  Stream<List<FarmaciaChegada>>? _stream;
  bool _aEnviar = false;

  @override
  void initState() {
    super.initState();
    try {
      _stream = FarmaciaChegadaService.instance.doPedido(widget.order.id);
    } catch (e) {
      // Sem Supabase (ex.: testes) o cartão fica como estava.
      debugPrint('[FarmaciaChegada] $e');
    }
  }

  Future<void> _marcar() async {
    if (_aEnviar) return;
    final escolha = await showModalBottomSheet<_EscolhaChegada>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EscolherChegadaSheet(order: widget.order),
    );
    if (escolha == null || !mounted) return;
    setState(() => _aEnviar = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FarmaciaChegadaService.instance.marcar(
        orderId: widget.order.id,
        chegaAs: escolha.chegaAs,
        linhaIdx: escolha.linhaIdx,
      );
      unawaited(cancelPartnerOrderNotification(widget.order.id));
      messenger.showSnackBar(SnackBar(
        content: Text('Cliente avisado. O pedido fica guardado até às '
            '${hhmmFarmacia(escolha.chegaAs)} enquanto ele não responde.'),
      ));
    } on FarmaciaChegadaErro catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.mensagem)));
    } finally {
      if (mounted) setState(() => _aEnviar = false);
    }
  }

  Future<void> _anular(FarmaciaChegada c) async {
    if (_aEnviar) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anular a hora marcada?'),
        content: const Text('O pedido volta a seguir já, sem esperar. O cliente é avisado.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Anular')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _aEnviar = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FarmaciaChegadaService.instance.anular(c.id);
      messenger.showSnackBar(const SnackBar(content: Text('Feito. O cliente foi avisado.')));
    } on FarmaciaChegadaErro catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.mensagem)));
    } finally {
      if (mounted) setState(() => _aEnviar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _stream;
    if (s == null) return const SizedBox.shrink();
    return StreamBuilder<List<FarmaciaChegada>>(
      stream: s,
      builder: (context, snap) {
        // Sem a tabela no servidor (ou sem rede) não se mostra nada.
        if (snap.hasError || !snap.hasData) return const SizedBox.shrink();
        final atual = FarmaciaChegada.maisRecente(snap.data!);
        final pode = FarmaciaChegadaParceiro.podeMarcar(widget.order);
        final mostrarBotao = pode && (atual == null || !atual.estado.viva);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (atual != null && atual.estado != EstadoChegada.anulado)
              _EstadoChegadaParceiro(
                chegada: atual,
                aoAnular: atual.estado.viva && pode && !_aEnviar ? () => _anular(atual) : null,
              ),
            if (mostrarBotao) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('farmacia_chega_mais_tarde'),
                onPressed: _aEnviar ? null : _marcar,
                icon: const Icon(Icons.schedule, size: 18),
                label: Text(widget.order.status == OrderStatus.created
                    ? 'Aceitar — um produto só chega mais tarde'
                    : 'Um produto só chega mais tarde'),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _EstadoChegadaParceiro extends StatelessWidget {
  const _EstadoChegadaParceiro({required this.chegada, this.aoAnular});

  final FarmaciaChegada chegada;
  final VoidCallback? aoAnular;

  @override
  Widget build(BuildContext context) {
    final hora = hhmmFarmacia(chegada.chegaAs);
    final quem = chegada.produtoNome != null ? '"${chegada.produtoNome}"' : 'O pedido';
    final (String texto, Color cor, IconData icone) = switch (chegada.estado) {
      EstadoChegada.pendente => (
          '$quem só chega às $hora. À espera da resposta do cliente — o pedido fica guardado até lá.',
          AppColors.warning,
          Icons.hourglass_top,
        ),
      EstadoChegada.esperar => (
          'O cliente espera. Pedido agendado para as $hora — o estafeta é chamado perto da hora.',
          AppColors.primary,
          Icons.event_available,
        ),
      EstadoChegada.tirar => (
          'O cliente prefere sem ${chegada.produtoNome != null ? '"${chegada.produtoNome}"' : 'o produto'}. '
              'Tire-o em "Marcar em falta" — o cliente recebe a diferença.',
          AppColors.error,
          Icons.remove_shopping_cart_outlined,
        ),
      EstadoChegada.cancelar => (
          'O cliente cancelou sem custo. Já não precisa de preparar.',
          AppColors.error,
          Icons.cancel_outlined,
        ),
      EstadoChegada.anulado => ('', AppColors.textSecondary, Icons.schedule),
    };
    return Container(
      key: const Key('farmacia_chegada_estado'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cor.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: cor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, height: 1.3)),
          ),
          if (aoAnular != null)
            TextButton(
              onPressed: aoAnular,
              child: Text(chegada.estado == EstadoChegada.esperar ? 'Já chegou' : 'Anular'),
            ),
        ],
      ),
    );
  }
}

/// O que a farmácia escolheu na folha: a linha (null = o pedido todo) e a hora.
class _EscolhaChegada {
  const _EscolhaChegada({required this.linhaIdx, required this.chegaAs});
  final int? linhaIdx;
  final DateTime chegaAs;
}

/// Próximo múltiplo de 5 minutos (para não marcar 14:37).
DateTime _arredondar5(DateTime t) {
  final m = t.minute % 5;
  final base = DateTime(t.year, t.month, t.day, t.hour, t.minute);
  return m == 0 ? base : base.add(Duration(minutes: 5 - m));
}

class _EscolherChegadaSheet extends StatefulWidget {
  const _EscolherChegadaSheet({required this.order});
  final OrderModel order;

  @override
  State<_EscolherChegadaSheet> createState() => _EscolherChegadaSheetState();
}

class _EscolherChegadaSheetState extends State<_EscolherChegadaSheet> {
  /// Linha escolhida; -1 = o pedido todo; null = ainda nada.
  int? _linha;
  DateTime? _chegaAs;
  int? _horasEscolhidas;

  void _daquiA(int horas) => setState(() {
        _horasEscolhidas = horas;
        _chegaAs = _arredondar5(DateTime.now().add(Duration(hours: horas)));
      });

  Future<void> _outraHora() async {
    final agora = DateTime.now();
    final sugestao = horaLisboa(agora.add(const Duration(hours: 2)));
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: sugestao.hour, minute: sugestao.minute),
      helpText: 'A que horas chega?',
    );
    if (t == null || !mounted) return;
    final hoje = horaLisboa(agora);
    var instante = instanteDeLisboa(DateTime(hoje.year, hoje.month, hoje.day, t.hour, t.minute));
    if (!instante.isAfter(agora)) {
      instante = instanteDeLisboa(DateTime(hoje.year, hoje.month, hoje.day + 1, t.hour, t.minute));
    }
    setState(() {
      _horasEscolhidas = null;
      _chegaAs = instante.toLocal();
    });
  }

  @override
  Widget build(BuildContext context) {
    final itens = widget.order.items;
    final pronto = _linha != null && _chegaAs != null;
    Widget opcao(int valor, String texto) => ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: Icon(
            _linha == valor ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            color: _linha == valor ? AppColors.primary : AppColors.textSecondary,
          ),
          title: Text(texto),
          onTap: () => setState(() => _linha = valor),
        );
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('O que só chega mais tarde?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text(
                'O cliente é avisado e escolhe: esperar, tirar o produto ou cancelar sem custo.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < itens.length; i++)
                opcao(i, '${itens[i].quantity} × ${itens[i].name}'),
              opcao(-1, 'O pedido todo'),
              const SizedBox(height: 8),
              const Text('A que horas chega?', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final h in const [1, 2, 3, 4])
                    ChoiceChip(
                      label: Text('Daqui a $h h'),
                      selected: _horasEscolhidas == h,
                      onSelected: (_) => _daquiA(h),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.access_time, size: 18),
                    label: const Text('Outra hora'),
                    onPressed: _outraHora,
                  ),
                ],
              ),
              if (_chegaAs != null) ...[
                const SizedBox(height: 8),
                Text('Chega às ${hhmmFarmacia(_chegaAs!)}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('farmacia_chegada_avisar'),
                onPressed: pronto
                    ? () => Navigator.pop(
                          context,
                          _EscolhaChegada(
                            linhaIdx: _linha == -1 ? null : _linha,
                            chegaAs: _chegaAs!,
                          ),
                        )
                    : null,
                child: const Text('Avisar o cliente'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Voltar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
