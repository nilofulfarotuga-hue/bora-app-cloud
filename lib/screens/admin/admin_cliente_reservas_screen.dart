// Painel admin — tudo o que UM cliente marcou (10/10/2026).
//
// Paridade do separador "Reservas" do cliente: as mesmas quatro coisas —
// mesas, corridas marcadas, limpezas e marcações — repartidas pelas mesmas
// três abas e com a mesma regra (`utils/minhas_reservas.dart`), para o Danilo
// ver exatamente o que o cliente vê. Só leitura: cancelar, reembolsar ou
// reatribuir faz-se no ecrã admin de cada tipo, que se abre daqui.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../models/appointment_model.dart';
import '../../models/cleaning_models.dart';
import '../../models/reservation_model.dart';
import '../../models/tvde_ride.dart';
import '../../utils/hora_lisboa.dart';
import '../../utils/minhas_reservas.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import 'admin_appointments_screen.dart';
import 'admin_cleaning_bookings_screen.dart';
import 'admin_reservations_screen.dart';
import 'admin_tvde_reservas_screen.dart';
import 'admin_tvde_rides_screen.dart';

class AdminClienteReservasScreen extends StatefulWidget {
  const AdminClienteReservasScreen({
    super.key,
    required this.userId,
    this.email,
    this.nome,
  });

  final String userId;
  final String? email;
  final String? nome;

  @override
  State<AdminClienteReservasScreen> createState() =>
      _AdminClienteReservasScreenState();
}

class _Carga {
  _Carga(this.dados, this.falhas);
  final MinhasReservas dados;

  /// Tipo → motivo, para os que não carregaram.
  final Map<TipoReserva, String> falhas;
}

class _AdminClienteReservasScreenState
    extends State<AdminClienteReservasScreen> {
  late Future<_Carga> _future = _load();

  SupabaseClient get _sb => Supabase.instance.client;

  Future<_Carga> _load() async {
    final uid = widget.userId;
    final falhas = <TipoReserva, String>{};

    // Cada tipo com o seu try/catch: um que falhe não esconde os outros.
    Future<List<T>> tentar<T>(
        TipoReserva tipo, Future<List<T>> Function() carga) async {
      try {
        return await carga().timeout(const Duration(seconds: 20));
      } catch (e) {
        falhas[tipo] = '$e';
        return <T>[];
      }
    }

    final mesasF = tentar<ReservationModel>(TipoReserva.mesa, () async {
      final rows = await _sb
          .from('reservations')
          .select('*, restaurants(id, name, photo_url)')
          .eq('client_user_id', uid)
          .order('reserved_for', ascending: false)
          .limit(100);
      return [
        for (final r in rows)
          ReservationModel.fromSupabase(Map<String, dynamic>.from(r)),
      ];
    });

    final corridasF = tentar<TvdeRide>(TipoReserva.corrida, () async {
      final rows = await _sb
          .from('tvde_rides')
          .select()
          .eq('client_id', uid)
          .not('scheduled_at', 'is', null)
          .order('scheduled_at', ascending: false)
          .limit(100);
      return [
        for (final r in rows) TvdeRide.fromMap(Map<String, dynamic>.from(r)),
      ];
    });

    // `cleaning_bookings` não tem leitura direta para o admin: passa pela
    // RPC da lista de limpezas (pesquisa pelo email) e filtra-se pelo id.
    final limpezasF =
        tentar<CleaningBooking>(TipoReserva.limpeza, () async {
      final email = (widget.email ?? '').trim();
      if (email.isEmpty) {
        throw 'cliente sem email — as limpezas procuram-se pelo email';
      }
      final res = await _sb.rpc('admin_list_cleanings', params: {
        'p_search': email,
        'p_limit': 500,
      });
      return [
        for (final r in (res as List? ?? const []))
          if ((r as Map)['client_user_id']?.toString() == uid)
            CleaningBooking.fromSupabase(Map<String, dynamic>.from(r)),
      ];
    });

    final marcacoesF =
        tentar<AppointmentModel>(TipoReserva.marcacao, () async {
      final rows = await _sb
          .from('appointments')
          .select('*, service_providers(id, name, photo_url, hero_image_url, '
              'booking_cancellation_policy, booking_payment_mode), '
              'provider_services(id, name), staff_members(id, name)')
          .eq('client_user_id', uid)
          .eq('is_walk_in', false)
          .order('scheduled_at', ascending: false)
          .limit(100);
      return [
        for (final r in rows)
          AppointmentModel.fromSupabase(Map<String, dynamic>.from(r)),
      ];
    });

    final dados = juntarReservas(
      mesas: await mesasF,
      corridas: await corridasF,
      limpezas: await limpezasF,
      marcacoes: await marcacoesF,
      agora: DateTime.now(),
    );
    return _Carga(dados, falhas);
  }

  Future<void> _recarregar() async {
    final f = _load();
    setState(() {
      _future = f;
    });
    await f;
  }

  void _abrirNoAdmin(ItemReserva item) {
    final Widget ecra = switch (item.tipo) {
      TipoReserva.mesa => const AdminReservationsScreen(),
      TipoReserva.corrida => item.grupo == GrupoReserva.proximas
          ? const AdminTvdeReservasScreen()
          : const AdminTvdeRidesScreen(),
      TipoReserva.limpeza =>
        AdminCleaningBookingsScreen(pesquisaInicial: widget.email),
      TipoReserva.marcacao => AdminAppointmentsScreen(
          pesquisaInicial: _nomeOuTelefone(item.origem)),
    };
    Navigator.push(context, MaterialPageRoute(builder: (_) => ecra));
  }

  String? _nomeOuTelefone(Object o) {
    if (o is! AppointmentModel) return null;
    final nome = (o.clientName ?? '').trim();
    if (nome.isNotEmpty) return nome;
    final tel = (o.clientPhone ?? '').trim();
    return tel.isEmpty ? null : tel;
  }

  @override
  Widget build(BuildContext context) {
    final quem = [
      if ((widget.nome ?? '').trim().isNotEmpty) widget.nome!.trim(),
      if ((widget.email ?? '').trim().isNotEmpty) widget.email!.trim(),
    ].join(' · ');

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: const BoraScreenAppBar(
          title: 'Reservas do cliente',
          bottom: TabBar(
            tabs: [
              Tab(text: 'Próximas'),
              Tab(text: 'Passadas'),
              Tab(text: 'Canceladas'),
            ],
          ),
        ),
        body: FutureBuilder<_Carga>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('Erro ao carregar: ${snap.error}'));
            }
            final carga = snap.data!;
            final d = carga.dados;
            Widget lista(List<ItemReserva> itens, String vazio) =>
                RefreshIndicator(
                  onRefresh: _recarregar,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      Text(
                        quem.isEmpty ? widget.userId : quem,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Mesma lista que o cliente vê no separador Reservas do '
                        'app. Horas em hora de Lisboa. Só leitura: para '
                        'cancelar, reembolsar ou reatribuir, abre o ecrã do '
                        'tipo (botão à direita).',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                      for (final f in carga.falhas.entries)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(10),
                          color: AppColors.warning.withValues(alpha: 0.12),
                          child: Text(
                              'Não carregou ${_tipoBr(f.key).toLowerCase()}: '
                              '${f.value}',
                              style: const TextStyle(fontSize: 12)),
                        ),
                      const SizedBox(height: 8),
                      if (itens.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Center(
                            child: Text(vazio,
                                style: const TextStyle(
                                    color: AppColors.textSecondary)),
                          ),
                        )
                      else
                        for (final i in itens)
                          _LinhaAdmin(
                            item: i,
                            onAbrir: () => _abrirNoAdmin(i),
                          ),
                    ],
                  ),
                );
            return TabBarView(
              children: [
                lista(d.proximas, 'Nada marcado para a frente.'),
                lista(d.passadas, 'Nada no histórico.'),
                lista(d.canceladas, 'Nada cancelado.'),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LinhaAdmin extends StatelessWidget {
  const _LinhaAdmin({required this.item, required this.onAbrir});
  final ItemReserva item;
  final VoidCallback onAbrir;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(_iconeBr(item.tipo), color: AppColors.primary),
        title: Text('${_tipoBr(item.tipo)} · ${_dataHora(item.quando)}'),
        subtitle: Text(
          [
            if ((item.sitio ?? '').trim().isNotEmpty) item.sitio!.trim(),
            'Situação: ${_estadoBr(item.estado)} (no banco: ${_bruto(item)})',
            'Pagamento: ${_pagamentoBr(item.pagamento)} '
                '(no banco: ${_pagamentoBruto(item)})',
            'ID: ${item.id}',
          ].join('\n'),
        ),
        isThreeLine: true,
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: item.id));
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('ID copiado.')));
        },
        trailing: IconButton(
          tooltip: 'Abrir no ecrã de ${_tipoBr(item.tipo).toLowerCase()}',
          icon: const Icon(Icons.open_in_new),
          onPressed: onAbrir,
        ),
      ),
    );
  }
}

String _dataHora(DateTime instante) {
  final l = paredeLisboa(instante);
  String dd(int n) => n.toString().padLeft(2, '0');
  return '${dd(l.day)}/${dd(l.month)}/${l.year} ${dd(l.hour)}:${dd(l.minute)}';
}

IconData _iconeBr(TipoReserva t) => switch (t) {
      TipoReserva.mesa => Icons.restaurant,
      TipoReserva.corrida => Icons.local_taxi,
      TipoReserva.limpeza => Icons.cleaning_services,
      TipoReserva.marcacao => Icons.content_cut,
    };

String _tipoBr(TipoReserva t) => switch (t) {
      TipoReserva.mesa => 'Mesa',
      TipoReserva.corrida => 'Corrida marcada',
      TipoReserva.limpeza => 'Limpeza',
      TipoReserva.marcacao => 'Marcação',
    };

String _estadoBr(EstadoReserva e) => switch (e) {
      EstadoReserva.aguardaPagamento => 'Aguardando pagamento',
      EstadoReserva.aguardaConfirmacao => 'Aguardando confirmação da loja',
      EstadoReserva.agendada => 'Agendada (sem profissional ainda)',
      EstadoReserva.procuraMotorista => 'Procurando motorista',
      EstadoReserva.confirmada => 'Confirmada',
      EstadoReserva.motoristaConfirmado => 'Motorista confirmado',
      EstadoReserva.aCaminho => 'A caminho',
      EstadoReserva.motoristaChegou => 'Motorista chegou',
      EstadoReserva.emCurso => 'Em andamento',
      EstadoReserva.porConfirmarFim =>
        'Feita — falta o cliente confirmar',
      EstadoReserva.concluida => 'Concluída',
      EstadoReserva.naoCompareceu => 'Não compareceu (no-show)',
      EstadoReserva.cancelada => 'Cancelada',
      EstadoReserva.semPrestador => 'Cancelada — ninguém disponível',
    };

String _pagamentoBr(PagamentoReserva p) => switch (p) {
      PagamentoReserva.pago => 'Pago',
      PagamentoReserva.porPagar => 'A pagar (pendente)',
      PagamentoReserva.emDinheiro => 'Em dinheiro, no local',
      PagamentoReserva.noPacote => 'Incluída no pacote ida e volta',
      PagamentoReserva.noPlano => 'Incluída no plano (assinatura)',
      PagamentoReserva.semPagamento => 'Sem pré-pagamento',
      PagamentoReserva.desconhecido => 'Ver no ecrã do tipo',
    };

/// O estado tal como está na tabela, para o Danilo cruzar com o SQL.
String _bruto(ItemReserva item) => switch (item.origem) {
      final ReservationModel r => r.status,
      final TvdeRide c => c.reservationStatus == null
          ? c.status
          : '${c.status} / reserva ${c.reservationStatus}',
      final CleaningBooking b => b.status.name,
      final AppointmentModel a => a.status,
      _ => '—',
    };

String _pagamentoBruto(ItemReserva item) => switch (item.origem) {
      final ReservationModel r =>
        'sinal ${(r.prepaymentCents / 100).toStringAsFixed(2)} €',
      final TvdeRide c => '${c.paymentMethod} ${c.paymentStatus ?? '-'}',
      final CleaningBooking b => '${b.paymentMethod} ${b.paymentStatus}',
      final AppointmentModel a =>
        'deposit_status ${a.depositStatus ?? '-'} · '
            'full_payment_status ${a.fullPaymentStatus ?? '-'}',
      _ => '—',
    };
