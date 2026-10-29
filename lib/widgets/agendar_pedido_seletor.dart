/// AGENDAR PEDIDOS (item 5 do adendo 5, 29/10/2026) — o seletor do cliente no
/// carrinho: "Entregar agora" ou "Agendar" (dia + janela de 30 min, até 7 dias).
///
/// Só aparece com o interruptor `scheduled_orders_enabled` ligado. Com a loja
/// FECHADA agora, "Entregar agora" fica desligado e a primeira janela livre
/// vem já escolhida (o cliente só confirma ou troca). A hora fica em
/// [AgendarPedidoEstado]; o carrinho grava-a no pedido depois de ele existir
/// (ver `CartStore.finishOrder` e o ecrã de pagamento).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../l10n/tr.dart';
import '../models/restaurant_model.dart';
import '../services/agendar_pedido.dart';
import '../services/agendar_pedido_service.dart';
import '../stores/cart_store.dart';
import '../stores/restaurant_store.dart';

/// O que o carrinho põe no ecrã: lê o carrinho e a loja e mostra o seletor
/// (ou nada). Uma só linha no `cart_screen.dart`.
class AgendarPedidoNoCarrinho extends StatefulWidget {
  const AgendarPedidoNoCarrinho({super.key});

  @override
  State<AgendarPedidoNoCarrinho> createState() => _AgendarPedidoNoCarrinhoState();
}

class _AgendarPedidoNoCarrinhoState extends State<AgendarPedidoNoCarrinho> {
  @override
  void initState() {
    super.initState();
    // A configuração pode ainda não ter chegado quando o carrinho abre.
    unawaited(AgendarPedidoEstado.instance.carregarConfig());
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartStore>();
    if (!cart.agendamentoDisponivel) return const SizedBox.shrink();
    final loja = context.watch<RestaurantStore>().restaurantById(cart.vendorRestaurantId);
    if (loja == null) return const SizedBox.shrink();
    return AgendarPedidoSeletor(
      key: ValueKey('agendar-${loja.id}'),
      restaurantId: loja.id,
      horas: loja.businessHours,
      pausaAte: loja.pausaAte,
      lojaFechadaAgora: cart.lojaFechadaAgora,
    );
  }
}

class AgendarPedidoSeletor extends StatefulWidget {
  const AgendarPedidoSeletor({
    super.key,
    required this.restaurantId,
    required this.horas,
    required this.lojaFechadaAgora,
    this.pausaAte,
    this.estado,
    this.relogio,
  });

  final String restaurantId;
  final BusinessHours horas;
  final bool lojaFechadaAgora;
  final DateTime? pausaAte;

  /// Só para testes: outro estado (com a sua porta de mentira).
  final AgendarPedidoEstado? estado;

  /// Só para testes: um relógio fixo.
  final DateTime Function()? relogio;

  @override
  State<AgendarPedidoSeletor> createState() => _AgendarPedidoSeletorState();
}

class _AgendarPedidoSeletorState extends State<AgendarPedidoSeletor> {
  late final AgendarPedidoEstado _estado =
      widget.estado ?? AgendarPedidoEstado.instance;

  bool _agendar = false;
  DateTime? _dia;
  List<JanelaAgendada> _janelas = const [];
  bool _aCarregar = false;
  int _geracao = 0;

  DateTime _agora() => (widget.relogio ?? DateTime.now)();

  List<DateTime> get _dias => diasComJanelas(
        horas: widget.horas,
        agora: _agora(),
        maxDias: _estado.config.maxDias,
        antecedenciaMin: _estado.config.antecedenciaMin,
        pausaAte: widget.pausaAte,
      );

  @override
  void initState() {
    super.initState();
    _estado.addListener(_aoMudarEstado);
    final jaEscolheu = _estado.escolhaPara(widget.restaurantId);
    _agendar = widget.lojaFechadaAgora || jaEscolheu;
    if (_agendar) {
      final escolha = _estado.escolha;
      _dia = jaEscolheu && escolha != null
          ? escolha.dia
          : (_dias.isEmpty ? null : _dias.first);
      if (_dia != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _dia != null) unawaited(_carregarJanelas(_dia!));
        });
      }
    }
  }

  @override
  void didUpdateWidget(AgendarPedidoSeletor old) {
    super.didUpdateWidget(old);
    // A loja abriu/fechou enquanto o ecrã estava aberto.
    if (widget.lojaFechadaAgora && !_agendar) _mudarModo(true);
  }

  @override
  void dispose() {
    _estado.removeListener(_aoMudarEstado);
    super.dispose();
  }

  void _aoMudarEstado() {
    if (mounted) setState(() {});
  }

  void _mudarModo(bool agendar) {
    setState(() => _agendar = agendar);
    if (!agendar) {
      _estado.limpar();
      return;
    }
    final dias = _dias;
    _dia ??= dias.isEmpty ? null : dias.first;
    if (_dia != null) unawaited(_carregarJanelas(_dia!));
  }

  Future<void> _carregarJanelas(DateTime dia) async {
    final minha = ++_geracao;
    setState(() {
      _dia = dia;
      _aCarregar = true;
    });
    List<JanelaAgendada> lista;
    try {
      lista = await _estado.api.janelas(widget.restaurantId, dia);
    } catch (_) {
      // Sem resposta do servidor: mostra o que o horário da loja diz. O
      // servidor volta a validar quando o pedido é gravado.
      lista = janelasDoDia(
        horas: widget.horas,
        dia: dia,
        agora: _agora(),
        maxDias: _estado.config.maxDias,
        antecedenciaMin: _estado.config.antecedenciaMin,
        pausaAte: widget.pausaAte,
      );
    }
    if (!mounted || minha != _geracao) return;
    setState(() {
      _janelas = lista;
      _aCarregar = false;
    });
    final atual = _estado.escolha;
    final aindaValida = atual != null &&
        _estado.escolhaPara(widget.restaurantId) &&
        lista.contains(atual);
    // Loja fechada: a primeira janela livre já vem escolhida.
    if (!aindaValida && widget.lojaFechadaAgora && lista.isNotEmpty && _agendar) {
      _estado.escolher(widget.restaurantId, lista.first);
    } else if (!aindaValida && atual != null && atual.dia == dia) {
      _estado.limpar();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_estado.ligado) return const SizedBox.shrink();
    final dias = _dias;
    final escolha = _estado.escolhaPara(widget.restaurantId) ? _estado.escolha : null;
    return Container(
      key: const Key('agendar-seletor'),
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quando queres receber?'.tr,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            key: const Key('agendar-modo'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment<bool>(
                value: false,
                enabled: !widget.lojaFechadaAgora,
                label: Text('Entregar agora'.tr),
                icon: const Icon(Icons.flash_on, size: 18),
              ),
              ButtonSegment<bool>(
                value: true,
                label: Text('Agendar'.tr),
                icon: const Icon(Icons.event, size: 18),
              ),
            ],
            selected: {_agendar},
            onSelectionChanged: (s) => _mudarModo(s.first),
          ),
          if (widget.lojaFechadaAgora) ...[
            const SizedBox(height: 6),
            Text(
              'A loja está fechada agora. Escolhe quando queres receber.'.tr,
              key: const Key('agendar-fechada'),
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
          if (_agendar) ...[
            const SizedBox(height: 10),
            if (dias.isEmpty)
              Text(
                'Esta loja não aceita pedidos agendados neste momento.'.tr,
                key: const Key('agendar-sem-dias'),
                style: const TextStyle(fontSize: 13, color: AppColors.error),
              )
            else ...[
              SizedBox(
                height: 40,
                child: ListView.separated(
                  key: const Key('agendar-dias'),
                  scrollDirection: Axis.horizontal,
                  itemCount: dias.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final d = dias[i];
                    final sel = _dia != null && _dia == d;
                    return ChoiceChip(
                      key: Key('agendar-dia-${d.year}-${d.month}-${d.day}'),
                      label: Text(rotuloDoDia(d, _agora())),
                      selected: sel,
                      onSelected: (_) => _carregarJanelas(d),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              if (_aCarregar)
                Text('A carregar horários…'.tr,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))
              else if (_janelas.isEmpty)
                Text('Sem horários livres neste dia.'.tr,
                    key: const Key('agendar-sem-janelas'),
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))
              else
                Wrap(
                  key: const Key('agendar-janelas'),
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final j in _janelas)
                      ChoiceChip(
                        key: Key('agendar-janela-${j.horas}'),
                        label: Text(j.horas),
                        selected: escolha == j,
                        onSelected: (_) => _estado.escolher(widget.restaurantId, j),
                      ),
                  ],
                ),
            ],
            const SizedBox(height: 8),
            if (escolha != null) ...[
              Text(
                textoAgendadoPara(escolha),
                key: const Key('agendar-resumo'),
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.primaryDark),
              ),
              const SizedBox(height: 2),
              Text(
                'Podes cancelar sem custo até 1 h antes.'.tr,
                key: const Key('agendar-cancelar'),
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ] else if (dias.isNotEmpty)
              Text(
                'Escolhe uma hora para continuar.'.tr,
                key: const Key('agendar-falta'),
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
          ],
        ],
      ),
    );
  }
}
