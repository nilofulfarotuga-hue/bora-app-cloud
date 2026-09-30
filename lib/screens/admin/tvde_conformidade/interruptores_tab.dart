// Separador 1 — Interruptores da conformidade TVDE + contadores do resumo.
// Lê admin_tvde_conf_resumo(); grava com admin_tvde_conf_set(p_key, p_value).
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '_comum.dart';

const String kTvdeMestre = 'tvde_compliance_enforce';
const String kTvdePrecoFixo = 'tvde_fixed_price_option_enabled';
const String kTvdeTextoMestre =
    'Enquanto o mestre estiver desligado nenhuma regra nova muda a app.';
const String kTvdeAvisoPrecoFixo =
    '⚠️ Mexe no valor cobrado — ainda é só proposta';

/// Contadores do resumo, pela ordem pedida: (chave, rótulo, alerta se > 0).
const List<(String, String, bool)> kTvdeContadores = [
  ('motoristas_com_impedimentos', 'Motoristas com impedimentos', true),
  ('veiculos_pendentes', 'Veículos pendentes', true),
  ('queixas_abertas', 'Queixas abertas', true),
  ('sos_7d', 'SOS (últimos 7 dias)', true),
  ('acima_teto', 'Corridas acima do teto de 25%', true),
  ('operadores_aprovados', 'Operadores aprovados', false),
  ('veiculos', 'Veículos registados', false),
  ('motoristas', 'Motoristas TVDE aprovados', false),
];

class TvdeInterruptoresTab extends StatefulWidget {
  const TvdeInterruptoresTab({super.key, this.rpc});

  final TvdeRpc? rpc;

  @override
  State<TvdeInterruptoresTab> createState() => _TvdeInterruptoresTabState();
}

class _TvdeInterruptoresTabState extends State<TvdeInterruptoresTab>
    with TvdeAGravar {
  bool _carregando = true;
  String? _erro;
  Map<String, dynamic> _resumo = {};
  List<Map<String, dynamic>> _itens = [];
  final Map<String, TextEditingController> _ctl = {};

  TvdeRpc get _rpc => widget.rpc ?? tvdeRpcPadrao;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final r = tvdeMapa(await _rpc('admin_tvde_conf_resumo'));
      final itens = tvdeLista(r['interruptores']);
      for (final c in _ctl.values) {
        c.dispose();
      }
      _ctl.clear();
      for (final i in itens) {
        final v = i['value'];
        if (v is! bool) {
          _ctl[i['key'] as String] = TextEditingController(
              text: v is String ? v : (v == null ? '' : jsonEncode(v)));
        }
      }
      if (!mounted) return;
      setState(() {
        _resumo = r;
        _itens = itens;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = tvdeErro(e);
        _carregando = false;
      });
    }
  }

  Future<void> _gravar(String key, dynamic valor) async {
    await correr(key, () async {
      final r = tvdeMapa(
          await _rpc('admin_tvde_conf_set', {'p_key': key, 'p_value': valor}));
      final novo = r.containsKey('value') ? r['value'] : valor;
      setState(() {
        for (final i in _itens) {
          if (i['key'] == key) i['value'] = novo;
        }
      });
    }, ok: 'Gravado: $key');
  }

  Future<void> _mudarBool(String key, bool v) async {
    if (key == kTvdeMestre) {
      final ok = await tvdeConfirmar(context,
          titulo: v ? 'Ligar o interruptor mestre?' : 'Desligar o interruptor mestre?',
          texto: v
              ? 'Ligado, as regras novas da Lei 59/2026 passam a valer na app '
                  '(motoristas sem documentos deixam de poder ficar online, etc.).'
              : kTvdeTextoMestre,
          perigo: v);
      if (!ok) return;
    }
    if (key == kTvdePrecoFixo && v) {
      if (!mounted) return;
      final ok = await tvdeConfirmar(context,
          titulo: 'Ligar o preço fixo?',
          texto: '$kTvdeAvisoPrecoFixo. Isto muda o que o passageiro paga. '
              'Só confirme se já decidiu mesmo ligar.',
          perigo: true);
      if (!ok) return;
    }
    await _gravar(key, v);
  }

  Future<void> _gravarTexto(Map<String, dynamic> item) async {
    final key = item['key'] as String;
    final atual = item['value'];
    final bruto = _ctl[key]!.text.trim();
    dynamic valor;
    if (atual is num) {
      final n = num.tryParse(bruto.replaceAll(',', '.'));
      if (n == null) {
        tvdeAvisar(context, 'Escreva um número.', erro: true);
        return;
      }
      valor = n;
    } else if (atual is String || atual == null) {
      if (key == 'plataforma_nif' &&
          bruto.isNotEmpty &&
          !RegExp(r'^\d{9}$').hasMatch(bruto)) {
        tvdeAvisar(context, 'O NIF tem de ter 9 dígitos.', erro: true);
        return;
      }
      valor = bruto;
    } else {
      try {
        valor = jsonDecode(bruto);
      } catch (_) {
        tvdeAvisar(context, 'Valor não é JSON válido.', erro: true);
        return;
      }
    }
    await _gravar(key, valor);
  }

  Widget _contadores() {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final c in kTvdeContadores)
        if (_resumo.containsKey(c.$1))
          Container(
            key: Key('tvde-contador-${c.$1}'),
            width: 170,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: c.$3 && tvdeInt(_resumo[c.$1]) > 0
                      ? AppColors.error
                      : AppColors.divider),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${tvdeInt(_resumo[c.$1])}',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: c.$3 && tvdeInt(_resumo[c.$1]) > 0
                          ? AppColors.error
                          : AppColors.textPrimary)),
              Text(c.$2, style: const TextStyle(fontSize: 12)),
            ]),
          ),
    ]);
  }

  Widget _mestre(Map<String, dynamic>? item) {
    if (item == null) {
      return tvdeNota('O interruptor mestre ($kTvdeMestre) não veio do servidor.',
          cor: AppColors.error, icone: Icons.warning_amber);
    }
    final ligado = tvdeBool(item['value']) ?? false;
    return Card(
      key: const Key('tvde-mestre'),
      color: (ligado ? AppColors.success : AppColors.warning).withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.power_settings_new),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Interruptor mestre da conformidade TVDE',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            Switch(
              key: const Key('tvde-switch-$kTvdeMestre'),
              value: ligado,
              onChanged: aGravar.contains(kTvdeMestre)
                  ? null
                  : (v) => _mudarBool(kTvdeMestre, v),
            ),
          ]),
          Text(ligado ? 'LIGADO — as regras novas estão a valer.' : 'DESLIGADO',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: ligado ? AppColors.success : AppColors.warning)),
          const SizedBox(height: 4),
          const Text(kTvdeTextoMestre),
          if (item['description'] != null) ...[
            const SizedBox(height: 4),
            Text('${item['description']}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 2),
          const Text(kTvdeMestre,
              style: TextStyle(fontFamily: 'monospace', fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _linha(Map<String, dynamic> item) {
    final key = item['key'] as String;
    final v = item['value'];
    final preco = key == kTvdePrecoFixo;
    final gravando = aGravar.contains(key);
    final descricao = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(key,
          style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
      if (item['description'] != null)
        Text('${item['description']}', style: const TextStyle(fontSize: 12)),
      if (preco)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(kTvdeAvisoPrecoFixo,
              key: const Key('tvde-aviso-preco-fixo'),
              style: const TextStyle(
                  color: AppColors.error, fontWeight: FontWeight.w700)),
        ),
    ]);
    return Card(
      key: Key('tvde-interruptor-$key'),
      shape: preco
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.error, width: 1.5))
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: v is bool
            ? Row(children: [
                Expanded(child: descricao),
                Switch(
                  key: Key('tvde-switch-$key'),
                  value: v,
                  onChanged: gravando ? null : (nv) => _mudarBool(key, nv),
                ),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                descricao,
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      key: Key('tvde-campo-$key'),
                      controller: _ctl[key],
                      keyboardType:
                          v is num ? TextInputType.number : TextInputType.text,
                      decoration: InputDecoration(
                        isDense: true,
                        border: const OutlineInputBorder(),
                        helperText: v is num
                            ? 'Número'
                            : (v is String || v == null ? 'Texto' : 'JSON'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  tvdeBotao(
                    key: Key('tvde-gravar-$key'),
                    rotulo: 'Gravar',
                    icone: Icons.save,
                    aGravar: gravando,
                    onPressed: () => _gravarTexto(item),
                  ),
                ]),
              ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return tvdeCorpo(
      carregando: _carregando,
      erro: _erro,
      tentar: _carregar,
      conteudo: () {
        Map<String, dynamic>? mestre;
        for (final i in _itens) {
          if (i['key'] == kTvdeMestre) mestre = i;
        }
        final outros = _itens.where((i) => i['key'] != kTvdeMestre).toList();
        return RefreshIndicator(
          onRefresh: _carregar,
          child: ListView(
            key: const Key('tvde-interruptores-lista'),
            padding: const EdgeInsets.all(12),
            children: [
              _mestre(mestre),
              const SizedBox(height: 12),
              _contadores(),
              const SizedBox(height: 16),
              const Text('Outros interruptores e dados da plataforma',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (outros.isEmpty) tvdeVazio('Nenhum outro interruptor.'),
              for (final i in outros) _linha(i),
            ],
          ),
        );
      },
    );
  }
}
