import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../services/modo_ocupado_service.dart';
import '../../utils/hora_lisboa.dart';
import '../modo_ocupado_ligado.dart';

/// "Modo ocupado" no painel do parceiro (C6 · 29/10/2026) — como o "busy mode" da
/// Uber Eats / Glovo / iFood. Botões +10 / +20 / +30 min e "Desligar".
///
/// Só se desenha com o interruptor `partner_busy_mode_enabled` ligado no painel
/// admin; desligado (o estado de fábrica) não ocupa espaço nenhum. Carregar noutro
/// botão TROCA o valor (não soma) e volta a contar 2 horas. Expira sozinho.
///
/// [inicial] é o que a loja já tem (`restaurants.busy_*`), para o cartão abrir já
/// com "Ocupado: +20 min até 15:30" se a loja estava ocupada.
class CartaoModoOcupado extends StatefulWidget {
  const CartaoModoOcupado({
    super.key,
    required this.restaurantId,
    this.inicial = EstadoOcupado.nenhum,
    this.api,
    this.agora,
  });

  final String restaurantId;
  final EstadoOcupado inicial;

  /// Só para testes: servidor falso.
  final ModoOcupadoApi? api;

  /// Só para testes: relógio fixo.
  final DateTime Function()? agora;

  @override
  State<CartaoModoOcupado> createState() => _CartaoModoOcupadoState();
}

class _CartaoModoOcupadoState extends State<CartaoModoOcupado> {
  late EstadoOcupado _estado = widget.inicial;
  bool _aMudar = false;

  ModoOcupadoApi? _apiCriada;
  ModoOcupadoApi get _api =>
      widget.api ?? (_apiCriada ??= ModoOcupadoSupabase());

  DateTime _agora() => widget.agora?.call() ?? DateTime.now();

  @override
  void didUpdateWidget(CartaoModoOcupado antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.inicial != widget.inicial) _estado = widget.inicial;
  }

  Future<void> _mudar(int minutos) async {
    if (_aMudar) return;
    setState(() => _aMudar = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final novo = await _api.definir(widget.restaurantId, minutos);
    if (!mounted) return;
    if (novo != null) {
      setState(() {
        _estado = novo;
        _aMudar = false;
      });
      messenger?.showSnackBar(SnackBar(
        content: Text(minutos == 0
            ? 'Modo ocupado desligado. Os clientes voltam a ver o tempo normal.'
            : 'Modo ocupado: +$minutos min${novo.ate == null ? '' : ' até às ${hhmmLisboa(novo.ate!)}'}. Desliga-se sozinho.'),
      ));
    } else {
      setState(() => _aMudar = false);
      messenger?.showSnackBar(SnackBar(
        content: Text(_api.ultimoErro == 'desligado'
            ? 'O modo ocupado não está ligado na plataforma.'
            : 'Não foi possível mudar o modo ocupado. Tenta de novo.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ModoOcupadoLigado(
      builder: (context, ligado) {
        if (!ligado) return const SizedBox.shrink();
        final agora = _agora();
        final ativo = _estado.ativoEm(agora);
        return Card(
          key: const Key('cartao_modo_ocupado'),
          margin: const EdgeInsets.only(top: 8),
          color: ativo ? AppColors.warning.withValues(alpha: 0.12) : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      ativo ? Icons.hourglass_top : Icons.hourglass_empty,
                      color: ativo ? AppColors.warning : AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Modo ocupado',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  ativo
                      ? _estado.textoEm(agora)
                      : 'Muitos pedidos? Avisa os clientes de que vai demorar mais. Volta ao normal sozinho ao fim de 2 horas.',
                  key: const Key('modo_ocupado_texto'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: ativo ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final m in kMinutosOcupado)
                      _botaoMinutos(m, selecionado: ativo && _estado.extraMinutos == m),
                    if (_aMudar)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    if (ativo)
                      TextButton(
                        key: const Key('btn_ocupado_desligar'),
                        style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                        onPressed: _aMudar ? null : () => _mudar(0),
                        child: const Text('Desligar'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _botaoMinutos(int m, {required bool selecionado}) {
    const estilo = Size(0, 48);
    final texto = Text('+$m min');
    return selecionado
        ? FilledButton(
            key: Key('btn_ocupado_$m'),
            style: FilledButton.styleFrom(minimumSize: estilo),
            onPressed: _aMudar ? null : () => _mudar(m),
            child: texto,
          )
        : OutlinedButton(
            key: Key('btn_ocupado_$m'),
            style: OutlinedButton.styleFrom(minimumSize: estilo),
            onPressed: _aMudar ? null : () => _mudar(m),
            child: texto,
          );
  }
}

/// Como se escolhe a hora (por defeito, o relógio do Material em 24 h).
typedef EscolherHora = Future<TimeOfDay?> Function(
    BuildContext context, TimeOfDay inicial);

Future<TimeOfDay?> _relogio24h(BuildContext context, TimeOfDay inicial) {
  return showTimePicker(
    context: context,
    initialTime: inicial,
    helpText: 'Fica pronto às…',
    builder: (ctx, child) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
      child: child ?? const SizedBox.shrink(),
    ),
  );
}

/// "Fica pronto às…" num pedido de entrega JÁ ACEITE (C6 · 29/10/2026). A loja
/// escolhe a hora e o servidor guarda-a em `orders.ready_at_promised`; o cliente vê
/// o tempo recalculado. Só aparece com o interruptor do modo ocupado ligado.
class BotaoFicaProntoAs extends StatefulWidget {
  const BotaoFicaProntoAs({
    super.key,
    required this.orderId,
    this.atual,
    this.api,
    this.agora,
    this.escolherHora,
  });

  final String orderId;

  /// A hora já prometida neste pedido (null = nenhuma).
  final DateTime? atual;

  /// Só para testes.
  final ModoOcupadoApi? api;
  final DateTime Function()? agora;
  final EscolherHora? escolherHora;

  @override
  State<BotaoFicaProntoAs> createState() => _BotaoFicaProntoAsState();
}

class _BotaoFicaProntoAsState extends State<BotaoFicaProntoAs> {
  late DateTime? _hora = widget.atual;
  bool _aMudar = false;

  ModoOcupadoApi? _apiCriada;
  ModoOcupadoApi get _api =>
      widget.api ?? (_apiCriada ??= ModoOcupadoSupabase());

  DateTime _agora() => widget.agora?.call() ?? DateTime.now();

  @override
  void didUpdateWidget(BotaoFicaProntoAs antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.atual != widget.atual) _hora = widget.atual;
  }

  Future<void> _escolher() async {
    if (_aMudar) return;
    final agora = _agora();
    final sugestao = horaLisboa(agora.add(const Duration(minutes: 15)));
    final t = await (widget.escolherHora ?? _relogio24h)(
        context, TimeOfDay(hour: sugestao.hour, minute: sugestao.minute));
    if (t == null || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final instante = instanteDoFicaPronto(
        hora: t.hour, minuto: t.minute, agora: _agora());
    if (instante == null) {
      messenger?.showSnackBar(const SnackBar(
          content: Text('Escolhe uma hora que seja daqui a menos de 4 horas.')));
      return;
    }
    await _gravar(instante, messenger);
  }

  Future<void> _gravar(DateTime? instante, ScaffoldMessengerState? messenger) async {
    setState(() => _aMudar = true);
    final ok = await _api.prometerPronto(widget.orderId, instante);
    if (!mounted) return;
    setState(() {
      _aMudar = false;
      if (ok) _hora = instante;
    });
    messenger?.showSnackBar(SnackBar(
      content: Text(!ok
          ? 'Não foi possível guardar a hora. Tenta de novo.'
          : instante == null
              ? 'Hora retirada.'
              : 'Combinado: fica pronto às ${hhmmLisboa(instante)}. O estafeta é chamado a tempo.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ModoOcupadoLigado(
      builder: (context, ligado) {
        if (!ligado) return const SizedBox.shrink();
        final hora = _hora;
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                key: const Key('btn_fica_pronto_as'),
                style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: _aMudar ? null : _escolher,
                icon: const Icon(Icons.schedule),
                label: Text(hora == null
                    ? 'Fica pronto às…'
                    : 'Pronto às ${hhmmLisboa(hora)} · mudar'),
              ),
              if (hora != null)
                TextButton(
                  key: const Key('btn_tirar_hora'),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: _aMudar ? null : () => _gravar(null, ScaffoldMessenger.maybeOf(context)),
                  child: const Text('Tirar'),
                ),
            ],
          ),
        );
      },
    );
  }
}
