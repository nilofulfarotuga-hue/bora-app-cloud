/// Palavras do painel admin (PT-BR) para o registro de ofertas
/// (`ofertas_prestador_log`) e para a chamada de reforço.
///
/// Funções puras — sem Flutter nem Supabase — para se poderem testar sem
/// ecrã. Nasceram na missão "a chamada grita sempre" (10/10/2026): o painel
/// passa a mostrar, pedido a pedido, quem foi chamado, em que fase, se o
/// toque chegou ao FCM e como acabou.
library;

/// O que o painel mostra quando a migração ainda não foi aplicada no servidor
/// (tabela, função ou definição em falta). Nunca um erro vermelho.
const String kAindaNaoAtivo = 'Ainda não ativo no servidor';

/// Definições da chamada de reforço (migração 20261010063000).
const List<String> kChavesReforcoEntregas = [
  'dispatch_forcado_ligado',
  'dispatch_voltas_online_antes_forcado',
  'dispatch_forcado_tentativas',
  'dispatch_forcado_prioridade',
  'dispatch_forcado_visto_horas',
  'dispatch_forcado_horario_inicio',
  'dispatch_forcado_horario_fim',
  'dispatch_forcado_max_por_dia',
  'dispatch_voltas_online_depois_forcado',
  'dispatch_cancelar_so_no_fim',
  'dispatch_cancelar_limite_absoluto_segundos',
];

const List<String> kChavesReforcoTvde = [
  'tvde_forcado_ligado',
  'tvde_forcado_tentativas',
  'tvde_forcado_prioridade',
];

/// Chaves de [pedidas] que não existem em [existentes] (pela ordem pedida).
List<String> chavesEmFalta(
        Iterable<String> pedidas, Iterable<String> existentes) {
  final ha = existentes.toSet();
  return [for (final k in pedidas) if (!ha.contains(k)) k];
}

/// `true` quando o erro diz que o servidor ainda não tem a função, a tabela,
/// a coluna ou a definição — ou seja, a migração ainda não foi aplicada.
/// Erros de outra natureza (sem rede, sem permissão) devolvem `false`.
bool servidorAindaSemIsto(Object? erro) {
  if (erro == null) return false;
  final s = erro.toString();
  const marcas = [
    'PGRST202', // função não está no schema cache do PostgREST
    'PGRST205', // tabela não está no schema cache do PostgREST
    '42883', // undefined_function
    '42P01', // undefined_table
    '42703', // undefined_column
    'Could not find the function',
    'Could not find the table',
    'unknown_setting',
  ];
  if (marcas.any(s.contains)) return true;
  final baixo = s.toLowerCase();
  return baixo.contains('does not exist') &&
      (baixo.contains('function') ||
          baixo.contains('relation') ||
          baixo.contains('column'));
}

/// A fase em que a oferta foi feita, em palavras.
String faseEmPalavras(Object? fase) {
  switch ('${fase ?? ''}'.trim()) {
    case '':
      return '—';
    case 'online':
      return 'online';
    case 'desligado':
      return 'desligado';
    case 'online1':
      return '1ª rodada online';
    case 'forcado':
      return 'chamada de reforço';
    case 'online2':
      return 'rodada online final';
    default:
      return '$fase'.replaceAll('_', ' ');
  }
}

/// Como a oferta acabou, em palavras.
String desfechoEmPalavras(Object? desfecho) {
  switch ('${desfecho ?? ''}'.trim()) {
    case '':
    case 'a decorrer':
      return 'em andamento';
    case 'aceite':
      return 'aceitou';
    case 'recusou':
    case 'recusada':
      return 'recusou';
    case 'expirou':
      return 'expirou sem resposta';
    case 'sem_resposta':
      return 'não respondeu';
    case 'pedido_cancelado':
      return 'pedido cancelado';
    case 'pedido_mudou':
      return 'pedido mudou de estado';
    case 'sem_motorista':
      return 'corrida ficou sem motorista';
    default:
      return '$desfecho'.replaceAll('_', ' ');
  }
}

/// Categoria do registro, em palavras.
String categoriaEmPalavras(Object? categoria) {
  switch ('${categoria ?? ''}'.trim()) {
    case 'entrega':
      return 'Entrega';
    case 'favor':
      return 'Favor';
    case 'tvde':
      return 'TVDE (corrida)';
    case 'limpeza':
      return 'Limpeza';
    case 'lavagem':
      return 'Lavagem';
    case '':
      return '—';
    default:
      return '$categoria';
  }
}

/// "sim (1 de 2 aparelhos)" / "não (0 de 1 aparelho)" / "sem registro".
/// [enviados] = quantos aparelhos o FCM aceitou; [aparelhos] = a quantos se
/// tentou mandar.
String toqueEntregueEmPalavras(Object? enviados, Object? aparelhos) {
  final e = _int(enviados);
  final a = _int(aparelhos);
  if (e == null) return 'sem registro';
  final resposta = e > 0 ? 'sim' : 'não';
  if (a == null) return resposta;
  return '$resposta ($e de $a ${a == 1 ? 'aparelho' : 'aparelhos'})';
}

/// "40 s", "2 min", "1 min 30 s"; "—" se não houver.
String janelaEmPalavras(Object? segundos) {
  final s = _int(segundos);
  if (s == null || s < 0) return '—';
  if (s < 60) return '$s s';
  final m = s ~/ 60;
  final r = s % 60;
  return r == 0 ? '$m min' : '$m min $r s';
}

/// `true` quando o `admin_ofertas_log` já devolve o resumo novo (com as
/// entregas, Favores e TVDE). O antigo não tem `reforco` nem `toque_falhou`.
bool registroNovoAtivo(Map<String, dynamic> resumo) =>
    resumo.containsKey('reforco') || resumo.containsKey('toque_falhou');

/// Nova lista de prioridade da chamada de reforço: primeiro quem consentiu,
/// pela ordem mostrada no painel; depois, pela ordem antiga, quem estava na
/// lista mas ainda não consentiu (não perde o lugar por ter o interruptor
/// desligado hoje). Sem repetidos.
List<String> novaPrioridade(
    List<String> consentidosPorOrdem, List<String> prioridadeAntiga) {
  final saida = <String>[];
  for (final id in [...consentidosPorOrdem, ...prioridadeAntiga]) {
    if (id.isEmpty || saida.contains(id)) continue;
    saida.add(id);
  }
  return saida;
}

/// Ordem inicial (user_id) de quem consentiu, a partir dos itens de
/// `admin_reforco_lista`: primeiro quem já tem lugar na prioridade (`ordem`
/// 1, 2, 3…), depois os outros por nome. Quem não consentiu fica de fora.
List<String> ordemInicialConsentidos(List<Map<String, dynamic>> itens) {
  final cons = itens
      .where((i) => i['consentiu'] == true && '${i['user_id'] ?? ''}'.isNotEmpty)
      .toList();
  cons.sort((a, b) {
    final oa = _int(a['ordem']);
    final ob = _int(b['ordem']);
    if (oa != null && ob != null && oa != ob) return oa.compareTo(ob);
    if (oa != null && ob == null) return -1;
    if (oa == null && ob != null) return 1;
    return '${a['nome'] ?? ''}'
        .toLowerCase()
        .compareTo('${b['nome'] ?? ''}'.toLowerCase());
  });
  return [for (final i in cons) '${i['user_id']}'];
}

/// Lista de user_id guardada numa definição jsonb (array); vazia se não for.
List<String> listaDeIds(Object? valor) =>
    valor is List ? [for (final v in valor) if (v != null) '$v'] : <String>[];

/// Move o elemento [indice] de [lista] uma posição ([delta] = -1 sobe,
/// +1 desce). Fora dos limites devolve a lista igual.
List<T> moverNaLista<T>(List<T> lista, int indice, int delta) {
  final alvo = indice + delta;
  if (indice < 0 || indice >= lista.length) return List<T>.of(lista);
  if (alvo < 0 || alvo >= lista.length) return List<T>.of(lista);
  final copia = List<T>.of(lista);
  final x = copia.removeAt(indice);
  copia.insert(alvo, x);
  return copia;
}

/// "HH:MM" válido (00:00..23:59), ou `null`.
String? horaHhMm(Object? valor) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch('${valor ?? ''}'.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final mi = int.parse(m.group(2)!);
  if (h > 23 || mi > 59) return null;
  return '${h.toString().padLeft(2, '0')}:${mi.toString().padLeft(2, '0')}';
}

int? _int(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse('$v'.trim());
}
