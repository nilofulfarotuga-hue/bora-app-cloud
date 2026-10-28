import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Dados fiscais do parceiro (DAC7, Lei n.º 36/2023) — funções puras.
///
/// Missão boom-burger-2026-10-27, F3. O servidor diz o que falta com os
/// códigos de `_conformidade_em_falta` (migração
/// `20261027160958_conformidade_data_nascimento_so_pessoa_singular_2026_10_27`):
/// 'nome', 'nif', 'morada', 'iban', 'data_nascimento' (só pessoa singular) e
/// 'autocertificacao'. Chegam em `parceiro_dados_fiscais().em_falta`, na
/// resposta de `admin_parceiro_atualizar_dados_fiscais` e no erro do portão
/// `conformidade_incompleta: faltam nif, iban` quando se tira o "Em breve" a
/// uma loja parceira sem os dados.

/// Os seis códigos, pela ordem do formulário.
const List<String> kCodigosEmFalta = [
  'nome',
  'nif',
  'morada',
  'iban',
  'data_nascimento',
  'autocertificacao',
];

/// Rótulo de um código de `em_falta` (igual em PT-PT e PT-BR). Um código
/// desconhecido volta tal e qual, para não esconder nada.
String rotuloEmFalta(String codigo) => switch (codigo.trim()) {
      'nome' => 'Nome legal',
      'nif' => 'NIF',
      'morada' => 'Morada',
      'iban' => 'IBAN',
      'data_nascimento' => 'Data de nascimento',
      'autocertificacao' => 'Autocertificação',
      final outro => outro,
    };

/// Lê a lista `em_falta` que vem do servidor (lista de texto, ou nada) e
/// devolve os códigos limpos, sem vazios nem repetidos, pela ordem recebida.
List<String> codigosEmFalta(Object? emFalta) {
  if (emFalta is! List) return const [];
  final vistos = <String>{};
  return [
    for (final e in emFalta)
      if (e != null && e.toString().trim().isNotEmpty && vistos.add(e.toString().trim()))
        e.toString().trim(),
  ];
}

/// Os rótulos de uma lista `em_falta`.
List<String> rotulosEmFalta(Object? emFalta) =>
    codigosEmFalta(emFalta).map(rotuloEmFalta).toList();

/// Os códigos que vêm depois de "faltam" no texto do erro do portão.
/// Só a lista: pára no primeiro ponto, parêntese, dois pontos ou quebra de
/// linha, e só aceita palavras em minúsculas com `_` — o resto (HINT, código
/// do erro) fica de fora. Quando o corte é nuns dois pontos, a palavra antes
/// deles é um rótulo colado (`, code: P0001`) e também sai.
List<String> codigosDoErroConformidade(String texto) {
  final i = texto.indexOf('faltam');
  if (i < 0) return const [];
  final depois = texto.substring(i + 'faltam'.length);
  final corte = RegExp(r'[.(:\n]').firstMatch(depois);
  final partes =
      (corte == null ? depois : depois.substring(0, corte.start)).split(',');
  if (corte != null && corte.group(0) == ':' && partes.length > 1) {
    partes.removeLast();
  }
  final vistos = <String>{};
  return partes
      .map((e) => e.trim())
      .where((e) => RegExp(r'^[a-z_]+$').hasMatch(e) && vistos.add(e))
      .toList();
}

/// Painel admin (PT-BR): a frase a mostrar quando o servidor recusa abrir a
/// loja ao público (tirar o "Em breve") por faltarem dados fiscais. Devolve
/// null quando o erro é outro — o chamador mostra então o erro de sempre.
String? mensagemAbrirLojaConformidade(Object? erro) {
  if (erro == null) return null;
  final texto = erro is PostgrestException ? erro.message : erro.toString();
  if (!texto.contains('conformidade_incompleta')) return null;
  final rotulos = codigosDoErroConformidade(texto).map(rotuloEmFalta).toList();
  const comoResolver =
      'Complete no cartão "Dados fiscais (DAC7)" da ficha do parceiro.';
  if (rotulos.isEmpty) {
    return 'Não dá para abrir a loja ao público: faltam dados fiscais. '
        '$comoResolver';
  }
  return 'Não dá para abrir a loja ao público: faltam ${rotulos.join(', ')}. '
      '$comoResolver';
}

/// Painel admin (PT-BR): erros de `admin_parceiro_atualizar_dados_fiscais`.
String mensagemErroDadosFiscaisAdmin(Object erro) {
  final texto = erro is PostgrestException ? erro.message : erro.toString();
  if (texto.contains('admin_required')) {
    return 'Sem permissão de admin para esta ação.';
  }
  if (texto.contains('nif_invalido')) {
    return 'O servidor recusou o NIF: tem de ter 9 dígitos.';
  }
  if (texto.contains('iban_invalido')) {
    return 'O servidor recusou o IBAN: PT seguido de 23 dígitos.';
  }
  if (texto.contains('menor_de_idade')) {
    return 'A data de nascimento é de alguém com menos de 18 anos.';
  }
  if (texto.contains('autocertificacao_no_futuro')) {
    return 'A data da autocertificação não pode ser no futuro.';
  }
  if (texto.contains('loja_nao_encontrada')) {
    return 'Loja não encontrada. Atualize a ficha.';
  }
  return 'Não foi possível salvar os dados fiscais: $texto';
}
