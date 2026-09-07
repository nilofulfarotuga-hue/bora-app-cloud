import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '../../services/admin_export_service.dart';

/// Contas encerradas a pedido do próprio (RGPD art. 17).
///
/// Lê `deleted_accounts`, que a Edge Function `delete-account` preenche a cada
/// encerramento. Cada linha diz **o que foi anonimizado** e **o que ficou
/// guardado por obrigação legal** — é esta a resposta a dar se alguém, ou o
/// regulador, perguntar o que aconteceu a uma conta.
///
/// Painel admin = PT-BR (só o Danilo usa).
class AdminDeletedAccountsScreen extends StatefulWidget {
  const AdminDeletedAccountsScreen({super.key});

  @override
  State<AdminDeletedAccountsScreen> createState() =>
      _AdminDeletedAccountsScreenState();
}

class _AdminDeletedAccountsScreenState
    extends State<AdminDeletedAccountsScreen> {
  List<Map<String, dynamic>> _linhas = const [];
  bool _carregando = true;
  String? _erro;
  String _busca = '';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final res = await Supabase.instance.client
          .from('deleted_accounts')
          .select()
          .order('encerrada_em', ascending: false)
          .limit(500);
      setState(() {
        _linhas = List<Map<String, dynamic>>.from(res as List);
        _carregando = false;
      });
    } catch (e) {
      setState(() {
        _erro = '$e';
        _carregando = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtradas {
    final q = _busca.trim().toLowerCase();
    if (q.isEmpty) return _linhas;
    return _linhas.where((l) {
      final alvo = [
        l['papel'],
        l['original_user_id'],
        l['email_hash'],
        l['motivo'],
        l['origem'],
      ].map((v) => '$v'.toLowerCase()).join(' ');
      return alvo.contains(q);
    }).toList();
  }

  /// Resume o JSON de prova numa frase legível: "carteira, tokens, 3 pedidos…".
  String _resumoAnonimizado(dynamic anonimizado) {
    if (anonimizado is! Map) return '—';
    final partes = <String>[];
    anonimizado.forEach((tabela, v) {
      if (v is! Map) return;
      final accao = '${v['accao']}';
      if (accao == 'nada_a_fazer' || accao == 'nao_aplicavel') return;
      final linhas = v['linhas'];
      final nome = _nomeAmigavel('$tabela');
      partes.add(linhas is int && linhas > 0 ? '$nome ($linhas)' : nome);
    });
    return partes.isEmpty ? '—' : partes.join(', ');
  }

  String _nomeAmigavel(String tabela) => const {
        'bora_tokens': 'tokens',
        'client_wallets': 'carteira',
        'orders': 'pedidos',
        'appointments': 'agendamentos',
        'reservations': 'reservas',
        'cleaning_bookings': 'limpezas',
        'drivers': 'entregador',
        'restaurants': 'loja',
        'service_providers': 'prestador',
        'cleaners': 'faxineiro',
        'washers': 'lavador',
        'users': 'perfil',
        'auth_users': 'acesso',
        'storage': 'arquivos',
        'dados_de_conveniencia': 'preferências',
      }[tabela] ??
      tabela;

  Future<void> _exportar() async {
    final headers = [
      'encerrada_em',
      'papel',
      'user_id_original',
      'email_hash',
      'anonimizado',
      'mantido',
      'motivo',
      'origem',
    ];
    final rows = _filtradas
        .map((l) => [
              '${l['encerrada_em']}',
              '${l['papel']}',
              '${l['original_user_id']}',
              '${l['email_hash']}',
              '${l['anonimizado']}',
              '${l['mantido']}',
              '${l['motivo'] ?? ''}',
              '${l['origem']}',
            ])
        .toList();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    await AdminExportService.instance.exportCsv(
      filename: 'bora_contas_encerradas_$stamp.csv',
      headers: headers,
      rows: rows,
      subject: 'Bora — Contas encerradas $stamp',
    );
  }

  @override
  Widget build(BuildContext context) {
    final linhas = _filtradas;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Contas encerradas',
        actions: [
          IconButton(
            onPressed: _carregando ? null : _carregar,
            tooltip: 'Recarregar',
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: linhas.isEmpty ? null : _exportar,
            tooltip: 'Exportar CSV',
            icon: const Icon(Icons.download),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar por papel, ID, hash do e-mail ou motivo',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _busca = v),
            ),
          ),
          if (_carregando)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_erro != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.lg),
                  child: Text('Não deu para carregar: $_erro',
                      textAlign: TextAlign.center),
                ),
              ),
            )
          else if (linhas.isEmpty)
            const Expanded(
              child: Center(
                child: Text('Nenhuma conta encerrada até agora.'),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                itemCount: linhas.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _Cartao(
                  linha: linhas[i],
                  resumo: _resumoAnonimizado(linhas[i]['anonimizado']),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(Spacing.sm),
            child: Text(
              '${linhas.length} de ${_linhas.length} conta(s)',
              style: TextStyle(color: AppColors.textSubtle, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _Cartao extends StatelessWidget {
  const _Cartao({required this.linha, required this.resumo});

  final Map<String, dynamic> linha;
  final String resumo;

  @override
  Widget build(BuildContext context) {
    final quando = DateTime.tryParse('${linha['encerrada_em']}')?.toLocal();
    final data = quando == null
        ? '${linha['encerrada_em']}'
        : '${quando.day.toString().padLeft(2, '0')}/'
            '${quando.month.toString().padLeft(2, '0')}/${quando.year} '
            '${quando.hour.toString().padLeft(2, '0')}:'
            '${quando.minute.toString().padLeft(2, '0')}';
    final mantido = linha['mantido'];
    final rasto = mantido is Map ? '${mantido['rasto_fiscal'] ?? ''}' : '';
    final loja = mantido is Map ? mantido['loja'] : null;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${linha['papel']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(data, style: TextStyle(color: AppColors.textSubtle)),
              ],
            ),
            const SizedBox(height: 6),
            _Par(rotulo: 'Anonimizado', valor: resumo),
            if (rasto.isNotEmpty) _Par(rotulo: 'Mantido', valor: rasto),
            if (loja != null) _Par(rotulo: 'Loja', valor: '$loja'),
            if ('${linha['motivo'] ?? ''}'.isNotEmpty)
              _Par(rotulo: 'Motivo', valor: '${linha['motivo']}'),
            const SizedBox(height: 4),
            SelectableText(
              'ID original: ${linha['original_user_id']}',
              style: TextStyle(fontSize: 11, color: AppColors.textSubtle),
            ),
            SelectableText(
              'Hash do e-mail: ${linha['email_hash']}',
              style: TextStyle(fontSize: 11, color: AppColors.textSubtle),
            ),
          ],
        ),
      ),
    );
  }
}

class _Par extends StatelessWidget {
  const _Par({required this.rotulo, required this.valor});

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style.copyWith(fontSize: 13),
          children: [
            TextSpan(
                text: '$rotulo: ',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: valor),
          ],
        ),
      ),
    );
  }
}
