import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../utils/hora_lisboa_ext.dart';
import '../../utils/telefone_internacional.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '_admin_rpc_errors.dart';

/// Painel admin (PT-BR) — Clientes sem telefone ou morada (28/11/2026).
///
/// Ordem do Danilo (09:38): o cliente entra na app sem telefone e sem morada,
/// mas para FAZER PEDIDO precisa dos dois. O servidor recusa com os motivos
/// `SEM_TELEFONE` / `SEM_MORADA` (gatilhos `_a0_pedido_exige_contacto` e
/// `trg_00a_exige_contacto`) e a app abre o passo "Falta só isto".
///
/// Aqui: quantos clientes não têm telefone ou morada, quem abriu o passo nos
/// últimos 30 dias e não terminou (com o motivo), e o botão para o Danilo pôr
/// ou corrigir o telefone de um cliente. Número estrangeiro → WhatsApp.
/// Dados: `admin_clientes_contacto_resumo()` e `admin_cliente_definir_telefone`.
class AdminClientesContactoScreen extends StatefulWidget {
  const AdminClientesContactoScreen({super.key});

  @override
  State<AdminClientesContactoScreen> createState() =>
      _AdminClientesContactoScreenState();
}

class _AdminClientesContactoScreenState
    extends State<AdminClientesContactoScreen> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  String? _erro;
  Map<String, dynamic> _resumo = const {};
  List<Map<String, dynamic>> _parados = const [];

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
      final r = await _sb
          .rpc('admin_clientes_contacto_resumo')
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      final m = r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
      setState(() {
        _resumo = m;
        _parados = ((m['parados'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = humanizeAdminRpcError(e);
        _loading = false;
      });
    }
  }

  Future<void> _definirTelefone(Map<String, dynamic> c) async {
    final ctrl = TextEditingController(text: (c['telefone'] ?? '').toString());
    final numero = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Telefone de ${c['nome'] ?? 'cliente'}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.phone,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Telefone',
            helperText:
                'Com indicativo do país (ex.: +5511987654321). Sem indicativo vale como Portugal.',
            helperMaxLines: 2,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Salvar')),
        ],
      ),
    );
    ctrl.dispose();
    if (numero == null || numero.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _sb.rpc('admin_cliente_definir_telefone', params: {
        'p_user': c['user_id'],
        'p_phone': numero,
      }).timeout(const Duration(seconds: 20));
      messenger.showSnackBar(
          const SnackBar(content: Text('Telefone salvo.')));
      await _carregar();
    } catch (e) {
      final txt = e.toString().contains('TELEFONE_INVALIDO')
          ? 'Número inválido. Confira o indicativo do país e o número.'
          : humanizeAdminRpcError(e);
      messenger.showSnackBar(SnackBar(content: Text(txt)));
    }
  }

  Future<void> _contactar(String telefone) async {
    final whats = digitosWhatsApp(telefone);
    final uri = telefoneEstrangeiro(telefone) && whats != null
        ? Uri.parse('https://wa.me/$whats')
        : Uri.parse('tel:${telefoneInternacional(telefone, kPaisTelefonePorDefeito.iso) ?? telefone}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static String _categoria(String? c) => switch (c) {
        'carrinho' || 'pagamento' => 'Pedido (carrinho)',
        'favor' => 'Favor',
        'casa' => 'Casa',
        'limpeza' => 'Limpeza',
        'lavagem' => 'Lavagem de carro',
        'marcacao' => 'Marcação',
        'reserva' => 'Reserva de mesa',
        null || '' => '—',
        _ => c,
      };

  Widget _numero(String titulo, Object? valor, Color cor) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text('${valor ?? 0}',
                    style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold, color: cor)),
                const SizedBox(height: 4),
                Text(titulo,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      );

  Widget _motivo(String texto, Color cor) => Container(
        margin: const EdgeInsets.only(right: 6, top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(texto,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: cor)),
      );

  Widget _linha(Map<String, dynamic> c) {
    final faltaTel = c['falta_telefone_agora'] == true;
    final faltaMor = c['falta_morada_agora'] == true;
    final tel = (c['telefone'] ?? '').toString();
    final quando = DateTime.tryParse((c['quando'] ?? '').toString());
    final quandoTxt = quando == null
        ? ''
        : () {
            final l = quando.toLisboa();
            String d(int n) => n.toString().padLeft(2, '0');
            return '${d(l.day)}/${d(l.month)} ${d(l.hour)}:${d(l.minute)}';
          }();
    return Card(
      child: ListTile(
        title: Text((c['nome'] ?? c['email'] ?? 'Sem nome').toString()),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_categoria(c['categoria']?.toString())} · $quandoTxt'
                '${tel.isEmpty ? '' : ' · $tel'}'),
            Wrap(children: [
              if (faltaTel)
                _motivo('SEM_TELEFONE — falta o telefone', AppColors.error),
              if (faltaMor)
                _motivo('SEM_MORADA — falta a morada exata', AppColors.accent),
              if (!faltaTel && !faltaMor)
                _motivo('Já tem os dois — só não terminou o pedido',
                    AppColors.primary),
            ]),
          ],
        ),
        isThreeLine: true,
        trailing: Wrap(
          spacing: 4,
          children: [
            if (tel.isNotEmpty && telefoneGuardadoValido(tel))
              IconButton(
                tooltip: telefoneEstrangeiro(tel)
                    ? 'Falar pelo WhatsApp (número estrangeiro)'
                    : 'Ligar',
                icon: Icon(telefoneEstrangeiro(tel)
                    ? Icons.chat_outlined
                    : Icons.phone_outlined),
                onPressed: () => _contactar(tel),
              ),
            IconButton(
              tooltip: 'Pôr ou corrigir o telefone',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _definirTelefone(c),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BoraScreenAppBar(
        title: 'Clientes sem telefone ou morada',
        actions: [
          IconButton(
              tooltip: 'Atualizar',
              icon: const Icon(Icons.refresh),
              onPressed: _carregar),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_erro!, textAlign: TextAlign.center),
                ))
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      const Text(
                        'Desde 28/11 o servidor só aceita pedidos, reservas, marcações, Casa, '
                        'limpeza e lavagem com telefone (de qualquer país) e, quando há entrega '
                        'ou visita, com a morada exata. Motivos: SEM_TELEFONE e SEM_MORADA. '
                        'A app pede o que falta no passo "Falta só isto".',
                        style: TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        _numero('Clientes', _resumo['clientes'],
                            AppColors.primary),
                        _numero('Sem telefone (SEM_TELEFONE)',
                            _resumo['sem_telefone'], AppColors.error),
                        _numero('Sem morada (SEM_MORADA)',
                            _resumo['sem_morada'], AppColors.accent),
                      ]),
                      const SizedBox(height: 12),
                      Text(
                        'Pararam no "Falta só isto" e não terminaram (últimos 30 dias): ${_parados.length}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      if (_parados.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Ninguém parado. Tudo certo.'),
                        ),
                      for (final c in _parados) _linha(c),
                    ],
                  ),
                ),
    );
  }
}
