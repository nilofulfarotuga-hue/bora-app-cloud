// Painel admin (PT-BR) — "Dados fiscais (DAC7)". Missão
// fecho-contabilista-2026-11-10, bloco C: a lei DAC7 obriga a plataforma a
// comunicar, de cada prestador e loja, nome, NIF, morada, data de nascimento,
// conta bancária, valor pago e taxas retidas. Aqui o admin vê quem está pronto
// e o que falta a cada um (estafetas aprovados, limpeza, Casa e Manutenção,
// lavagem e lojas parceiras ativas), filtra "só em falta" e exporta CSV.
// O IBAN só aparece como sim/não — nunca o número.
//
// Servidor: RPC admin_prestadores_dados_fiscais(). O mesmo "o que falta" vai na
// secção 8 do fecho ao contabilista e aparece na app de cada prestador
// (meus_dados_fiscais_em_falta). Sem a RPC publicada: aviso "ainda não publicada".
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../utils/ofertas_em_palavras.dart' show servidorAindaSemIsto;
import '../../widgets/admin/admin_csv_button.dart';

const String kDadosFiscaisNaoPublicada =
    'Função ainda não publicada no servidor (migração dos dados fiscais por aplicar).';

/// Nome do papel em PT-BR.
String papelDadosFiscais(String? p) => switch (p) {
      'estafeta' => 'Entregador',
      'limpeza' => 'Limpeza',
      'casa' => 'Casa e Manutenção',
      'lavagem' => 'Lavagem',
      'loja_parceira' => 'Loja parceira',
      _ => p ?? '—',
    };

/// Uma linha do CSV (sem IBAN em claro: só "sim"/"não").
Map<String, dynamic> linhaCsvDadosFiscais(Map<String, dynamic> l) => {
      'papel': papelDadosFiscais(l['papel'] as String?),
      'nome': l['nome'],
      'nif': l['nif'],
      'morada': l['morada'],
      'data_nascimento': l['data_nascimento'],
      'tem_iban': l['tem_iban'] == true ? 'sim' : 'não',
      'atividade': l['atividade'],
      'falta': l['falta'] is List ? (l['falta'] as List).join(', ') : '',
      'nota': l['nota'],
    };

class AdminDadosFiscaisScreen extends StatefulWidget {
  const AdminDadosFiscaisScreen({super.key, this.carregar});

  /// Testes: em vez do Supabase.
  final Future<Object?> Function()? carregar;

  static const List<(String, String)> colunasCsv = [
    ('papel', 'Papel'),
    ('nome', 'Nome'),
    ('nif', 'NIF'),
    ('morada', 'Morada'),
    ('data_nascimento', 'Data de nascimento'),
    ('tem_iban', 'Tem IBAN'),
    ('atividade', 'Comprovativo de atividade'),
    ('falta', 'O que falta'),
    ('nota', 'Nota'),
  ];

  @override
  State<AdminDadosFiscaisScreen> createState() => _AdminDadosFiscaisScreenState();
}

class _AdminDadosFiscaisScreenState extends State<AdminDadosFiscaisScreen> {
  bool _aCarregar = true;
  bool _soEmFalta = true;
  String? _erro;
  List<Map<String, dynamic>> _linhas = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _aCarregar = true;
      _erro = null;
    });
    try {
      final f = widget.carregar;
      final res = f != null
          ? await f()
          : await Supabase.instance.client.rpc('admin_prestadores_dados_fiscais');
      final m = res is Map ? res : const {};
      final linhas = m['linhas'] is List
          ? (m['linhas'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _linhas = linhas;
        _aCarregar = false;
      });
    } catch (e) {
      debugPrint('[AdminDadosFiscais] $e');
      if (!mounted) return;
      setState(() {
        _aCarregar = false;
        _erro = servidorAindaSemIsto(e) ? kDadosFiscaisNaoPublicada : 'Não foi possível carregar: $e';
      });
    }
  }

  List<Map<String, dynamic>> get _visiveis =>
      _soEmFalta ? _linhas.where((l) => l['em_falta'] == true).toList() : _linhas;

  @override
  Widget build(BuildContext context) {
    final emFalta = _linhas.where((l) => l['em_falta'] == true).length;
    final visiveis = _visiveis;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dados fiscais (DAC7)'),
        actions: [
          AdminCsvButton(
            nome: 'dados_fiscais_dac7',
            colunas: AdminDadosFiscaisScreen.colunasCsv,
            linhas: () => [for (final l in _visiveis) linhaCsvDadosFiscais(l)],
          ),
          IconButton(
              tooltip: 'Atualizar', icon: const Icon(Icons.refresh), onPressed: _carregar),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text(
            'Pela lei DAC7 a Bora tem de comunicar, de cada prestador e loja: nome, NIF, morada, '
            'data de nascimento (pessoas), conta bancária, valor pago e taxas retidas. Quem tem algo '
            'em falta recebe o pedido na app. O IBAN aparece só como sim/não.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          FilterChip(
            key: const Key('dados_fiscais_so_em_falta'),
            label: const Text('Só com dados em falta'),
            selected: _soEmFalta,
            onSelected: (v) => setState(() => _soEmFalta = v),
          ),
          const SizedBox(height: 8),
          if (_aCarregar)
            const LinearProgressIndicator()
          else if (_erro != null)
            Text(_erro!, key: const Key('dados_fiscais_erro'), style: const TextStyle(color: AppColors.error))
          else ...[
            Text('${_linhas.length} prestadores e lojas · $emFalta com dados em falta',
                key: const Key('dados_fiscais_resumo'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            if (visiveis.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('Nada em falta.')),
              ),
            for (final l in visiveis) _linha(l),
          ],
        ],
      ),
    );
  }

  Widget _linha(Map<String, dynamic> l) {
    final falta = l['falta'] is List ? (l['falta'] as List).cast<Object?>().join(', ') : '';
    final ok = l['em_falta'] != true;
    return Card(
      child: ListTile(
        key: Key('dados_fiscais_${l['papel']}_${l['ref_id']}'),
        leading: Icon(ok ? Icons.check_circle_outline : Icons.error_outline,
            color: ok ? AppColors.success : AppColors.error),
        title: Text('${l['nome'] ?? '—'} · ${papelDadosFiscais(l['papel'] as String?)}'),
        subtitle: Text(
          ok
              ? (l['nota'] as String? ?? 'Dados completos.')
              : 'Falta: $falta',
          style: TextStyle(color: ok ? AppColors.textSecondary : AppColors.error),
        ),
        trailing: Text(
          'NIF ${l['nif'] ?? '—'}\nIBAN ${l['tem_iban'] == true ? 'sim' : 'não'}',
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }
}
