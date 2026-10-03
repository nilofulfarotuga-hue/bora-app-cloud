/// AS ACTIVIDADES DE QUEM TRABALHA NO BORA — e a regra de que elas se somam.
///
/// Porque existe este ficheiro: até 2026-08-28 os papéis viviam aos pares.
/// O `RolesService` só sabia de estafeta ⇄ limpeza, o `role_screen` só tinha
/// três portas (cliente, estafeta, parceiro) e a lavagem de carros não tinha
/// porta nenhuma — a tabela `washers` existia sem forma de alguém se
/// candidatar. Cada actividade nova obrigava a mexer em tudo outra vez.
///
/// A regra do Danilo é simples e é esta: **a mesma pessoa pode ser estafeta,
/// motorista, faxineiro e lavador ao mesmo tempo. Os papéis acumulam-se, nunca
/// se substituem.** Quem já é motorista acrescenta lavagem sem criar conta
/// nova e sem repetir dados.
///
/// A lógica fica aqui, fora de qualquer ecrã, para poder ser testada sem
/// Flutter nem Supabase.
library;

/// Uma actividade que se pode exercer no Bora.
///
/// O `slug` é o nome do papel tal como vive na base: em `user_roles.role`, em
/// `push_tokens.role` e no nome da tabela do papel. Não renomear — está
/// gravado em dados reais.
enum Atividade {
  entregas('driver', 'Entregas', 'Levar comida e compras a casa das pessoas'),
  viagens('driver', 'Viagens', 'Levar pessoas de um lado ao outro (TVDE)'),
  limpeza('cleaner', 'Limpeza', 'Limpar casas e escritórios'),
  lavagem('washer', 'Lavagem de carros', 'Lavar carros onde o cliente estiver');

  const Atividade(this.slug, this.titulo, this.descricao);

  /// Papel na base de dados. Repare que `entregas` e `viagens` partilham o
  /// mesmo papel `driver`: por dentro é a mesma pessoa e a mesma tabela, o que
  /// muda é o tipo de veículo e o ecrã onde ela trabalha. Separam-se aqui
  /// porque, para quem se candidata, "levar comida" e "levar pessoas" são
  /// coisas diferentes — e obrigá-lo a perceber que é "a mesma" era exactamente
  /// uma das coisas que tornava o cadastro confuso.
  final String slug;
  final String titulo;
  final String descricao;
}

/// Os papéis de base que estas actividades exigem, sem repetições.
///
/// Escolher Entregas e Viagens ao mesmo tempo dá **um** papel `driver`, não
/// dois — senão criavam-se duas linhas iguais em `user_roles` e a candidatura
/// era submetida a dobrar.
Set<String> papeisPara(Iterable<Atividade> escolhidas) =>
    escolhidas.map((a) => a.slug).toSet();

/// O que falta a esta pessoa, dadas as actividades que escolheu e os papéis
/// que já tem.
///
/// É isto que evita mandar alguém preencher outra vez o que já deu: quem já é
/// `driver` aprovado e escolhe Lavagem só tem de tratar do `washer`.
Set<String> papeisEmFalta(
  Iterable<Atividade> escolhidas,
  Iterable<String> papeisQueJaTem,
) =>
    papeisPara(escolhidas).difference(papeisQueJaTem.toSet());

/// Esta escolha é submissível?
///
/// Tem de haver pelo menos uma actividade, e pelo menos um papel novo — se a
/// pessoa só escolheu o que já tem, não há candidatura a fazer, há um atalho
/// para o ecrã de trabalho dela.
bool escolhaValida(
  Iterable<Atividade> escolhidas,
  Iterable<String> papeisQueJaTem,
) =>
    escolhidas.isNotEmpty && papeisEmFalta(escolhidas, papeisQueJaTem).isNotEmpty;

/// Frase que se mostra a quem escolheu só actividades que já exerce.
String? avisoJaTemTudo(
  Iterable<Atividade> escolhidas,
  Iterable<String> papeisQueJaTem,
) {
  if (escolhidas.isEmpty) return null;
  if (papeisEmFalta(escolhidas, papeisQueJaTem).isNotEmpty) return null;
  return escolhidas.length == 1
      ? 'Já trabalha em ${escolhidas.first.titulo.toLowerCase()}. '
          'Vá ao seu perfil para abrir esse ecrã.'
      : 'Já trabalha em todas estas actividades. '
          'Vá ao seu perfil para abrir o ecrã de cada uma.';
}
