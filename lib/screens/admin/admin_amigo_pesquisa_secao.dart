// Painel /admin/assistente — separador "Amigo Bora", secção "Pesquisa na internet"
// (missão fechar-tudo-2026-11-11, bloco 2). PT-BR, termos técnicos explicados.
//
// O Amigo pode pesquisar na internet (ferramenta web_search da API do Claude) para o tempo, a agenda da
// Guarda, notícias e a farmácia de serviço. Aqui: o interruptor, o máximo de pesquisas por mensagem
// (1 a 5) e quantas pesquisas foram feitas hoje e no mês (lidas de ia_gastos, ~0,01 US$ cada).
// Gravar usa admin_amigo_pesquisa_definir (fica na auditoria). Nada aqui mexe em dinheiro de clientes.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';

typedef AdminAmigoPesquisaCarregar = Future<Map<String, dynamic>?> Function();
typedef AdminAmigoPesquisaDefinir = Future<void> Function(Map<String, Object> mudancas);

/// Máximo de pesquisas por mensagem que o painel oferece (o servidor recusa fora disto).
const List<int> kAdminAmigoPesquisaUsos = [1, 2, 3, 4, 5];

int _int(Object? v, int padrao) => v is num ? v.round() : int.tryParse('${v ?? ''}') ?? padrao;

String _usd(Object? v) {
  final n = v is num ? v : num.tryParse('${v ?? 0}') ?? 0;
  return 'US\$ ${n.toStringAsFixed(2)}';
}

class AdminAmigoPesquisaSecao extends StatefulWidget {
  const AdminAmigoPesquisaSecao({super.key, this.carregar, this.definir});

  /// Trocáveis nos testes (por defeito, o Supabase).
  final AdminAmigoPesquisaCarregar? carregar;
  final AdminAmigoPesquisaDefinir? definir;

  @override
  State<AdminAmigoPesquisaSecao> createState() => _AdminAmigoPesquisaSecaoState();
}

class _AdminAmigoPesquisaSecaoState extends State<AdminAmigoPesquisaSecao> {
  Map<String, dynamic>? _v;
  bool _carregando = true;
  bool _semServidor = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, dynamic>?> _carregarSupabase() async {
    final r = await Supabase.instance.client.rpc('admin_amigo_pesquisa_overview');
    return r is Map ? Map<String, dynamic>.from(r) : null;
  }

  Future<void> _definirSupabase(Map<String, Object> m) async {
    await Supabase.instance.client.rpc('admin_amigo_pesquisa_definir', params: m);
  }

  Future<void> _load() async {
    setState(() => _carregando = true);
    try {
      final v = await (widget.carregar ?? _carregarSupabase)();
      if (!mounted) return;
      setState(() {
        _v = v;
        _semServidor = v == null;
        _carregando = false;
      });
    } catch (e) {
      debugPrint('[AdminAmigoPesquisa] $e');
      if (!mounted) return;
      setState(() {
        _semServidor = true;
        _carregando = false;
      });
    }
  }

  Future<void> _definir(Map<String, Object> m, String oQue) async {
    try {
      await (widget.definir ?? _definirSupabase)(m);
      _aviso('Salvo: $oQue (fica na auditoria)');
      await _load();
    } catch (e) {
      _aviso('Não salvei $oQue: $e');
    }
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Map<String, dynamic> _mapa(String k) => Map<String, dynamic>.from((_v?[k] as Map?) ?? const {});

  @override
  Widget build(BuildContext context) {
    final d = _mapa('definicoes');
    final hoje = _mapa('hoje');
    final mes = _mapa('mes');
    final ativo = d['assistant_web_search_enabled'] == true;
    final lido = _int(d['assistant_web_search_max_uses'], 3);
    final maxUsos = lido < 1 ? 1 : (lido > 5 ? 5 : lido);
    final podeGravar = !_semServidor && !_carregando;

    return Column(
      key: const Key('admin-amigo-pesquisa'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Pesquisa na internet',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 4),
        const Text(
          'O Amigo pesquisa na internet (ferramenta web_search da API do Claude) só para o tempo, a agenda e os '
          'eventos da Guarda, notícias e a farmácia de serviço — nunca para produtos, preços ou lojas da Bora. '
          'Cada pesquisa custa cerca de US\$ 0,01 do crédito dos robôs (mais os tokens) e fica registrada em '
          'ia_gastos. Desligada, o Amigo responde que não sabe, como antes.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        if (_semServidor && !_carregando)
          Container(
            key: const Key('admin-amigo-pesquisa-sem-migracao'),
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'A pesquisa na internet ainda não existe no banco (migração 20261111090000_amigo_pesquisa_e_lojas_abertas '
              'por aplicar). Enquanto isso o Amigo não pesquisa.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        SwitchListTile(
          key: const Key('admin-amigo-pesquisa-ativo'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Pesquisa na internet ligada (assistant_web_search_enabled)'),
          subtitle: const Text('Desligada = nenhuma pesquisa e nenhum gasto com ela.'),
          value: ativo,
          onChanged: podeGravar
              ? (x) => _definir({'p_ativo': x}, 'pesquisa na internet ${x ? 'ligada' : 'desligada'}')
              : null,
        ),
        Row(
          children: [
            const Expanded(
              child: Text('Máximo de pesquisas por mensagem (assistant_web_search_max_uses)',
                  style: TextStyle(fontSize: 13)),
            ),
            DropdownButton<int>(
              key: const Key('admin-amigo-pesquisa-max'),
              value: maxUsos,
              items: [
                for (final n in kAdminAmigoPesquisaUsos) DropdownMenuItem(value: n, child: Text('$n')),
              ],
              onChanged: podeGravar
                  ? (n) {
                      if (n != null && n != maxUsos) _definir({'p_max_usos': n}, 'máximo de $n pesquisas por mensagem');
                    }
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_carregando)
          const LinearProgressIndicator()
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Numero(
                key: const Key('admin-amigo-pesquisa-hoje'),
                titulo: 'Pesquisas hoje',
                valor: '${_int(hoje['pesquisas'], 0)}',
                detalhe: '${_int(hoje['chamadas'], 0)} respostas com pesquisa · ${_usd(hoje['usd'])}',
              ),
              _Numero(
                key: const Key('admin-amigo-pesquisa-mes'),
                titulo: 'Pesquisas no mês',
                valor: '${_int(mes['pesquisas'], 0)}',
                detalhe: '${_int(mes['chamadas'], 0)} respostas com pesquisa · ${_usd(mes['usd'])}',
              ),
            ],
          ),
      ],
    );
  }
}

class _Numero extends StatelessWidget {
  const _Numero({super.key, required this.titulo, required this.valor, required this.detalhe});
  final String titulo;
  final String valor;
  final String detalhe;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 4),
          Text(valor, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(detalhe, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
