/// CASA E MANUTENÇÃO (faz-tudo) — peças comuns do hub do painel (PT-BR, só o
/// Danilo usa). Missão casa-manutencao-2026-10-30. Contrato das funções do
/// servidor em `.claude/.ai/provas/casa-manutencao-2026-10-30/ESPEC.md`.
///
/// Regras (skill painel-admin-limpo):
///  · datas sempre na hora de Lisboa, nunca no fuso do navegador;
///  · dinheiro em euros com vírgula ("25,00 €"), cêntimos inteiros do servidor;
///  · nenhum cálculo de dinheiro aqui: o painel só mostra o que o servidor dá;
///  · cada ação pede confirmação antes de chamar o servidor.
library;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../models/casa_models.dart' show casaEuro;
import '../../utils/hora_lisboa.dart';
import '../../widgets/admin/papeis_da_pessoa.dart'
    show ChamarRpcPainel, rpcPainelPadrao;
import '../../widgets/bora_foto_ecra_inteiro.dart';
import '_admin_rpc_errors.dart';

export '../../widgets/admin/papeis_da_pessoa.dart'
    show ChamarRpcPainel, rpcPainelPadrao;

/// Baldes privados da Casa (contrato do servidor).
const String kBaldeCasaDocumentos = 'handyman-documents';
const String kBaldeCasaFotos = 'casa-fotos';

/// Texto do aviso quando os valores ainda não têm o "autorizo".
const String kCasaTextoProposta = 'PROPOSTA — aguardando o autorizo do Danilo';

/// Aviso fixo do catálogo.
const String kCasaAvisoMudarPreco =
    'Mudar preço volta a pôr os valores como PROPOSTA até o Danilo dizer '
    'autorizo.';

/// Escolhe a função do servidor: a injetada (testes) ou a verdadeira.
ChamarRpcPainel casaRpc(ChamarRpcPainel? injetada) =>
    injetada ?? rpcPainelPadrao;

// ── Leitura tolerante do JSON ─────────────────────────────────────────────

Map<String, dynamic> casaMapa(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> casaLista(Object? v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <Map<String, dynamic>>[];

int casaInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse('${v ?? ''}') ?? 0;
}

double casaDouble(Object? v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

/// Texto para mostrar; vazio vira "—".
String casaTexto(Object? v) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty ? '—' : s;
}

/// Cêntimos do servidor → "25,00 €". Nulo → "—".
String casaEuroAdmin(Object? cents) =>
    cents == null || '$cents'.isEmpty ? '—' : casaEuro(casaInt(cents));

/// Euros escritos pelo Danilo ("25", "25,5", "25.50") → cêntimos. Nulo se
/// não for um número positivo.
int? casaCentimosDeTexto(String texto) {
  final t = texto.trim().replaceAll('€', '').replaceAll(' ', '').replaceAll(',', '.');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null || v <= 0) return null;
  return (v * 100).round();
}

/// Cêntimos → "25,00" (sem o símbolo), para pôr num campo de texto.
String casaEuroCampo(Object? cents) => cents == null
    ? ''
    : (casaInt(cents) / 100).toStringAsFixed(2).replaceAll('.', ',');

// ── Datas em Lisboa ────────────────────────────────────────────────────────

String _dd(int n) => n.toString().padLeft(2, '0');

/// "31/10/2026 14:05" na hora de Lisboa; "—" se não houver data.
String casaDataHora(Object? iso) {
  final d = DateTime.tryParse('${iso ?? ''}');
  if (d == null) return '—';
  final l = paredeLisboa(d);
  return '${_dd(l.day)}/${_dd(l.month)}/${l.year} ${_dd(l.hour)}:${_dd(l.minute)}';
}

/// "31/10/2026". Uma data simples ("2026-10-31", ex. validade) não muda de
/// dia; um instante converte-se para Lisboa.
String casaData(Object? isoOuData) {
  final s = '${isoOuData ?? ''}'.trim();
  if (s.isEmpty) return '—';
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
    return '${s.substring(8, 10)}/${s.substring(5, 7)}/${s.substring(0, 4)}';
  }
  final d = DateTime.tryParse(s);
  if (d == null) return s;
  final l = paredeLisboa(d);
  return '${_dd(l.day)}/${_dd(l.month)}/${l.year}';
}

/// Validade escrita pelo Danilo: vazio (sem validade), "AAAA-MM-DD" ou
/// "DD/MM/AAAA". `ok=false` quando não se percebe a data.
({bool ok, String? iso}) casaLerValidade(String texto) {
  final t = texto.trim();
  if (t.isEmpty) return (ok: true, iso: null);
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(t);
  final pt = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(t);
  int? a, m, d;
  if (iso != null) {
    a = int.parse(iso.group(1)!);
    m = int.parse(iso.group(2)!);
    d = int.parse(iso.group(3)!);
  } else if (pt != null) {
    d = int.parse(pt.group(1)!);
    m = int.parse(pt.group(2)!);
    a = int.parse(pt.group(3)!);
  }
  if (a == null || m == null || d == null) return (ok: false, iso: null);
  final dt = DateTime.utc(a, m, d);
  if (dt.year != a || dt.month != m || dt.day != d) {
    return (ok: false, iso: null);
  }
  return (ok: true, iso: casaIsoData(dt));
}

/// "2026-10-26" a partir de um dia (só lê ano/mês/dia).
String casaIsoData(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_dd(d.month)}-${_dd(d.day)}';

/// Dia de HOJE em Lisboa (meia-noite, marca UTC, só para ler o dia).
DateTime casaHojeLisboa([DateTime? agora]) {
  final l = paredeLisboa(agora ?? DateTime.now());
  return DateTime.utc(l.year, l.month, l.day);
}

/// Segunda-feira (dia de Lisboa) da semana que contém [instante]. A semana
/// do acerto vai de segunda 00:00 a domingo 23:59 de Lisboa.
DateTime casaSegundaLisboa([DateTime? instante]) {
  final dia = casaHojeLisboa(instante);
  return dia.subtract(Duration(days: dia.weekday - DateTime.monday));
}

/// "26/10 a 01/11" para a semana que começa em [segunda].
String casaRotuloSemana(DateTime segunda) {
  final fim = segunda.add(const Duration(days: 6));
  return '${_dd(segunda.day)}/${_dd(segunda.month)} a '
      '${_dd(fim.day)}/${_dd(fim.month)}';
}

// ── Rótulos PT-BR ──────────────────────────────────────────────────────────

/// Os estados do pedido, pela ordem da vida do pedido.
const List<String> kCasaEstados = [
  'aguarda_pagamento',
  'procura',
  'orcamentos',
  'aceite',
  'a_caminho',
  'chegou',
  'em_curso',
  'concluido',
  'confirmado',
  'disputa',
  'cancelado',
  'expirado',
];

String casaEstadoPtBr(String? e) => switch (e) {
      'aguarda_pagamento' => 'Aguardando pagamento',
      'procura' => 'Procurando profissional',
      'orcamentos' => 'Aguardando orçamentos',
      'aceite' => 'Aceito (profissional definido)',
      'a_caminho' => 'Profissional a caminho',
      'chegou' => 'Profissional chegou',
      'em_curso' => 'Trabalho em andamento',
      'concluido' => 'Concluído (aguardando o cliente)',
      'confirmado' => 'Confirmado pelo cliente',
      'disputa' => 'Disputa (cliente pediu para refazer)',
      'cancelado' => 'Cancelado',
      'expirado' => 'Expirado (sem profissional)',
      null || '' => '—',
      _ => e,
    };

Color casaEstadoCor(String? e) => switch (e) {
      'aguarda_pagamento' || 'procura' || 'orcamentos' => AppColors.warning,
      'aceite' || 'a_caminho' || 'chegou' || 'em_curso' => AppColors.info,
      'concluido' || 'confirmado' => AppColors.success,
      'disputa' || 'cancelado' => AppColors.error,
      _ => AppColors.textSecondary,
    };

/// Estados da aprovação do profissional (filtros da aba Profissionais).
const List<String> kCasaAprovacoes = [
  'pending',
  'approved',
  'suspended',
  'rejected',
  'banned',
];

String casaAprovacaoPtBr(String? s) => switch (s) {
      'pending' => 'Pendente',
      'approved' => 'Aprovado',
      'suspended' => 'Suspenso',
      'rejected' => 'Recusado',
      'banned' => 'Banido',
      null || '' => '—',
      _ => s,
    };

Color casaAprovacaoCor(String? s) => switch (s) {
      'approved' => AppColors.success,
      'pending' => AppColors.warning,
      'suspended' || 'rejected' || 'banned' => AppColors.error,
      _ => AppColors.textSecondary,
    };

String casaOficioEstadoPtBr(String? s) => switch (s) {
      'pending' => 'Ofício pendente',
      'approved' => 'Ofício aprovado',
      'rejected' => 'Ofício recusado',
      'suspended' => 'Ofício suspenso',
      null || '' => '—',
      _ => s,
    };

String casaDocumentoTipoPtBr(String? t) => switch (t) {
      'cartao_cidadao' => 'Cartão de cidadão',
      'seguro_acidentes' => 'Seguro de acidentes de trabalho',
      'seguro_rc' => 'Seguro de responsabilidade civil',
      'dgeg_eletricidade' => 'Habilitação DGEG (eletricidade)',
      'dgeg_gas' => 'Credenciação DGEG (gás)',
      'impic' => 'Certificado IMPIC',
      'outro' => 'Outro documento',
      null || '' => 'Documento',
      _ => t,
    };

String casaDocumentoEstadoPtBr(String? s) => switch (s) {
      'pending' => 'Em análise',
      'approved' => 'Aprovado',
      'rejected' => 'Recusado',
      'expired' => 'Vencido',
      null || '' => '—',
      _ => s,
    };

String casaModoPtBr(String? m) => switch (m) {
      'fixo' => 'Preço fixo',
      'hora' => 'Por hora',
      'orcamento' => 'Orçamento',
      null || '' => '—',
      _ => m,
    };

String casaUnidadePtBr(String? u) => switch (u) {
      'tarefa' => 'por tarefa',
      'movel' => 'por móvel',
      'hora' => 'por hora',
      null || '' => '',
      _ => u,
    };

String casaPagamentoPtBr(String? p) => switch (p) {
      'card' => 'Cartão',
      'mbway' => 'MB Way',
      'cash' => 'Dinheiro',
      null || '' => '—',
      _ => p,
    };

String casaPagamentoStatusPtBr(String? s) => switch (s) {
      'unpaid' => 'Não pago',
      'held' => 'Retido (aguardando confirmação)',
      'released' => 'Liberado',
      'estornado' => 'Estornado',
      'cash_pending' => 'Dinheiro a acertar',
      'cash_settled' => 'Dinheiro acertado',
      null || '' => '—',
      _ => s,
    };

const List<String> kCasaOrcamentoEstados = [
  'enviado',
  'aceite',
  'recusado',
  'expirado',
  'retirado',
];

String casaOrcamentoEstadoPtBr(String? s) => switch (s) {
      'enviado' => 'Enviado (aberto)',
      'aceite' => 'Aceito (ganhou)',
      'recusado' => 'Recusado',
      'expirado' => 'Expirado',
      'retirado' => 'Retirado',
      null || '' => '—',
      _ => s,
    };

String casaExtraEstadoPtBr(String? s) => switch (s) {
      'pedido' => 'Aguardando o cliente',
      'aceite' => 'Aceito pelo cliente',
      'recusado' => 'Recusado pelo cliente',
      null || '' => '—',
      _ => s,
    };

String casaAcertoStatusPtBr(String? s) => switch (s) {
      'pending' => 'Pendente',
      'paid' => 'Pago',
      'received' => 'Recebido',
      'disputed' => 'Em disputa',
      null || '' => '—',
      _ => s,
    };

String casaDirecaoPtBr(String? d) => switch (d) {
      'bora_to_handyman' => 'Bora paga ao profissional',
      'handyman_to_bora' => 'Profissional paga à Bora',
      'zero' => 'Nada a acertar',
      null || '' => '—',
      _ => d,
    };

String casaOfertaTipoPtBr(String? t) => switch (t) {
      'oferta' => 'Oferta',
      'convite_orcamento' => 'Convite para orçar',
      'repeticao' => 'Toque repetido',
      null || '' => '—',
      _ => t,
    };

String casaOfertaRespostaPtBr(String? r) => switch (r) {
      'aceite' => 'Aceitou',
      'recusada' => 'Recusou',
      'expirada' => 'Deixou expirar',
      'sem_aparelho' => 'Sem aparelho registrado',
      'orcamento_enviado' => 'Enviou orçamento',
      null || '' => 'Aguardando resposta',
      _ => r,
    };

String casaPapelPtBr(String? p) => switch (p) {
      'client' || 'cliente' => 'Cliente',
      'handyman' || 'profissional' => 'Profissional',
      'admin' => 'Admin',
      'system' || 'sistema' || 'cron' => 'Sistema',
      null || '' => '—',
      _ => p,
    };

String casaAtividadePtBr(String? s) => switch (s) {
      'em_analise' => 'Comprovativo de atividade em análise',
      'aprovada' => 'Comprovativo de atividade aprovado',
      'recusada' => 'Comprovativo de atividade recusado',
      'sem_atividade' || null || '' => 'Sem comprovativo de atividade',
      _ => 'Comprovativo de atividade: $s',
    };

String casaDiaSemanaPtBr(Object? weekday) => switch (casaInt(weekday)) {
      0 => 'Domingo',
      1 => 'Segunda',
      2 => 'Terça',
      3 => 'Quarta',
      4 => 'Quinta',
      5 => 'Sexta',
      6 => 'Sábado',
      _ => '—',
    };

/// Resolução de disputa (contrato `admin_casa_resolver_disputa`).
const Map<String, String> kCasaResolucoes = {
  'refeito': 'Trabalho refeito (garantia cumprida)',
  'sem_razao': 'Cliente sem razão (fica como está)',
  'reembolso_pendente': 'Reembolso pendente (o Danilo decide o dinheiro)',
};

// ── Valores autorizados ────────────────────────────────────────────────────

/// `valores_autorizados{autorizado, em, texto}` do servidor.
class CasaValores {
  const CasaValores({this.autorizado = false, this.em, this.texto});
  final bool autorizado;
  final String? em;
  final String? texto;

  factory CasaValores.fromJson(Object? v) {
    if (v is bool) return CasaValores(autorizado: v);
    final m = casaMapa(v);
    return CasaValores(
      autorizado: m['autorizado'] == true,
      em: m['em']?.toString(),
      texto: m['texto']?.toString(),
    );
  }
}

/// Faixa que diz se os preços/comissão valem ou ainda são PROPOSTA.
class CasaAvisoValores extends StatelessWidget {
  const CasaAvisoValores({super.key, required this.valores, this.extra});
  final CasaValores valores;

  /// Linha a mais por baixo (ex.: o aviso do catálogo).
  final String? extra;

  @override
  Widget build(BuildContext context) {
    final ok = valores.autorizado;
    final cor = ok ? AppColors.success : AppColors.warning;
    return Container(
      key: ValueKey(ok ? 'casa-valores-autorizados' : 'casa-valores-proposta'),
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        border: Border.all(color: cor, width: ok ? 1 : 2),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(ok ? Icons.verified : Icons.warning_amber_rounded,
                color: cor),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                ok ? 'Valores AUTORIZADOS' : kCasaTextoProposta,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: ok ? 14 : 16,
                    color: ok ? AppColors.success : AppColors.textPrimary),
              ),
            ),
          ]),
          const SizedBox(height: Spacing.xs),
          Text(
            ok
                ? 'Autorizado em ${casaDataHora(valores.em)}'
                    '${(valores.texto ?? '').trim().isEmpty ? '' : ' — "${valores.texto}"'}'
                : 'Preços do catálogo, comissão e promoção dos 5 primeiros '
                    'ainda não valem: o servidor recusa pedidos reais de preço '
                    'fixo e o acerto não calcula comissão até o Danilo dizer '
                    '"autorizo" (registrar em Configurações).',
            style: const TextStyle(fontSize: 12),
          ),
          if (extra != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(extra!,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ],
      ),
    );
  }
}

// ── Erros do servidor ─────────────────────────────────────────────────────

/// Resposta `{ok:false, error}` de uma função do servidor.
class CasaErroServidor implements Exception {
  const CasaErroServidor(this.codigo);
  final String codigo;
  @override
  String toString() => codigo;
}

/// Lança [CasaErroServidor] quando o servidor responde `{ok:false}`.
dynamic casaVerOk(dynamic res) {
  if (res is Map && res['ok'] == false) {
    throw CasaErroServidor('${res['error'] ?? res['erro'] ?? 'erro'}');
  }
  return res;
}

/// Códigos curtos do servidor (contrato) → texto PT-BR para o Danilo.
const Map<String, String> kCasaErrosPtBr = {
  'casa_desligada': 'A Casa está desligada (interruptor geral).',
  'valores_por_autorizar':
      'Os valores ainda são PROPOSTA: falta registrar o "autorizo" do Danilo.',
  'dinheiro_acima_do_limite': 'Valor acima do limite de dinheiro em mão.',
  'sem_permissao': 'Sem permissão para esta ação.',
  'estado_invalido':
      'O pedido já mudou de estado e esta ação não vale mais. Atualize a tela.',
  'pagamento_cartao_indisponivel':
      'Cartão e MB Way ainda não estão ligados na Casa (só proposta).',
  'foto_depois_em_falta': 'Falta a foto "depois" para concluir.',
  'limite_fotos': 'Limite de fotos atingido.',
  'orcamentos_completos': 'Este pedido já tem todos os orçamentos.',
  'nao_e_profissional': 'Esta pessoa não é profissional da Casa.',
  'antecedencia_minima': 'Horário com antecedência menor que a mínima.',
  'morada_em_falta': 'Falta o endereço.',
  'motivo_obrigatorio': 'Escreva o motivo (pelo menos 3 letras).',
  'texto_sem_autorizo': 'O texto tem de conter a palavra "autorizo".',
  'documento_em_falta':
      'Falta o documento DGEG/IMPIC aprovado para este ofício.',
  // 31/10 (retoma): códigos das funções admin_casa_* (casa_05_admin.sql).
  'tem_trabalhos_ativos':
      'Este profissional tem trabalhos em andamento. Reatribua-os antes.',
  'atividade_por_aprovar':
      'Falta aprovar o comprovativo de atividade (Finanças) desta pessoa.',
  'conformidade_incompleta':
      'Faltam dados legais (nome, NIF, endereço, IBAN, nascimento) para ativar.',
  'profissional_ocupado': 'O profissional já tem trabalho nesse horário.',
  'profissional_sem_oficio':
      'O profissional não está aprovado (ou ativo) neste ofício.',
  'validade_passada': 'A validade do documento já passou.',
  'usar_interruptor': 'Use o interruptor geral para ligar/desligar a Casa.',
  'chave_invalida': 'Essa configuração não existe na Casa.',
  'valor_invalido': 'Valor inválido para esta configuração.',
  'acao_invalida': 'Ação inválida.',
  // 01/11 (revisão C16): o único código das admin_casa_* que faltava aqui.
  'oficio_invalido': 'Esse ofício não existe (ou está desativado) na Casa.',
};

String casaErroPtBr(Object e) {
  final msg = e is PostgrestException ? e.message : e.toString();
  for (final k in kCasaErrosPtBr.entries) {
    if (msg.contains(k.key)) return k.value;
  }
  if (e is CasaErroServidor) return 'O servidor recusou: ${e.codigo}';
  return humanizeAdminRpcError(e);
}

void casaMsg(BuildContext c, String t) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(t)));

/// Corre uma ação no servidor, mostra o resultado e devolve se correu bem.
Future<bool> casaExecutar(BuildContext context,
    Future<dynamic> Function() acao, String sucesso) async {
  try {
    casaVerOk(await acao());
    if (context.mounted) casaMsg(context, sucesso);
    return true;
  } catch (e) {
    if (context.mounted) casaMsg(context, casaErroPtBr(e));
    return false;
  }
}

// ── Confirmações ───────────────────────────────────────────────────────────

/// Confirmação antes de cada ação. Devolve `null` se o Danilo cancelar; se
/// confirmar, devolve o texto escrito ('' quando não se pede texto).
///
/// [exigido]: o texto tem de ser exatamente este (sem diferença de
/// maiúsculas) — a confirmação forte do interruptor.
/// [contem]: o texto tem de conter esta palavra (ex. "autorizo").
Future<String?> casaConfirmar(
  BuildContext context, {
  required String titulo,
  required String texto,
  String botao = 'Confirmar',
  bool perigo = false,
  bool pedirTexto = false,
  bool textoObrigatorio = false,
  String rotuloTexto = 'Motivo',
  String? exigido,
  String? contem,
  int linhas = 1,
  String? inicial,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => CasaConfirmarDialog(
        titulo: titulo,
        texto: texto,
        botao: botao,
        perigo: perigo,
        pedirTexto: pedirTexto || exigido != null || contem != null,
        textoObrigatorio: textoObrigatorio || exigido != null || contem != null,
        rotuloTexto: rotuloTexto,
        exigido: exigido,
        contem: contem,
        linhas: linhas,
        inicial: inicial,
      ),
    );

/// Diálogo de confirmação (público para os testes o encontrarem).
class CasaConfirmarDialog extends StatefulWidget {
  const CasaConfirmarDialog({
    super.key,
    required this.titulo,
    required this.texto,
    this.botao = 'Confirmar',
    this.perigo = false,
    this.pedirTexto = false,
    this.textoObrigatorio = false,
    this.rotuloTexto = 'Motivo',
    this.exigido,
    this.contem,
    this.linhas = 1,
    this.inicial,
  });

  final String titulo;
  final String texto;
  final String botao;
  final bool perigo;
  final bool pedirTexto;
  final bool textoObrigatorio;
  final String rotuloTexto;
  final String? exigido;
  final String? contem;
  final int linhas;

  /// Texto já escrito no campo ao abrir.
  final String? inicial;

  /// Regra do botão: sem texto pedido, sempre; com [exigido], igual; com
  /// [contem], contém; obrigatório, pelo menos 3 letras.
  static bool podeConfirmar({
    required String escrito,
    bool obrigatorio = false,
    String? exigido,
    String? contem,
  }) {
    final t = escrito.trim();
    if (exigido != null) return t.toUpperCase() == exigido.toUpperCase();
    if (contem != null) {
      return t.toLowerCase().contains(contem.toLowerCase());
    }
    if (obrigatorio) return t.length >= 3;
    return true;
  }

  @override
  State<CasaConfirmarDialog> createState() => _CasaConfirmarDialogState();
}

class _CasaConfirmarDialogState extends State<CasaConfirmarDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.inicial ?? '');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _ok => !widget.pedirTexto ||
      CasaConfirmarDialog.podeConfirmar(
        escrito: _ctrl.text,
        obrigatorio: widget.textoObrigatorio,
        exigido: widget.exigido,
        contem: widget.contem,
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.texto),
            if (widget.pedirTexto) ...[
              const SizedBox(height: Spacing.md),
              TextField(
                key: const ValueKey('casa-confirmar-texto'),
                controller: _ctrl,
                autofocus: true,
                minLines: widget.linhas,
                maxLines: widget.linhas < 2 ? 1 : widget.linhas + 2,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: widget.rotuloTexto,
                  helperText: widget.exigido != null
                      ? 'Escreva ${widget.exigido} para confirmar'
                      : widget.contem != null
                          ? 'Tem de conter a palavra "${widget.contem}"'
                          : widget.textoObrigatorio
                              ? 'Obrigatório'
                              : 'Opcional',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Voltar'),
        ),
        FilledButton(
          key: const ValueKey('casa-confirmar-ok'),
          style: FilledButton.styleFrom(
              backgroundColor:
                  widget.perigo ? AppColors.error : AppColors.primary),
          onPressed:
              _ok ? () => Navigator.pop(context, _ctrl.text.trim()) : null,
          child: Text(widget.botao),
        ),
      ],
    );
  }
}

// ── Ficheiros privados (documentos e fotos) ───────────────────────────────

/// Assina o caminho no balde privado (1 hora). Aceita "caminho" ou
/// "balde/caminho"; um URL completo volta igual.
Future<String> casaUrlAssinada(String balde, String caminho) async {
  final c = caminho.trim();
  if (c.startsWith('http')) return c;
  final path = c.startsWith('$balde/') ? c.substring(balde.length + 1) : c;
  return Supabase.instance.client.storage
      .from(balde)
      .createSignedUrl(path, 3600);
}

/// Abre um documento ou foto de um balde privado da Casa. Fotos abrem no
/// visualizador com zoom; PDF abre fora (navegador).
Future<void> casaAbrirFicheiro(
  BuildContext context, {
  required String balde,
  required String caminho,
  required String titulo,
}) async {
  if (caminho.trim().isEmpty) {
    casaMsg(context, 'Sem arquivo.');
    return;
  }
  String url;
  try {
    url = await casaUrlAssinada(balde, caminho);
  } catch (e) {
    if (context.mounted) {
      casaMsg(context, 'Não foi possível abrir o arquivo: $e');
    }
    return;
  }
  if (!context.mounted) return;
  if (caminho.toLowerCase().endsWith('.pdf')) {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    return;
  }
  await BoraFotoEcraInteiro.abrir(context, urlOrPath: url, titulo: titulo);
}

/// Galeria de fotos de um balde privado (passa com o dedo).
Future<void> casaAbrirFotos(
  BuildContext context, {
  required String balde,
  required List<String> caminhos,
  int inicial = 0,
  String? titulo,
}) async {
  if (caminhos.isEmpty) return;
  final urls = <String>[];
  try {
    for (final c in caminhos) {
      urls.add(await casaUrlAssinada(balde, c));
    }
  } catch (e) {
    if (context.mounted) casaMsg(context, 'Não foi possível abrir as fotos: $e');
    return;
  }
  if (!context.mounted) return;
  await BoraFotoEcraInteiro.abrirVarias(
    context,
    [for (final u in urls) BoraFoto.url(u)],
    inicial: inicial,
    titulo: titulo,
  );
}

// ── Peças de desenho ───────────────────────────────────────────────────────

/// Etiqueta pequena colorida.
class CasaEtiqueta extends StatelessWidget {
  const CasaEtiqueta(this.texto, {super.key, required this.cor});
  final String texto;
  final Color cor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Text(texto,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: cor)),
      );
}

/// Título de secção dentro das fichas.
class CasaSeccao extends StatelessWidget {
  const CasaSeccao(this.titulo, {super.key});
  final String titulo;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Spacing.lg, bottom: Spacing.xs),
        child: Text(titulo,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
      );
}

/// "Rótulo: valor" numa linha.
class CasaLinha extends StatelessWidget {
  const CasaLinha(this.rotulo, this.valor, {super.key, this.cor});
  final String rotulo;
  final Object? valor;
  final Color? cor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text(rotulo,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
            ),
            Expanded(
              child: Text(casaTexto(valor),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cor ?? AppColors.textPrimary)),
            ),
          ],
        ),
      );
}

/// Ecrã de erro com "Tentar de novo".
class CasaErroCarregar extends StatelessWidget {
  const CasaErroCarregar({super.key, required this.erro, required this.onTentar});
  final Object erro;
  final VoidCallback onTentar;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 36),
              const SizedBox(height: Spacing.sm),
              Text(casaErroPtBr(erro), textAlign: TextAlign.center),
              const SizedBox(height: Spacing.md),
              OutlinedButton.icon(
                onPressed: onTentar,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
      );
}

/// Lista vazia.
class CasaVazio extends StatelessWidget {
  const CasaVazio(this.texto, {super.key});
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(Spacing.xxl),
        child: Center(
          child: Text(texto,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary)),
        ),
      );
}

/// Fila de filtros (chips). `null` = todos.
class CasaFiltros extends StatelessWidget {
  const CasaFiltros({
    super.key,
    required this.opcoes,
    required this.valor,
    required this.rotulo,
    required this.onMudar,
    this.comTodos = true,
  });
  final List<String> opcoes;
  final String? valor;
  final String Function(String) rotulo;
  final ValueChanged<String?> onMudar;
  final bool comTodos;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md, vertical: Spacing.sm),
        child: Row(
          children: [
            if (comTodos)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: const Text('Todos'),
                  selected: valor == null,
                  onSelected: (_) => onMudar(null),
                ),
              ),
            for (final o in opcoes)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(rotulo(o)),
                  selected: valor == o,
                  onSelected: (_) => onMudar(o),
                ),
              ),
          ],
        ),
      );
}
