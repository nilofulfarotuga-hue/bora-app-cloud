import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/small_order_fee.dart';
import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Admin Platform Settings — edit configurable parameters in `platform_settings`.
/// HIGH-RISK: changes propagate live; use with care. All changes audited.
class AdminPlatformSettingsScreen extends StatefulWidget {
  const AdminPlatformSettingsScreen({super.key});
  @override
  State<AdminPlatformSettingsScreen> createState() => _AdminPlatformSettingsScreenState();
}

class _AdminPlatformSettingsScreenState extends State<AdminPlatformSettingsScreen> {
  Map<String, List<_Setting>> _byCategory = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client.rpc('admin_list_settings',
          params: {'p_category': null});
      final list = (res as List)
          .map((e) => _Setting.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      final by = <String, List<_Setting>>{};
      for (final s in list) {
        if (_obsoleteDepositKeys.contains(s.key)) continue;
        by.putIfAbsent(s.category ?? 'other', () => []).add(s);
      }
      if (mounted) setState(() => _byCategory = by);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Bloco 4 — as 5 chaves de cancelamento são editáveis COM auditoria + motivo
  /// obrigatório (via RPC admin_update_cancel_setting). As restantes chaves
  /// financeiras continuam protegidas.
  static const _cancelKeys = <String>{
    'cancel_grace_seconds',
    'cancel_fee_before_dispatch_cents',
    'cancel_fee_after_accept_cents',
    'cancel_fee_after_accept_driver_cents',
    'cancel_fee_after_pickup_ratio',
  };
  bool _isCancelKey(String key) => _cancelKeys.contains(key);

  /// Whitelist operacional: só chaves de dispatch e operação de reservas são
  /// editáveis aqui. Tudo o resto (fees, comissões, markup, tokens, wallet,
  /// valores em cêntimos, Stripe) é READ-ONLY — alterar requer sessão dedicada.
  /// Fail-safe: chave nova/desconhecida nasce protegida.
  bool _isEditable(String key) {
    if (_isCancelKey(key)) return true; // Bloco 4 — editável com auditoria
    if (key.startsWith('robot_b_')) return true; // kill switches Robot B v4
    if (key.startsWith('dispatch_')) return true;
    // [botoes-navbar-eta 31/08] As 3 chaves eta_* (velocidade média do
    // fallback + intervalo de compra não-parceiro) são OPERACIONAIS — afinam
    // o tempo MOSTRADO ao cliente, nunca um valor cobrado ou pago. Autoridade
    // total do Danilo: ver e editar aqui, sem deploy.
    if (key.startsWith('eta_')) return true;
    if (key.startsWith('reservation_')) {
      const financialMarkers = ['cents', 'payout', 'prepayment', 'bora_service', 'credit'];
      return !financialMarkers.any(key.contains);
    }
    // TVDE parada adicional (CAMPO-02): só as chaves OPERACIONAIS são editáveis
    // aqui. As de dinheiro (tvde_stop_fee_cents = taxa do cliente,
    // tvde_stop_driver_cents = ganho do motorista) ficam blindadas — alterá-las
    // é ação 🔴 que escala a pagamentos-wallet.
    // `tvde_roundtrip_discount_pct` (a % de desconto do pacote ida+volta) É
    // editável aqui por decisão explícita do Danilo (2026-08-01): o painel admin
    // é a superfície onde o DONO mexe no preço do próprio produto — é a regra da
    // autoridade total, não um agente a alterar dinheiro sozinho. As chaves em
    // cêntimos (tvde_stop_fee_cents, tvde_stop_driver_cents) continuam blindadas.
    const tvdeOperational = {
      'tvde_max_stops',
      'tvde_stop_timer_seconds',
      'tvde_roundtrip_discount_pct',
      // 2026-08-13 — o interruptor "passada a graça, cancelar custa a corrida
      // toda". Foi ele que, combinado com o webhook cego (BUG 1), cobrou €5 ao
      // Danilo por uma corrida que nunca teve motorista. É booleano e não é um
      // valor em cêntimos: o dono tem de o poder desligar sem deploy.
      // A janela em si é `cancel_grace_seconds`, já editável acima (_cancelKeys).
      'tvde_cancel_full_after_grace',
      // Tecto do desconto por Bora Tokens (% do valor). Mesma regra de
      // autoridade total do `tvde_roundtrip_discount_pct`: é o preço do produto
      // da própria Bora. NOTA: até à migration 20260813200000 o TVDE tinha os
      // 50% CRAVADOS no SQL e ignorava esta chave — mexer aqui só afeta o TVDE
      // depois dessa migration estar aplicada.
      'token_payment_max_pct',
    };
    if (tvdeOperational.contains(key)) return true;
    // BLOCO E (2026-07-28) — reagendamento de marcações. São chaves
    // OPERACIONAIS (horas de antecedência, nº de reagendamentos, janela de
    // dias): não mexem em nenhum valor cobrado, por isso são editáveis aqui.
    const appointmentRescheduleOperational = {
      'appointment_reschedule_min_hours',
      'appointment_reschedule_max_count',
      'appointment_reschedule_max_days',
    };
    if (appointmentRescheduleOperational.contains(key)) return true;
    // FIM DO SINAL (2026-08-03) — a taxa por marcação e a taxa de walk-in são
    // o preço do PRÓPRIO produto da Bora. Editáveis aqui por decisão explícita
    // do Danilo (mesma regra do `tvde_roundtrip_discount_pct`): o painel admin
    // é a superfície onde o DONO mexe no preço do seu produto. Um agente
    // continua sem poder alterar estes valores sozinho.
    const appointmentFees = {
      'appointment_booking_fee_cents',
      'appointment_walkin_fee_cents',
    };
    if (appointmentFees.contains(key)) return true;
    // RESERVA AGENDADA (2026-08-19) — as 15 chaves `tvde_reservation_*`.
    // São todas OPERACIONAIS (janelas de tempo, contagens, interruptores):
    // regulam QUANDO se procura motorista, QUANDO se avisa e QUANDO se prende
    // a reserva. Nenhuma delas altera um valor cobrado ao cliente nem pago ao
    // motorista, por isso são editáveis aqui — ao lado do
    // `tvde_roundtrip_discount_pct`, pela mesma regra de autoridade total.
    //
    // Duas exceções que MEXEM EM DINHEIRO e por isso ficam de fora:
    //   - `tvde_reservation_driver_tokens` (tokens que o motorista ganha)
    //   - `tvde_reservation_late_cancel_fee_cents` (taxa cobrada ao cliente)
    // Alterá-las é ação 🔴 que escala a pagamentos-wallet.
    const reservationOperational = {
      'tvde_reservation_enabled',
      'tvde_reservation_min_advance_minutes',
      'tvde_reservation_max_advance_days',
      'tvde_reservation_offer_ttl_seconds',
      'tvde_reservation_retry_minutes',
      'tvde_reservation_stop_search_minutes',
      'tvde_reservation_lock_minutes',
      'tvde_reservation_activate_minutes',
      'tvde_reservation_force_redispatch_minutes',
      'tvde_reservation_reminder_minutes',
      'tvde_reservation_client_ask_hours',
      'tvde_reservation_free_cancel_hours',
      'tvde_reservation_payment_timeout_minutes',
    };
    if (reservationOperational.contains(key)) return true;
    // TAXA DE PEDIDO PEQUENO (2026-08-27). Mesma regra do
    // `appointment_booking_fee_cents` e do `tvde_roundtrip_discount_pct`: e o
    // preco do PROPRIO produto da Bora (a taxa fica toda para a plataforma,
    // nao e repassada a parceiro nem a estafeta), e o painel admin e a
    // superficie onde o DONO mexe no preco do seu produto. Um agente continua
    // sem poder alterar estes valores sozinho.
    //
    // `small_order_fee_enabled` e o interruptor que acende a taxa nos dois
    // lados ao mesmo tempo (cliente e servidor leem o mesmo valor).
    const smallOrderFeeKeys = {
      'min_order_cents',
      'small_order_fee_cents',
      'small_order_fee_enabled',
    };
    if (smallOrderFeeKeys.contains(key)) return true;
    // BLOCO 4E (2026-09-05) — mapa/navegação do TVDE. Corrigimos o cliente
    // sem ver o carro no mapa e o mapa do motorista a travar; todo o
    // comportamento novo ficou afinável por platform_settings para o Danilo
    // mexer sem esperar por build. São OPERACIONAIS: afinam o zoom/inclinação
    // da câmara, a sensibilidade de desvio de rota, a suavidade da animação
    // da câmara e a frequência de polling do cartão do motorista no ecrã do
    // cliente. NENHUMA altera um valor cobrado a cliente nem pago a
    // motorista — não são 🔴 zona vermelha.
    const tvdeNavOperational = {
      'tvde_nav_zoom',
      'tvde_nav_tilt',
      'tvde_nav_offroute_meters',
      'tvde_nav_offroute_fixes',
      'tvde_nav_reroute_min_seconds',
      'tvde_nav_camera_follow_ms',
      'tvde_driver_card_poll_seconds',
      // [Parte 2 · 05/09] Quando é que a posição do motorista deixa de ser de
      // confiança no mapa do cliente. Passados os `stale`, o carro pára de
      // animar e fica esbatido, com "última posição há X min"; passados os
      // `lost`, aparece "A ligar-se ao motorista". Antes disto, um motorista
      // com GPS morto parecia um motorista parado e o cliente não percebia
      // porquê. São segundos de ecrã — não são dinheiro.
      'tvde_driver_stale_seconds',
      'tvde_driver_lost_seconds',
    };
    if (tvdeNavOperational.contains(key)) return true;
    // BLOCO 4E (2026-09-05) — ETA do TVDE mostrado ao cliente. Mesma regra
    // do `eta_*` genérico (linha ~75): afinam só o TEMPO MOSTRADO no ecrã,
    // nunca um valor cobrado ou pago. Usam o prefixo `tvde_eta_`, não
    // `eta_`, por isso precisam de entrada própria aqui — o
    // `startsWith('eta_')` de cima não as apanha.
    const tvdeEtaClientOperational = {
      'tvde_eta_client_discount_pct',
      'tvde_eta_client_discount_max_min',
      'tvde_eta_client_floor_min',
      'tvde_eta_arriving_push_min',
    };
    if (tvdeEtaClientOperational.contains(key)) return true;
    // As chaves em cêntimos da parada adicional (tvde_stop_fee_cents = taxa
    // do cliente, tvde_stop_driver_cents = ganho do motorista) NÃO entram em
    // nenhum destes blocos — continuam blindadas (nota na linha ~81).
    return false;
  }

  /// Validação das três chaves da taxa de pedido pequeno.
  /// Devolve a mensagem de erro (PT-BR) ou `null` quando o valor serve.
  String? _validaTaxaPedidoPequeno(String key, dynamic valor) {
    switch (key) {
      case 'small_order_fee_enabled':
        return valor is bool
            ? null
            : 'Use true ou false (liga/desliga a taxa nos dois lados: app e servidor).';
      case 'min_order_cents':
        if (valor is! num || valor != valor.roundToDouble()) {
          return 'Use centavos INTEIROS. Exemplo: 1200 = 12,00 €.';
        }
        if (valor < 0 || valor > 100000) {
          return 'Fora da faixa permitida (0 a 100000 centavos = 1.000,00 €).';
        }
        return null;
      case 'small_order_fee_cents':
        if (valor is! num || valor != valor.roundToDouble()) {
          return 'Use centavos INTEIROS. Exemplo: 139 = 1,39 €.';
        }
        if (valor < 0 || valor > 2000) {
          return 'Fora da faixa permitida (0 a 2000 centavos = 20,00 €).';
        }
        return null;
      default:
        return null;
    }
  }

  /// FIM DO SINAL (2026-08-03) — chaves do sinal de €3 que a regra de negócio
  /// já não usa. `client_book_appointment` deixou de as ler e
  /// `compute_provider_weekly_payout` deixou de as somar. Ficam na tabela por
  /// histórico, mas não têm de poluir o painel.
  static const _obsoleteDepositKeys = <String>{
    'appointment_deposit_cents',
    'appointment_deposit_partner_cut_cents',
    'appointment_deposit_bora_cut_cents',
  };

  /// Nota do cadeado. As duas chaves de dinheiro da RESERVA AGENDADA ficam
  /// VISÍVEIS aqui (decisão Danilo 2026-08-20) — antes o risco era ninguém
  /// saber que existiam. Continuam em leitura: mexer nelas é decisão do dono,
  /// não de um agente.
  String _protectedNote(String key) {
    switch (key) {
      case 'tvde_reservation_driver_tokens':
        return '🔒 Somente leitura — mexe em DINHEIRO.\n'
            'São os Bora Tokens que o motorista ganha por cumprir uma reserva. '
            'Subir isto aumenta o custo de cada reserva para a Bora.\n'
            'Muda-se por decisão do Danilo.';
      case 'tvde_reservation_late_cancel_fee_cents':
        return '🔒 Somente leitura — mexe em DINHEIRO.\n'
            'É a taxa cobrada ao CLIENTE quando cancela a reserva fora da '
            'janela grátis (tvde_reservation_free_cancel_hours). Está a 0, ou '
            'seja, hoje não se cobra nada.\n'
            'Muda-se por decisão do Danilo.';
      default:
        return '🔒 Chave financeira/protegida — somente leitura.\n'
            'Alterar requer sessão dedicada com validação de impacto.';
    }
  }

  void _showProtectedInfo(_Setting s) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.lock, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(s.key, style: const TextStyle(fontSize: 15))),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (s.description != null)
              Text(s.description!, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Text('Valor atual: ${s.value}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Text(
              _protectedNote(s.key),
              style: const TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
        ],
      ),
    );
  }

  Future<void> _editSetting(_Setting s) async {
    final ctrl = TextEditingController(text: s.value.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.key),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (s.description != null) Text(s.description!, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Valor (JSON)',
                border: OutlineInputBorder(),
                hintText: 'ex: 250 ou 0.80 ou "abc"',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '⚠️ Esta alteração propaga-se live. Tens a certeza?',
              style: TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Atualizar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      // Try parse as number first, then as raw JSON, fallback to quoted string.
      final txt = ctrl.text.trim();
      dynamic parsed;
      final asNum = num.tryParse(txt);
      if (asNum != null) {
        parsed = asNum;
      } else if (txt == 'true' || txt == 'false') {
        parsed = txt == 'true';
      } else {
        parsed = txt;
      }
      // TAXA DE PEDIDO PEQUENO — validação antes de gravar. Um valor absurdo
      // aqui muda o que TODO cliente paga, por isso não passa sem verificação.
      final erro = _validaTaxaPedidoPequeno(s.key, parsed);
      if (erro != null) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(erro)));
        }
        return;
      }
      await Supabase.instance.client.rpc('admin_update_setting',
          params: {'p_key': s.key, 'p_value': parsed});
      // O app do cliente tem estes valores em cache: força a releitura para o
      // carrinho não continuar a mostrar o valor antigo.
      SmallOrderFeeService.esquecerCache();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Atualizado')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  /// Bloco 4 — edição auditada de uma taxa de cancelamento (motivo obrigatório).
  Future<void> _editCancelSetting(_Setting s) async {
    final ctrl = TextEditingController(text: s.value.toString());
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(s.key),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (s.description != null)
                Text(s.description!, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Novo valor (número)',
                  border: OutlineInputBorder(),
                  hintText: 'ex: 180 (seg) · 250 (cêntimos) · 1.0 (rácio)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: reasonCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Motivo (obrigatório)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setD(() {}),
              ),
              const SizedBox(height: 8),
              const Text(
                '⚠️ Taxa de cancelamento — propaga-se live e fica auditada.',
                style: TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: reasonCtrl.text.trim().length < 3
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Atualizar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final value = num.tryParse(ctrl.text.trim());
    if (value == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Valor inválido — usa um número.')));
      }
      return;
    }
    try {
      await Supabase.instance.client.rpc('admin_update_cancel_setting', params: {
        'p_key': s.key,
        'p_new_value': value,
        'p_reason': reasonCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Taxa atualizada e auditada')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  /// Bloco 4 — histórico das alterações de taxas (admin_audit_log).
  Future<void> _showCancelAudit() async {
    List<dynamic> rows = const [];
    try {
      final res = await Supabase.instance.client
          .rpc('admin_list_cancel_setting_audit');
      rows = (res as List?) ?? const [];
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Auditoria de taxas de cancelamento',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            if (rows.isEmpty) const Text('Sem alterações registadas.'),
            ...rows.map((r) {
              final m = (r as Map).cast<String, dynamic>();
              final d = (m['details'] as Map?)?.cast<String, dynamic>() ?? {};
              return ListTile(
                dense: true,
                title: Text(
                    '${m['entity_id_text']}: ${d['old_value']} → ${d['new_value']}'),
                subtitle: Text(
                    '${m['admin_email'] ?? ''} · ${d['reason'] ?? ''}\n${m['created_at'] ?? ''}'),
                isThreeLine: true,
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCancelAudit,
        icon: const Icon(Icons.history),
        label: const Text('Auditoria taxas'),
      ),
      appBar: const BoraScreenAppBar(title: 'Configurações'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.error)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    children: _byCategory.entries.map((entry) {
                      return ExpansionTile(
                        title: Text(entry.key.toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        children: entry.value.map((s) {
                          final editable = _isEditable(s.key);
                          return ListTile(
                            leading: editable
                                ? const Icon(Icons.edit_outlined,
                                    size: 18, color: AppColors.textSecondary)
                                : const Icon(Icons.lock_outline,
                                    size: 18, color: AppColors.textSubtle),
                            title: Text(s.key, style: const TextStyle(fontFamily: 'monospace')),
                            subtitle: s.description != null ? Text(s.description!) : null,
                            trailing: Text(s.value.toString(),
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            onTap: () => editable
                                ? (_isCancelKey(s.key)
                                    ? _editCancelSetting(s)
                                    : _editSetting(s))
                                : _showProtectedInfo(s),
                          );
                        }).toList(),
                      );
                    }).toList(),
                  ),
                ),
    );
  }
}

class _Setting {
  final String key;
  final dynamic value;
  final String? description;
  final String? category;
  _Setting({required this.key, required this.value, this.description, this.category});
  factory _Setting.fromJson(Map<String, dynamic> j) => _Setting(
        key: j['key'] as String,
        value: j['value'],
        description: j['description'] as String?,
        category: j['category'] as String?,
      );
}
