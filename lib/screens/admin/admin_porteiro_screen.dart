// PAINEL ADMIN (PT-BR) — Porteiro do Telegram (missão fecho-pendentes 31/10/2026).
//
// A tabela `porteiro_entrada` é a fila de avisos da base (Edge
// notify-admin-urgent e outras) que o porteiro da VPS lê de 10 em 10 segundos
// e manda para o chat do Danilo no Telegram (texto e voz). A tabela não tem
// políticas RLS: o Flutter NUNCA a lê direto — só pelas duas RPCs de admin:
//   · admin_porteiro_listar(p_limit, p_so_por_tratar) → linhas com id,
//     created_at, origem, nivel, texto, tratado_em, resultado, destino, estado;
//   · admin_porteiro_reenviar(p_id) → {ok, novo_id} (cópia nova na fila).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/bora/bora_empty_placeholder.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '_admin_rpc_errors.dart';

/// Normaliza a resposta de `admin_porteiro_listar`: aceita linhas de tabela
/// (mapas), `setof jsonb` (mapas ou texto JSON) e o embrulho
/// `{"admin_porteiro_listar": {...}}`. Mais recentes primeiro (id maior).
List<Map<String, dynamic>> linhasDoPorteiro(Object? res) {
  if (res is! List) return const [];
  final out = <Map<String, dynamic>>[];
  for (final e in res) {
    Object? v = e;
    if (v is Map && v.length == 1 && v['admin_porteiro_listar'] != null) {
      v = v['admin_porteiro_listar'];
    }
    if (v is String) {
      try {
        v = jsonDecode(v);
      } catch (_) {
        continue;
      }
    }
    if (v is Map) out.add(Map<String, dynamic>.from(v));
  }
  out.sort((a, b) => (_idPorteiro(b['id']) ?? 0).compareTo(_idPorteiro(a['id']) ?? 0));
  return out;
}

int? _idPorteiro(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

/// O `resultado` que o porteiro escreveu (mapa), venha como mapa ou texto.
Map<String, dynamic> resultadoDoPorteiro(Object? v) {
  if (v is Map) return Map<String, dynamic>.from(v);
  if (v is String && v.isNotEmpty) {
    try {
      final d = jsonDecode(v);
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {
      // Texto que não é JSON: fica sem resultado (o ecrã mostra o resto).
    }
  }
  return const {};
}

/// Destino em PT-BR. 'chat' e 'registo' são os que aparecem nas linhas reais.
String textoDestinoPorteiro(Object? destino) {
  final d = destino?.toString() ?? '';
  switch (d) {
    case '':
      return 'ainda sem destino';
    case 'chat':
      return 'chat do Telegram';
    case 'registo':
      return 'só registado (não foi ao Telegram)';
    case 'voz':
      return 'Telegram com voz';
    case 'telegram':
      return 'Telegram';
    default:
      return d;
  }
}

/// Cor do chip do nível: URGENTE vermelho, RESULTADO verde, INFO cinza.
Color corNivelPorteiro(Object? nivel) {
  switch (nivel?.toString()) {
    case 'URGENTE':
      return AppColors.error;
    case 'RESULTADO':
      return AppColors.success;
    default:
      return AppColors.textSubtle;
  }
}

class AdminPorteiroScreen extends StatefulWidget {
  const AdminPorteiroScreen({super.key});

  @override
  State<AdminPorteiroScreen> createState() => _AdminPorteiroScreenState();
}

class _AdminPorteiroScreenState extends State<AdminPorteiroScreen> {
  List<Map<String, dynamic>> _linhas = const [];
  bool _soPorTratar = false;
  bool _carregando = true;
  String? _erro;
  final Set<int> _abertos = <int>{};
  final Set<int> _reenviando = <int>{};

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
      _carregando = _linhas.isEmpty;
      _erro = null;
    });
    try {
      final res = await Supabase.instance.client.rpc(
        'admin_porteiro_listar',
        params: {'p_limit': 100, 'p_so_por_tratar': _soPorTratar},
      );
      if (!mounted) return;
      setState(() {
        _linhas = linhasDoPorteiro(res);
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = humanizeAdminRpcError(e);
        _carregando = false;
      });
    }
  }

  Future<void> _reenviar(Map<String, dynamic> r) async {
    final id = _idPorteiro(r['id']);
    if (id == null || _reenviando.contains(id)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reenviar o aviso #$id?'),
        content: const Text(
          'Coloca uma cópia nova deste aviso na fila. O porteiro da VPS envia '
          'essa cópia para o Telegram do Danilo nos 10 segundos seguintes (o '
          'aviso antigo fica como está).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reenviar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _reenviando.add(id);
    });
    try {
      final res = await Supabase.instance.client
          .rpc('admin_porteiro_reenviar', params: {'p_id': id});
      final m = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      if (m['ok'] == true) {
        _msg('Reenviado: aviso novo #${m['novo_id'] ?? '?'} na fila. '
            'O porteiro trata dele nos próximos 10 segundos.');
        await _carregar();
      } else {
        _msg('Não foi reenviado (${m['erro'] ?? m['motivo'] ?? 'o servidor não confirmou'}).',
            erro: true);
      }
    } catch (e) {
      _msg(humanizeAdminRpcError(e), erro: true);
    } finally {
      if (mounted) {
        setState(() {
          _reenviando.remove(id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Porteiro do Telegram',
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _carregar,
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(Spacing.md),
                children: [
                  _cartaoExplicacao(),
                  const SizedBox(height: Spacing.sm),
                  Wrap(
                    spacing: Spacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilterChip(
                        label: const Text('Só por tratar'),
                        tooltip: 'Só os avisos que o porteiro ainda não mandou',
                        selected: _soPorTratar,
                        onSelected: (v) {
                          setState(() => _soPorTratar = v);
                          _carregar();
                        },
                      ),
                      Text(
                        '${_linhas.length} aviso(s)',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.sm),
                  if (_erro != null)
                    _cartaoErro()
                  else if (_linhas.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: Spacing.xxl),
                      child: BoraEmptyPlaceholder(
                        icon: Icons.mark_chat_read_outlined,
                        title: _soPorTratar
                            ? 'Nada por tratar'
                            : 'A fila está vazia',
                        message: _soPorTratar
                            ? 'O porteiro já mandou todos os avisos.'
                            : 'Ainda não chegou nenhum aviso da base.',
                      ),
                    )
                  else
                    for (final r in _linhas) _cartao(r),
                ],
              ),
            ),
    );
  }

  Widget _cartaoExplicacao() {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: const Padding(
        padding: EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fila de avisos da base que o porteiro da VPS manda para o '
              'Telegram do Danilo (texto e voz). Atualiza de 10 em 10 segundos '
              'no servidor.',
              style: TextStyle(fontSize: 13),
            ),
            SizedBox(height: Spacing.xs),
            Text(
              'Nível: URGENTE (vermelho), RESULTADO (verde), INFO (cinza). '
              'Destino = para onde o porteiro mandou (chat do Telegram ou só '
              'registado). Toque no texto para ver tudo.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cartaoErro() {
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.xl),
      child: Column(
        children: [
          Text(_erro!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.error)),
          const SizedBox(height: Spacing.md),
          FilledButton(
            onPressed: _carregar,
            child: const Text('Tentar de novo'),
          ),
        ],
      ),
    );
  }

  /// Tocar no texto abre/fecha (2 linhas ↔ tudo).
  void _alternar(int? id) {
    if (id == null) return;
    final n = id;
    setState(() {
      if (!_abertos.remove(n)) _abertos.add(n);
    });
  }

  Widget _chipNivel(Object? nivel) {
    final cor = corNivelPorteiro(nivel);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: cor.withValues(alpha: 0.5)),
      ),
      child: Text(
        nivel?.toString() ?? '—',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cor),
      ),
    );
  }

  Widget _cartao(Map<String, dynamic> r) {
    final id = _idPorteiro(r['id']);
    final aberto = id != null && _abertos.contains(id);
    final resultado = resultadoDoPorteiro(r['resultado']);
    final destino = r['destino'] ?? resultado['destino'];
    final tratadoEm = r['tratado_em'];
    final estado = r['estado']?.toString() ??
        (tratadoEm == null ? 'por tratar' : 'tratado');
    final tratado = estado == 'tratado';
    final erroPorteiro = resultado['erro'];
    final duplicado = resultado['duplicado'];
    final aReenviar = id != null && _reenviando.contains(id);
    const pequeno = TextStyle(fontSize: 12, color: AppColors.textSecondary);

    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _chipNivel(r['nivel']),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    r['origem']?.toString() ?? '—',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text('#${id ?? '?'} · ${dataHoraLisboa(r['created_at'])}',
                    style: pequeno),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            InkWell(
              onTap: () => _alternar(id),
              child: Text(
                r['texto']?.toString() ?? '',
                maxLines: aberto ? null : 2,
                overflow: aberto ? TextOverflow.visible : TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Text('Destino: ${textoDestinoPorteiro(destino)}', style: pequeno),
            Text(
              tratado
                  ? 'Tratado às ${dataHoraLisboa(tratadoEm)}'
                  : 'Por tratar (o porteiro ainda não o mandou)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: tratado ? AppColors.success : AppColors.warning,
              ),
            ),
            if (erroPorteiro != null && erroPorteiro.toString().isNotEmpty)
              Text('Erro do porteiro: $erroPorteiro',
                  style: const TextStyle(fontSize: 12, color: AppColors.error)),
            if (duplicado != null && duplicado != false)
              Text('Marcado como repetido pelo porteiro ($duplicado)', style: pequeno),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: id == null || aReenviar ? null : () => _reenviar(r),
                icon: aReenviar
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.replay),
                label: const Text('Reenviar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
