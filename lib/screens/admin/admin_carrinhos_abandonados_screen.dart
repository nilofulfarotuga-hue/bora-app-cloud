import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Painel admin (PT-BR) — Carrinho abandonado (ronda 04/10/2026).
///
/// Como a Uber Eats e a Glovo: quem deixa produtos no carrinho e não faz o
/// pedido recebe UM push ("Ficou alguma coisa no teu carrinho 🛒") depois de
/// X minutos — no máximo 1 por carrinho e 1 por dia. Aqui o Danilo liga/desliga,
/// muda os minutos e o texto, e vê os números. Nasce DESLIGADO.
///
/// Servidor: tabela `carrinhos_abandonados`, cron `carrinhos-abandonados-15min`
/// (função `carrinhos_abandonados_avisar`), RPCs
/// `admin_carrinhos_abandonados_resumo` / `admin_carrinho_abandonado_config`.
class AdminCarrinhosAbandonadosScreen extends StatefulWidget {
  const AdminCarrinhosAbandonadosScreen({super.key});

  @override
  State<AdminCarrinhosAbandonadosScreen> createState() =>
      _AdminCarrinhosAbandonadosScreenState();
}

class _AdminCarrinhosAbandonadosScreenState
    extends State<AdminCarrinhosAbandonadosScreen> {
  final _sb = Supabase.instance.client;
  final _minutosCtrl = TextEditingController();
  final _tituloCtrl = TextEditingController();
  final _textoCtrl = TextEditingController();

  bool _carregando = true;
  bool _aGravar = false;
  String? _erro;
  Map<String, dynamic> _r = const {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _minutosCtrl.dispose();
    _tituloCtrl.dispose();
    _textoCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final res = await _sb.rpc('admin_carrinhos_abandonados_resumo');
      if (!mounted) return;
      _aplicar(Map<String, dynamic>.from(res as Map));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não deu para carregar: $e';
        _carregando = false;
      });
    }
  }

  void _aplicar(Map<String, dynamic> r) {
    setState(() {
      _r = r;
      _minutosCtrl.text = '${r['minutos'] ?? 60}';
      _tituloCtrl.text = '${r['titulo'] ?? ''}';
      _textoCtrl.text = '${r['texto'] ?? ''}';
      _carregando = false;
    });
  }

  Future<void> _gravar({bool? ligado}) async {
    if (_aGravar) return;
    final minutos = int.tryParse(_minutosCtrl.text.trim());
    if (minutos == null || minutos < 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Minutos inválidos (mínimo 5).')));
      return;
    }
    setState(() => _aGravar = true);
    try {
      final res = await _sb.rpc('admin_carrinho_abandonado_config', params: {
        'p_ligado': ligado ?? (_r['ligado'] == true),
        'p_minutos': minutos,
        'p_titulo': _tituloCtrl.text.trim(),
        'p_texto': _textoCtrl.text.trim(),
      });
      if (!mounted) return;
      _aplicar(Map<String, dynamic>.from(res as Map));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Gravado.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Não deu para gravar: $e')));
    } finally {
      if (mounted) setState(() => _aGravar = false);
    }
  }

  String _eur(Object? v) {
    final n = v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return '€${n.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final ligado = _r['ligado'] == true;
    final lista = (_r['lista'] as List?) ?? const [];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Carrinho abandonado'),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_erro!),
                ))
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: SwitchListTile(
                          value: ligado,
                          onChanged:
                              _aGravar ? null : (v) => _gravar(ligado: v),
                          activeColor: AppColors.primary,
                          title: const Text('Aviso de carrinho abandonado',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(ligado
                              ? 'LIGADO — o cliente recebe 1 push quando larga o carrinho.'
                              : 'DESLIGADO — ninguém recebe aviso.'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _Numero('Carrinhos abertos',
                              '${_r['carrinhos_abertos'] ?? 0}'),
                          _Numero('Valor parado', _eur(_r['valor_aberto'])),
                          _Numero('Avisados (7 dias)',
                              '${_r['avisados_7d'] ?? 0}'),
                          _Numero('Pediram depois do aviso (7 dias)',
                              '${_r['convertidos_apos_aviso_7d'] ?? 0}'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('Configuração',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _minutosCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Minutos até o aviso',
                          helperText:
                              'Depois da última mexida no carrinho. Máx. 1 aviso por carrinho e 1 por dia.',
                        ),
                      ),
                      TextField(
                        controller: _tituloCtrl,
                        maxLength: 80,
                        decoration:
                            const InputDecoration(labelText: 'Título do push'),
                      ),
                      TextField(
                        controller: _textoCtrl,
                        maxLength: 200,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Texto do push',
                          helperText: '{loja} vira o nome da loja.',
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _aGravar ? null : () => _gravar(),
                        icon: _aGravar
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.save),
                        label: const Text('Salvar'),
                      ),
                      const SizedBox(height: 20),
                      const Text('Últimos carrinhos',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      if (lista.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text('Nenhum carrinho registrado ainda.'),
                        ),
                      for (final raw in lista)
                        _LinhaCarrinho(
                          l: Map<String, dynamic>.from(raw as Map),
                          eur: _eur,
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _Numero extends StatelessWidget {
  const _Numero(this.titulo, this.valor);

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppColors.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(valor,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(titulo,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _LinhaCarrinho extends StatelessWidget {
  const _LinhaCarrinho({required this.l, required this.eur});

  final Map<String, dynamic> l;
  final String Function(Object?) eur;

  @override
  Widget build(BuildContext context) {
    final String estado;
    if (l['convertido_em'] != null) {
      estado = 'Fechado/pedido feito ${dataHoraLisboa(l['convertido_em'])}';
    } else if (l['avisado_em'] != null) {
      estado = 'Avisado ${dataHoraLisboa(l['avisado_em'])}';
    } else {
      estado = 'Aberto';
    }
    final cliente = '${l['cliente'] ?? ''}'.trim();
    return Card(
      child: ListTile(
        title: Text(
            '${cliente.isEmpty ? 'Cliente' : cliente} · ${l['loja'] ?? '—'}'),
        subtitle: Text(
            '${l['resumo'] ?? ''}\nMexido ${dataHoraLisboa(l['atualizado_em'])} · $estado'),
        isThreeLine: true,
        trailing: Text(eur(l['total']),
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
