// BLOCO A (2026-05-18) — Inbox de notificações admin.
//
// Lê da tabela admin_notifications (criada na migration
// 20260518000100_admin_notifications_infra.sql). Suporta:
//   • Filtro por severity (all/critical/high/medium/low)
//   • Filtro por event_type
//   • Marcar como lido (1-tap)
//   • Arquivar (botão "Arquivar" à vista e swipe)
//   • Contador de não-lidos
//   • Pull-to-refresh
//   • Realtime para notificações novas
//   • Detalhes do aviso (toque sem tela de destino, ou toque longo)
//
// PT-BR (Regra 6).
//
// app-15-11 (auditoria S5): cada tipo de aviso tem nome em português (eram
// 48 tipos na base, a maioria aparecia em inglês, ex. "robot_b_auto_fix"),
// o nível também ("Crítico", "Alto", "Médio", "Baixo"), "Arquivar" passou a
// ser um botão, e os avisos com link '/admin' deixaram de abrir outro painel
// por cima da caixa.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/tvde_visibilidade.dart';
import '../../utils/hora_lisboa_ext.dart';

class AdminNotificationsInboxScreen extends StatefulWidget {
  const AdminNotificationsInboxScreen({super.key});

  /// Nome em português de cada tipo de aviso (`admin_notifications.event_type`).
  /// Os 48 tipos que existiam na base a 15/11/2026 e os que o código já
  /// conhecia. Tipo novo sem nome aqui aparece como "Aviso: <tipo>".
  static const Map<String, String> rotulosPorTipo = {
    // Pedidos de entrega
    'new_order': 'Pedido novo',
    'phone_order_call': 'Ligar à loja (pedido por telefone)',
    'order_orphan': 'Pedido órfão',
    'pedido_no_vermelho': 'Pedido no vermelho',
    'dispatch_ttl_auto_cancel': 'Cancelado: ninguém aceitou a tempo',
    'order_cancel_in_flight': 'Cancelado em rota',
    'order_cancel_mid_delivery': 'Cancelado no meio da entrega',
    'order_driver_direct_update': 'Entregador trocado direto na base',
    'order_refund_high': 'Reembolso alto',
    'order_refund_needed': 'Reembolso a fazer',
    'order_refund_auto': 'Reembolso automático',
    'pedido_reativado_pos_pagamento': 'Pedido reativado depois do pagamento',
    'catalog_price_gap': 'Preço desatualizado no catálogo',
    'catalogo_extra_mais_caro': 'Extra mais caro no balcão',
    'driver_phantom': 'Entregador fantasma',
    'driver_ghost': 'Entregador fantasma',
    'favor_diferenca_por_acertar': 'Favor com diferença por acertar',
    'nif_talao_diferente': 'NIF do talão diferente',
    // Dinheiro
    'reimbursement_pending': 'Reembolso de talão pendente',
    'weekly_closeout': 'Fecho da semana',
    'ledger_orphan': 'Livro de contas sem pedido',
    'pagamento_sem_etiqueta': 'Pagamento sem pedido',
    'pagamento_em_pedido_cancelado': 'Pagamento num pedido cancelado',
    'order_refund_failed': 'Reembolso de pedido falhou',
    'tip_refund_failed': 'Reembolso de gorjeta falhou',
    'stripe_failures': 'Cartões a falhar (3 ou mais)',
    'stripe_repeated_fails': 'Cartão a falhar várias vezes',
    'stripe_duas_contas': 'Stripe — duas contas',
    'stripe_connect_payout_failed': 'Pagamento pela Stripe Connect falhou',
    'wallet_debt_high': 'Dívida alta',
    'checkin_tecto_aviso': 'Check-in perto do teto do mês',
    // Pessoas e candidaturas
    'new_signup': 'Cadastro novo',
    'driver_application_pending': 'Candidatura de entregador',
    'partner_application_pending': 'Candidatura de parceiro',
    'service_provider_application_pending': 'Candidatura de serviço',
    'cleaner_application_pending': 'Candidatura de limpeza',
    'provider_atividade_enviada': 'Comprovativo de atividade enviado',
    // Suporte e reclamações
    'support_ticket_new': 'Pedido de ajuda novo',
    'support_user_message': 'Mensagem ao suporte',
    'complaint_high': 'Reclamação grave',
    // Serviços, limpeza, lavagem, reservas
    'new_appointment': 'Marcação nova',
    'appointment_awaiting_confirmation': 'Marcação por confirmar',
    'reservation_no_show': 'Cliente faltou à reserva',
    'cleaning_booking_new': 'Limpeza nova',
    'cleaning_booking_cancelled': 'Limpeza cancelada',
    'cleaning_series_cancelamentos': 'Limpezas em série canceladas',
    'cleaning_unpaid': 'Limpeza por pagar',
    'carwash_booking_new': 'Lavagem nova',
    // Bora Motorista (arquivo)
    'tvde_ride_new': 'Corrida nova (Bora Motorista)',
    'tvde_reservation_new': 'Reserva nova (Bora Motorista)',
    'tvde_reservation_no_driver': 'Reserva sem motorista',
    'tvde_reservation_redispatch': 'Reserva chamou outro motorista',
    'tvde_payment_failed': 'Corrida: cliente não conseguiu pagar',
    'tvde_reembolso_falhou': 'Reembolso de corrida falhou',
    'tvde_driver_application_pending': 'Pedido de acesso ao Bora Motorista',
    'tvde_compensacao_falhou': 'Compensação ao motorista falhou',
    'tvde_cancel_fee_nao_cobrada': 'Taxa de cancelamento não cobrada',
    // Robôs e sistema
    'robot_b_auto_fix': 'Correção automática do robô',
    'robot_b_suggestion': 'Sugestão do robô',
    'robot_b_digest': 'Resumo semanal do robô',
    'skill_suggestion_critical': 'Sugestão de skill crítica',
    'skill_proposal_realtime': 'Proposta de skill nova',
    'robo_documentos_pronto': 'Robô de documentos: candidato pronto',
    'cortex_red_proposal': 'Proposta da zona vermelha (Córtex)',
    'security_key_abuse': 'Chave roubada em uso',
    'funcao_sem_resposta': 'Função do servidor sem resposta',
    'system_report': 'Relatório do sistema',
    // Testes
    'teste': 'Teste',
    'teste_push_admin': 'Teste do aviso no telemóvel',
    'teste_aviso_pedido': 'Teste do aviso de pedido',
    'test_alertas': 'Teste de alertas',
  };

  /// Nome do tipo em português; tipo desconhecido fica "Aviso: <tipo>".
  ///
  /// 26/11/2026 (arquivo-tvde-total): com o Bora Motorista fechado, os avisos
  /// antigos `tvde_*` mostram-se como arquivo.
  static String rotuloDoTipo(String tipo) {
    final r = rotulosPorTipo[tipo] ?? 'Aviso: ${tipo.replaceAll('_', ' ')}';
    if (tipo.startsWith('tvde') && !TvdeVisibilidade.aberto) {
      return 'Arquivo (Bora Motorista): $r';
    }
    return r;
  }

  /// Nível do aviso em português (`severity`).
  static String nivelPtBr(String? severidade) => switch (severidade) {
        'critical' => 'Crítico',
        'high' => 'Alto',
        'medium' => 'Médio',
        'low' => 'Baixo',
        'warning' => 'Atenção',
        _ => severidade ?? '—',
      };

  /// Para onde leva o toque num aviso. `null` = fica na caixa e abre os
  /// detalhes. Os avisos "CHAVE ROUBADA EM USO" vinham com '/admin' (o
  /// próprio painel) e o toque abria outro painel por cima da caixa: vão
  /// para "Saúde das chaves". Outros com '/admin' (relatórios, testes) ou sem
  /// link mostram os detalhes aqui mesmo.
  static String? rotaDoAviso(String? tipo, String? link) {
    if (tipo == 'security_key_abuse') return '/admin/system-health';
    final l = (link ?? '').trim();
    if (!l.startsWith('/admin/')) return null;
    return l;
  }

  @override
  State<AdminNotificationsInboxScreen> createState() =>
      _AdminNotificationsInboxScreenState();
}

class _AdminNotificationsInboxScreenState
    extends State<AdminNotificationsInboxScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;
  String _severityFilter = 'all'; // all/critical/high/medium/low
  bool _hideArchived = true;
  RealtimeChannel? _channel;

  static const _severityColors = {
    'critical': Colors.red,
    'high': Colors.orange,
    'medium': Colors.amber,
    'low': Colors.blueGrey,
  };

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    if (_channel != null) _supabase.removeChannel(_channel!);
    super.dispose();
  }

  void _subscribeRealtime() {
    _channel = _supabase.channel('admin_notifications_inbox');
    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'admin_notifications',
          callback: (_) {
            if (mounted) _load();
          },
        )
        .subscribe();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var query = _supabase
          .from('admin_notifications')
          .select('id, created_at, event_type, severity, '
              'entity_type, entity_id, summary, payload, deep_link, '
              'read_at, archived_at');
      if (_severityFilter != 'all') {
        query = query.eq('severity', _severityFilter);
      }
      if (_hideArchived) {
        query = query.isFilter('archived_at', null);
      }
      final res = await query.order('created_at', ascending: false).limit(200);
      if (!mounted) return;
      setState(() {
        _rows = (res as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _markRead(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    if (id == null || row['read_at'] != null) return;
    try {
      await _supabase.from('admin_notifications').update({
        'read_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
      if (mounted) _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    }
  }

  /// PARTE A (2026-07-17) — tocar numa notificação marca-a lida E navega para
  /// o `deep_link` (ex.: /admin/drivers/approval). Antes o tap só marcava lida.
  /// app-15-11 (S5): o destino vem de `rotaDoAviso` — '/admin' (o próprio
  /// painel) já não abre outro painel por cima: mostra os detalhes aqui.
  Future<void> _openRow(Map<String, dynamic> row) async {
    await _markRead(row);
    if (!mounted) return;
    final rota = AdminNotificationsInboxScreen.rotaDoAviso(
        row['event_type']?.toString(), row['deep_link']?.toString());
    if (rota != null) {
      Navigator.of(context).pushNamed(rota);
    } else {
      _mostrarDetalhes(row);
    }
  }

  /// Detalhes de um aviso, sem sair da caixa: o texto inteiro, o tipo, o
  /// nível, a hora e o que o servidor guardou em `payload`.
  void _mostrarDetalhes(Map<String, dynamic> row) {
    final tipo = (row['event_type'] as String?) ?? 'unknown';
    final payload = row['payload'];
    final campos = <MapEntry<String, String>>[
      if (payload is Map)
        for (final e in payload.entries)
          if (e.value != null && '${e.value}'.trim().isNotEmpty)
            MapEntry(_nomeDoCampo('${e.key}'), _valorDoCampo(e.value)),
    ];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, controle) => ListView(
          controller: controle,
          padding: const EdgeInsets.all(20),
          children: [
            Text(AdminNotificationsInboxScreen.rotuloDoTipo(tipo),
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              'Nível ${AdminNotificationsInboxScreen.nivelPtBr(row['severity'] as String?)}'
              ' · ${_dataHora(row['created_at'] as String?)} (hora de Lisboa)',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            SelectableText((row['summary'] as String?) ?? ''),
            if (campos.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Detalhes',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final c in campos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: SelectableText.rich(TextSpan(children: [
                    TextSpan(
                        text: '${c.key}: ',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(text: c.value),
                  ])),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Nomes em português dos campos mais comuns do `payload`.
  static const _camposPtBr = {
    'ip': 'IP',
    'org': 'Rede',
    'rede': 'Rede',
    'country': 'País',
    'pais': 'País',
    'path': 'Caminho',
    'caminhos': 'Caminhos',
    'method': 'Método',
    'metodo': 'Método',
    'requests': 'Pedidos',
    'pedidos': 'Pedidos',
    'first': 'Primeira vez',
    'primeira': 'Primeira vez',
    'last': 'Última vez',
    'ultima': 'Última vez',
    'user_agent': 'Programa que chamou',
    'motivo': 'Motivo',
    'note': 'Nota',
    'nota': 'Nota',
    'client_name': 'Cliente',
    'client_phone': 'Telefone',
    'question': 'Pergunta',
    'subject': 'Assunto',
    'order_id': 'Pedido',
  };

  static String _nomeDoCampo(String k) => _camposPtBr[k] ?? k;

  /// Listas viram "a, b"; horas ISO viram hora de Lisboa.
  static String _valorDoCampo(Object? v) {
    if (v is List) return v.map((e) => '$e').join(', ');
    final s = '$v';
    if (RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(s) &&
        DateTime.tryParse(s) != null) {
      return _dataHora(s);
    }
    return s;
  }

  /// "14/11/2026 12:08", em hora de Lisboa.
  static String _dataHora(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso)?.toLisboa();
    if (d == null) return '—';
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(d.day)}/${p(d.month)}/${d.year} ${p(d.hour)}:${p(d.minute)}';
  }

  Future<void> _archive(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    if (id == null) return;
    try {
      await _supabase.from('admin_notifications').update({
        'archived_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
      if (mounted) _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _markAllRead() async {
    try {
      await _supabase
          .from('admin_notifications')
          .update({
            'read_at': DateTime.now().toUtc().toIso8601String(),
          })
          .isFilter('read_at', null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Todas marcadas como lidas.'),
            backgroundColor: AppColors.primary));
        _load();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    }
  }

  String _fmtDateTime(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso)?.toLisboa();
    if (d == null) return iso;
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inHours < 1) return '${diff.inMinutes} min';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Color _colorFor(String severity) =>
      _severityColors[severity] ?? Colors.blueGrey;

  IconData _iconFor(String eventType) {
    switch (eventType) {
      case 'order_refund_high':
      case 'order_cancel_in_flight':
        return Icons.money_off;
      case 'wallet_debt_high':
        return Icons.warning_amber;
      case 'reservation_no_show':
        return Icons.event_busy;
      case 'skill_suggestion_critical':
        return Icons.psychology;
      case 'complaint_high':
        return Icons.report_problem;
      case 'order_orphan':
        return Icons.shopping_bag;
      case 'driver_phantom':
        return Icons.two_wheeler;
      case 'stripe_failures':
        return Icons.credit_card_off;
      case 'pedido_no_vermelho':
        return Icons.trending_down;
      // [17/10/2026 · cancelamento tardio TVDE] os dois alertas da regra
      // abrem /admin/tvde/cancelamentos (deep_link gravado pelo servidor).
      case 'tvde_compensacao_falhou':
        return Icons.money_off;
      case 'tvde_cancel_fee_nao_cobrada':
        return Icons.warning_amber;
      case 'security_key_abuse':
        return Icons.vpn_key_off_outlined;
      default:
        return Icons.notifications;
    }
  }

  // app-15-11 (S5): o nome de cada tipo vive em
  // `AdminNotificationsInboxScreen.rotulosPorTipo` (todos os tipos da base).

  @override
  Widget build(BuildContext context) {
    final unreadCount = _rows.where((r) => r['read_at'] == null).length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        title: Row(
          children: [
            const Text('Notificações',
                style: TextStyle(fontWeight: FontWeight.bold)),
            if (unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('$unreadCount',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
              ),
            ],
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Filtrar por nível',
            initialValue: _severityFilter,
            onSelected: (v) {
              setState(() => _severityFilter = v);
              _load();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'all', child: Text('Todos os níveis')),
              PopupMenuItem(value: 'critical', child: Text('Crítico')),
              PopupMenuItem(value: 'high', child: Text('Alto')),
              PopupMenuItem(value: 'medium', child: Text('Médio')),
              PopupMenuItem(value: 'low', child: Text('Baixo')),
            ],
            icon: const Icon(Icons.filter_list),
          ),
          IconButton(
            tooltip: 'Marcar todas como lidas',
            icon: const Icon(Icons.done_all),
            onPressed: unreadCount > 0 ? _markAllRead : null,
          ),
          IconButton(
            tooltip: _hideArchived ? 'Mostrar arquivadas' : 'Esconder arquivadas',
            icon: Icon(_hideArchived ? Icons.archive_outlined : Icons.archive),
            onPressed: () {
              setState(() => _hideArchived = !_hideArchived);
              _load();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _load,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }
    if (_rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_none, size: 64, color: Colors.black26),
              SizedBox(height: 12),
              Text(
                'Nenhuma notificação no filtro atual.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _rows.length,
        itemBuilder: (_, i) => _buildRow(_rows[i]),
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> r) {
    final severity = (r['severity'] as String?) ?? 'medium';
    final eventType = (r['event_type'] as String?) ?? 'unknown';
    final summary = (r['summary'] as String?) ?? '';
    final isRead = r['read_at'] != null;
    final isArchived = r['archived_at'] != null;
    final color = _colorFor(severity);

    return Dismissible(
      key: ValueKey(r['id']),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.grey.shade400,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: const Icon(Icons.archive, color: Colors.white),
      ),
      confirmDismiss: (_) async => !isArchived,
      onDismissed: (_) => _archive(r),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        color: isRead ? null : color.withValues(alpha: 0.05),
        child: ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(_iconFor(eventType), color: color, size: 18),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  summary,
                  style: TextStyle(
                    fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!isRead)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          // Wrap e não Row: os nomes em português são mais compridos e a
          // linha não pode estourar num telemóvel estreito.
          subtitle: Wrap(
            spacing: 6,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '${AdminNotificationsInboxScreen.rotuloDoTipo(eventType)}'
                  ' · ${AdminNotificationsInboxScreen.nivelPtBr(severity)}',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: color),
                ),
              ),
              Text(
                _fmtDateTime(r['created_at'] as String?),
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
              if (isArchived)
                const Text('· arquivada',
                    style:
                        TextStyle(fontSize: 10, color: Colors.black38)),
            ],
          ),
          // app-15-11 (S5): arquivar só se fazia a deslizar o dedo (ninguém
          // sabia). Agora há o botão à vista; o deslizar continua.
          trailing: isArchived
              ? null
              : TextButton.icon(
                  key: ValueKey('arquivar_${r['id']}'),
                  onPressed: () => _archive(r),
                  icon: const Icon(Icons.archive_outlined, size: 16),
                  label: const Text('Arquivar'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: Colors.black54,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
          onTap: () => _openRow(r),
          onLongPress: () => _mostrarDetalhes(r),
        ),
      ),
    );
  }
}
