// lib/widgets/admin/escolher_estafeta_sheet.dart
//
// [Estafeta web 2026-09-16 · BLOCO 5] Painel admin (PT-BR): "Escolher
// entregador" para um pedido. Um único fluxo, usado no detalhe do pedido e na
// lista de pedidos parados:
//
//   1. lista TODOS os entregadores aprovados (RPC admin_drivers_for_assignment):
//      disponíveis agora primeiro, ordenados pela distância à loja; foto, nome,
//      telefone, ligado/desligado, último sinal, notificações sim/não, como
//      usa a Bora (app Android / app iPhone / navegador…) e pedidos em curso;
//      pesquisa por nome ou telefone;
//   2. toque → confirmação. Se ele NÃO vai receber (desligado, sem sinal, GPS
//      parado ou sem notificações) aparece o aviso vermelho e o botão "Atribuir
//      mesmo assim" — a escolha fica registada no motivo da auditoria;
//   3. atribui pelo caminho oficial admin_reassign_order (que pré-atribui se o
//      pedido ainda não estiver pronto e avisa o entregador pela Edge
//      notify-driver-assigned). Nunca UPDATE direto.
//
// "Mandar para todos" (admin_release_order_driver) tira o entregador e devolve
// o pedido ao dispatch normal, com registro.
//
// [ronda-fecho 23/09 · A10] "Ligado agora" passou a exigir também GPS fresco
// (servidor: `online_agora` = heartbeat < 90 s E `gps_fresco`). A RPC devolve
// `gps_age_s`/`gps_fresco`; quem tem o GPS parado leva o chip vermelho
// "GPS parado há X min" e, no aviso da confirmação, é esse o motivo que se lê.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../utils/gps_parado.dart';

/// Rótulo humano da plataforma registada pelo heartbeat.
String plataformaLabel(String? p) {
  switch (p) {
    case 'android_app':
      return 'App Android';
    case 'ios_app':
      return 'App iPhone';
    case 'web_ios':
      return 'Navegador iPhone';
    case 'web_android':
      return 'Navegador Android';
    case 'web_desktop':
      return 'Computador';
    default:
      return 'Não registrado';
  }
}

String haQuantoTempo(DateTime? t) {
  if (t == null) return 'nunca';
  final d = DateTime.now().difference(t.toLocal());
  if (d.inSeconds < 60) return 'há ${d.inSeconds} s';
  if (d.inMinutes < 60) return 'há ${d.inMinutes} min';
  if (d.inHours < 48) return 'há ${d.inHours} h';
  return 'há ${d.inDays} dias';
}

class EstafetaParaAtribuir {
  EstafetaParaAtribuir.fromRow(Map<String, dynamic> r)
      : userId = (r['user_id'] ?? '').toString(),
        driverId = (r['driver_id'] ?? '').toString(),
        nome = (r['name'] ?? 'Entregador').toString(),
        telefone = (r['phone'] ?? '').toString(),
        fotoUrl = r['photo_url']?.toString(),
        veiculo = r['vehicle_type']?.toString(),
        ligado = r['is_online'] == true,
        ligadoAgora = r['online_agora'] == true,
        ultimoSinal = DateTime.tryParse(r['last_heartbeat_at']?.toString() ?? ''),
        temNotificacoes = r['tem_notificacoes'] == true,
        plataforma = r['last_platform']?.toString(),
        pedidosEmCurso = (r['pedidos_em_curso'] as num?)?.toInt() ?? 0,
      distanciaKm = (r['distancia_km'] as num?)?.toDouble(),
      gpsAgeS = (r['gps_age_s'] as num?)?.toInt(),
      // Só é "parado" quando o servidor o diz; sem a coluna (RPC antiga)
      // não se inventa alarme.
      gpsFresco = r['gps_fresco'] != false;

  final String userId;
  final String driverId;
  final String nome;
  final String telefone;
  final String? fotoUrl;
  final String? veiculo;
  final bool ligado;
  final bool ligadoAgora;
  final DateTime? ultimoSinal;
  final bool temNotificacoes;
  final String? plataforma;
  final int pedidosEmCurso;
  final double? distanciaKm;

  /// Segundos desde a última posição GPS (null = nunca mandou posição).
  final int? gpsAgeS;

  /// Posição GPS dentro de `dispatch_gps_fresh_seconds` (180 s). Sem isto o
  /// servidor não o considera ligado agora, mesmo com heartbeat vivo.
  final bool gpsFresco;

  /// Vai receber o pedido? (ligado agora — heartbeat vivo E GPS fresco, já
  /// decidido no servidor — e notificações registadas)
  bool get vaiReceber => ligadoAgora && temNotificacoes;

  /// Heartbeat recebido nos últimos 90 s (o mesmo limite do servidor).
  bool get sinalFresco =>
      ultimoSinal != null &&
      DateTime.now().toUtc().difference(ultimoSinal!.toUtc()).inSeconds <= 90;

  /// Porque é que NÃO vai receber, em palavras simples (vai para o aviso
  /// vermelho e para o motivo da auditoria). Heartbeat vivo mas GPS parado é
  /// o caso da app morta com o serviço em segundo plano a bater: aí a causa
  /// é o GPS e diz-se "GPS parado há X min".
  String get motivoNaoRecebe {
    final m = <String>[];
    if (!ligadoAgora) {
      if (!ligado) {
        m.add('desligado');
      } else if (sinalFresco && !gpsFresco) {
        m.add(gpsParadoTexto(gpsAgeS));
      } else {
        m.add('sem sinal há mais de 90 s');
      }
    }
    if (!temNotificacoes) m.add('sem notificações neste aparelho');
    return m.join(' e ');
  }
}

/// Abre o fluxo completo. Devolve true se o pedido ficou atribuído/reservado.
Future<bool> escolherEstafetaParaPedido(
  BuildContext context, {
  required String orderId,
  required String status,
}) async {
  final escolhido = await showModalBottomSheet<EstafetaParaAtribuir>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _EscolherEstafetaSheet(orderId: orderId, status: status),
  );
  if (escolhido == null || !context.mounted) return false;

  final aindaNaoPronto = !const ['callingDriver', 'driverAccepted', 'pickedUp', 'onTheWay'].contains(status);
  final forcar = !escolhido.vaiReceber;

  final confirmado = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(aindaNaoPronto ? 'Reservar para ${escolhido.nome}?' : 'Atribuir a ${escolhido.nome}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(aindaNaoPronto
              ? 'O pedido ainda não está pronto. Fica reservado: quando a loja marcar pronto, '
                  'a oferta vai primeiro para ele (tempo normal). Se não aceitar ou estiver '
                  'desligado, o pedido segue para todos.'
              : 'O pedido passa já para este entregador e ele recebe o aviso no aparelho.'),
          if (forcar) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                border: Border.all(color: const Color(0xFFFCA5A5)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFB91C1C)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Este entregador NÃO vai receber o aviso: ${escolhido.motivoNaoRecebe}. '
                      '${escolhido.motivoNaoRecebe.contains('GPS parado') ? 'A app dele deixou de mandar a posição (fechou ou perdeu o GPS) — peça-lhe para abrir a Bora. ' : ''}'
                      'Se atribuir mesmo assim, o pedido pode ficar parado — a rede de segurança '
                      'liberta-o em 3 minutos e avisa você.',
                      style: const TextStyle(color: Color(0xFF7F1D1D), fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(
          style: forcar ? FilledButton.styleFrom(backgroundColor: const Color(0xFFB91C1C)) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(forcar ? 'Atribuir mesmo assim' : (aindaNaoPronto ? 'Reservar' : 'Atribuir')),
        ),
      ],
    ),
  );
  if (confirmado != true || !context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);
  try {
    final res = await Supabase.instance.client.rpc('admin_reassign_order', params: {
      'p_order_id': orderId,
      'p_new_driver': escolhido.userId,
      'p_motivo': forcar
          ? 'escolhido no painel — ATRIBUÍDO MESMO ASSIM (${escolhido.motivoNaoRecebe})'
          : 'escolhido no painel',
    });
    final data = res is Map ? Map<String, dynamic>.from(res) : const <String, dynamic>{};
    if (data['ok'] == true) {
      final reservado = data['pre_atribuicao'] == true;
      messenger.showSnackBar(SnackBar(
        content: Text(reservado
            ? 'Pedido reservado para ${data['estafeta'] ?? escolhido.nome}. Recebe a oferta quando ficar pronto.'
            : 'Pedido atribuído a ${data['estafeta'] ?? escolhido.nome}. Aviso enviado.'),
      ));
      return true;
    }
    messenger.showSnackBar(SnackBar(content: Text('Não foi possível: ${_erroLegivel(data['error'])}')));
    return false;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Erro ao atribuir: $e')));
    return false;
  }
}

/// "Mandar para todos": tira o entregador e devolve ao dispatch. true se feito.
Future<bool> mandarPedidoParaTodos(BuildContext context, {required String orderId}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Mandar para todos?'),
      content: const Text(
        'Tira o entregador deste pedido (ou a reserva) e devolve-o ao dispatch normal: '
        'volta a tocar a quem estiver disponível. O entregador é avisado.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mandar para todos')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final res = await Supabase.instance.client.rpc('admin_release_order_driver', params: {
      'p_order_id': orderId,
      'p_motivo': 'mandar para todos (painel)',
    });
    final data = res is Map ? Map<String, dynamic>.from(res) : const <String, dynamic>{};
    if (data['ok'] == true) {
      messenger.showSnackBar(const SnackBar(content: Text('Pedido devolvido ao dispatch.')));
      return true;
    }
    messenger.showSnackBar(SnackBar(content: Text('Não foi possível: ${_erroLegivel(data['error'])}')));
    return false;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Erro: $e')));
    return false;
  }
}

String _erroLegivel(Object? e) {
  switch (e?.toString()) {
    case 'pedido_nao_encontrado':
      return 'pedido não encontrado';
    case 'pedido_ja_terminal':
      return 'o pedido já terminou';
    case 'estafeta_nao_encontrado':
      return 'entregador não encontrado';
    case 'estafeta_nao_aprovado':
      return 'entregador não aprovado';
    case 'takeaway_sem_estafeta':
      return 'pedido de recolha, não leva entregador';
    case 'estafeta_ja_tem_a_encomenda':
      return 'o entregador já tem a encomenda com ele';
    default:
      return e?.toString() ?? 'erro';
  }
}

class _EscolherEstafetaSheet extends StatefulWidget {
  const _EscolherEstafetaSheet({required this.orderId, required this.status});
  final String orderId;
  final String status;

  @override
  State<_EscolherEstafetaSheet> createState() => _EscolherEstafetaSheetState();
}

class _EscolherEstafetaSheetState extends State<_EscolherEstafetaSheet> {
  List<EstafetaParaAtribuir> _todos = const [];
  bool _loading = true;
  String? _erro;
  String _pesquisa = '';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final res = await Supabase.instance.client.rpc('admin_drivers_for_assignment', params: {
        'p_order_id': widget.orderId,
        'p_search': null,
      });
      final lista = (res is List)
          ? res.whereType<Map>().map((e) => EstafetaParaAtribuir.fromRow(Map<String, dynamic>.from(e))).toList()
          : <EstafetaParaAtribuir>[];
      if (!mounted) return;
      setState(() {
        _todos = lista;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _loading = false;
      });
    }
  }

  List<EstafetaParaAtribuir> get _visiveis {
    final q = _pesquisa.trim().toLowerCase();
    if (q.isEmpty) return _todos;
    return _todos.where((d) => d.nome.toLowerCase().contains(q) || d.telefone.contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final disponiveis = _visiveis.where((d) => d.ligadoAgora).length;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Escolher entregador',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  tooltip: 'Atualizar',
                  onPressed: _loading ? null : _carregar,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            Text(
              _loading
                  ? 'A carregar…'
                  : '$disponiveis disponível(is) agora · ${_visiveis.length} aprovado(s). Ordenados pela distância à loja.',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Pesquisar por nome ou telefone',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _pesquisa = v),
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_erro != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text('Não foi possível carregar: $_erro',
                    textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
              )
            else if (_visiveis.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Nenhum entregador encontrado.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _visiveis.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _EstafetaTile(
                    d: _visiveis[i],
                    onTap: () => Navigator.pop(context, _visiveis[i]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EstafetaTile extends StatelessWidget {
  const _EstafetaTile({required this.d, required this.onTap});
  final EstafetaParaAtribuir d;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final corEstado = d.ligadoAgora ? Colors.green.shade700 : Colors.grey.shade600;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 6),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: Colors.grey.shade200,
        backgroundImage: (d.fotoUrl != null && d.fotoUrl!.isNotEmpty) ? NetworkImage(d.fotoUrl!) : null,
        child: (d.fotoUrl == null || d.fotoUrl!.isEmpty)
            ? Icon(Icons.person, color: Colors.grey.shade600)
            : null,
      ),
      title: Row(
        children: [
          Expanded(child: Text(d.nome, style: const TextStyle(fontWeight: FontWeight.w600))),
          if (d.distanciaKm != null)
            Text('${d.distanciaKm!.toStringAsFixed(1).replaceAll('.', ',')} km',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (d.telefone.isNotEmpty)
              Text(d.telefone, style: const TextStyle(fontSize: 12)),
            _Chip(
              icon: Icons.circle,
              iconColor: corEstado,
              text: d.ligadoAgora ? 'Ligado agora' : 'Desligado',
              cor: d.ligadoAgora ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6),
            ),
            _Chip(
              icon: Icons.wifi_tethering,
              text: 'sinal ${haQuantoTempo(d.ultimoSinal)}',
            ),
            if (!d.gpsFresco)
              _Chip(
                icon: Icons.gps_off,
                iconColor: const Color(0xFFB91C1C),
                corTexto: const Color(0xFF7F1D1D),
                text: gpsParadoTexto(d.gpsAgeS),
                cor: const Color(0xFFFEE2E2),
              ),
            _Chip(
              icon: d.temNotificacoes ? Icons.notifications_active : Icons.notifications_off,
              text: d.temNotificacoes ? 'notificações: sim' : 'notificações: NÃO',
              cor: d.temNotificacoes ? null : const Color(0xFFFEE2E2),
            ),
            _Chip(icon: Icons.devices, text: plataformaLabel(d.plataforma)),
            if (d.pedidosEmCurso > 0)
              _Chip(icon: Icons.delivery_dining, text: '${d.pedidosEmCurso} em curso'),
          ],
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.text,
    this.cor,
    this.iconColor,
    this.corTexto,
  });
  final IconData icon;
  final String text;
  final Color? cor;
  final Color? iconColor;
  final Color? corTexto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cor ?? const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: iconColor ?? Colors.grey.shade700),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: corTexto,
              fontWeight: corTexto == null ? null : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
