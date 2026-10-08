// Favores (08/10/2026, pedido real 74dd4ecc da Cristina) — a rota do estafeta
// num favor, num sítio só: quais são os passos (casa da cliente → local do
// favor → entrega), em qual está agora, o nome e a morada de cada um.
//
// Regras:
//  - O passo 1 (casa da cliente) existe SEMPRE que `errandHomeStop` = true.
//    Morada: `errandHomeStopAddress`; se vier vazia, a morada de entrega
//    (a app defende-se sozinha, não depende só do gatilho do servidor).
//  - Num favor nunca se mostra `pickupAddress`: é texto que a app da cliente
//    pode ter herdado de outro carrinho ("Rua do Ferrinho").
//  - O passo atual vem do servidor (`orders.errand_passo`, gatilho
//    `trg_orders_errand_passo`); em pedidos antigos deduz-se pelo estado, com
//    a mesma regra do gatilho.
import 'package:latlong2/latlong.dart';

import '../models/order_model.dart';

enum FavorPassoTipo { casa, favor, entrega }

class FavorPasso {
  const FavorPasso({
    required this.tipo,
    required this.numero,
    required this.nome,
    required this.rotuloCurto,
    required this.morada,
    this.coords,
  });

  final FavorPassoTipo tipo;

  /// Número que o estafeta lê (1, 2, 3).
  final int numero;

  /// Nome grande do sítio: "Casa da cliente — Cristina", "Farmácia Tavares",
  /// "Entrega à cliente — Cristina".
  final String nome;

  /// Nome curto para o resumo da rota ("Casa da cliente → Farmácia Tavares").
  final String rotuloCurto;

  /// Morada completa ('' quando não se sabe).
  final String morada;

  /// Coordenadas para o mapa e para o "Navegar" (null quando não há).
  final LatLng? coords;
}

class FavorRota {
  const FavorRota._(this.passos, this.indiceAtual);

  final List<FavorPasso> passos;

  /// Índice em [passos] do passo em que o estafeta está.
  final int indiceAtual;

  FavorPasso get atual => passos[indiceAtual];

  /// Passos que ainda faltam, a começar pelo atual.
  List<FavorPasso> get restantes => passos.sublist(indiceAtual);

  bool get naEntrega => atual.tipo == FavorPassoTipo.entrega;

  /// "Casa da cliente → Farmácia Tavares → Casa da cliente".
  String get resumo => passos.map((p) => p.rotuloCurto).join(' → ');

  /// A rota de um favor, ou null se o pedido não for favor.
  static FavorRota? de(OrderModel o) {
    if (o.serviceType != OrderServiceType.errand) return null;

    final cliente = primeiroNome(o.customerName);
    final comNome = cliente == null ? '' : ' — $cliente';
    final entregaMorada = _primeiroTexto([o.dropoffAddress, o.dropoffStreet]);
    final entregaCoords = o.destination;

    final passos = <FavorPasso>[];
    LatLng? casaCoords;
    if (o.errandHomeStop) {
      casaCoords = (o.errandHomeStopLat != null && o.errandHomeStopLng != null)
          ? LatLng(o.errandHomeStopLat!, o.errandHomeStopLng!)
          : entregaCoords;
      passos.add(FavorPasso(
        tipo: FavorPassoTipo.casa,
        numero: passos.length + 1,
        nome: 'Casa da cliente$comNome',
        rotuloCurto: 'Casa da cliente',
        morada: _primeiroTexto([o.errandHomeStopAddress, entregaMorada]),
        coords: casaCoords,
      ));
    }

    final local = (o.errandLocation ?? '').trim();
    passos.add(FavorPasso(
      tipo: FavorPassoTipo.favor,
      numero: passos.length + 1,
      nome: nomeDoLocal(local) ?? 'Local do favor',
      rotuloCurto: nomeDoLocal(local) ?? 'Local do favor',
      morada: local,
      coords: (o.errandLocationLat != null && o.errandLocationLng != null)
          ? LatLng(o.errandLocationLat!, o.errandLocationLng!)
          : null,
    ));

    final voltaACasa = o.errandHomeStop &&
        _mesmoSitio(casaCoords, entregaCoords,
            passos.first.morada, entregaMorada);
    passos.add(FavorPasso(
      tipo: FavorPassoTipo.entrega,
      numero: passos.length + 1,
      nome: 'Entrega à cliente$comNome',
      rotuloCurto: voltaACasa ? 'Casa da cliente' : 'Entrega à cliente',
      morada: entregaMorada,
      coords: entregaCoords,
    ));

    final tipoAtual = tipoDoPasso(passoAtual(o));
    var i = passos.indexWhere((p) => p.tipo == tipoAtual);
    if (i < 0) i = 0; // passo 0 sem paragem em casa → o primeiro que existe
    return FavorRota._(passos, i);
  }
}

/// 0 = casa da cliente, 1 = tratar do favor, 2 = entrega.
/// Do servidor quando existe; senão a mesma regra do gatilho
/// `fn_orders_errand_passo`.
int passoAtual(OrderModel o) {
  var p = o.errandPasso ?? _deduzirPasso(o);
  if (p == 0 && !o.errandHomeStop) p = 1;
  return p.clamp(0, 2);
}

int _deduzirPasso(OrderModel o) {
  switch (o.status) {
    case OrderStatus.pickedUp:
    case OrderStatus.onTheWay:
      // Com compra: até fechar o talão está no favor. Sem compra e com
      // paragem em casa, a folha vai da recolha direta à entrega sem estado
      // intermédio — fica no favor para o mapa e o "Navegar" passarem por lá.
      if (o.errandHasPurchase) return o.isPurchaseFinalized ? 2 : 1;
      return o.errandHomeStop ? 1 : 2;
    case OrderStatus.delivered:
      return 2;
    default:
      if (o.isPurchaseFinalized) return 2;
      return o.errandHomeStop ? 0 : 1;
  }
}

/// O que fazer ao dinheiro na entrega do favor — a MESMA conta da folha do
/// favor (`_deliveryAmount` em errand_execution_sheet.dart):
///  - pago na app → null (nada a cobrar);
///  - paragem em casa para levantar dinheiro → devolve o troco (recebido −
///    talão − taxa) ou cobra o que faltar;
///  - dinheiro normal → cobra `totalToCollectCash` (final_total depois do
///    talão). Revisão de 08/10: a faixa e o cartão diziam "cobrar" o total
///    quando o estafeta já tinha o dinheiro e tinha de devolver o troco.
({String rotulo, double valor, bool devolver})? contaDaEntregaFavor(
    OrderModel o) {
  if (o.paymentMethod != PaymentMethod.cash) return null;
  if (o.errandHomeStop && o.errandHomeStopReason == 'dinheiro') {
    final recebido = (o.errandHomeStopCashCents ?? 0) / 100.0;
    final talao = o.finalPurchaseValue ?? 0;
    final liquido = recebido - talao - o.deliveryFee;
    return liquido >= 0
        ? (rotulo: 'Devolver à cliente', valor: liquido, devolver: true)
        : (rotulo: 'Cobrar à cliente', valor: -liquido, devolver: false);
  }
  return (rotulo: 'Cobrar à cliente', valor: o.totalToCollectCash, devolver: false);
}

/// Favor em que o estafeta leva o dinheiro da cliente de casa (troco na
/// entrega) — a faixa "RECEBER €X" não se aplica.
bool favorComDinheiroDeCasa(OrderModel o) =>
    o.serviceType == OrderServiceType.errand &&
    o.errandHomeStop &&
    o.errandHomeStopReason == 'dinheiro';

FavorPassoTipo tipoDoPasso(int passo) => switch (passo) {
      0 => FavorPassoTipo.casa,
      1 => FavorPassoTipo.favor,
      _ => FavorPassoTipo.entrega,
    };

final RegExp _reFarmacia = RegExp(
    r'farm[aá]cia|medicament|rem[eé]dio|receita|\bsns\b',
    caseSensitive: false);

/// Texto (descrição ou local) que cheira a farmácia/medicamento/receita.
bool textoPareceFarmacia(String? texto) =>
    texto != null && _reFarmacia.hasMatch(texto);

/// O favor é numa farmácia ou é de medicamentos.
bool favorEhFarmacia(OrderModel o) =>
    o.serviceType == OrderServiceType.errand &&
    (textoPareceFarmacia(o.errandDescription) ||
        textoPareceFarmacia(o.errandLocation));

/// Motivo da paragem em casa, em PT-PT, para o estafeta.
String motivoParagemEmCasa(String? motivo) => switch (motivo) {
      'receita' => 'Buscar a receita médica',
      'cartao' => 'Buscar o cartão',
      'dinheiro' => 'Buscar o dinheiro da compra',
      _ => 'Outro motivo — vê a descrição do favor',
    };

/// "Farmácia Tavares, Avenida Cidade de Safed, Guarda" → "Farmácia Tavares".
String? nomeDoLocal(String? local) {
  final t = (local ?? '').trim();
  if (t.isEmpty) return null;
  final primeiro = t.split(',').first.trim();
  return primeiro.isEmpty ? t : primeiro;
}

/// "Cristina Silva" → "Cristina".
String? primeiroNome(String? nome) {
  final t = (nome ?? '').trim();
  if (t.isEmpty) return null;
  return t.split(RegExp(r'\s+')).first;
}

/// Distância em linha recta do estafeta ao passo, em km.
double? distanciaKm(LatLng? de, LatLng? para) {
  if (de == null || para == null) return null;
  return const Distance().as(LengthUnit.Meter, de, para) / 1000.0;
}

/// "350 m" / "2,4 km".
String distanciaTexto(double km) {
  if (km < 1) return '${(km * 1000).round()} m';
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
}

String _primeiroTexto(List<String?> opcoes) {
  for (final o in opcoes) {
    final t = (o ?? '').trim();
    if (t.isNotEmpty) return t;
  }
  return '';
}

bool _mesmoSitio(LatLng? a, LatLng? b, String moradaA, String moradaB) {
  if (a != null && b != null) {
    return const Distance().as(LengthUnit.Meter, a, b) < 80;
  }
  return moradaA.isNotEmpty && moradaA == moradaB;
}
