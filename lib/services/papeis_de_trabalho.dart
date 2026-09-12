/// A CAIXA "O QUE QUERES ACEITAR?" — construída dos papéis REAIS da pessoa.
///
/// Antes era um rádio de duas opções fixas: só corridas, ou corridas mais
/// entregas. Quem acumulava quatro papéis via duas linhas e não tinha onde
/// ligar a limpeza nem a lavagem de carros — a categoria estava no ar e o
/// prestador não a via em lado nenhum.
///
/// Agora a caixa vem de `user_roles`: quem tem dois papéis vê dois, quem tem
/// quatro vê quatro. Cada um é um interruptor independente, e a escolha fica
/// no servidor, por isso sobrevive a fechar a app e acompanha a pessoa se ela
/// trocar de telemóvel.
///
/// As entregas são trabalho PRÓPRIO desde 2026-08-28, não um modo do papel de
/// motorista. Quem anda de bicicleta ou mota a entregar não é motorista de
/// TVDE — o TVDE exige certificado do IMT e levar comida não exige. Antes
/// disto, quem só queria entregar tinha de se inscrever como motorista.
/// `drivers.work_mode` continua a existir mas é PROJECÇÃO desta preferência,
/// mantida por gatilho: só há um sítio onde se escreve.
library;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


/// Um papel de trabalho com o seu interruptor.
@immutable
class PapelDeTrabalho {
  const PapelDeTrabalho({
    required this.papel,
    required this.aceita,
  });

  /// Nome do papel tal como vive em `user_roles.role`. Não renomear.
  final String papel;

  /// A pessoa quer receber pedidos deste papel hoje.
  final bool aceita;

  /// Como se chama isto a quem está a ler, em português de Portugal.
  String get titulo => switch (papel) {
        'driver' => 'Corridas de passageiros',
        'delivery' => 'Entregas',
        'cleaner' => 'Limpeza',
        'washer' => 'Lavagem de carros',
        // NUNCA devolver o nome técnico. Foi assim que apareceu "delivery",
        // em inglês e minúsculas, no ecrã do Danilo a 2026-08-28: o papel
        // entrou na base antes de alguém lhe dar nome. Um papel novo sem
        // tradução mostra isto e o teste rebenta — que é o que se quer.
        _ => 'Outro trabalho',
      };

  String get descricao => switch (papel) {
        'driver' => 'Levar pessoas de um lado ao outro.',
        'delivery' => 'Levar comida, compras e encomendas.',
        'cleaner' => 'Limpezas de casas e escritórios.',
        'washer' => 'Lavagens de carro onde o cliente estiver.',
        _ => '',
      };

  /// Este papel tem nome de gente, ou caiu no recurso?
  ///
  /// Serve o teste que impede um papel novo de chegar ao ecrã sem tradução.
  bool get temNomeProprio => titulo != 'Outro trabalho' && descricao.isNotEmpty;

  /// Todos os papéis de trabalho que a base pode devolver. Papel novo entra
  /// aqui E nas duas traduções acima, ou o teste apanha.
  static const List<String> conhecidos = ['driver', 'delivery', 'cleaner', 'washer'];

  PapelDeTrabalho copyWith({bool? aceita}) =>
      PapelDeTrabalho(papel: papel, aceita: aceita ?? this.aceita);

  @override
  bool operator ==(Object other) =>
      other is PapelDeTrabalho && other.papel == papel && other.aceita == aceita;

  @override
  int get hashCode => Object.hash(papel, aceita);
}

/// A caixa só aparece a quem tem mais do que um papel.
///
/// Quem só é motorista não tem escolha nenhuma a fazer — mostrar-lhe uma caixa
/// com uma linha só é estorvo. Foi pedido assim.
bool mostrarCaixaDePapeis(List<PapelDeTrabalho> papeis) => papeis.length > 1;

/// Desligar o ÚLTIMO papel ligado deixaria a pessoa online sem receber nada —
/// e isso lê-se como avaria, não como escolha. Quem quer parar de todo desliga
/// o "estou online", que é o interruptor que existe para isso.
///
/// Ligar é sempre permitido; esta pergunta só se faz ao desligar.
bool podeDesligar(List<PapelDeTrabalho> papeis) =>
    papeis.where((p) => p.aceita).length > 1;

/// Aviso a mostrar a quem tenta desligar o último.
const String avisoUltimoPapel =
    'Este é o único que tem ligado. Para não receber nada, '
    'desligue o "estou online".';

class PapeisDeTrabalhoService {
  const PapeisDeTrabalhoService._();

  /// Lê os papéis da pessoa e o estado de cada interruptor.
  ///
  /// Devolve lista vazia se algo correr mal — e nesse caso a caixa não
  /// aparece, que é melhor do que aparecer meia.
  static Future<List<PapelDeTrabalho>> meus() async {
    try {
      final res = await Supabase.instance.client
          .rpc('meus_papeis_e_preferencias');
      if (res is! List) return const <PapelDeTrabalho>[];
      return res
          .whereType<Map>()
          .map((m) => PapelDeTrabalho(
                papel: (m['papel'] ?? '').toString(),
                aceita: m['aceita'] != false,
              ))
          .where((p) => p.papel.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[PapeisDeTrabalho] meus() falhou: $e');
      return const <PapelDeTrabalho>[];
    }
  }

  /// Liga ou desliga um papel. Devolve se ficou gravado.
  static Future<bool> definir(String papel, bool aceita) async {
    try {
      await Supabase.instance.client.rpc(
        'definir_preferencia_papel',
        params: {'p_papel': papel, 'p_aceita': aceita},
      );
      return true;
    } catch (e) {
      debugPrint('[PapeisDeTrabalho] definir($papel, $aceita) falhou: $e');
      return false;
    }
  }
}
