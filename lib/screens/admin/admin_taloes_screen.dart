// Painel admin (PT-BR) — "Talões" (08/11/2026, missão m1-dinheiro-favores,
// adendo 1 — pedido do Danilo às 20:39: "toda foto de talão que o estafeta
// tira tem de ficar guardada num sítio certo, para sempre (papel fiscal, 10
// anos)"). Lista as fotos de talão guardadas (registro order_receipt_fotos)
// com filtro por mês (Lisboa), loja e entregador; contadores (fotos, pedidos,
// soma dos valores escritos); botão "Baixar o mês (ZIP)" que chama a
// Edge taloes-zip-mes (fotos + indice.csv para o contabilista, link de 1 hora);
// e o separador "Pedidos sem talão" (RPC admin_pedidos_sem_talao).
//
// Servidor: RPC admin_taloes_listar, admin_pedidos_sem_talao e a Edge
// taloes-zip-mes. Sem elas publicadas: "Função ainda não publicada no servidor".
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../utils/hora_lisboa.dart';
import '../../utils/ofertas_em_palavras.dart' show servidorAindaSemIsto;
import '../../widgets/admin/admin_talao_pedido_section.dart';
import '../../widgets/private_bucket_image.dart';
import 'admin_order_detail_screen.dart';

const String kTaloesFuncaoNaoPublicada = 'Função ainda não publicada no servidor';

/// Os filtros da página (os mesmos vão para a lista e para o ZIP).
class FiltroTaloes {
  const FiltroTaloes({required this.mes, this.loja, this.driverUid});

  /// 'AAAA-MM' (mês de Lisboa).
  final String mes;

  /// Loja: id do restaurante/loja ou parte do nome.
  final String? loja;

  /// user_id do entregador.
  final String? driverUid;

  Map<String, dynamic> paraRpc({int limite = AdminTaloesScreen.kLimite}) => {
        'p_mes': mes,
        'p_loja': loja,
        'p_driver_uid': driverUid,
        'p_limite': limite,
      };

  Map<String, dynamic> paraZip() => {
        'mes': mes,
        if (loja != null) 'loja': loja,
        if (driverUid != null) 'driver_uid': driverUid,
      };

  @override
  bool operator ==(Object other) =>
      other is FiltroTaloes && other.mes == mes && other.loja == loja && other.driverUid == driverUid;

  @override
  int get hashCode => Object.hash(mes, loja, driverUid);

  @override
  String toString() => 'FiltroTaloes(mes: $mes, loja: $loja, driverUid: $driverUid)';
}

/// Uma opção do filtro "Entregador".
typedef EntregadorTalao = ({String uid, String nome});

class AdminTaloesScreen extends StatefulWidget {
  const AdminTaloesScreen({
    super.key,
    this.agora,
    this.listar,
    this.listarSemTalao,
    this.carregarEntregadores,
    this.gerarZip,
    this.abrirLink,
  });

  /// Quantas fotos a lista mostra de cada vez (o ZIP leva o mês inteiro).
  static const int kLimite = 500;

  /// Só para testes.
  final DateTime Function()? agora;
  final Future<Map<String, dynamic>> Function(FiltroTaloes filtro)? listar;
  final Future<List<Map<String, dynamic>>> Function(String? desde)? listarSemTalao;
  final Future<List<EntregadorTalao>> Function()? carregarEntregadores;
  final Future<Map<String, dynamic>> Function(FiltroTaloes filtro)? gerarZip;
  final Future<bool> Function(Uri url)? abrirLink;

  static Future<Map<String, dynamic>> listarDoServidor(FiltroTaloes filtro) async {
    final r = await Supabase.instance.client.rpc('admin_taloes_listar', params: filtro.paraRpc());
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  /// [desde] é uma data 'AAAA-MM-DD' (Lisboa) ou null (desde sempre).
  static Future<List<Map<String, dynamic>>> listarSemTalaoDoServidor(String? desde) async {
    final r = await Supabase.instance.client.rpc('admin_pedidos_sem_talao', params: {'p_desde': desde});
    if (r is List) {
      return r.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const [];
  }

  /// Entregadores pelo user_id (o que o servidor filtra), com o nome da ficha
  /// do entregador ou, na falta, o nome/e-mail da conta.
  static Future<List<EntregadorTalao>> carregarEntregadoresDoServidor() async {
    final sb = Supabase.instance.client;
    final ds = await sb.from('drivers').select('user_id, name').order('name');
    final linhas = List<Map<String, dynamic>>.from(ds)
        .where((d) => '${d['user_id'] ?? ''}'.trim().isNotEmpty)
        .toList();
    final ids = linhas.map((d) => '${d['user_id']}').toSet().toList();
    final contas = <String, Map<String, dynamic>>{};
    try {
      for (var i = 0; i < ids.length; i += 200) {
        final us = await sb
            .from('users')
            .select('id, name, email')
            .inFilter('id', ids.sublist(i, math.min(i + 200, ids.length)));
        for (final u in us) {
          final m = Map<String, dynamic>.from(u);
          contas['${m['id']}'] = m;
        }
      }
    } catch (e) {
      debugPrint('[AdminTaloes] users: $e');
    }
    final vistos = <String>{};
    final r = <EntregadorTalao>[];
    for (final d in linhas) {
      final uid = '${d['user_id']}';
      if (!vistos.add(uid)) continue;
      final conta = contas[uid] ?? const <String, dynamic>{};
      final nome = [d['name'], conta['name'], conta['email']]
          .map((x) => '${x ?? ''}'.trim())
          .firstWhere((x) => x.isNotEmpty, orElse: () => uid.substring(0, math.min(8, uid.length)));
      r.add((uid: uid, nome: nome));
    }
    r.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    return r;
  }

  /// Chama a Edge taloes-zip-mes com a sessão do admin. Nunca lança: os erros
  /// voltam como `{ok: false, error: ...}`.
  static Future<Map<String, dynamic>> gerarZipNoServidor(FiltroTaloes filtro) async {
    try {
      final res = await Supabase.instance.client.functions.invoke('taloes-zip-mes', body: filtro.paraZip());
      final d = res.data;
      if (d is Map) return Map<String, dynamic>.from(d);
      return {'ok': false, 'error': 'resposta_invalida', 'detalhe': '$d'};
    } on FunctionException catch (e) {
      final d = e.details;
      if (d is Map && d['error'] != null) {
        return {...Map<String, dynamic>.from(d), 'ok': false, 'status': e.status};
      }
      if (e.status == 404) return {'ok': false, 'error': 'funcao_nao_publicada'};
      return {'ok': false, 'error': 'http_${e.status}', 'detalhe': '${d ?? e.reasonPhrase ?? ''}'};
    } catch (e) {
      return {'ok': false, 'error': servidorAindaSemIsto(e) ? 'funcao_nao_publicada' : 'excecao', 'detalhe': '$e'};
    }
  }

  /// Os últimos [quantos] meses de Lisboa, do mais recente para trás ('AAAA-MM').
  static List<String> ultimosMeses(DateTime agora, {int quantos = 24}) {
    final l = paredeLisboa(agora);
    var ano = l.year;
    var mes = l.month;
    final r = <String>[];
    for (var i = 0; i < quantos; i++) {
      r.add('$ano-${mes.toString().padLeft(2, '0')}');
      mes--;
      if (mes == 0) {
        mes = 12;
        ano--;
      }
    }
    return r;
  }

  static const _nomesMeses = [
    'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho', //
    'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
  ];

  /// '2026-11' → 'Novembro de 2026'.
  static String nomeDoMes(String aaaamm) {
    final p = aaaamm.split('-');
    final m = p.length == 2 ? int.tryParse(p[1]) : null;
    if (m == null || m < 1 || m > 12) return aaaamm;
    return '${_nomesMeses[m - 1]} de ${p[0]}';
  }

  /// 19084083 → '18,2 MB'; 655360 → '640 KB'.
  static String tamanhoLegivel(Object? bytes) {
    final b = (bytes is num) ? bytes.toDouble() : 0.0;
    const mb = 1024 * 1024;
    if (b < mb) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / mb).toStringAsFixed(1).replaceAll('.', ',')} MB';
  }

  /// Mensagem PT-BR da resposta da Edge taloes-zip-mes.
  static String mensagemZip(Map<String, dynamic> r) {
    if (r['ok'] == true) {
      final n = (r['fotos'] as num?)?.toInt() ?? 0;
      final faltaram = r['faltaram'] is List ? (r['faltaram'] as List).length : 0;
      final fotos = n == 1 ? '1 foto' : '$n fotos';
      final aviso = faltaram > 0
          ? ' — $faltaram ${faltaram == 1 ? 'foto não foi encontrada' : 'fotos não foram encontradas'} '
              'no armazenamento (ficaram fora do ZIP)'
          : '';
      final msg = '$fotos, ${tamanhoLegivel(r['bytes'])}$aviso';
      if ('${r['url'] ?? ''}'.trim().isEmpty) return '$msg. O servidor não devolveu o link: tente de novo.';
      return '$msg. O link vale 1 hora.';
    }
    final detalhe = '${r['detalhe'] ?? ''}'.trim();
    return switch (r['error']) {
      'funcao_nao_publicada' => '$kTaloesFuncaoNaoPublicada (taloes-zip-mes).',
      'mes_invalido' => 'Mês inválido (o formato é AAAA-MM).',
      'demasiadas_fotos' =>
        'Fotos demais para um ZIP só (máximo ${r['max'] ?? 1500}). Filtre por loja ou entregador.',
      'sem_sessao' => 'Sessão expirada: entre de novo no painel.',
      'so_admin' => 'Só administradores podem baixar o ZIP dos talões.',
      'leitura_falhou' || 'zip_nao_guardado' || 'link_falhou' =>
        'O servidor não conseguiu montar o ZIP (${r['error']}${detalhe.isEmpty ? '' : ': $detalhe'}). Tente de novo.',
      _ => 'Não foi possível montar o ZIP: ${r['error'] ?? 'erro desconhecido'}'
          '${detalhe.isEmpty ? '' : ' ($detalhe)'}',
    };
  }

  @override
  State<AdminTaloesScreen> createState() => _AdminTaloesScreenState();
}

class _AdminTaloesScreenState extends State<AdminTaloesScreen> {
  late final List<String> _meses;
  late String _mes;
  String? _loja;
  String? _driverUid;
  final _lojaCtrl = TextEditingController();
  List<EntregadorTalao> _entregadores = const [];

  // Fotos do mês.
  List<Map<String, dynamic>>? _fotos;
  String? _erro;
  bool _semServidor = false;
  int _seq = 0;

  // ZIP.
  bool _aGerar = false;
  String? _resultadoZip;
  bool _zipFalhou = false;
  String? _linkZip;

  // Pedidos sem talão.
  int? _desdeDias = 30;
  List<Map<String, dynamic>>? _semTalao;
  String? _erroSemTalao;
  bool _semTalaoSemServidor = false;
  int _seqSemTalao = 0;

  DateTime _agora() => (widget.agora ?? DateTime.now)();

  FiltroTaloes get _filtro => FiltroTaloes(mes: _mes, loja: _loja, driverUid: _driverUid);

  @override
  void initState() {
    super.initState();
    _meses = AdminTaloesScreen.ultimosMeses(_agora());
    _mes = _meses.first;
    _carregarEntregadores();
    _carregar();
    _carregarSemTalao();
  }

  @override
  void dispose() {
    _lojaCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregarTudo() => Future.wait([_carregar(), _carregarSemTalao()]);

  Future<void> _carregarEntregadores() async {
    try {
      final l = await (widget.carregarEntregadores ?? AdminTaloesScreen.carregarEntregadoresDoServidor)();
      if (mounted) setState(() => _entregadores = l);
    } catch (e) {
      debugPrint('[AdminTaloes] entregadores: $e');
    }
  }

  Future<void> _carregar() async {
    final seq = ++_seq;
    final filtro = _filtro;
    setState(() {
      _fotos = null;
      _erro = null;
      _semServidor = false;
    });
    try {
      final r = await (widget.listar ?? AdminTaloesScreen.listarDoServidor)(filtro);
      if (!mounted || seq != _seq) return;
      setState(() {
        if (r['ok'] == false) {
          _erro = r['error'] == 'mes_invalido' ? 'Mês inválido (o formato é AAAA-MM).' : '${r['error']}';
          _fotos = const [];
        } else {
          final l = r['fotos'];
          _fotos = l is List ? l.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];
        }
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _semServidor = servidorAindaSemIsto(e);
        _erro = _semServidor ? null : e.toString();
        _fotos = const [];
      });
    }
  }

  String? _desde() {
    final dias = _desdeDias;
    if (dias == null) return null;
    final d = paredeLisboa(_agora()).subtract(Duration(days: dias));
    String dd(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${dd(d.month)}-${dd(d.day)}';
  }

  Future<void> _carregarSemTalao() async {
    final seq = ++_seqSemTalao;
    final desde = _desde();
    setState(() {
      _semTalao = null;
      _erroSemTalao = null;
      _semTalaoSemServidor = false;
    });
    try {
      final l = await (widget.listarSemTalao ?? AdminTaloesScreen.listarSemTalaoDoServidor)(desde);
      if (!mounted || seq != _seqSemTalao) return;
      setState(() => _semTalao = l);
    } catch (e) {
      if (!mounted || seq != _seqSemTalao) return;
      setState(() {
        _semTalaoSemServidor = servidorAindaSemIsto(e);
        _erroSemTalao = _semTalaoSemServidor ? null : e.toString();
        _semTalao = const [];
      });
    }
  }

  void _mudouFiltro(VoidCallback mudar) {
    setState(() {
      mudar();
      _resultadoZip = null;
      _zipFalhou = false;
      _linkZip = null;
    });
    _carregar();
  }

  void _aplicarLoja() {
    final t = _lojaCtrl.text.trim();
    final nova = t.isEmpty ? null : t;
    if (nova == _loja) return;
    _mudouFiltro(() => _loja = nova);
  }

  Future<bool> _abrirLinkPadrao(Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);

  Future<void> _descarregarZip() async {
    final filtro = _filtro;
    setState(() {
      _aGerar = true;
      _resultadoZip = null;
      _zipFalhou = false;
      _linkZip = null;
    });
    Map<String, dynamic> r;
    try {
      r = await (widget.gerarZip ?? AdminTaloesScreen.gerarZipNoServidor)(filtro);
    } catch (e) {
      r = {
        'ok': false,
        'error': servidorAindaSemIsto(e) ? 'funcao_nao_publicada' : 'excecao',
        'detalhe': '$e',
      };
    }
    if (!mounted) return;
    final url = '${r['url'] ?? ''}'.trim();
    setState(() {
      _aGerar = false;
      _resultadoZip = AdminTaloesScreen.mensagemZip(r);
      _zipFalhou = r['ok'] != true;
      _linkZip = r['ok'] == true && url.isNotEmpty ? url : null;
    });
    if (_linkZip != null) await _abrir(_linkZip!);
  }

  Future<void> _abrir(String url) async {
    var abriu = false;
    try {
      abriu = await (widget.abrirLink ?? _abrirLinkPadrao)(Uri.parse(url));
    } catch (_) {
      abriu = false;
    }
    if (!abriu && mounted) _mostrarLink(url);
  }

  void _mostrarLink(String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Link do ZIP (vale 1 hora)'),
        content: SelectableText(url, style: const TextStyle(fontSize: 12)),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: url)),
            child: const Text('Copiar'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
        ],
      ),
    );
  }

  void _abrirPedido(String orderId) {
    if (orderId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AdminOrderDetailScreen(orderId: orderId)),
    );
  }

  static String _curto(String id) => id.substring(0, id.length < 8 ? id.length : 8);

  static String _metodo(Object? m) => switch (m) {
        'mbway' => 'MB Way',
        'cash' => 'Dinheiro',
        'card' || 'stripe' => 'Cartão',
        _ => '${m ?? '—'}',
      };

  // ─── Separador 1: fotos ────────────────────────────────────────────────

  Widget _filtros() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<String>(
            key: const Key('taloes_filtro_mes'),
            initialValue: _mes,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Mês',
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            items: [
              for (final m in _meses)
                DropdownMenuItem<String>(
                  value: m,
                  child: Text(AdminTaloesScreen.nomeDoMes(m), overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) {
              if (v == null || v == _mes) return;
              _mudouFiltro(() => _mes = v);
            },
          ),
        ),
        SizedBox(
          width: 230,
          child: TextField(
            key: const Key('taloes_filtro_loja'),
            controller: _lojaCtrl,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _aplicarLoja(),
            decoration: InputDecoration(
              labelText: 'Loja (nome ou id)',
              isDense: true,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              suffixIcon: IconButton(
                key: const Key('taloes_filtro_loja_aplicar'),
                tooltip: 'Filtrar pela loja',
                icon: const Icon(Icons.search, size: 20),
                onPressed: _aplicarLoja,
              ),
            ),
          ),
        ),
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String?>(
            key: const Key('taloes_filtro_entregador'),
            initialValue: _driverUid,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Entregador',
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
              for (final e in _entregadores)
                DropdownMenuItem<String?>(
                  value: e.uid,
                  child: Text(e.nome, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) {
              if (v == _driverUid) return;
              _mudouFiltro(() => _driverUid = v);
            },
          ),
        ),
      ],
    );
  }

  Widget _contadoresEZip() {
    final fotos = _fotos ?? const <Map<String, dynamic>>[];
    // Soma por pedido (o último valor escrito de cada pedido), para não contar
    // duas vezes o mesmo talão fotografado duas vezes.
    final porPedido = <String, num>{};
    for (final f in fotos.reversed) {
      final v = f['total_cents'];
      if (v is num) porPedido['${f['order_id']}'] = v;
    }
    final pedidos = fotos.map((f) => '${f['order_id']}').toSet().length;
    final soma = porPedido.values.fold<num>(0, (a, b) => a + b);
    final carregado = _fotos != null && !_semServidor && _erro == null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (carregado) ...[
              Text(
                '${fotos.length == 1 ? '1 foto' : '${fotos.length} fotos'} · '
                '${pedidos == 1 ? '1 pedido' : '$pedidos pedidos'} · '
                'soma dos valores escritos: ${eurosDoTalao(soma)}',
                key: const Key('taloes_contadores'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (fotos.length >= AdminTaloesScreen.kLimite)
                const Text(
                  'Mostrando as ${AdminTaloesScreen.kLimite} mais recentes. Use os filtros para ver as outras '
                  '(o ZIP leva o mês inteiro).',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              const SizedBox(height: 8),
            ],
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              FilledButton.icon(
                key: const Key('btn_taloes_zip'),
                onPressed: _aGerar ? null : _descarregarZip,
                icon: const Icon(Icons.download_outlined),
                label: Text(_aGerar ? 'Montando o ZIP…' : 'Baixar o mês (ZIP)'),
              ),
              if (_linkZip != null && !_aGerar)
                TextButton.icon(
                  key: const Key('btn_taloes_zip_link'),
                  onPressed: () => _abrir(_linkZip!),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Abrir o link de novo'),
                ),
            ]),
            Text(
              'ZIP de ${AdminTaloesScreen.nomeDoMes(_mes)}${_loja != null ? ', loja "$_loja"' : ''}'
              '${_driverUid != null ? ', só o entregador escolhido' : ''}: as fotos e um indice.csv '
              '(planilha com pedido, data, loja, valor e NIF) para o contabilista.',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            if (_aGerar)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
            if (_resultadoZip != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _resultadoZip!,
                  key: const Key('taloes_zip_resultado'),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _zipFalhou ? AppColors.error : AppColors.success,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cartaoFoto(Map<String, dynamic> f, int i) {
    final id = '${f['order_id'] ?? ''}';
    final antigo = f['origem'] == 'antigo';
    final copia = f['copia_em'] != null;
    final valor = f['total_cents'];
    return Card(
      key: Key('talao_item_$i'),
      child: InkWell(
        onTap: () => _abrirPedido(id),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PrivateBucketImage(
                urlOrPath: caminhoDaFotoDoTalao(f),
                width: 72,
                height: 72,
                placeholderHeight: 72,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(8),
                tituloAmpliada: 'Talão · pedido ${_curto(id)}',
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pedido ${_curto(id)} · ${f['loja'] ?? '—'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('Entregador: ${f['estafeta'] ?? '—'}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    Text('Valor escrito: ${valor is num ? eurosDoTalao(valor) : '—'} · '
                        'pagamento: ${_metodo(f['payment_method'])}',
                        style: const TextStyle(fontSize: 13)),
                    Text(textoNifUsado(f['nif']), style: const TextStyle(fontSize: 12)),
                    Text('Recebida ${dataHoraLisboa(f['recebida_em'])}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    if (antigo || copia)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(spacing: 4, children: [
                          if (antigo) _selo('antigo', AppColors.textSecondary),
                          if (copia) _selo('cópia no Drive ✓', AppColors.success),
                        ]),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selo(String texto, Color cor) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.10),
          border: Border.all(color: cor.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(texto, style: TextStyle(fontSize: 11, color: cor, fontWeight: FontWeight.w600)),
      );

  Widget _avisoSemServidor(String detalhe) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            const Icon(Icons.cloud_off_outlined, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text('$kTaloesFuncaoNaoPublicada. $detalhe',
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ),
          ]),
        ),
      );

  Widget _textoErro(String erro) => Text('Não foi possível carregar: $erro',
      maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.error));

  Widget _carregando() => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );

  Widget _separadorFotos() {
    final fotos = _fotos;
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          const Text(
            'Toda foto de talão que o entregador tira fica guardada 10 anos (papel fiscal), cada uma no '
            'seu arquivo, nunca substituída. Toque na foto para ampliar; toque no resto do cartão para '
            'abrir o pedido.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          _filtros(),
          const SizedBox(height: 10),
          _contadoresEZip(),
          const SizedBox(height: 4),
          if (_semServidor)
            _avisoSemServidor('A lista aparece aqui quando a migração dos talões guardados for aplicada.')
          else if (_erro != null)
            _textoErro(_erro!)
          else if (fotos == null)
            _carregando()
          else if (fotos.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('Nenhuma foto de talão em ${AdminTaloesScreen.nomeDoMes(_mes)} com esses filtros.'),
            )
          else
            for (var i = 0; i < fotos.length; i++) _cartaoFoto(fotos[i], i),
        ],
      ),
    );
  }

  // ─── Separador 2: pedidos sem talão ────────────────────────────────────

  Widget _separadorSemTalao() {
    final lista = _semTalao;
    const periodos = <int?>[7, 30, 90, null];
    return RefreshIndicator(
      onRefresh: _carregarSemTalao,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          const Text(
            'Pedidos de mercados e restaurantes NÃO parceiros (e Favores com compra) entregues sem a foto '
            'do talão guardada. Pedidos de teste ficam de fora. Toque para abrir o pedido.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final p in periodos)
              ChoiceChip(
                key: Key('sem_talao_${p ?? 'sempre'}'),
                label: Text(p == null ? 'Desde sempre' : 'Últimos $p dias'),
                selected: _desdeDias == p,
                onSelected: (_) {
                  if (_desdeDias == p) return;
                  setState(() => _desdeDias = p);
                  _carregarSemTalao();
                },
              ),
          ]),
          const SizedBox(height: 8),
          if (_semTalaoSemServidor)
            _avisoSemServidor('A lista aparece aqui quando a migração dos talões guardados for aplicada.')
          else if (_erroSemTalao != null)
            _textoErro(_erroSemTalao!)
          else if (lista == null)
            _carregando()
          else if (lista.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Nenhum pedido entregue sem talão neste período.'),
            )
          else ...[
            Text(
              lista.length == 1 ? '1 pedido entregue sem talão' : '${lista.length} pedidos entregues sem talão',
              key: const Key('sem_talao_total'),
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.warning),
            ),
            const SizedBox(height: 6),
            for (final p in lista) _cartaoSemTalao(p),
          ],
        ],
      ),
    );
  }

  Widget _cartaoSemTalao(Map<String, dynamic> p) {
    final id = '${p['order_id'] ?? ''}';
    final foto = '${p['foto'] ?? ''}'.trim();
    return Card(
      key: Key('sem_talao_$id'),
      child: ListTile(
        leading: const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
        title: Text('Pedido ${_curto(id)} · ${p['loja'] ?? '—'}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          'Entregue ${dataHoraLisboa(p['delivered_at'])} · pagamento: ${_metodo(p['payment_method'])}'
          '${foto.isEmpty ? ' · sem foto' : ' · registro antigo: $foto (sem arquivo guardado)'}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _abrirPedido(id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = _semTalao?.length;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Talões'),
          actions: [
            IconButton(tooltip: 'Atualizar', onPressed: _carregarTudo, icon: const Icon(Icons.refresh)),
          ],
          bottom: TabBar(
            tabs: [
              const Tab(text: 'Fotos do talão'),
              Tab(text: n == null || n == 0 ? 'Pedidos sem talão' : 'Pedidos sem talão ($n)'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _separadorFotos(),
            _separadorSemTalao(),
          ],
        ),
      ),
    );
  }
}
