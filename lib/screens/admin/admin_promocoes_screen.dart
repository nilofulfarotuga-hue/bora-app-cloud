/// PROMOÇÕES COM PREÇO RISCADO — o ecrã do admin (adendo 5 · item 4, 29/10/2026).
/// Painel em PT-BR.
///
/// Mostra: o interruptor geral e se o servidor já aplica o preço promocional; a
/// lista de promoções (ativas, agendadas, expiradas, desligadas e sem datas) com
/// filtro; ligar/desligar cada uma; criar uma promoção para qualquer produto; e a
/// auditoria (quem criou, mudou, ligou ou desligou).
///
/// Desligado (o estado de fábrica), nada muda para os clientes. Mesmo ligado, a
/// app só mostra preço riscado quando o servidor já aplica a promoção.
library;

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/promocao.dart';
import '../../services/promocoes_service.dart';

class AdminPromocoesScreen extends StatefulWidget {
  const AdminPromocoesScreen({super.key, this.api, this.relogio});

  /// Só para testes: troca o servidor por uma porta de mentira.
  final PromocoesApi? api;

  /// Só para testes: relógio fixo.
  final DateTime Function()? relogio;

  @override
  State<AdminPromocoesScreen> createState() => _AdminPromocoesScreenState();
}

enum _Filtro { todas, ativas, agendadas, expiradas, desligadas, semDatas }

class _AdminPromocoesScreenState extends State<AdminPromocoesScreen> {
  late final PromocoesApi _api = widget.api ?? PromocoesApiSupabase();
  DateTime _agora() => (widget.relogio ?? DateTime.now)();

  EstadoPromocoes _estado = const EstadoPromocoes(ligado: false, servidorPronto: false);
  List<PromocaoAdmin> _lista = const [];
  List<AuditoriaPromocao> _auditoria = const [];
  _Filtro _filtro = _Filtro.todas;
  bool _carregando = true;
  bool _ocupado = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  void _msg(String t, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(t),
      backgroundColor: erro ? AppColors.error : null,
    ));
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final estado = await _api.estadoGeral();
      final lista = await _api.lista();
      List<AuditoriaPromocao> auditoria = const [];
      try {
        auditoria = await _api.auditoria(limite: 40);
      } catch (_) {
        // A auditoria é um extra: se falhar, a lista continua a servir.
      }
      if (!mounted) return;
      setState(() {
        _estado = estado;
        _lista = lista;
        _auditoria = auditoria;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = mensagemErroPromocao(e);
        _carregando = false;
      });
    }
  }

  Future<bool> _confirmar(String titulo, String texto, String ok) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _mudarInterruptor(bool ligar) async {
    if (_ocupado) return;
    if (ligar) {
      final aviso = _estado.servidorPronto
          ? ''
          : '\n\nAtenção: o servidor ainda NÃO aplica o preço promocional. Até isso estar feito, '
              'a app não mostra preço riscado e nada muda para os clientes.';
      final ok = await _confirmar(
        'Ligar as promoções?',
        'Com isto ligado, as promoções ativas passam a aparecer com o preço antigo riscado e o '
            'servidor cobra o preço promocional. A comissão da Bora, o markup e as taxas calculam-se '
            'sobre o preço promocional.$aviso',
        'Ligar',
      );
      if (!ok) return;
    }
    setState(() => _ocupado = true);
    try {
      await _api.definirInterruptor(ligar);
      await _carregar();
      _msg(ligar ? 'Promoções ligadas.' : 'Promoções desligadas.');
    } catch (e) {
      _msg(mensagemErroPromocao(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _alternar(PromocaoAdmin p, bool ativada) async {
    if (_ocupado) return;
    if (!ativada) {
      final ok = await _confirmar(
        'Desligar esta promoção?',
        '"${p.produto}" volta ao preço normal. Os dados da promoção ficam guardados e podes ligá-la outra vez.',
        'Desligar',
      );
      if (!ok) return;
    }
    setState(() => _ocupado = true);
    try {
      await _api.ligarDesligar(p.productId, ativada);
      await _carregar();
      _msg(ativada ? 'Promoção ligada.' : 'Promoção desligada.');
    } catch (e) {
      _msg(mensagemErroPromocao(e), erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _nova() async {
    final criada = await showDialog<bool>(
      context: context,
      builder: (_) => _NovaPromocaoDialog(api: _api),
    );
    if (criada == true) {
      await _carregar();
      _msg('Promoção criada.');
    }
  }

  EstadoPromocao _estadoDe(PromocaoAdmin p) => p.estado(_agora());

  bool _passaCom(_Filtro f, PromocaoAdmin p) {
    final e = _estadoDe(p);
    switch (f) {
      case _Filtro.todas:
        return true;
      case _Filtro.ativas:
        return e == EstadoPromocao.ativa;
      case _Filtro.agendadas:
        return e == EstadoPromocao.agendada;
      case _Filtro.expiradas:
        return e == EstadoPromocao.expirada;
      case _Filtro.desligadas:
        return e == EstadoPromocao.desligada;
      case _Filtro.semDatas:
        return e == EstadoPromocao.semDatas || e == EstadoPromocao.invalida;
    }
  }

  int _conta(_Filtro f) => _lista.where((p) => _passaCom(f, p)).length;

  static String _eur(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} €';

  static String _fmt(DateTime d) {
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(d.day)}/${dois(d.month)}/${d.year} ${dois(d.hour)}:${dois(d.minute)}';
  }

  static String _rotulo(_Filtro f) => switch (f) {
        _Filtro.todas => 'Todas',
        _Filtro.ativas => 'Ativas',
        _Filtro.agendadas => 'Agendadas',
        _Filtro.expiradas => 'Expiradas',
        _Filtro.desligadas => 'Desligadas',
        _Filtro.semDatas => 'Sem datas',
      };

  static (String, Color) _chip(EstadoPromocao e) => switch (e) {
        EstadoPromocao.ativa => ('Ativa', AppColors.primary),
        EstadoPromocao.agendada => ('Agendada', Colors.blueGrey),
        EstadoPromocao.expirada => ('Expirada', Colors.grey),
        EstadoPromocao.desligada => ('Desligada', Colors.orange.shade800),
        EstadoPromocao.semDatas => ('Sem datas (não é aplicada)', Colors.orange.shade800),
        EstadoPromocao.invalida => ('Preço inválido (não é aplicada)', AppColors.error),
      };

  @override
  Widget build(BuildContext context) {
    final visiveis = _lista.where((p) => _passaCom(_filtro, p)).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Promoções'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_erro!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _carregar, child: const Text('Tentar de novo')),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    _cartaoInterruptor(),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Promoções (${_lista.length})',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                          ),
                        ),
                        FilledButton.icon(
                          key: const Key('promo_nova'),
                          onPressed: _ocupado ? null : _nova,
                          icon: const Icon(Icons.add),
                          label: const Text('Nova promoção'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final f in _Filtro.values)
                          ChoiceChip(
                            key: Key('promo_filtro_${f.name}'),
                            label: Text('${_rotulo(f)} (${_conta(f)})'),
                            selected: _filtro == f,
                            onSelected: (_) => setState(() => _filtro = f),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (visiveis.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          _lista.isEmpty
                              ? 'Ainda não há nenhuma promoção. Os parceiros criam as deles no ecrã de editar produto, ou cria uma aqui.'
                              : 'Nenhuma promoção neste filtro.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ),
                    for (final p in visiveis) _tile(p),
                    const SizedBox(height: 12),
                    _auditoriaTile(),
                  ],
                ),
    );
  }

  Widget _cartaoInterruptor() {
    final pronto = _estado.servidorPronto;
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            key: const Key('promo_interruptor'),
            title: const Text('Promoções com preço riscado'),
            subtitle: Text(_estado.ligado
                ? 'Ligado: as promoções ativas aparecem riscadas na app (se o servidor já as aplicar).'
                : 'Desligado: a app não mostra preço riscado e o servidor não aplica nenhuma promoção.'),
            value: _estado.ligado,
            onChanged: _ocupado ? null : _mudarInterruptor,
          ),
          ListTile(
            key: const Key('promo_servidor'),
            leading: Icon(pronto ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                color: pronto ? AppColors.primary : Colors.orange.shade800),
            title: Text(pronto
                ? 'O servidor já aplica o preço promocional.'
                : 'O servidor ainda NÃO aplica o preço promocional.'),
            subtitle: pronto
                ? const Text('A comissão da Bora, o markup e as taxas calculam-se sobre o preço promocional.')
                : const Text('Enquanto isso não estiver feito, a app não mostra preço riscado, mesmo com o interruptor ligado.'),
          ),
        ],
      ),
    );
  }

  Widget _tile(PromocaoAdmin p) {
    final e = _estadoDe(p);
    final (rotulo, cor) = _chip(e);
    final desconto = p.preco > 0 ? ((1 - p.precoPromocional / p.preco) * 100).round() : 0;
    final periodo = p.inicio == null
        ? 'Sem data de início: o servidor não a aplica até lhe dares datas.'
        : 'De ${_fmt(p.inicio!)} ${p.fim == null ? 'sem data de fim' : 'até ${_fmt(p.fim!)}'}';
    return Card(
      key: Key('promo_item_${p.productId}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(p.produto,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(rotulo,
                      key: Key('promo_estado_${p.productId}'),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cor)),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text('${p.loja} · ${p.lojaParceira ? 'loja parceira' : 'loja não parceira'}',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
            const SizedBox(height: 4),
            Text('Preço normal ${_eur(p.preco)} → promocional ${_eur(p.precoPromocional)} (−$desconto%) · preço de catálogo'),
            Text(periodo, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
            if (p.maisBaixo30d != null)
              Text('Preço mais baixo dos últimos 30 dias: ${_eur(p.maisBaixo30d!)}',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
            if (p.aoPeso)
              Text('Produto vendido ao peso: o servidor não aplica promoção.',
                  style: TextStyle(color: Colors.orange.shade800, fontSize: 13)),
            if (p.criadaPor != null)
              Text('Criada por ${p.criadaPor}',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(p.ativada ? 'Ligada' : 'Desligada'),
                  Switch(
                    key: Key('promo_switch_${p.productId}'),
                    value: p.ativada,
                    onChanged: _ocupado ? null : (v) => _alternar(p, v),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _auditoriaTile() {
    return Card(
      child: ExpansionTile(
        key: const Key('promo_auditoria'),
        title: Text('Auditoria (${_auditoria.length})'),
        subtitle: const Text('Quem criou, mudou, ligou e desligou'),
        children: [
          if (_auditoria.isEmpty)
            const ListTile(title: Text('Ainda não há registos.')),
          for (final a in _auditoria)
            ListTile(
              dense: true,
              title: Text('${a.descricao}${a.produto == null ? '' : ': ${a.produto}'}'),
              subtitle: Text('${a.quando == null ? '' : '${_fmt(a.quando!)} · '}${a.quem}'),
            ),
        ],
      ),
    );
  }
}

// ─── Criar uma promoção ─────────────────────────────────────────────────────

class _NovaPromocaoDialog extends StatefulWidget {
  const _NovaPromocaoDialog({required this.api});
  final PromocoesApi api;

  @override
  State<_NovaPromocaoDialog> createState() => _NovaPromocaoDialogState();
}

class _NovaPromocaoDialogState extends State<_NovaPromocaoDialog> {
  final _busca = TextEditingController();
  final _preco = TextEditingController();
  List<ProdutoPesquisa> _achados = const [];
  ProdutoPesquisa? _escolhido;
  DateTime? _inicio;
  DateTime? _fim;
  bool _aProcurar = false;
  bool _ocupado = false;
  String? _erro;

  @override
  void dispose() {
    _busca.dispose();
    _preco.dispose();
    super.dispose();
  }

  Future<void> _procurar() async {
    setState(() {
      _aProcurar = true;
      _erro = null;
    });
    try {
      final r = await widget.api.procurarProdutos(_busca.text);
      if (!mounted) return;
      setState(() => _achados = r);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemErroPromocao(e));
    } finally {
      if (mounted) setState(() => _aProcurar = false);
    }
  }

  Future<void> _data({required bool inicio}) async {
    final hoje = DateTime.now();
    final r = await showDatePicker(
      context: context,
      initialDate: hoje,
      firstDate: DateTime(hoje.year, hoje.month, hoje.day),
      lastDate: hoje.add(const Duration(days: 365)),
    );
    if (r == null || !mounted) return;
    setState(() {
      if (inicio) {
        _inicio = DateTime(r.year, r.month, r.day);
      } else {
        _fim = DateTime(r.year, r.month, r.day, 23, 59, 59);
      }
    });
  }

  static String _dia(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _criar() async {
    final p = _escolhido;
    if (p == null || _ocupado) return;
    final x = double.tryParse(_preco.text.trim().replaceAll(',', '.'));
    if (x == null || x <= 0 || x >= p.preco) {
      setState(() => _erro =
          'O preço promocional tem de ser maior que zero e menor que o preço normal (${p.preco.toStringAsFixed(2).replaceAll('.', ',')} €).');
      return;
    }
    if (_inicio != null && _fim != null && !_fim!.isAfter(_inicio!)) {
      setState(() => _erro = 'O fim tem de ser depois do início.');
      return;
    }
    setState(() {
      _ocupado = true;
      _erro = null;
    });
    try {
      await widget.api.definir(
        productId: p.id,
        precoPromocional: x,
        inicio: _inicio,
        fim: _fim,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemErroPromocao(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _escolhido;
    return AlertDialog(
      title: const Text('Nova promoção'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p == null) ...[
                TextField(
                  key: const Key('nova_busca'),
                  controller: _busca,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _procurar(),
                  decoration: InputDecoration(
                    labelText: 'Procurar produto pelo nome',
                    suffixIcon: IconButton(
                      key: const Key('nova_procurar'),
                      onPressed: _aProcurar ? null : _procurar,
                      icon: const Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (_aProcurar) const LinearProgressIndicator(),
                for (final a in _achados)
                  ListTile(
                    key: Key('nova_achado_${a.id}'),
                    dense: true,
                    enabled: !a.aoPeso,
                    title: Text(a.nome),
                    subtitle: Text(
                        '${a.loja} · ${a.preco.toStringAsFixed(2).replaceAll('.', ',')} €${a.aoPeso ? ' · ao peso: não leva promoção' : ''}'),
                    onTap: a.aoPeso
                        ? null
                        : () => setState(() {
                              _escolhido = a;
                              _erro = null;
                            }),
                  ),
              ] else ...[
                Text(p.nome, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('${p.loja} · ${p.lojaParceira ? 'loja parceira' : 'loja não parceira'} · '
                    'preço normal ${p.preco.toStringAsFixed(2).replaceAll('.', ',')} €'),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('nova_preco'),
                  controller: _preco,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Preço promocional de catálogo (€)',
                    helperText: p.lojaParceira
                        ? 'Em loja parceira é o preço que o cliente vê.'
                        : 'Em loja não parceira é o preço sem os 15 % da Bora.',
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _ocupado ? null : () => _data(inicio: true),
                      child: Text(_inicio == null ? 'Início: agora' : 'Início: ${_dia(_inicio!)}'),
                    ),
                    OutlinedButton(
                      onPressed: _ocupado ? null : () => _data(inicio: false),
                      child: Text(_fim == null ? 'Fim: sem fim' : 'Fim: ${_dia(_fim!)}'),
                    ),
                  ],
                ),
              ],
              if (_erro != null) ...[
                const SizedBox(height: 8),
                Text(_erro!, key: const Key('nova_erro'), style: const TextStyle(color: AppColors.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _ocupado ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        if (p != null)
          FilledButton(
            key: const Key('nova_criar'),
            onPressed: _ocupado ? null : _criar,
            child: Text(_ocupado ? 'A criar…' : 'Criar promoção'),
          ),
      ],
    );
  }
}
