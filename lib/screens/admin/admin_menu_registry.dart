import 'package:flutter/material.dart';

import '../../config/app_colors.dart';

import 'admin_acerto_unificado_screen.dart';
import 'admin_acertos_semana_screen.dart';
import 'admin_advanced_kpis_screen.dart';
import 'admin_ai_assistant_screen.dart';
import 'admin_ai_models_screen.dart';
import 'admin_appointments_metrics_screen.dart';
import 'admin_appointments_screen.dart';
import 'admin_audit_log_screen.dart';
import 'admin_businesses_screen.dart';
import 'admin_cancellation_requests_screen.dart';
import 'admin_cancellations_screen.dart';
import 'admin_carwash_screen.dart';
import 'admin_cashbacks_screen.dart';
import 'admin_catalog_screen.dart';
import 'admin_category_mapping_screen.dart';
import 'admin_cleaning_bookings_screen.dart';
import 'admin_cleaning_cleaners_screen.dart';
import 'admin_clients_screen.dart';
import 'admin_complaints_screen.dart';
import 'admin_connect_payments_screen.dart';
import 'admin_continente_prices_screen.dart';
import 'admin_correcoes_preco_screen.dart';
import 'admin_crosstalk_screen.dart';
import 'admin_deleted_accounts_screen.dart';
import 'admin_discovery_filters_screen.dart';
import 'admin_dispatch_settings_screen.dart';
import 'admin_driver_approval_screen.dart';
import 'admin_drivers_screen.dart';
import 'admin_edge_functions_screen.dart';
import 'admin_errand_catalog_screen.dart';
import 'admin_ganho_do_dia_screen.dart';
import 'admin_gdpr_screen.dart';
import 'admin_knowledge_screen.dart';
import 'admin_live_orders_map_screen.dart';
import 'admin_marcacoes_confirmacao_screen.dart';
import 'admin_motores_screen.dart';
import 'admin_notification_failures_screen.dart';
import 'admin_ofertas_log_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_stuck_orders_screen.dart';
import 'admin_orphan_payments_screen.dart';
import 'admin_papeis_screen.dart';
import 'admin_partners_pending_screen.dart';
import 'admin_partners_screen.dart';
import 'admin_payments_cards_screen.dart';
import 'admin_pending_actions_screen.dart';
import 'admin_platform_settings_screen.dart';
import 'admin_promo_codes_screen.dart';
import 'admin_ratings_screen.dart';
import 'admin_receipts_screen.dart';
import 'admin_referrals_screen.dart';
import 'admin_reservations_config_screen.dart';
import 'admin_reservations_metrics_screen.dart';
import 'admin_reservations_screen.dart';
import 'admin_robot_suggestions_screen.dart';
import 'admin_search_kpi_screen.dart';
import 'admin_send_notification_screen.dart';
import 'admin_service_providers_screen.dart';
import 'admin_skill_suggestions_screen.dart';
import 'admin_stuck_reservations_screen.dart';
import 'admin_support_stats_screen.dart';
import 'admin_support_tickets_screen.dart';
import 'admin_tokens_screen.dart';
import 'admin_tvde_cancellations_screen.dart';
import 'admin_tvde_docs_review_screen.dart';
import 'admin_tvde_driver_debts_screen.dart';
import 'admin_tvde_drivers_screen.dart';
import 'admin_tvde_noshows_screen.dart';
import 'admin_tvde_plan_requests_screen.dart';
import 'admin_tvde_reservas_screen.dart';
import 'admin_tvde_rides_screen.dart';
import 'admin_tvde_roundtrips_screen.dart';
import 'admin_tvde_stuck_payments_screen.dart';
import 'admin_tvde_subscriptions_screen.dart';
import 'admin_wallets_screen.dart';
import 'admin_web_health_screen.dart';
import 'admin_whatsapp_screen.dart';

/// Registo ÚNICO do menu do painel admin (PT-BR).
///
/// 2026-09-14 (missão painel-admin-limpo). Antes, o dashboard tinha ~90
/// cartões numa lista plana de 1700 linhas e sete ecrãs de dinheiro a dizer
/// quase o mesmo. Agora cada ecrã vive aqui uma vez, numa secção, com uma
/// linha em português simples a dizer o que faz. O dashboard só desenha:
/// secções fechadas (accordion), busca por nome, favoritos e a secção
/// "Arquivado" no fim (escondida por defeito).
///
/// Regras:
///  · um ecrã, uma entrada — quem duplicar outro vai para "Arquivado" com o
///    motivo escrito, e continua a abrir (nada se apaga);
///  · os ecrãs antigos de dinheiro abrem o hub "Dinheiro e acertos" já no
///    separador certo (filtroInicial);
///  · `id` é estável: é o que os favoritos guardam.
class AdminMenuItem {
  const AdminMenuItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.builder,
    this.keywords = const [],
    this.badge,
    this.archivedReason,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget Function() builder;
  final List<String> keywords;

  /// Chave do contador dinâmico ('acertos' | 'skills'), se houver.
  final String? badge;

  /// Preenchido só nos itens da secção Arquivado.
  final String? archivedReason;

  bool matches(String q) {
    final n = q.trim().toLowerCase();
    if (n.isEmpty) return true;
    return title.toLowerCase().contains(n) ||
        subtitle.toLowerCase().contains(n) ||
        keywords.any((k) => k.contains(n));
  }
}

class AdminMenuSection {
  const AdminMenuSection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.items,
    this.archived = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<AdminMenuItem> items;
  final bool archived;
}

/// Todas as secções, pela ordem em que aparecem no painel.
List<AdminMenuSection> adminMenuSections() => [

  AdminMenuSection(
    id: 'operacao',
    title: 'Operação do dia',
    subtitle: 'O que está a acontecer agora: pedidos, corridas, avisos.',
    icon: Icons.bolt,
    color: AppColors.accent,
    items: [
    AdminMenuItem(
      id: 'operacao_pedidos_ao_vivo',
      title: 'Pedidos ao Vivo',
      subtitle: 'Mapa ao vivo: onde estão os pedidos e os entregadores agora',
      icon: Icons.map,
      color: Colors.teal,
      builder: () => const AdminLiveOrdersMapScreen(),
      keywords: const ['agora', 'entregadores', 'estao', 'mapa', 'onde', 'pedidos', 'vivo'],
    ),
    AdminMenuItem(
      id: 'operacao_pedidos',
      title: 'Pedidos',
      subtitle: 'Ver, filtrar e cancelar pedidos de entrega',
      icon: Icons.receipt_long,
      color: AppColors.accent,
      builder: () => const AdminOrdersScreen(),
      keywords: const ['cancelar', 'entrega', 'filtrar', 'pedidos'],
    ),
    AdminMenuItem(
      id: 'operacao_pedidos_parados',
      title: 'Pedidos parados',
      subtitle: 'A chamar entregador há mais de 3 min (mesmo com entregador atribuído): escolher estafeta ou mandar para todos',
      icon: Icons.hourglass_bottom,
      color: Colors.red,
      builder: () => const AdminStuckOrdersScreen(),
      keywords: const ['parados', 'presos', 'chamar', 'entregador', 'escolher', 'estafeta', 'atribuir', 'reatribuir', 'mandar', 'todos'],
    ),
    AdminMenuItem(
      id: 'operacao_pedidos_de_cancelamento',
      title: 'Pedidos de Cancelamento',
      subtitle: 'Pedidos de cancelamento feitos por entregadores e parceiros: aprovar ou recusar',
      icon: Icons.cancel_schedule_send,
      color: Colors.deepOrange,
      builder: () => const AdminCancellationRequestsScreen(),
      keywords: const ['aprovar', 'cancelamento', 'entregadores', 'feitos', 'parceiros', 'pedidos', 'recusar'],
    ),
    AdminMenuItem(
      id: 'operacao_cancelamentos',
      title: 'Cancelamentos',
      subtitle: 'Histórico de cancelamentos, taxas e reembolsos (com reprocessar os que falharam)',
      icon: Icons.cancel_schedule_send_outlined,
      color: AppColors.error,
      builder: () => const AdminCancellationsScreen(),
      keywords: const ['cancelamentos', 'falharam', 'historico', 'reembolsos', 'reprocessar', 'taxas'],
    ),
    AdminMenuItem(
      id: 'operacao_ofertas_de_prestadores',
      title: 'Ofertas de prestadores',
      subtitle: 'Registro de cada oferta enviada a um prestador: para quem foi, quanto tempo teve, como acabou',
      icon: Icons.record_voice_over,
      color: Colors.teal,
      builder: () => const AdminOfertasLogScreen(),
      keywords: const ['acabou', 'cada', 'como', 'enviada', 'oferta', 'ofertas', 'para', 'prestador', 'prestadores', 'quanto', 'quem', 'registro'],
    ),
    AdminMenuItem(
      id: 'operacao_avisos_que_falharam',
      title: 'Avisos que falharam',
      subtitle: 'Avisos por telemóvel que não chegaram nas últimas 24h, e o motivo',
      icon: Icons.notifications_off_outlined,
      color: AppColors.error,
      builder: () => const AdminNotificationFailuresScreen(),
      keywords: const ['avisos', 'chegaram', 'falharam', 'motivo', 'telemovel', 'ultimas'],
    ),
    ],
  ),
  AdminMenuSection(
    id: 'dinheiro',
    title: 'Dinheiro e acertos',
    subtitle: 'Quem recebe, quem paga, cartões, carteiras e códigos.',
    icon: Icons.account_balance_wallet_outlined,
    color: AppColors.primary,
    items: [
    AdminMenuItem(
      id: 'dinheiro_dinheiro_e_acertos',
      title: 'Dinheiro e acertos',
      subtitle: 'Um só lugar: quem a Bora paga, quem deve à Bora, marcar pago num toque, recibos e CSV',
      icon: Icons.account_balance_wallet,
      color: AppColors.primary,
      builder: () => const AdminAcertosSemanaScreen(),
      keywords: const ['acertos', 'bora', 'deve', 'dinheiro', 'lugar', 'marcar', 'paga', 'pago', 'quem', 'recibos', 'toque'],
      badge: 'acertos',
    ),
    AdminMenuItem(
      id: 'dinheiro_pagamentos_cartoes',
      title: 'Pagamentos/Cartões',
      subtitle: 'Todas as cobranças por cartão e MB Way, de todas as áreas; estornos',
      icon: Icons.credit_card,
      color: const Color(0xFF1565C0),
      builder: () => const AdminPaymentsCardsScreen(),
      keywords: const ['areas', 'cartao', 'cartoes', 'cobrancas', 'estornos', 'pagamentos', 'todas'],
    ),
    AdminMenuItem(
      id: 'dinheiro_pagamentos_orfaos',
      title: 'Pagamentos órfãos',
      subtitle: 'Pagamentos recebidos sem pedido ligado a eles',
      icon: Icons.warning_amber_rounded,
      color: const Color(0xFFD32F2F),
      builder: () => const AdminOrphanPaymentsScreen(),
      keywords: const ['eles', 'ligado', 'orfaos', 'pagamentos', 'pedido', 'recebidos'],
    ),
    AdminMenuItem(
      id: 'dinheiro_reembolsos_estafetas',
      title: 'Reembolsos estafetas',
      subtitle: 'Talões das compras em mercado e o reembolso ao entregador',
      icon: Icons.receipt,
      color: AppColors.accent,
      builder: () => const AdminReceiptsScreen(),
      keywords: const ['compras', 'entregador', 'estafetas', 'mercado', 'reembolso', 'reembolsos', 'taloes'],
    ),
    AdminMenuItem(
      id: 'dinheiro_precos_por_talao',
      title: 'Preços por talão',
      subtitle: 'Correções de preço detectadas nos talões dos mercados',
      icon: Icons.price_change_outlined,
      color: AppColors.primary,
      builder: () => const AdminCorrecoesPrecoScreen(),
      keywords: const ['correcoes', 'detectadas', 'mercados', 'preco', 'precos', 'talao', 'taloes'],
    ),
    AdminMenuItem(
      id: 'dinheiro_wallets',
      title: 'Wallets',
      subtitle: 'Saldo livre e tokens de cada cliente',
      icon: Icons.wallet,
      color: Colors.green,
      builder: () => const AdminWalletsScreen(),
      keywords: const ['cada', 'cliente', 'livre', 'saldo', 'tokens', 'wallets'],
    ),
    AdminMenuItem(
      id: 'dinheiro_tokens',
      title: 'Tokens',
      subtitle: 'Tokens: saldo, dar, tirar (clientes e entregadores)',
      icon: Icons.account_balance_wallet,
      color: Colors.deepPurple,
      builder: () => const AdminTokensScreen(),
      keywords: const ['clientes', 'entregadores', 'saldo', 'tirar', 'tokens'],
    ),
    AdminMenuItem(
      id: 'dinheiro_promo_codes',
      title: 'Promo Codes',
      subtitle: 'Criar e desligar códigos promocionais',
      icon: Icons.local_offer,
      color: Colors.pinkAccent,
      builder: () => const AdminPromoCodesScreen(),
      keywords: const ['codes', 'codigos', 'criar', 'desligar', 'promo', 'promocionais'],
    ),
    ],
  ),
  AdminMenuSection(
    id: 'entregas',
    title: 'Entregas',
    subtitle: 'Estafetas, lojas dos favores, mercados e despacho.',
    icon: Icons.delivery_dining,
    color: Colors.blue,
    items: [
    AdminMenuItem(
      id: 'entregas_entregadores',
      title: 'Entregadores',
      subtitle: 'Lista e estado de todos os entregadores',
      icon: Icons.delivery_dining,
      color: Colors.blue,
      builder: () => const AdminDriversScreen(),
      keywords: const ['entregadores', 'estado', 'lista', 'todos'],
    ),
    AdminMenuItem(
      id: 'entregas_aprovacoes',
      title: 'Aprovações',
      subtitle: 'Candidaturas a entregador: pendentes, aprovadas e recusadas',
      icon: Icons.how_to_reg,
      color: Colors.teal,
      builder: () => const AdminDriverApprovalScreen(),
      keywords: const ['aprovacoes', 'aprovadas', 'candidaturas', 'entregador', 'pendentes', 'recusadas'],
    ),
    AdminMenuItem(
      id: 'entregas_comercios_da_guarda',
      title: 'Comércios da Guarda',
      subtitle: 'Lojas e comércios da Guarda usados nos Favores: importar, editar, esconder',
      icon: Icons.storefront,
      color: const Color(0xFF14B8A6),
      builder: () => const AdminBusinessesScreen(),
      keywords: const ['comercios', 'editar', 'esconder', 'favores', 'guarda', 'importar', 'lojas', 'usados'],
    ),
    AdminMenuItem(
      id: 'entregas_catalogo_de_favores',
      title: 'Catálogo de Favores',
      subtitle: 'Aprovar produtos lidos automaticamente dos talões',
      icon: Icons.task_alt_outlined,
      color: const Color(0xFF14B8A6),
      builder: () => const AdminErrandCatalogScreen(),
      keywords: const ['aprovar', 'automaticamente', 'catalogo', 'favores', 'lidos', 'produtos', 'taloes'],
    ),
    AdminMenuItem(
      id: 'entregas_precos_continente_pvpr',
      title: 'Preços Continente (PVPR)',
      subtitle: 'Rever e aplicar os preços oficiais do site do Continente',
      icon: Icons.price_change,
      color: Colors.green,
      builder: () => const AdminContinentePricesScreen(),
      keywords: const ['aplicar', 'continente', 'oficiais', 'precos', 'pvpr', 'rever', 'site'],
    ),
    AdminMenuItem(
      id: 'entregas_configuracoes_de_despacho',
      title: 'Configurações de Despacho',
      subtitle: 'Regras de como os pedidos chegam aos entregadores (tempos, distâncias)',
      icon: Icons.local_shipping_outlined,
      color: Colors.orange,
      builder: () => const AdminDispatchSettingsScreen(),
      keywords: const ['chegam', 'como', 'configuracoes', 'despacho', 'distancias', 'entregadores', 'pedidos', 'regras', 'tempos'],
    ),
    ],
  ),
  AdminMenuSection(
    id: 'tvde',
    title: 'Bora Motorista',
    subtitle: 'Transporte de passageiros: corridas, motoristas, planos.',
    icon: Icons.local_taxi,
    color: const Color(0xFF0EA5E9),
    items: [
    AdminMenuItem(
      id: 'tvde_corridas',
      title: 'Corridas',
      subtitle: 'Todas as corridas: em curso, feitas, canceladas',
      icon: Icons.local_taxi,
      color: Colors.teal,
      builder: () => const AdminTvdeRidesScreen(),
      keywords: const ['canceladas', 'corridas', 'curso', 'feitas', 'todas'],
    ),
    AdminMenuItem(
      id: 'tvde_cancelamentos_de_corridas',
      title: 'Cancelamentos de corridas',
      subtitle: 'Corridas canceladas e as taxas cobradas',
      icon: Icons.cancel_schedule_send,
      color: Colors.redAccent,
      builder: () => const AdminTvdeCancellationsScreen(),
      keywords: const ['canceladas', 'cancelamentos', 'cobradas', 'corridas', 'taxas'],
    ),
    AdminMenuItem(
      id: 'tvde_motoristas_de_passageiros',
      title: 'Motoristas de passageiros',
      subtitle: 'Motoristas: gerir, banir, saldo, avaliações',
      icon: Icons.directions_car,
      color: Colors.indigo,
      builder: () => const AdminTvdeDriversScreen(),
      keywords: const ['avaliacoes', 'banir', 'gerir', 'motoristas', 'passageiros', 'saldo'],
    ),
    AdminMenuItem(
      id: 'tvde_documentos_tvde',
      title: 'Documentos TVDE',
      subtitle: 'Rever e aprovar os documentos dos motoristas (IMT, seguro, carta)',
      icon: Icons.badge_outlined,
      color: const Color(0xFF6366F1),
      builder: () => const AdminTvdeDocsReviewScreen(),
      keywords: const ['aprovar', 'carta', 'documentos', 'motoristas', 'rever', 'seguro', 'tvde'],
    ),
    AdminMenuItem(
      id: 'tvde_assinaturas',
      title: 'Assinaturas',
      subtitle: 'Dar assinatura a um cliente e ver as que estão ativas',
      icon: Icons.card_membership,
      color: Colors.deepPurple,
      builder: () => const AdminTvdeSubscriptionsScreen(),
      keywords: const ['assinatura', 'assinaturas', 'ativas', 'cliente', 'estao'],
    ),
    AdminMenuItem(
      id: 'tvde_pedidos_de_plano',
      title: 'Pedidos de plano',
      subtitle: 'Pedidos de plano feitos pelos clientes: aprovar e ativar',
      icon: Icons.assignment_turned_in,
      color: Colors.purple,
      builder: () => const AdminTvdePlanRequestsScreen(),
      keywords: const ['aprovar', 'ativar', 'clientes', 'feitos', 'pedidos', 'pelos', 'plano'],
    ),
    AdminMenuItem(
      id: 'tvde_reservas_corridas_agendadas',
      title: 'Reservas (corridas agendadas)',
      subtitle: 'Corridas marcadas com antecedência',
      icon: Icons.event,
      color: Colors.indigo,
      builder: () => const AdminTvdeReservasScreen(),
      keywords: const ['agendadas', 'antecedencia', 'corridas', 'marcadas', 'reservas'],
    ),
    AdminMenuItem(
      id: 'tvde_ida_e_volta',
      title: 'Ida e volta',
      subtitle: 'Pacotes de ida e volta: por usar, usados, expirados',
      icon: Icons.sync_alt,
      color: Colors.teal,
      builder: () => const AdminTvdeRoundtripsScreen(),
      keywords: const ['expirados', 'pacotes', 'usados', 'usar', 'volta'],
    ),
    AdminMenuItem(
      id: 'tvde_corridas_presas_no_pagamento',
      title: 'Corridas presas no pagamento',
      subtitle: 'Corridas cujo pagamento ficou preso',
      icon: Icons.hourglass_bottom,
      color: Colors.redAccent,
      builder: () => const AdminTvdeStuckPaymentsScreen(),
      keywords: const ['corridas', 'cujo', 'ficou', 'pagamento', 'presas', 'preso'],
    ),
    AdminMenuItem(
      id: 'tvde_dividas_em_dinheiro',
      title: 'Dívidas em dinheiro',
      subtitle: 'O que cada motorista deve à Bora das corridas pagas em dinheiro',
      icon: Icons.account_balance_wallet,
      color: Colors.brown,
      builder: () => const AdminTvdeDriverDebtsScreen(),
      keywords: const ['bora', 'cada', 'corridas', 'deve', 'dinheiro', 'dividas', 'motorista', 'pagas'],
    ),
    AdminMenuItem(
      id: 'tvde_no_shows_tvde',
      title: 'No-shows TVDE',
      subtitle: 'Faltas de clientes nas corridas: ver e reverter',
      icon: Icons.person_off,
      color: const Color(0xFF0EA5E9),
      builder: () => const AdminTvdeNoShowsScreen(),
      keywords: const ['clientes', 'corridas', 'faltas', 'reverter', 'shows', 'tvde'],
    ),
    ],
  ),
  AdminMenuSection(
    id: 'servicos',
    title: 'Serviços e Barbearias',
    subtitle: 'Barbearias e beleza: agenda, confirmações, faltas.',
    icon: Icons.content_cut,
    color: const Color(0xFF8B5CF6),
    items: [
    AdminMenuItem(
      id: 'servicos_barbearias_beleza',
      title: 'Barbearias & Beleza',
      subtitle: 'Barbearias e salões: aprovar, recusar, ligar e desligar',
      icon: Icons.content_cut,
      color: Colors.indigo,
      builder: () => const AdminServiceProvidersScreen(),
      keywords: const ['aprovar', 'barbearias', 'beleza', 'desligar', 'ligar', 'recusar', 'saloes'],
    ),
    AdminMenuItem(
      id: 'servicos_agenda_de_marcacoes',
      title: 'Agenda de marcações',
      subtitle: 'Marcações de todas as barbearias; cancelar em nome do cliente',
      icon: Icons.event_available,
      color: Colors.teal,
      builder: () => const AdminAppointmentsScreen(),
      keywords: const ['agenda', 'barbearias', 'cancelar', 'cliente', 'marcacoes', 'nome', 'todas'],
    ),
    AdminMenuItem(
      id: 'servicos_marcacoes_por_confirmar_e_faltas',
      title: 'Marcações por confirmar e faltas',
      subtitle: 'Serviços que acabaram sem o parceiro dizer se foram feitos, e dinheiro retido por falta — reverter num toque',
      icon: Icons.rule,
      color: AppColors.warning,
      builder: () => const AdminMarcacoesConfirmacaoScreen(),
      keywords: const ['acabaram', 'confirmar', 'dinheiro', 'dizer', 'falta', 'faltas', 'feitos', 'foram', 'marcacoes', 'parceiro', 'retido', 'reverter'],
    ),
    AdminMenuItem(
      id: 'servicos_metricas_barbearias',
      title: 'Métricas Barbearias',
      subtitle: 'Números das barbearias: marcações, faltas, sem marcação',
      icon: Icons.bar_chart,
      color: Colors.deepPurple,
      builder: () => const AdminAppointmentsMetricsScreen(),
      keywords: const ['barbearias', 'faltas', 'marcacao', 'marcacoes', 'metricas', 'numeros'],
    ),
    ],
  ),
  AdminMenuSection(
    id: 'limpeza',
    title: 'Limpeza e Lavagem',
    subtitle: 'Limpeza doméstica e lavagem de carros.',
    icon: Icons.cleaning_services_outlined,
    color: const Color(0xFF14B8A6),
    items: [
    AdminMenuItem(
      id: 'limpeza_limpezas',
      title: 'Limpezas',
      subtitle: 'Limpezas marcadas, em curso e feitas',
      icon: Icons.cleaning_services,
      color: const Color(0xFF0284C7),
      builder: () => const AdminCleaningBookingsScreen(),
      keywords: const ['curso', 'feitas', 'limpezas', 'marcadas'],
    ),
    AdminMenuItem(
      id: 'limpeza_profissionais_de_limpeza',
      title: 'Profissionais de limpeza',
      subtitle: 'Profissionais de limpeza: aprovar e gerir',
      icon: Icons.badge,
      color: const Color(0xFF38BDF8),
      builder: () => const AdminCleaningCleanersScreen(),
      keywords: const ['aprovar', 'gerir', 'limpeza', 'profissionais'],
    ),
    AdminMenuItem(
      id: 'limpeza_lavagem_auto',
      title: 'Lavagem Auto',
      subtitle: 'Lavagens de carro: pedidos, lavadores, acerto',
      icon: Icons.local_car_wash,
      color: const Color(0xFF0891B2),
      builder: () => const AdminCarwashScreen(),
      keywords: const ['acerto', 'auto', 'carro', 'lavadores', 'lavagem', 'lavagens', 'pedidos'],
    ),
    ],
  ),
  AdminMenuSection(
    id: 'reservas',
    title: 'Reservas de mesa',
    subtitle: 'Mesas nos restaurantes e configuração das reservas.',
    icon: Icons.table_restaurant_outlined,
    color: Colors.deepOrange,
    items: [
    AdminMenuItem(
      id: 'reservas_reservas',
      title: 'Reservas',
      subtitle: 'Reservas de mesa em todos os restaurantes',
      icon: Icons.event_seat,
      color: Colors.teal,
      builder: () => const AdminReservationsScreen(),
      keywords: const ['mesa', 'reservas', 'restaurantes', 'todos'],
    ),
    AdminMenuItem(
      id: 'reservas_metricas_reservas_pro',
      title: 'Métricas Reservas Pro',
      subtitle: 'Números das reservas (7, 30 e 90 dias)',
      icon: Icons.bar_chart,
      color: Colors.deepPurple,
      builder: () => const AdminReservationsMetricsScreen(),
      keywords: const ['dias', 'metricas', 'numeros', 'reservas'],
    ),
    AdminMenuItem(
      id: 'reservas_marcacoes_presas',
      title: 'Marcações presas',
      subtitle: 'Reservas que ficaram presas a meio',
      icon: Icons.lock_clock,
      color: AppColors.error,
      builder: () => const AdminStuckReservationsScreen(),
      keywords: const ['ficaram', 'marcacoes', 'meio', 'presas', 'reservas'],
    ),
    AdminMenuItem(
      id: 'reservas_reservas_pro_config',
      title: 'Reservas Pro — Config',
      subtitle: 'Ritmo, regras por restaurante e fila de espera',
      icon: Icons.event_seat_outlined,
      color: const Color(0xFF10B981),
      builder: () => const AdminReservationsConfigScreen(),
      keywords: const ['config', 'espera', 'fila', 'regras', 'reservas', 'restaurante', 'ritmo'],
    ),
    ],
  ),
  AdminMenuSection(
    id: 'clientes',
    title: 'Clientes',
    subtitle: 'Quem compra: contas, avaliações, suporte, avisos.',
    icon: Icons.people_outline,
    color: Colors.teal,
    items: [
    AdminMenuItem(
      id: 'clientes_clientes',
      title: 'Clientes',
      subtitle: 'Clientes: listar, banir, suspender, ver histórico',
      icon: Icons.people_outline,
      color: Colors.indigo,
      builder: () => const AdminClientsScreen(),
      keywords: const ['banir', 'clientes', 'historico', 'listar', 'suspender'],
    ),
    AdminMenuItem(
      id: 'clientes_avaliacoes',
      title: 'Avaliações',
      subtitle: 'Avaliações baixas, casos problemáticos e denúncias',
      icon: Icons.star_outline,
      color: Colors.amber,
      builder: () => const AdminRatingsScreen(),
      keywords: const ['avaliacoes', 'baixas', 'casos', 'denuncias', 'problematicos'],
    ),
    AdminMenuItem(
      id: 'clientes_suporte_tickets',
      title: 'Suporte — Tickets',
      subtitle: 'Pedidos de ajuda dos utilizadores, abertos e antigos',
      icon: Icons.support_agent,
      color: Colors.indigo,
      builder: () => const AdminSupportTicketsScreen(),
      keywords: const ['abertos', 'ajuda', 'antigos', 'pedidos', 'suporte', 'tickets', 'utilizadores'],
    ),
    AdminMenuItem(
      id: 'clientes_contas_encerradas',
      title: 'Contas encerradas',
      subtitle: 'Contas que foram encerradas',
      icon: Icons.person_off_outlined,
      color: Colors.brown,
      builder: () => const AdminDeletedAccountsScreen(),
      keywords: const ['contas', 'encerradas', 'foram'],
    ),
    AdminMenuItem(
      id: 'clientes_privacidade_rgpd',
      title: 'Privacidade (RGPD)',
      subtitle: 'Exportar ou apagar os dados de um cliente (proteção de dados)',
      icon: Icons.privacy_tip_outlined,
      color: const Color(0xFF0EA5E9),
      builder: () => const AdminGdprScreen(),
      keywords: const ['apagar', 'cliente', 'dados', 'exportar', 'privacidade', 'protecao', 'rgpd'],
    ),
    AdminMenuItem(
      id: 'clientes_referrals',
      title: 'Referrals',
      subtitle: 'Convites entre amigos: quem convidou, quem entrou',
      icon: Icons.card_giftcard,
      color: Colors.purple,
      builder: () => const AdminReferralsScreen(),
      keywords: const ['amigos', 'convidou', 'convites', 'entre', 'entrou', 'quem', 'referrals'],
    ),
    AdminMenuItem(
      id: 'clientes_enviar_notificacao',
      title: 'Enviar notificação',
      subtitle: 'Mandar um aviso a um cliente ou a todos',
      icon: Icons.campaign,
      color: Colors.amber,
      builder: () => const AdminSendNotificationScreen(),
      keywords: const ['aviso', 'cliente', 'enviar', 'mandar', 'notificacao', 'todos'],
    ),
    AdminMenuItem(
      id: 'clientes_personalizacao',
      title: 'Personalização',
      subtitle: 'O que as pessoas mais procuram e os parceiros mais guardados',
      icon: Icons.search,
      color: Colors.indigo,
      builder: () => const AdminSearchKpiScreen(),
      keywords: const ['guardados', 'mais', 'parceiros', 'personalizacao', 'pessoas', 'procuram'],
    ),
    AdminMenuItem(
      id: 'clientes_filtros_de_descoberta',
      title: 'Filtros de Descoberta',
      subtitle: 'Filtros que o cliente vê na página inicial (aberto agora, dieta)',
      icon: Icons.tune,
      color: const Color(0xFF8B5CF6),
      builder: () => const AdminDiscoveryFiltersScreen(),
      keywords: const ['aberto', 'agora', 'cliente', 'descoberta', 'dieta', 'filtros', 'inicial', 'pagina'],
    ),
    ],
  ),
  AdminMenuSection(
    id: 'parceiros',
    title: 'Parceiros',
    subtitle: 'Restaurantes e lojas: aprovar, editar, catálogo, WhatsApp.',
    icon: Icons.storefront,
    color: Colors.purple,
    items: [
    AdminMenuItem(
      id: 'parceiros_parceiros',
      title: 'Parceiros',
      subtitle: 'Ligar e desligar restaurantes e lojas; editar dados',
      icon: Icons.storefront,
      color: Colors.purple,
      builder: () => const AdminPartnersScreen(),
      keywords: const ['dados', 'desligar', 'editar', 'ligar', 'lojas', 'parceiros', 'restaurantes'],
    ),
    AdminMenuItem(
      id: 'parceiros_aprovacao_de_parceiros',
      title: 'Aprovação de parceiros',
      subtitle: 'Candidaturas de parceiros: pendentes, aprovadas, recusadas',
      icon: Icons.how_to_reg,
      color: Colors.deepPurple,
      builder: () => const AdminPartnersPendingScreen(),
      keywords: const ['aprovacao', 'aprovadas', 'candidaturas', 'parceiros', 'pendentes', 'recusadas'],
    ),
    AdminMenuItem(
      id: 'parceiros_papeis_e_candidaturas',
      title: 'Papeis e candidaturas',
      subtitle: 'Papéis de cada pessoa (entregador, lavador, limpador...) e candidaturas',
      icon: Icons.badge,
      color: Colors.deepPurple,
      builder: () => const AdminPapeisScreen(),
      keywords: const ['cada', 'candidaturas', 'entregador', 'lavador', 'limpador', 'papeis', 'pessoa'],
    ),
    AdminMenuItem(
      id: 'parceiros_catalogo',
      title: 'Catálogo',
      subtitle: 'Produtos de cada parceiro: ligar, desligar, preço',
      icon: Icons.inventory_2_outlined,
      color: Colors.brown,
      builder: () => const AdminCatalogScreen(),
      keywords: const ['cada', 'catalogo', 'desligar', 'ligar', 'parceiro', 'preco', 'produtos'],
    ),
    AdminMenuItem(
      id: 'parceiros_whatsapp_da_loja',
      title: 'WhatsApp da loja',
      subtitle: 'Conversas do robô do WhatsApp: pausar, assumir, lista de espera',
      icon: Icons.chat_bubble_outline,
      color: Colors.green,
      builder: () => const AdminWhatsappScreen(),
      keywords: const ['assumir', 'conversas', 'espera', 'lista', 'loja', 'pausar', 'robo', 'whatsapp'],
    ),
    ],
  ),
  AdminMenuSection(
    id: 'sistema',
    title: 'Sistema e Configurações',
    subtitle: 'Regras da plataforma, histórico, servidor.',
    icon: Icons.settings_outlined,
    color: Colors.blueGrey,
    items: [
    AdminMenuItem(
      id: 'sistema_configuracoes',
      title: 'Configurações',
      subtitle: 'Regras da plataforma: preços, taxas, carteira, demo',
      icon: Icons.settings,
      color: Colors.grey,
      builder: () => const AdminPlatformSettingsScreen(),
      keywords: const ['carteira', 'configuracoes', 'demo', 'plataforma', 'precos', 'regras', 'taxas'],
    ),
    AdminMenuItem(
      id: 'sistema_historico_de_accoes',
      title: 'Histórico de Acções',
      subtitle: 'Tudo o que foi feito no painel, por quem e quando',
      icon: Icons.history,
      color: Colors.blueGrey,
      builder: () => const AdminAuditLogScreen(),
      keywords: const ['accoes', 'feito', 'historico', 'painel', 'quando', 'quem', 'tudo'],
    ),
    AdminMenuItem(
      id: 'sistema_edge_functions',
      title: 'Edge Functions',
      subtitle: 'Funções do servidor e os erros recentes',
      icon: Icons.cloud_outlined,
      color: Colors.cyan,
      builder: () => const AdminEdgeFunctionsScreen(),
      keywords: const ['edge', 'erros', 'funcoes', 'functions', 'recentes', 'servidor'],
    ),
    AdminMenuItem(
      id: 'sistema_kpis_avancado',
      title: 'KPIs Avançado',
      subtitle: 'Zonas com mais pedidos, valor médio, conversão',
      icon: Icons.insights,
      color: Colors.cyan,
      builder: () => const AdminAdvancedKpisScreen(),
      keywords: const ['avancado', 'conversao', 'kpis', 'mais', 'medio', 'pedidos', 'valor', 'zonas'],
    ),
    ],
  ),
  AdminMenuSection(
    id: 'robos',
    title: 'Robôs e Autonomia',
    subtitle: 'O que os robôs propõem e como estão os motores.',
    icon: Icons.smart_toy_outlined,
    color: Colors.indigo,
    items: [
    AdminMenuItem(
      id: 'robos_central_de_autonomia',
      title: 'Central de Autonomia',
      subtitle: 'Aprovar ou recusar o que o robô propõe; travar tudo se preciso',
      icon: Icons.hub_outlined,
      color: AppColors.primary,
      builder: () => const AdminRobotSuggestionsScreen(),
      keywords: const ['aprovar', 'autonomia', 'central', 'preciso', 'propoe', 'recusar', 'robo', 'travar', 'tudo'],
    ),
    AdminMenuItem(
      id: 'robos_propostas_ia',
      title: 'Propostas IA',
      subtitle: 'Ações que o robô quer fazer e esperam a sua aprovação',
      icon: Icons.fact_check_outlined,
      color: AppColors.accent,
      builder: () => const AdminPendingActionsScreen(),
      keywords: const ['acoes', 'aprovacao', 'esperam', 'fazer', 'propostas', 'quer', 'robo'],
    ),
    AdminMenuItem(
      id: 'robos_sugestoes_skills_ia',
      title: 'Sugestões Skills IA',
      subtitle: 'Novas habilidades propostas pelo robô semanal',
      icon: Icons.auto_awesome,
      color: const Color(0xFFFF8F00),
      builder: () => const AdminSkillSuggestionsScreen(),
      keywords: const ['habilidades', 'novas', 'pelo', 'propostas', 'robo', 'semanal', 'skills', 'sugestoes'],
      badge: 'skills',
    ),
    AdminMenuItem(
      id: 'robos_motores_e_agentes',
      title: 'Motores e Agentes',
      subtitle: 'Motores de IA: quota, velocidade, ligar e desligar cada robô',
      icon: Icons.bolt,
      color: Colors.deepOrange,
      builder: () => const AdminMotoresScreen(),
      keywords: const ['agentes', 'cada', 'desligar', 'ligar', 'motores', 'quota', 'robo', 'velocidade'],
    ),
    AdminMenuItem(
      id: 'robos_assistente_ia_admin',
      title: 'Assistente IA — Admin',
      subtitle: 'Conversar com o assistente: consultar dados e configurações',
      icon: Icons.auto_awesome,
      color: const Color(0xFF7E57C2),
      builder: () => const AdminAiAssistantScreen(),
      keywords: const ['admin', 'assistente', 'configuracoes', 'consultar', 'conversar', 'dados'],
    ),
    AdminMenuItem(
      id: 'robos_modelos_de_ia',
      title: 'Modelos de IA',
      subtitle: 'Qual modelo de IA cada robô usa',
      icon: Icons.memory_outlined,
      color: Colors.deepPurple,
      builder: () => const AdminAiModelsScreen(),
      keywords: const ['cada', 'modelo', 'modelos', 'qual', 'robo'],
    ),
    AdminMenuItem(
      id: 'robos_knowledge_base',
      title: 'Knowledge Base',
      subtitle: 'Base de conhecimento que os robôs leem',
      icon: Icons.menu_book_outlined,
      color: Colors.indigo,
      builder: () => const AdminKnowledgeScreen(),
      keywords: const ['base', 'conhecimento', 'knowledge', 'leem', 'robos'],
    ),
    AdminMenuItem(
      id: 'robos_estatisticas_suporte_ia',
      title: 'Estatísticas Suporte IA',
      subtitle: 'Números do suporte automático: sessões, resolvidos, custo',
      icon: Icons.smart_toy_outlined,
      color: Colors.deepPurple,
      builder: () => const AdminSupportStatsScreen(),
      keywords: const ['automatico', 'custo', 'estatisticas', 'numeros', 'resolvidos', 'sessoes', 'suporte'],
    ),
    ],
  ),
  AdminMenuSection(
    id: 'arquivado',
    title: 'Arquivado',
    subtitle: 'Ecrãs que você não usa ou que duplicam outros. Continuam a abrir; só saíram da frente.',
    icon: Icons.inventory_2_outlined,
    color: Colors.grey,
    archived: true,
    items: [
    AdminMenuItem(
      id: 'arquivado_pagamentos',
      title: 'Pagamentos',
      subtitle: 'Saques e ganhos semanais dos entregadores (agora dentro do hub)',
      icon: Icons.payments,
      color: AppColors.primary,
      builder: () => const AdminAcertosSemanaScreen(filtroInicial: 'driver'),
      keywords: const ['agora', 'dentro', 'entregadores', 'ganhos', 'pagamentos', 'saques', 'semanais'],
      archivedReason: 'duplica o hub Dinheiro e acertos',
    ),
    AdminMenuItem(
      id: 'arquivado_acerto_semanal_por_pessoa',
      title: 'Acerto semanal por pessoa',
      subtitle: 'Acerto semanal por pessoa (agora dentro do hub)',
      icon: Icons.groups_2,
      color: AppColors.primary,
      builder: () => const AdminAcertoUnificadoScreen(),
      keywords: const ['acerto', 'agora', 'dentro', 'pessoa', 'semanal'],
      archivedReason: 'duplica o hub Dinheiro e acertos',
    ),
    AdminMenuItem(
      id: 'arquivado_ganho_do_dia_por_pessoa',
      title: 'Ganho do dia por pessoa',
      subtitle: 'Ganho do dia por pessoa (agora dentro do hub)',
      icon: Icons.today,
      color: AppColors.primary,
      builder: () => const AdminGanhoDoDiaScreen(),
      keywords: const ['agora', 'dentro', 'ganho', 'pessoa'],
      archivedReason: 'duplica o hub Dinheiro e acertos',
    ),
    AdminMenuItem(
      id: 'arquivado_fechamento_semanal_estafetas',
      title: 'Fechamento Semanal — Estafetas',
      subtitle: 'Fecho semanal antigo dos entregadores (agora dentro do hub)',
      icon: Icons.account_balance,
      color: Colors.indigo,
      builder: () => const AdminAcertosSemanaScreen(filtroInicial: 'driver'),
      keywords: const ['agora', 'antigo', 'dentro', 'entregadores', 'estafetas', 'fechamento', 'fecho', 'semanal'],
      archivedReason: 'ecrã antigo do fecho, duplica o hub',
    ),
    AdminMenuItem(
      id: 'arquivado_pagamentos_connect',
      title: 'Pagamentos Connect',
      subtitle: 'Pagamentos por Stripe Connect (agora dentro do hub)',
      icon: Icons.account_balance_wallet,
      color: Colors.deepPurple,
      builder: () => const AdminConnectPaymentsScreen(),
      keywords: const ['agora', 'connect', 'dentro', 'pagamentos', 'stripe'],
      archivedReason: 'duplica o hub Dinheiro e acertos',
    ),
    AdminMenuItem(
      id: 'arquivado_acerto_reservas_parceiros',
      title: 'Acerto reservas parceiros',
      subtitle: 'Acerto das reservas de mesa (agora dentro do hub)',
      icon: Icons.event_seat,
      color: Colors.teal,
      builder: () => const AdminAcertosSemanaScreen(filtroInicial: 'partner'),
      keywords: const ['acerto', 'agora', 'dentro', 'mesa', 'parceiros', 'reservas'],
      archivedReason: 'duplica o hub Dinheiro e acertos',
    ),
    AdminMenuItem(
      id: 'arquivado_repasses_a_parceiros',
      title: 'Repasses a Parceiros',
      subtitle: 'Repasses a parceiros (agora dentro do hub)',
      icon: Icons.payments_outlined,
      color: Colors.indigo,
      builder: () => const AdminAcertosSemanaScreen(filtroInicial: 'partner'),
      keywords: const ['agora', 'dentro', 'parceiros', 'repasses'],
      archivedReason: 'duplica o hub Dinheiro e acertos',
    ),
    AdminMenuItem(
      id: 'arquivado_fechamento_semanal_barbearias',
      title: 'Fechamento Semanal — Barbearias',
      subtitle: 'Fecho semanal das barbearias (agora dentro do hub)',
      icon: Icons.payments_outlined,
      color: Colors.indigo,
      builder: () => const AdminAcertosSemanaScreen(filtroInicial: 'provider'),
      keywords: const ['agora', 'barbearias', 'dentro', 'fechamento', 'fecho', 'semanal'],
      archivedReason: 'duplica o hub Dinheiro e acertos',
    ),
    AdminMenuItem(
      id: 'arquivado_fechamento_semanal_limpeza',
      title: 'Fechamento Semanal — Limpeza',
      subtitle: 'Fecho semanal da limpeza (agora dentro do hub)',
      icon: Icons.payments_outlined,
      color: const Color(0xFF0EA5E9),
      builder: () => const AdminAcertosSemanaScreen(filtroInicial: 'cleaner'),
      keywords: const ['agora', 'dentro', 'fechamento', 'fecho', 'limpeza', 'semanal'],
      archivedReason: 'duplica o hub Dinheiro e acertos',
    ),
    AdminMenuItem(
      id: 'arquivado_cashbacks',
      title: 'Cashbacks',
      subtitle: 'Histórico de cashback (sem dados)',
      icon: Icons.celebration,
      color: Colors.green,
      builder: () => const AdminCashbacksScreen(),
      keywords: const ['cashback', 'cashbacks', 'dados', 'historico'],
      archivedReason: 'sem dados: não existe tabela de cashback',
    ),
    AdminMenuItem(
      id: 'arquivado_reclamacoes',
      title: 'Reclamações',
      subtitle: 'Caixa de reclamações antiga (sem registos; o suporte vive nos Tickets)',
      icon: Icons.report_problem_outlined,
      color: Colors.redAccent,
      builder: () => const AdminComplaintsScreen(),
      keywords: const ['antiga', 'caixa', 'reclamacoes', 'registos', 'suporte', 'tickets', 'vive'],
      archivedReason: 'sem dados: 0 reclamações desde sempre (o suporte vive nos Tickets)',
    ),
    AdminMenuItem(
      id: 'arquivado_saude_da_web',
      title: 'Saúde da Web',
      subtitle: 'Falhas do campo de morada na versão web',
      icon: Icons.travel_explore_outlined,
      color: Colors.teal,
      builder: () => const AdminWebHealthScreen(),
      keywords: const ['campo', 'falhas', 'morada', 'saude', 'versao'],
      archivedReason: 'sem uso: 4 registos desde sempre',
    ),
    AdminMenuItem(
      id: 'arquivado_mapeamento_de_categorias',
      title: 'Mapeamento de categorias',
      subtitle: 'Mapa das categorias dos mercados (ferramenta pontual)',
      icon: Icons.account_tree,
      color: Colors.brown,
      builder: () => const AdminCategoryMappingScreen(),
      keywords: const ['categorias', 'ferramenta', 'mapa', 'mapeamento', 'mercados', 'pontual'],
      archivedReason: 'ferramenta pontual, sem uso nos últimos 30 dias',
    ),
    AdminMenuItem(
      id: 'arquivado_comunicacao_ab',
      title: 'Comunicação A↔B',
      subtitle: 'Perguntas do robô de suporte ao robô técnico',
      icon: Icons.forum_outlined,
      color: AppColors.primary,
      builder: () => const AdminCrosstalkScreen(),
      keywords: const ['comunicacao', 'perguntas', 'robo', 'suporte', 'tecnico'],
      archivedReason: 'sem uso: 1 mensagem nos últimos 30 dias',
    ),
    ],
  ),
];

/// Todos os itens (activos e arquivados), para a busca e os favoritos.
List<AdminMenuItem> adminMenuAllItems() =>
    adminMenuSections().expand((s) => s.items).toList();
