// Painel admin (PT-BR) — Fila inteligente do Bora Motorista (missão
// fechar-pendencias-2026-10-20, bloco A2).
//
// Correspondência no painel para a fila inteligente (decisão do Danilo de 15/10:
// "se o 1.º não aceitar em 40 s, passa ao 2.º da mesma fila, sem recalcular") e
// para o carro a deslizar no mapa do cliente. Aqui o Danilo:
//   • vê AO VIVO cada corrida à procura: a lista calculada (ordem, tempo de estrada,
//     nota, taxa de aceitação, pontos), quem tem a oferta e quanto tempo falta;
//   • liga/desliga a fila (tvde_fila_inteligente_enabled) e o canal da posição
//     (tvde_pos_ao_vivo_enabled), e muda o tempo de cada oferta e os pesos;
//   • vê o histórico de quem recusou, deixou expirar ou foi pulado (e porquê), e
//     exporta em CSV.
// As mudanças passam pela RPC admin_update_setting (fica no registo de auditoria).
// Nada aqui mexe em preços, ganhos ou pagamentos.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../utils/hora_lisboa_ext.dart';

// ─── Peças puras (testadas em test/admin_tvde_fila_test.dart) ────────────────

double _num(Object? v, [double porDefeito = 0]) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? porDefeito;
}

int? _intOuNulo(Object? v) {
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}');
}

DateTime? _data(Object? v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toUtc();

bool _bool(Object? v, {required bool porDefeito}) {
  if (v == null) return porDefeito;
  if (v is bool) return v;
  final s = v.toString().trim().toLowerCase().replaceAll('"', '');
  if (s == 'true' || s == '1') return true;
  if (s == 'false' || s == '0') return false;
  return porDefeito;
}

/// Um motorista na lista de uma corrida.
class FilaEntradaView {
  const FilaEntradaView({
    required this.pos,
    required this.motoristaId,
    required this.motorista,
    required this.etaMin,
    required this.distKm,
    required this.nota,
    required this.taxaAceitacao,
    required this.pontos,
    required this.estado,
    this.motivo,
    this.oferecidaEm,
    this.expiraEm,
    this.terminouEm,
  });

  final int pos;
  final String motoristaId;
  final String motorista;
  final double etaMin;
  final double distKm;
  final double nota;
  final double taxaAceitacao;
  final double pontos;
  final String estado;
  final String? motivo;
  final DateTime? oferecidaEm;
  final DateTime? expiraEm;
  final DateTime? terminouEm;

  factory FilaEntradaView.fromMap(Map<String, dynamic> m) => FilaEntradaView(
        pos: _intOuNulo(m['pos']) ?? 0,
        motoristaId: '${m['motorista_id'] ?? ''}',
        motorista: (m['motorista'] ?? '').toString().trim().isEmpty
            ? 'Motorista ${'${m['motorista_id'] ?? ''}'.padRight(8).substring(0, 8)}'
            : m['motorista'].toString(),
        etaMin: _num(m['eta_min']),
        distKm: _num(m['dist_km']),
        nota: _num(m['nota']),
        taxaAceitacao: _num(m['taxa_aceitacao']),
        pontos: _num(m['pontos']),
        estado: '${m['estado'] ?? 'espera'}',
        motivo: m['motivo']?.toString(),
        oferecidaEm: _data(m['oferecida_em']),
        expiraEm: _data(m['expira_em']),
        terminouEm: _data(m['terminou_em']),
      );
}

/// Uma corrida à procura (ou acabada de atribuir) com a sua fila.
class FilaCorridaView {
  const FilaCorridaView({
    required this.rideId,
    required this.status,
    required this.origem,
    required this.destino,
    required this.entradas,
    this.rideKind,
    this.criadaEm,
    this.reserva = false,
    this.balcao = false,
    this.ofertaMotorista,
    this.ofertaExpiraEm,
    this.segundosRestantes,
    this.ronda,
    this.rondaEstado,
    this.rondaMotivoFim,
  });

  final String rideId;
  final String status;
  final String? rideKind;
  final String origem;
  final String destino;
  final DateTime? criadaEm;
  final bool reserva;
  final bool balcao;
  final String? ofertaMotorista;
  final DateTime? ofertaExpiraEm;
  final int? segundosRestantes;
  final int? ronda;
  final String? rondaEstado;
  final String? rondaMotivoFim;
  final List<FilaEntradaView> entradas;

  factory FilaCorridaView.fromMap(Map<String, dynamic> m) => FilaCorridaView(
        rideId: '${m['ride_id'] ?? ''}',
        status: '${m['status'] ?? ''}',
        rideKind: m['ride_kind']?.toString(),
        origem: '${m['origem'] ?? '—'}',
        destino: '${m['destino'] ?? '—'}',
        criadaEm: _data(m['criada_em']),
        reserva: _bool(m['reserva'], porDefeito: false),
        balcao: _bool(m['balcao'], porDefeito: false),
        ofertaMotorista: m['oferta_motorista']?.toString(),
        ofertaExpiraEm: _data(m['oferta_expira_em']),
        segundosRestantes: _intOuNulo(m['segundos_restantes']),
        ronda: _intOuNulo(m['ronda']),
        rondaEstado: m['ronda_estado']?.toString(),
        rondaMotivoFim: m['ronda_motivo_fim']?.toString(),
        entradas: ((m['entradas'] as List?) ?? const [])
            .map((e) => FilaEntradaView.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

/// O que a RPC admin_tvde_fila_ao_vivo devolve.
class FilaAoVivoView {
  const FilaAoVivoView({
    required this.ligada,
    required this.corridas,
    this.agora,
    this.ofertaS,
    this.maxMotoristas,
    this.pesoNotaMin,
    this.pesoAceitacaoMin,
    this.historicoDias,
  });

  final DateTime? agora;
  final bool ligada;
  final int? ofertaS;
  final int? maxMotoristas;
  final double? pesoNotaMin;
  final double? pesoAceitacaoMin;
  final int? historicoDias;
  final List<FilaCorridaView> corridas;

  factory FilaAoVivoView.fromMap(Map<String, dynamic> m) => FilaAoVivoView(
        agora: _data(m['agora']),
        ligada: _bool(m['ligada'], porDefeito: false),
        ofertaS: _intOuNulo(m['oferta_s']),
        maxMotoristas: _intOuNulo(m['max_motoristas']),
        pesoNotaMin: m['peso_nota_min'] == null ? null : _num(m['peso_nota_min']),
        pesoAceitacaoMin:
            m['peso_aceitacao_min'] == null ? null : _num(m['peso_aceitacao_min']),
        historicoDias: _intOuNulo(m['historico_dias']),
        corridas: ((m['corridas'] as List?) ?? const [])
            .map((e) => FilaCorridaView.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

/// Uma linha do histórico (admin_tvde_fila_historico).
class FilaHistoricoLinha {
  const FilaHistoricoLinha({
    required this.rideId,
    required this.motorista,
    required this.estado,
    this.pos,
    this.ronda,
    this.motivo,
    this.quando,
    this.origem,
    this.etaMin,
    this.nota,
    this.taxaAceitacao,
  });

  final String rideId;
  final String motorista;
  final String estado;
  final int? pos;
  final int? ronda;
  final String? motivo;
  final DateTime? quando;
  final String? origem;
  final double? etaMin;
  final double? nota;
  final double? taxaAceitacao;

  factory FilaHistoricoLinha.fromMap(Map<String, dynamic> m) => FilaHistoricoLinha(
        rideId: '${m['ride_id'] ?? ''}',
        motorista: '${m['motorista'] ?? m['motorista_id'] ?? '—'}',
        estado: '${m['estado'] ?? ''}',
        pos: _intOuNulo(m['pos']),
        ronda: _intOuNulo(m['ronda']),
        motivo: m['motivo']?.toString(),
        quando: _data(m['quando']),
        origem: m['origem']?.toString(),
        etaMin: m['eta_min'] == null ? null : _num(m['eta_min']),
        nota: m['nota'] == null ? null : _num(m['nota']),
        taxaAceitacao: m['taxa_aceitacao'] == null ? null : _num(m['taxa_aceitacao']),
      );
}

/// Rótulo PT-BR do estado de um motorista na fila.
String rotuloEstadoFila(String estado) {
  switch (estado) {
    case 'espera':
      return 'Na fila';
    case 'oferta':
      return 'Com a oferta';
    case 'aceitou':
      return 'Aceitou';
    case 'recusou':
      return 'Recusou';
    case 'expirou':
      return 'Deixou expirar';
    case 'saltado':
      return 'Pulado';
    case 'cancelada':
      return 'Corrida cancelada';
    default:
      return estado;
  }
}

/// Validação de um número escrito no painel. Inteiro: só algarismos (nada de
/// "5,5" nem "40.5" — o servidor lê estas chaves como número inteiro).
/// Devolve `(valor, null)` ou `(null, mensagem em PT-BR)`.
(num?, String?) validarNumeroAjuste(String texto,
    {required bool inteiro, required num min, required num max}) {
  final t = texto.trim();
  if (t.isEmpty) return (null, 'Escreva um número.');
  num? v;
  if (inteiro) {
    if (!RegExp(r'^[0-9]{1,9}$').hasMatch(t)) {
      return (null, 'Só número inteiro, sem vírgula nem ponto (ex.: 40).');
    }
    v = int.tryParse(t);
  } else {
    if (!RegExp(r'^[0-9]{1,9}([.,][0-9]{1,3})?$').hasMatch(t)) {
      return (null, 'Número inválido (ex.: 2 ou 2,5).');
    }
    v = num.tryParse(t.replaceAll(',', '.'));
  }
  if (v == null) return (null, 'Número inválido.');
  if (v < min || v > max) return (null, 'Tem de estar entre $min e $max.');
  return (v, null);
}

/// Uma linha do registo da fila (admin_tvde_fila_registo): erros e ofertas
/// encurtadas a quem não pode ser avisado.
class FilaRegistoLinha {
  const FilaRegistoLinha({
    required this.tipo,
    required this.detalhe,
    this.em,
    this.rideId,
    this.motorista,
  });

  final String tipo;
  final Map<String, dynamic> detalhe;
  final DateTime? em;
  final String? rideId;
  final String? motorista;

  factory FilaRegistoLinha.fromMap(Map<String, dynamic> m) => FilaRegistoLinha(
        tipo: '${m['tipo'] ?? ''}',
        detalhe: m['detalhe'] is Map
            ? Map<String, dynamic>.from(m['detalhe'] as Map)
            : const <String, dynamic>{},
        em: _data(m['em']),
        rideId: m['ride_id']?.toString(),
        motorista: m['motorista']?.toString(),
      );

  bool get erro => tipo == 'erro';

  /// Frase curta PT-BR para o painel.
  String get frase {
    if (erro) {
      return 'Erro na fila (${detalhe['onde'] ?? '?'}): ${detalhe['mensagem'] ?? '?'} '
          '→ seguiu o ${detalhe['seguiu'] ?? 'despacho de sempre'}';
    }
    final quem = motorista ?? '${detalhe['driver_id'] ?? '?'}';
    final porque = detalhe['motivo'] == 'push_falhou'
        ? 'a notificação falhou'
        : 'sem notificação no telemóvel';
    return 'Oferta a $quem encurtada para ${detalhe['janela_s'] ?? '?'} s ($porque)';
  }
}

/// Rótulo PT-BR do estado da fila de uma corrida.
String rotuloRondaFila(String? estado) {
  switch (estado) {
    case 'ativa':
      return 'Fila ativa';
    case 'esgotada':
      return 'Fila esgotada → despacho normal';
    case 'aceite':
      return 'Aceita';
    case 'anulada':
      return 'Anulada (nova rodada)';
    case 'terminada':
      return 'Terminada (a corrida saiu da procura)';
    default:
      return 'Sem fila → despacho normal';
  }
}

/// Motivo técnico de "pulado" em PT-BR (o código fica entre parênteses).
String rotuloMotivoFila(String? motivo) {
  if (motivo == null || motivo.isEmpty) return '';
  const m = {
    'desligado': 'ficou offline',
    'sem_sinal_recente': 'sem sinal recente',
    'gps_velho': 'GPS parado',
    'sem_posicao': 'sem posição',
    'ja_tentado_nesta_procura': 'já tentado nesta procura',
    'recusou_ha_pouco': 'recusou há pouco',
    'ocupado_com_corrida': 'ocupado com outra corrida',
    'ocupado_com_entrega': 'ocupado com uma entrega',
    'reserva_a_seguir': 'tem uma reserva a seguir',
    'papel_desligado_ou_conformidade': 'desligou o TVDE ou documentos',
    'sem_aviso_no_telemovel': 'sem notificação no telemóvel',
    'nao_e_motorista_aprovado': 'não está aprovado',
    'nova roda pedida': 'nova rodada pedida',
  };
  final t = m[motivo];
  return t == null ? motivo : '$t ($motivo)';
}

/// Segundos que faltam na oferta, contados a partir do que o servidor disse
/// quando se leu ([segundosNaLeitura]) menos o tempo passado desde então.
int segundosQueFaltam(int? segundosNaLeitura, DateTime lidoEm, DateTime agora) {
  if (segundosNaLeitura == null) return 0;
  final passou = agora.difference(lidoEm).inSeconds;
  final r = segundosNaLeitura - passou;
  return r < 0 ? 0 : r;
}

String _csvCampo(Object? v) {
  final s = (v ?? '').toString();
  if (s.contains(';') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

/// Exportação do histórico (separador ";", para abrir no Excel em PT).
String csvHistoricoFila(List<FilaHistoricoLinha> linhas) {
  final b = StringBuffer(
      'quando_lisboa;corrida;rodada;posicao;motorista;estado;motivo;eta_min;nota;taxa_aceitacao;origem\n');
  for (final l in linhas) {
    b.writeln([
      l.quando == null ? '' : l.quando!.toLisboa().toIso8601String().substring(0, 19),
      l.rideId,
      l.ronda ?? '',
      l.pos ?? '',
      l.motorista,
      rotuloEstadoFila(l.estado),
      rotuloMotivoFila(l.motivo),
      l.etaMin ?? '',
      l.nota ?? '',
      l.taxaAceitacao ?? '',
      l.origem ?? '',
    ].map(_csvCampo).join(';'));
  }
  return b.toString();
}

/// As chaves que o separador "Ajustes" mostra e edita.
const List<String> kChavesAjustesFila = [
  'tvde_fila_inteligente_enabled',
  'tvde_offer_ttl_seconds',
  'tvde_fila_max_motoristas',
  'tvde_fila_peso_nota_min',
  'tvde_fila_peso_aceitacao_min',
  'tvde_fila_historico_dias',
  'tvde_fila_nota_min_avaliacoes',
  'tvde_fila_janela_sem_aviso_s',
  'tvde_pos_ao_vivo_enabled',
  'tvde_pos_ao_vivo_intervalo_s',
];

// ─── Ecrã ─────────────────────────────────────────────────────────────────────

typedef CarregarMapa = Future<Map<String, dynamic>> Function();
typedef CarregarLista = Future<List<dynamic>> Function();
typedef GravarAjuste = Future<void> Function(String chave, Object valor);

class AdminTvdeFilaScreen extends StatefulWidget {
  const AdminTvdeFilaScreen({
    super.key,
    this.carregarAoVivo,
    this.carregarHistorico,
    this.carregarAjustes,
    this.carregarRegisto,
    this.gravarAjuste,
    this.autoAtualizar = true,
  });

  /// Para os testes; em produção vêm das RPCs.
  final CarregarMapa? carregarAoVivo;
  final CarregarLista? carregarHistorico;
  final CarregarMapa? carregarAjustes;
  final CarregarLista? carregarRegisto;
  final GravarAjuste? gravarAjuste;
  final bool autoAtualizar;

  @override
  State<AdminTvdeFilaScreen> createState() => _AdminTvdeFilaScreenState();
}

class _AdminTvdeFilaScreenState extends State<AdminTvdeFilaScreen> {
  FilaAoVivoView? _vivo;
  DateTime _lidoEm = DateTime.now();
  List<FilaHistoricoLinha> _historico = const [];
  List<FilaRegistoLinha> _registo = const [];
  Map<String, dynamic> _ajustes = const {};
  String? _erro;
  bool _carregando = true;
  Timer? _atualizar;
  Timer? _relogio;

  SupabaseClient get _c => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _carregarTudo();
    if (widget.autoAtualizar) {
      _atualizar = Timer.periodic(const Duration(seconds: 5), (_) => _carregarAoVivo());
      _relogio = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _atualizar?.cancel();
    _relogio?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>> _lerAoVivo() async {
    final f = widget.carregarAoVivo;
    if (f != null) return f();
    final r = await _c.rpc('admin_tvde_fila_ao_vivo');
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  Future<List<dynamic>> _lerHistorico() async {
    final f = widget.carregarHistorico;
    if (f != null) return f();
    final r = await _c.rpc('admin_tvde_fila_historico',
        params: {'p_horas': 48, 'p_limite': 300});
    return r is List ? r : const [];
  }

  Future<List<dynamic>> _lerRegisto() async {
    final f = widget.carregarRegisto;
    if (f != null) return f();
    final r = await _c.rpc('admin_tvde_fila_registo',
        params: {'p_horas': 24, 'p_limite': 100});
    return r is List ? r : const [];
  }

  Future<Map<String, dynamic>> _lerAjustes() async {
    final f = widget.carregarAjustes;
    if (f != null) return f();
    final rows = await _c
        .from('platform_settings')
        .select('key, value')
        .inFilter('key', kChavesAjustesFila);
    return {
      for (final r in (rows as List))
        '${(r as Map)['key']}': r['value'],
    };
  }

  Future<void> _carregarTudo() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final vivo = await _lerAoVivo();
      final hist = await _lerHistorico();
      final aj = await _lerAjustes();
      final reg = await _lerRegisto();
      if (!mounted) return;
      setState(() {
        _vivo = FilaAoVivoView.fromMap(vivo);
        _lidoEm = DateTime.now();
        _historico = hist
            .map((e) => FilaHistoricoLinha.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
        _ajustes = aj;
        _registo = reg
            .map((e) => FilaRegistoLinha.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _carregando = false;
      });
    }
  }

  Future<void> _carregarAoVivo() async {
    try {
      final vivo = await _lerAoVivo();
      if (!mounted) return;
      setState(() {
        _vivo = FilaAoVivoView.fromMap(vivo);
        _lidoEm = DateTime.now();
      });
    } catch (_) {/* a próxima volta tenta outra vez; o erro grande fica no carregar */}
  }

  Future<void> _gravar(String chave, Object valor, String feito) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final f = widget.gravarAjuste;
      if (f != null) {
        await f(chave, valor);
      } else {
        await _c.rpc('admin_update_setting', params: {'p_key': chave, 'p_value': valor});
      }
      messenger.showSnackBar(SnackBar(content: Text(feito)));
      await _carregarTudo();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erro ao gravar ($chave): $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Fila inteligente (TVDE)'),
          actions: [
            IconButton(
              onPressed: _carregarTudo,
              icon: const Icon(Icons.refresh),
              tooltip: 'Atualizar',
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Ao vivo'),
            Tab(text: 'Histórico'),
            Tab(text: 'Ajustes'),
          ]),
        ),
        body: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _erro != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Erro: $_erro',
                          style: const TextStyle(color: AppColors.error)),
                    ),
                  )
                : TabBarView(children: [
                    _abaAoVivo(),
                    _abaHistorico(),
                    _abaAjustes(),
                  ]),
      ),
    );
  }

  Widget _abaAoVivo() {
    final v = _vivo;
    final corridas = v?.corridas ?? const <FilaCorridaView>[];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: (v?.ligada ?? false)
              ? AppColors.primary.withValues(alpha: 0.08)
              : Colors.grey.withValues(alpha: 0.10),
          child: ListTile(
            leading: Icon(
              (v?.ligada ?? false) ? Icons.queue : Icons.pause_circle_outline,
              color: (v?.ligada ?? false) ? AppColors.primary : Colors.grey,
            ),
            title: Text((v?.ligada ?? false)
                ? 'Fila inteligente LIGADA'
                : 'Fila inteligente DESLIGADA (despacho de sempre)'),
            subtitle: Text(
                'Cada oferta dura ${v?.ofertaS ?? '?'} s (tvde_offer_ttl_seconds). '
                'Até ${v?.maxMotoristas ?? '?'} motoristas por lista. '
                'Tempo até à recolha em linha recta. '
                'Atualiza sozinho de 5 em 5 s.'),
          ),
        ),
        if (_registo.any((g) => g.erro))
          Card(
            key: const Key('fila_erros_24h'),
            color: AppColors.error.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Erros da fila nas últimas 24 h: ${_registo.where((g) => g.erro).length} '
                    '(as corridas seguiram pelo despacho de sempre)',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.error),
                  ),
                  for (final g in _registo.where((g) => g.erro).take(5))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${g.em == null ? '' : '${_hora(g.em!)} · '}${g.frase}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        if (corridas.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('Nenhuma corrida à procura de motorista agora.')),
          ),
        for (final c in corridas) _cartaoCorrida(c),
      ],
    );
  }

  Widget _cartaoCorrida(FilaCorridaView c) {
    final falta = segundosQueFaltam(c.segundosRestantes, _lidoEm, DateTime.now());
    final tipo = c.rideKind == 'encomendas' ? 'Encomenda' : 'Passageiros';
    final etiquetas = [
      tipo,
      if (c.reserva) 'Reserva',
      if (c.balcao) 'Balcão (fila justa)',
    ].join(' · ');
    return Card(
      key: Key('fila_corrida_${c.rideId}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${c.origem} → ${c.destino}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              '$etiquetas · status: ${c.status} · '
              '${c.criadaEm == null ? '' : 'pedida às ${_hora(c.criadaEm!)}'}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 6),
            Text(
              rotuloRondaFila(c.rondaEstado) +
                  (c.ronda == null ? '' : ' · rodada ${c.ronda}') +
                  (c.rondaMotivoFim == null ? '' : ' · ${c.rondaMotivoFim}'),
              style: const TextStyle(fontSize: 13),
            ),
            if (c.ofertaMotorista != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Oferta agora: ${c.ofertaMotorista} · faltam $falta s',
                  key: Key('fila_oferta_${c.rideId}'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: AppColors.primary),
                ),
              ),
            if (c.entradas.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final e in c.entradas) _linhaEntrada(e),
            ],
          ],
        ),
      ),
    );
  }

  Widget _linhaEntrada(FilaEntradaView e) {
    final cor = switch (e.estado) {
      'oferta' => AppColors.primary,
      'aceitou' => Colors.green.shade800,
      'recusou' || 'expirou' => AppColors.error,
      'saltado' => Colors.grey,
      _ => Colors.black87,
    };
    final motivo = rotuloMotivoFila(e.motivo);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 26, child: Text('${e.pos}.')),
          Expanded(
            child: Text(
              '${e.motorista} · ${e.etaMin.toStringAsFixed(1)} min (linha recta) · '
              'nota ${e.nota.toStringAsFixed(2)} · aceita ${(e.taxaAceitacao * 100).round()}% · '
              'pontos ${e.pontos.toStringAsFixed(2)}'
              '${motivo.isEmpty ? '' : ' · $motivo'}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 6),
          Text(rotuloEstadoFila(e.estado),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cor)),
        ],
      ),
    );
  }

  Widget _abaHistorico() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Últimas 48 h: ${_historico.length} linhas · recusou '
                '${_historico.where((h) => h.estado == 'recusou').length} · deixou expirar '
                '${_historico.where((h) => h.estado == 'expirou').length} · pulado '
                '${_historico.where((h) => h.estado == 'saltado').length}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton.icon(
              key: const Key('fila_exportar_csv'),
              onPressed: _historico.isEmpty
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(
                          ClipboardData(text: csvHistoricoFila(_historico)));
                      messenger.showSnackBar(const SnackBar(
                          content: Text('Histórico copiado em CSV (cole no Excel).')));
                    },
              icon: const Icon(Icons.download),
              label: const Text('Exportar CSV'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_registo.isNotEmpty) ...[
          Text(
            'Registo da fila (24 h): ${_registo.where((g) => g.erro).length} erros · '
            '${_registo.where((g) => !g.erro).length} ofertas encurtadas a quem não recebe notificação',
            key: const Key('fila_registo_resumo'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          for (final g in _registo.take(20))
            ListTile(
              dense: true,
              leading: Icon(g.erro ? Icons.error_outline : Icons.timer_outlined,
                  color: g.erro ? AppColors.error : Colors.grey),
              title: Text(g.frase, style: const TextStyle(fontSize: 12)),
              subtitle: g.em == null ? null : Text(_hora(g.em!)),
            ),
          const Divider(),
        ],
        if (_historico.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('Sem histórico da fila nas últimas 48 h.')),
          ),
        for (final h in _historico)
          ListTile(
            dense: true,
            title: Text('${h.motorista} — ${rotuloEstadoFila(h.estado)}'),
            subtitle: Text([
              if (h.quando != null) _hora(h.quando!),
              if (h.origem != null) h.origem!,
              if (h.pos != null) 'posição ${h.pos}',
              if (rotuloMotivoFila(h.motivo).isNotEmpty) rotuloMotivoFila(h.motivo),
              'corrida ${h.rideId.length >= 8 ? h.rideId.substring(0, 8) : h.rideId}…',
            ].join(' · ')),
          ),
      ],
    );
  }

  Widget _abaAjustes() {
    final filaLigada = _bool(_ajustes['tvde_fila_inteligente_enabled'], porDefeito: false);
    final posLigado = _bool(_ajustes['tvde_pos_ao_vivo_enabled'], porDefeito: true);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: SwitchListTile(
            key: const Key('sw_fila_inteligente'),
            title: const Text('Fila inteligente'),
            subtitle: const Text(
                'Ao pedir, faz uma lista ordenada (tempo de estrada, nota, taxa de aceitação) '
                'só com quem recebe notificação; se o 1.º não aceitar no tempo da oferta, '
                'passa ao 2.º da MESMA lista. Desligado = despacho de sempre '
                '(tvde_fila_inteligente_enabled).'),
            value: filaLigada,
            onChanged: (v) => _gravar('tvde_fila_inteligente_enabled', v,
                v ? 'Fila inteligente ligada.' : 'Fila inteligente desligada: despacho de sempre.'),
          ),
        ),
        Card(
          child: SwitchListTile(
            key: const Key('sw_pos_ao_vivo'),
            title: const Text('Carro a deslizar no mapa do cliente'),
            subtitle: const Text(
                'O motorista manda a posição num canal privado da corrida (Realtime). '
                'Desligado = o mapa usa só a posição gravada (tvde_pos_ao_vivo_enabled).'),
            value: posLigado,
            onChanged: (v) => _gravar('tvde_pos_ao_vivo_enabled', v,
                v ? 'Canal da posição ligado.' : 'Canal da posição desligado.'),
          ),
        ),
        const SizedBox(height: 8),
        _campoNumero('tvde_offer_ttl_seconds', 'Tempo de cada oferta (segundos)',
            'Vale para TODAS as ofertas de corrida (é o mesmo relógio que o telemóvel do motorista usa). Só número inteiro.',
            min: 10, max: 120, inteiro: true),
        _campoNumero('tvde_fila_max_motoristas', 'Motoristas em cada lista',
            'Depois deles, despacho de sempre.', min: 1, max: 20, inteiro: true),
        _campoNumero('tvde_fila_peso_nota_min', 'Peso da nota (minutos por estrela abaixo de 5)',
            'Quanto mais alto, mais a nota pesa face à distância.', min: 0, max: 30, inteiro: false),
        _campoNumero('tvde_fila_peso_aceitacao_min', 'Peso da aceitação (minutos para 0% de aceitação)',
            'Quanto mais alto, mais quem recusa muito vai para trás.', min: 0, max: 30, inteiro: false),
        _campoNumero('tvde_fila_historico_dias', 'Dias de histórico para a taxa de aceitação',
            'Ofertas mais antigas não contam.', min: 1, max: 365, inteiro: true),
        _campoNumero('tvde_fila_nota_min_avaliacoes', 'Avaliações mínimas para usar a nota do Bora Motorista',
            'Com menos, usa a nota das entregas ou 4,8.', min: 1, max: 50, inteiro: true),
        _campoNumero('tvde_fila_janela_sem_aviso_s', 'Segundos de oferta para quem não recebe notificação',
            'Quem não pode ser avisado não prende a corrida os 40 s inteiros.', min: 5, max: 40, inteiro: true),
        _campoNumero('tvde_pos_ao_vivo_intervalo_s', 'Canal da posição: de quantos em quantos segundos',
            'Mais baixo = mais suave, mais mensagens.', min: 1, max: 10, inteiro: true),
      ],
    );
  }

  Widget _campoNumero(String chave, String titulo, String ajuda,
      {required int min, required int max, required bool inteiro}) {
    final atual = _ajustes[chave];
    return Card(
      child: ListTile(
        key: Key('aj_$chave'),
        title: Text(titulo),
        subtitle: Text('$ajuda ($chave)'),
        trailing: TextButton(
          child: Text(atual == null ? '—' : '$atual'),
          onPressed: () async {
            final ctrl = TextEditingController(text: atual == null ? '' : '$atual');
            final novo = await showDialog<num>(
              context: context,
              builder: (ctx) => _DialogoNumero(
                titulo: titulo,
                controlador: ctrl,
                inteiro: inteiro,
                min: min,
                max: max,
              ),
            );
            ctrl.dispose();
            if (novo == null) return;
            await _gravar(chave, inteiro ? novo.toInt() : novo, '$titulo: $novo gravado.');
          },
        ),
      ),
    );
  }

  String _hora(DateTime t) {
    final l = t.toLisboa();
    String d(int n) => n.toString().padLeft(2, '0');
    return '${d(l.day)}/${d(l.month)} ${d(l.hour)}:${d(l.minute)}:${d(l.second)}';
  }
}

/// Diálogo de um número: valida antes de gravar e diz porquê em PT-BR.
class _DialogoNumero extends StatefulWidget {
  const _DialogoNumero({
    required this.titulo,
    required this.controlador,
    required this.inteiro,
    required this.min,
    required this.max,
  });

  final String titulo;
  final TextEditingController controlador;
  final bool inteiro;
  final int min;
  final int max;

  @override
  State<_DialogoNumero> createState() => _DialogoNumeroState();
}

class _DialogoNumeroState extends State<_DialogoNumero> {
  String? _erro;

  void _gravar() {
    final (v, erro) = validarNumeroAjuste(widget.controlador.text,
        inteiro: widget.inteiro, min: widget.min, max: widget.max);
    if (erro != null) {
      setState(() => _erro = erro);
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: TextField(
        key: const Key('aj_campo_numero'),
        controller: widget.controlador,
        keyboardType: widget.inteiro
            ? TextInputType.number
            : const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: widget.inteiro
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        decoration: InputDecoration(
          helperText: widget.inteiro
              ? 'Número inteiro entre ${widget.min} e ${widget.max}'
              : 'Entre ${widget.min} e ${widget.max}',
          errorText: _erro,
        ),
        onSubmitted: (_) => _gravar(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _gravar, child: const Text('Gravar')),
      ],
    );
  }
}
