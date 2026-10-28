import 'package:latlong2/latlong.dart';

import '../utils/hora_lisboa.dart';

enum BusinessCategory {
  restaurant,
  supermarket,
  store,
  pharmacy,
  beauty,
  // Salgados, doces e bolos por encomenda (lançamento 2026-08-25).
  festas,
  // Sobremesas (2026-08-27) — açaí, gelados, doces prontos a comer.
  // Slug na base de dados: `sobremesa` (singular, minúsculas, sem acento).
  // É só um filtro visual: o fluxo de compra é o de entrega NORMAL, imediato.
  // Uma loja pode estar aqui E em Restaurantes ao mesmo tempo, via
  // `extra_categories` — é o caso da Goola Açaí.
  sobremesa,
}

extension BusinessCategoryLabel on BusinessCategory {
  String get label {
    switch (this) {
      case BusinessCategory.restaurant:
        return 'Restaurante';
      case BusinessCategory.supermarket:
        return 'Supermercado';
      case BusinessCategory.store:
        return 'Loja';
      case BusinessCategory.pharmacy:
        return 'Farmácia';
      case BusinessCategory.beauty:
        return 'Beleza';
      case BusinessCategory.festas:
        return 'Festas';
      case BusinessCategory.sobremesa:
        return 'Sobremesas';
    }
  }
}

/// Antecedência mínima das encomendas de festa, em dias (regra do Danilo,
/// 2026-08-25: UM dia, ponto — a data mais cedo é sempre o dia seguinte).
const int kFestasAvisoDias = 1;

/// Nome da prateleira de encomenda em `products.category` das lojas de festas.
/// Um carrinho com QUALQUER item desta prateleira é agendado por inteiro
/// (carrinho misto → manda a festa); só itens "Na hora" seguem o fluxo normal.
const String kFestasPrateleiraEncomenda = 'Para festa (encomenda)';

class DayHours {
  const DayHours({
    this.open = '09:00',
    this.close = '22:00',
    this.closed = false,
    this.breakStart,
    this.breakEnd,
  });

  final String open;
  final String close;
  final bool closed;

  /// Pausa do dia (27/10/2026, Boom! Burger: 14:30–19:00), 'HH:MM'. Os dois a
  /// null = sem pausa. Dentro da pausa a loja está fechada — igual ao
  /// `is_partner_open` do servidor (chaves `break_start`/`break_end`).
  final String? breakStart;
  final String? breakEnd;

  /// True quando o dia tem pausa (as duas horas preenchidas).
  bool get temPausa => breakStart != null && breakEnd != null;

  factory DayHours.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DayHours();
    return DayHours(
      open: (json['open'] as String?) ?? '09:00',
      close: (json['close'] as String?) ?? '22:00',
      closed: (json['closed'] as bool?) ?? false,
      breakStart: _horaOuNull(json['break_start']),
      breakEnd: _horaOuNull(json['break_end']),
    );
  }

  static String? _horaOuNull(dynamic v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  /// `break_start`/`break_end` vão SEMPRE (a null quando não há pausa): o
  /// gatilho `trg_business_hours_guarda_pausa` mantém a pausa antiga quando o
  /// dia novo chega sem estas chaves — só com elas a null é que a pausa sai.
  Map<String, dynamic> toJson() => {
        'open': open,
        'close': close,
        'closed': closed,
        'break_start': breakStart,
        'break_end': breakEnd,
      };

  /// [semPausa] tira a pausa (os dois a null).
  DayHours copyWith({
    String? open,
    String? close,
    bool? closed,
    String? breakStart,
    String? breakEnd,
    bool semPausa = false,
  }) =>
      DayHours(
        open: open ?? this.open,
        close: close ?? this.close,
        closed: closed ?? this.closed,
        breakStart: semPausa ? null : (breakStart ?? this.breakStart),
        breakEnd: semPausa ? null : (breakEnd ?? this.breakEnd),
      );

  /// Valida a pausa do dia. Null quando está bem (ou não há pausa, ou o dia
  /// está fechado); senão a frase do erro — PT-PT, ou PT-BR com [ptBr]
  /// (painel admin). A pausa tem de começar antes de acabar e ficar dentro
  /// do horário aberto.
  String? erroPausa({bool ptBr = false}) {
    if (closed) return null;
    if (breakStart == null && breakEnd == null) return null;
    final bs = RestaurantModel._minutosOuNull(breakStart);
    final be = RestaurantModel._minutosOuNull(breakEnd);
    if (bs == null || be == null) {
      return ptBr
          ? 'Preencha o início e o fim da pausa.'
          : 'Preenche o início e o fim da pausa.';
    }
    if (be <= bs) {
      return ptBr
          ? 'O fim da pausa precisa ser depois do início.'
          : 'O fim da pausa tem de ser depois do início.';
    }
    final o = RestaurantModel._parseMinutes(open);
    final c = RestaurantModel._parseMinutes(close);
    if (o == null || c == null) return null;
    // Horário que passa a meia-noite (ex.: 20:00–02:00): a pausa fica na
    // parte de antes da meia-noite, a única que o servidor lê nesse dia.
    final dentro = c > o ? (bs >= o && be <= c) : bs >= o;
    if (!dentro) {
      return ptBr
          ? 'A pausa precisa ficar dentro do horário de funcionamento.'
          : 'A pausa tem de ficar dentro do horário aberto.';
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is DayHours &&
      other.open == open &&
      other.close == close &&
      other.closed == closed &&
      other.breakStart == breakStart &&
      other.breakEnd == breakEnd;

  @override
  int get hashCode => Object.hash(open, close, closed, breakStart, breakEnd);
}

class BusinessHours {
  const BusinessHours({
    this.mon = const DayHours(),
    this.tue = const DayHours(),
    this.wed = const DayHours(),
    this.thu = const DayHours(),
    this.fri = const DayHours(),
    this.sat = const DayHours(),
    this.sun = const DayHours(),
    this.specialDates = const <String, DayHours>{},
  });

  /// Dias especiais (feriados, dias fechados, horário diferente) por data
  /// 'AAAA-MM-DD' de Lisboa: substituem o dia da semana, como `special_dates`
  /// no `is_partner_open` do servidor (27/10/2026).
  final Map<String, DayHours> specialDates;

  final DayHours mon;
  final DayHours tue;
  final DayHours wed;
  final DayHours thu;
  final DayHours fri;
  final DayHours sat;
  final DayHours sun;

  static const _defaultKeys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

  factory BusinessHours.fromJson(dynamic raw) {
    if (raw is! Map) return const BusinessHours();
    final m = Map<String, dynamic>.from(raw);
    return BusinessHours(
      mon: DayHours.fromJson(m['mon'] as Map<String, dynamic>?),
      tue: DayHours.fromJson(m['tue'] as Map<String, dynamic>?),
      wed: DayHours.fromJson(m['wed'] as Map<String, dynamic>?),
      thu: DayHours.fromJson(m['thu'] as Map<String, dynamic>?),
      fri: DayHours.fromJson(m['fri'] as Map<String, dynamic>?),
      sat: DayHours.fromJson(m['sat'] as Map<String, dynamic>?),
      sun: DayHours.fromJson(m['sun'] as Map<String, dynamic>?),
      specialDates: _lerDiasEspeciais(m['special_dates']),
    );
  }

  static Map<String, DayHours> _lerDiasEspeciais(dynamic raw) {
    if (raw is! List) return const <String, DayHours>{};
    final out = <String, DayHours>{};
    for (final e in raw) {
      if (e is! Map) continue;
      final data = e['date']?.toString() ?? '';
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(data)) continue;
      out[data] = DayHours.fromJson(Map<String, dynamic>.from(e));
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
        'mon': mon.toJson(),
        'tue': tue.toJson(),
        'wed': wed.toJson(),
        'thu': thu.toJson(),
        'fri': fri.toJson(),
        'sat': sat.toJson(),
        'sun': sun.toJson(),
        if (specialDates.isNotEmpty)
          'special_dates': [
            for (final e in specialDates.entries) {'date': e.key, ...e.value.toJson()},
          ],
      };

  /// O horário de um dia de calendário de Lisboa ([parede] vem de
  /// `paredeLisboa`): o dia especial dessa data, se houver, senão o da semana.
  DayHours diaEm(DateTime parede) {
    final chave = '${parede.year.toString().padLeft(4, '0')}-'
        '${parede.month.toString().padLeft(2, '0')}-'
        '${parede.day.toString().padLeft(2, '0')}';
    return specialDates[chave] ?? dayFor(parede.weekday);
  }

  DayHours dayFor(int weekday) {
    // DateTime.weekday: Mon=1 .. Sun=7
    switch (weekday) {
      case DateTime.monday:
        return mon;
      case DateTime.tuesday:
        return tue;
      case DateTime.wednesday:
        return wed;
      case DateTime.thursday:
        return thu;
      case DateTime.friday:
        return fri;
      case DateTime.saturday:
        return sat;
      case DateTime.sunday:
        return sun;
    }
    return const DayHours();
  }

  BusinessHours copyWithDay(int weekday, DayHours hours) {
    return BusinessHours(
      mon: weekday == DateTime.monday ? hours : mon,
      tue: weekday == DateTime.tuesday ? hours : tue,
      wed: weekday == DateTime.wednesday ? hours : wed,
      thu: weekday == DateTime.thursday ? hours : thu,
      fri: weekday == DateTime.friday ? hours : fri,
      sat: weekday == DateTime.saturday ? hours : sat,
      sun: weekday == DateTime.sunday ? hours : sun,
      specialDates: specialDates,
    );
  }

  static String keyForWeekday(int weekday) {
    final i = (weekday - 1).clamp(0, 6);
    return _defaultKeys[i];
  }

  @override
  bool operator ==(Object other) =>
      other is BusinessHours &&
      other.mon == mon &&
      other.tue == tue &&
      other.wed == wed &&
      other.thu == thu &&
      other.fri == fri &&
      other.sat == sat &&
      other.sun == sun &&
      other.specialDates.length == specialDates.length &&
      specialDates.entries.every((e) => other.specialDates[e.key] == e.value);

  @override
  int get hashCode => Object.hash(mon, tue, wed, thu, fri, sat, sun,
      Object.hashAllUnordered(specialDates.entries.map((e) => Object.hash(e.key, e.value))));
}

class RestaurantModel {
  const RestaurantModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.email,
    required this.photoUrl,
    required this.cuisineType,
    required this.isPartner,
    required this.category,
    this.extraCategories = const <BusinessCategory>{},
    this.isOnline = true,
    this.lat,
    this.lng,
    this.reservationsEnabled = false,
    this.takeawayEnabled = false,
    this.curbsideEnabled = false,
    this.takeawayDefaultPrepMinutes = 15,
    this.businessHours = const BusinessHours(),
    this.avgRating,
    this.ratingsCount = 0,
    this.heroImageUrl,
    this.comingSoon = false,
    this.comingSoonText,
    this.ownerId,
    this.appMarkupPct,
    this.pausaAte,
  });

  final String id;
  final String name;
  final String phone;
  final String address;
  final String email;
  final String photoUrl;
  final String cuisineType;
  final bool isPartner;
  final BusinessCategory category;

  /// Secções adicionais onde o negócio também aparece (coluna
  /// `restaurants.extra_categories`). A loja é sempre a MESMA (mesmo id, mesmo
  /// catálogo) — só passa a ser listada em mais do que uma secção do cliente.
  final Set<BusinessCategory> extraCategories;

  final bool isOnline;
  final double? lat;
  final double? lng;

  /// BR §14.10 — whether this restaurant accepts table reservations.
  /// Default false. Partner toggles it from the dashboard.
  final bool reservationsEnabled;

  /// BR §14.9 — restaurante aceita pedidos takeaway (cliente levanta no balcão).
  /// Default false. Partner toggles no dashboard.
  final bool takeawayEnabled;

  /// BR §14.9b — restaurante suporta curbside (cliente espera no carro).
  /// Default false. Só efectivo se takeawayEnabled=true.
  final bool curbsideEnabled;

  /// BR §14.9c — ETA default em minutos quando parceiro aceita o pedido sem
  /// escolher manualmente (3/5/10/15/20/30/45/60). Default 15.
  final int takeawayDefaultPrepMinutes;

  final BusinessHours businessHours;

  /// BR §44 — média de avaliações (1.0-5.0) ou null se ainda sem ratings.
  final double? avgRating;

  /// BR §44 — número de avaliações públicas + não flagged que contam para a média.
  final int ratingsCount;

  /// URL da imagem hero (banner largo) do mercado/restaurante.
  /// Gerida via admin → bucket restaurant-assets/hero/<id>.<ext>.
  /// Null quando ainda não configurada — UI usa fallback em cascata.
  final String? heroImageUrl;

  /// `restaurants.coming_soon` — a loja aparece no catálogo com selo "Em breve"
  /// e é totalmente navegável, mas NÃO aceita pedidos. O bloqueio real vive no
  /// servidor (erro `STORE_COMING_SOON`); isto é só a camada de UI.
  final bool comingSoon;

  /// `restaurants.coming_soon_text` — texto do banner na ficha da loja.
  /// Null/vazio → usar [comingSoonLabel].
  final String? comingSoonText;

  /// Dono da loja — `restaurants.user_id` (com `user_` como segunda hipótese,
  /// que é a coluna antiga que ainda coexiste).
  ///
  /// FONTE DE VERDADE de "esta loja é deste parceiro". Antes a app procurava
  /// a loja do parceiro comparando `restaurants.email` com o email do login, e
  /// isso partia sempre que a coluna de email da loja ficava por preencher —
  /// foi o que aconteceu à Goola Açaí a 2026-08-27, e mandou o dono para o
  /// wizard de criar conta em vez do painel dele. O email continua a servir de
  /// recurso para as lojas antigas que ainda não têm dono gravado.
  final String? ownerId;

  /// `restaurants.app_markup_pct` — percentagem que o app soma ao preço de
  /// balcão SÓ desta loja (0,10 = +10 %, modelo "comissão paga pelo cliente",
  /// ex.: Leonidas). Null = a fórmula da plataforma. Lido por
  /// `PartnerPriceRules`; espelha `partner_store_share(price, restaurant_id)`.
  final double? appMarkupPct;

  /// `restaurants.pausa_ate` (04/10/2026) — o parceiro carregou em "pausa"
  /// (muito movimento, falta de stock…). Até esta hora a loja aparece como
  /// "Fechada temporariamente — volta às HH:MM" e não se mete no carrinho.
  /// Campo opcional: sem a coluna (ou a null) a loja segue o horário normal.
  final DateTime? pausaAte;

  /// True enquanto a pausa do parceiro estiver a correr.
  bool emPausa([DateTime? nowOverride]) {
    final ate = pausaAte;
    if (ate == null) return false;
    return ate.isAfter(nowOverride ?? DateTime.now());
  }

  /// "HH:MM" (hora de Lisboa) do fim da pausa.
  String get pausaVoltaAs {
    final ate = pausaAte;
    if (ate == null) return '';
    final l = horaLisboa(ate);
    String dd(int n) => n.toString().padLeft(2, '0');
    return '${dd(l.hour)}:${dd(l.minute)}';
  }

  /// Lê `pausa_ate` de forma tolerante (coluna pode ainda não existir).
  static DateTime? parsePausaAte(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  /// Texto a mostrar no banner "Em breve" (com fallback).
  String get comingSoonLabel {
    final t = comingSoonText?.trim();
    return (t == null || t.isEmpty) ? 'Em breve' : t;
  }

  /// True quando o negócio pertence à secção [section] — pela sua categoria
  /// principal OU por [extraCategories].
  bool belongsTo(BusinessCategory section) =>
      category == section || extraCategories.contains(section);

  /// True quando faz sentido mostrar o selo "Frescura garantida".
  ///
  /// Só onde há comida fresca: Restaurantes, Supermercados e Sobremesas. Numa
  /// farmácia, numa loja de electrónica ou numa loja de festas por encomenda o
  /// selo é uma promessa falsa.
  ///
  /// O selo era mostrado **sem condição nenhuma** em `MarketStoreTab`: a Wells
  /// (farmácia) e a Worten (electrónica) apareciam a prometer frescura.
  /// Apanhado a 2026-09-03, nas capturas de ecrã para o filme do Bora.
  ///
  /// Usa [belongsTo], por isso lê também `extra_categories`: a Goola Açaí
  /// (`restaurant` + `sobremesa`) e a Sabores de Casa (`restaurant` +
  /// `supermarket`) continuam a mostrá-lo.
  bool get podeAnunciarFrescura =>
      belongsTo(BusinessCategory.restaurant) ||
      belongsTo(BusinessCategory.supermarket) ||
      belongsTo(BusinessCategory.sobremesa);

  /// Hora em PT-PT: "10:00" passa a "10h00".
  static String _horaBonita(String hhmm) => hhmm.replaceFirst(':', 'h');

  /// Mensagem única mostrada ao cliente quando tenta meter no carrinho com a
  /// loja fora de horário. Diz o que se passa e a que horas abre — e mais
  /// nada: não promete agendamento nem aviso de reabertura, porque isso ainda
  /// não existe.
  String get avisoLojaFechada => avisoLojaFechadaEm(DateTime.now());

  /// O mesmo aviso para um instante concreto (o dia é o de Lisboa).
  String avisoLojaFechadaEm(DateTime instante) {
    if (emPausa(instante)) {
      return '$name está fechada temporariamente. Volta às $pausaVoltaAs.';
    }
    final day = businessHours.diaEm(paredeLisboa(instante));
    final prox = proximaAbertura(instante);
    if (day.closed) {
      if (prox == null) {
        return '$name está fechada hoje. Volta noutro dia para fazer o pedido.';
      }
      return '$name está fechada hoje. Abre ${_abreQuando(prox)}.';
    }
    if (prox == null) return '$name está fechada agora.';
    return '$name está fechada agora. Abre ${_abreQuando(prox)}.';
  }

  static const _nomesDias = [
    'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo',
  ];

  /// "às 19h00" (hoje), "amanhã às 12h00" ou "segunda às 19h00" — as mesmas
  /// palavras do `opens_dia` do servidor.
  static String _abreQuando(({int emDias, int weekday, String hora}) p) {
    final h = _horaBonita(p.hora);
    if (p.emDias == 0) return 'às $h';
    if (p.emDias == 1) return 'amanhã às $h';
    return '${_nomesDias[p.weekday - 1]} às $h';
  }

  /// Próxima abertura da loja a partir de [instante] (relógio de Lisboa),
  /// pela mesma regra do `is_partner_open` do servidor: hoje mais tarde
  /// (antes de abrir, ou no fim da pausa) ou o primeiro dia aberto dos 7
  /// seguintes. [emDias] 0 = hoje, 1 = amanhã; [weekday] como `DateTime`;
  /// [hora] 'HH:MM'. Null quando nenhum dia abre. Respeita os dias especiais
  /// (`special_dates`), como o servidor; não olha à pausa do parceiro
  /// (`pausa_ate`).
  ({int emDias, int weekday, String hora})? proximaAbertura(DateTime instante) {
    final agora = paredeLisboa(instante);
    final agoraMin = agora.hour * 60 + agora.minute;
    for (var i = 0; i <= 7; i++) {
      final data = DateTime.utc(agora.year, agora.month, agora.day + i);
      final weekday = data.weekday;
      final d = businessHours.diaEm(data);
      if (d.closed) continue;
      final o = _parseMinutes(d.open);
      if (o == null) continue;
      if (i > 0) return (emDias: i, weekday: weekday, hora: d.open);
      if (agoraMin < o) return (emDias: 0, weekday: weekday, hora: d.open);
      final bs = _minutosOuNull(d.breakStart);
      final be = _minutosOuNull(d.breakEnd);
      if (bs != null && be != null && bs < be &&
          agoraMin >= bs && agoraMin < be) {
        return (emDias: 0, weekday: weekday, hora: d.breakEnd!);
      }
    }
    return null;
  }

  /// Converte o array `extra_categories` do Supabase em categorias válidas
  /// (valores desconhecidos são ignorados; a categoria principal nunca duplica).
  static Set<BusinessCategory> parseExtraCategories(
    dynamic raw,
    BusinessCategory mainCategory,
  ) {
    if (raw is! List) return const <BusinessCategory>{};
    final result = <BusinessCategory>{};
    for (final item in raw) {
      final name = item?.toString().trim();
      if (name == null || name.isEmpty) continue;
      for (final value in BusinessCategory.values) {
        if (value.name == name && value != mainCategory) result.add(value);
      }
    }
    return result;
  }

  /// Returns a [LatLng] when both coordinates are stored; null otherwise.
  LatLng? get location =>
      (lat != null && lng != null) ? LatLng(lat!, lng!) : null;

  /// True when the partner is online AND current time is within today's window.
  ///
  /// Hora de LISBOA, nunca a do telemóvel (06/10/2026): a Bora só opera em
  /// Portugal e o servidor (`is_partner_open`, travão `STORE_CLOSED`) decide
  /// pela hora de Lisboa. Pelo relógio do aparelho (emulador do CI em UTC,
  /// turista, relógio mal acertado) a app e o servidor divergiam uma hora.
  /// [nowOverride] é um instante; o dia e a hora tiram-se dele em Lisboa
  /// (por [paredeLisboa], que não cai nos buracos da mudança de hora do fuso
  /// do telemóvel).
  bool isOpenNow([DateTime? nowOverride]) {
    if (!isOnline) return false;
    final instante = nowOverride ?? DateTime.now();
    if (emPausa(instante)) return false;
    final now = paredeLisboa(instante);
    final day = businessHours.diaEm(now);
    if (day.closed) return false;
    final openMin = _parseMinutes(day.open);
    final closeMin = _parseMinutes(day.close);
    final nowMin = now.hour * 60 + now.minute;
    if (openMin == null || closeMin == null) return true;
    final dentroDoHorario = closeMin <= openMin
        // Overnight schedule (e.g. 20:00 → 02:00): open window spans midnight.
        ? nowMin >= openMin || nowMin < closeMin
        : nowMin >= openMin && nowMin < closeMin;
    if (!dentroDoHorario) return false;
    // Pausa do dia (27/10/2026): fechada de break_start (inclusive) a
    // break_end (exclusive), como o `is_partner_open`.
    final bs = _minutosOuNull(day.breakStart);
    final be = _minutosOuNull(day.breakEnd);
    if (bs != null && be != null && bs < be && nowMin >= bs && nowMin < be) {
      return false;
    }
    return true;
  }

  /// Human-readable label for the client UI.
  String statusLabel([DateTime? nowOverride]) {
    if (!isOnline) return 'Indisponível';
    if (emPausa(nowOverride)) {
      return 'Fechada temporariamente — volta às $pausaVoltaAs';
    }
    // Casas de festa vendem por encomenda com aviso prévio: nunca estão
    // "fechadas" para encomendar — o horário é de levantamento/entrega.
    if (belongsTo(BusinessCategory.festas)) return 'Aceita encomendas';
    final instante = nowOverride ?? DateTime.now();
    final day = businessHours.diaEm(paredeLisboa(instante));
    // Diz a próxima abertura com o dia, como o `opens_dia` do servidor:
    // "Fechada, abre às 19h00" (pausa ou antes de abrir), "Fechada, abre
    // amanhã às 12h00" (depois do fecho), "Fechada hoje — abre segunda às
    // 19h00" (dia fechado).
    if (day.closed) {
      final prox = proximaAbertura(instante);
      return prox == null
          ? 'Fechada hoje'
          : 'Fechada hoje — abre ${_abreQuando(prox)}';
    }
    if (isOpenNow(instante)) return 'Aberto';
    final prox = proximaAbertura(instante);
    return prox == null ? 'Fechada' : 'Fechada, abre ${_abreQuando(prox)}';
  }

  static int? _parseMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  static int? _minutosOuNull(String? hhmm) =>
      hhmm == null ? null : _parseMinutes(hhmm);

  /// ⚠️ Campo novo no modelo entra TAMBÉM aqui, senão desaparece em silêncio
  /// a cada `copyWith`. Já aconteceu com o `ownerId`, que é justamente o que
  /// liga a loja ao dono — perdê-lo devolve o parceiro ao assistente de criar
  /// conta. Ver `partner_entry_screen.dart`.
  RestaurantModel copyWith({
    String? name,
    String? phone,
    String? address,
    BusinessCategory? category,
    bool? isOnline,
    double? lat,
    double? lng,
    bool? reservationsEnabled,
    bool? takeawayEnabled,
    bool? curbsideEnabled,
    int? takeawayDefaultPrepMinutes,
    BusinessHours? businessHours,
    double? avgRating,
    int? ratingsCount,
    String? heroImageUrl,
    bool? comingSoon,
    String? comingSoonText,
    DateTime? pausaAte,
  }) {
    return RestaurantModel(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      email: email,
      photoUrl: photoUrl,
      cuisineType: cuisineType,
      isPartner: isPartner,
      category: category ?? this.category,
      extraCategories: extraCategories,
      isOnline: isOnline ?? this.isOnline,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      reservationsEnabled: reservationsEnabled ?? this.reservationsEnabled,
      takeawayEnabled: takeawayEnabled ?? this.takeawayEnabled,
      curbsideEnabled: curbsideEnabled ?? this.curbsideEnabled,
      takeawayDefaultPrepMinutes:
          takeawayDefaultPrepMinutes ?? this.takeawayDefaultPrepMinutes,
      businessHours: businessHours ?? this.businessHours,
      avgRating: avgRating ?? this.avgRating,
      ratingsCount: ratingsCount ?? this.ratingsCount,
      heroImageUrl: heroImageUrl ?? this.heroImageUrl,
      comingSoon: comingSoon ?? this.comingSoon,
      comingSoonText: comingSoonText ?? this.comingSoonText,
      ownerId: ownerId,
      appMarkupPct: appMarkupPct,
      pausaAte: pausaAte ?? this.pausaAte,
    );
  }
}
