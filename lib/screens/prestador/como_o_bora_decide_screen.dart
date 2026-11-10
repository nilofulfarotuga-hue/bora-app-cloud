import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/tvde_visibilidade.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// "Como o Bora decide" — informação sobre os sistemas automáticos da app
/// para quem trabalha com a Bora (Diretiva (UE) 2024/2831, art. 7.º a 11.º).
///
/// Missão app-fechar-2026-11-01, bloco B8. O texto é o de
/// `docs/legal/gestao-algoritmica-prestadores.md` (versão 2026-11-01), em
/// PT-PT. Quando o documento mudar, muda-se aqui também (e a versão).
/// Sem `.tr` de propósito: é texto legal, como o resto de "Sobre / Informação
/// legal" (`LegalInfoScreen`).
class ComoOBoraDecide {
  const ComoOBoraDecide._();

  static const String titulo =
      'Como o Bora decide — informação sobre sistemas automáticos';

  static const String versao = 'Versão em vigor desde 10 de novembro de 2026.';

  /// Identificador da versão gravado em `prestador_avisos_lidos.versao` quando
  /// o prestador carrega em "Li e percebi" (missão fechar-tudo-2026-11-10, E4).
  /// MUDA-SE SEMPRE que o texto mudar: cada prestador volta a ver o ecrã uma
  /// vez, como manda a Diretiva (UE) 2024/2831, art. 9.º ("sempre que mudar").
  /// 2026-11-10: junta o resumo da política de suspensão e revisão humana.
  static const String versaoId = '2026-11-10';

  /// Nome do aviso em `prestador_avisos_lidos.aviso`.
  static const String aviso = 'como_o_bora_decide';

  /// M10 2.11 (09/11/2026): parágrafo só dos motoristas TVDE. Com o Bora
  /// Motorista fechado (`tvde_app_visivel` = false) não se mostra — não há
  /// motoristas de passageiros a trabalhar. O texto legal fica igual.
  static bool soBoraMotorista(String paragrafo) =>
      paragrafo.contains('(motoristas TVDE)');

  static const String introducao =
      'Para estafetas, profissionais de limpeza, lavadores, profissionais de '
      'casa e lojas parceiras. Base legal: Diretiva (UE) 2024/2831, artigos '
      '7.º a 11.º (gestão algorítmica), e Código do Trabalho, artigos 24.º/3 e '
      '106.º/3 s). Escrito em linguagem simples, como a lei manda. Este texto '
      'fica na app (Sobre / Informação legal) e é entregue a cada prestador no '
      'primeiro dia e sempre que mudar.';

  /// (título da secção, parágrafos; um parágrafo que começa por "• " é um
  /// ponto de lista).
  static const List<(String, List<String>)> seccoes = [
    (
      '1. Quem somos e como falar com uma pessoa',
      [
        'A Bora é gerida por uma sociedade unipessoal com sede na Guarda '
            '(NIPC 519686233, o mesmo dos recibos). Os dados completos estão no '
            'ecrã Sobre / Informação legal.',
        'Há sempre uma pessoa da equipa Bora para falar consigo sobre qualquer '
            'decisão da app:',
        '• WhatsApp da Bora: +351 937 501 673',
        '• Email da Bora: boraappbora@gmail.com',
        'Não precisa de falar com um robô. Quando escreve, é uma pessoa que lê '
            'e responde.',
      ],
    ),
    (
      '2. Que dados a app usa sobre si',
      [
        'Usamos só o que é preciso para o trabalho:',
        '• Posição GPS enquanto está online (para lhe dar pedidos perto de si e '
            'para o cliente ver onde está a entrega).',
        '• Sinal de "estou ligado" da app (heartbeat) e estado do botão Online.',
        '• O que aceita, recusa ou cancela, e os tempos de cada pedido (aceitou, '
            'recolheu, entregou).',
        '• Notas que os clientes lhe dão e comentários.',
        '• Documentos que envia na candidatura (identificação, atividade nas '
            'Finanças, carta e veículo quando se aplica) e as datas de validade.',
        '• Dinheiro: o que ganhou, acertos semanais, recibos, dívidas em '
            'dinheiro de entregas pagas em numerário.',
        'O que NUNCA usamos (proibido pelo artigo 7.º da Diretiva): o seu estado '
            'emocional, conversas privadas, dados fora do trabalho, origem, '
            'saúde, religião, opinião política, filiação sindical, nem '
            'reconhecimento facial. A verificação automática de documentos só '
            'confirma que o ficheiro é o documento pedido; não faz comparação de '
            'caras.',
      ],
    ),
    (
      '3. O que é automático na app',
      [
        'A app faz sozinha estas coisas. Nenhuma delas suspende ou fecha a sua '
            'conta.',
        '• Oferecer pedidos. O sistema escolhe a quem toca primeiro pela '
            'distância, por quem está online com GPS recente, pela ordem de '
            'rotação e, nas corridas, também pela nota média e taxa de '
            'aceitação. Se não responder em 40 segundos passa ao seguinte. '
            'Recusar uma oferta não dá castigo.',
        '• Tirar das ofertas quem está sem sinal. Se a app não envia GPS há mais '
            'de 15 minutos deixa de receber ofertas até o GPS voltar. Só o botão '
            'Online desliga o Online; o GPS parado não o desliga.',
        '• Não deixar ficar online sem aprovação. Enquanto a candidatura não é '
            'aprovada por uma pessoa, não dá para ficar online.',
        '• Não deixar ficar online com documento caducado (motoristas TVDE). A '
            'app recusa o botão Online e diz qual o documento. Volta a funcionar '
            'assim que carregar o documento novo. É temporário e reversível por '
            'si.',
        '• Avisos automáticos: documento a expirar, recibo do mês em falta, '
            'dívida de dinheiro pendente.',
        '• Sinais para a equipa ver. Nota média abaixo de 4 nos últimos 10 '
            'serviços (limpeza) ou abaixo de 3,5 (lavagem), muitos cancelamentos '
            'tardios, ou atrasos repetidos: a app avisa a equipa Bora. É um aviso '
            'para uma pessoa olhar; não é uma decisão.',
        '• Taxa de cancelamento ao cliente, calculada pelas regras publicadas '
            '(hora do cancelamento e se já havia prestador a caminho).',
        '• Verificação automática de documentos na candidatura (só confirma que '
            'o ficheiro é o documento pedido).',
      ],
    ),
    (
      '4. O que tem sempre uma pessoa a decidir',
      [
        'Estas decisões são sempre tomadas por uma pessoa da equipa Bora, nunca '
            'pela app sozinha (artigo 11.º, n.º 5, da Diretiva):',
        '• Aprovar ou recusar a sua candidatura.',
        '• Suspender a sua conta, por tempo limitado ou não.',
        '• Encerrar a sua conta ou terminar a parceria.',
        '• Recusar um pagamento que lhe é devido.',
        '• Mudar o que combinámos consigo (condições, comissões).',
        '• Qualquer outra decisão com efeito igual a estas.',
        'Quando uma pessoa decide suspender ou encerrar, a Bora escreve-lhe o '
            'motivo, a data, quem decidiu e até quando (se for temporário), até '
            'ao dia em que a decisão começa a valer.',
      ],
    ),
    (
      '5. Como pedir explicação ou revisão',
      [
        '• Pode pedir, a qualquer momento, uma explicação sobre qualquer decisão '
            'da app que o afete (por exemplo, porque não recebeu pedidos num '
            'dia). Responde uma pessoa.',
        '• Se não concordar com uma suspensão, um encerramento, uma recusa de '
            'pagamento ou outra decisão importante, pode pedir revisão: na app, '
            'no ecrã "A minha conta", botão "Pedir revisão", ou pelo '
            'WhatsApp/email acima.',
        '• A revisão é feita por uma pessoa (o responsável da Bora), que não é a '
            'app.',
        '• Resposta por escrito, com os motivos, no prazo máximo de 7 dias (a '
            'lei dá 14; a Bora compromete-se a 7).',
        '• Se a Bora tiver errado, corrige logo: reativa a conta, paga o que '
            'faltava ou compensa o prejuízo.',
        '• Enquanto a revisão corre, a Bora não toma outra decisão pior sobre o '
            'mesmo assunto.',
      ],
    ),
    (
      '6. O que a Bora faz do lado dela',
      [
        '• Uma pessoa revê de 2 em 2 anos, no mínimo, o efeito das regras '
            'automáticas (artigo 10.º): se tratam todos de forma igual, se os '
            'prazos e limites são justos.',
        '• Todas as suspensões e encerramentos ficam registados com motivo, data '
            'e quem decidiu, e podem ser mostrados às autoridades (ACT, CNPD) se '
            'pedirem.',
        '• Este texto é atualizado antes de qualquer mudança nas regras '
            'automáticas e a nova versão é mostrada na app.',
      ],
    ),
    (
      '7. Sobre o seu estatuto',
      [
        'Os estafetas, profissionais e lojas da Bora são independentes, com '
            'atividade aberta nas Finanças. Não há contrato de trabalho. Mesmo '
            'assim, as regras deste documento aplicam-se a si por inteiro (a '
            'Diretiva manda aplicá-las a quem trabalha em plataformas sem '
            'contrato de trabalho). Se entender que a sua relação com a Bora é, '
            'na prática, de trabalho subordinado, a lei portuguesa (artigo '
            '12.º-A do Código do Trabalho) permite-lhe pedir que isso seja '
            'reconhecido.',
      ],
    ),
  ];

  /// Título do resumo da segunda página do livro
  /// (`legal-politica-suspensao-revisao-humana`, versão 2026-11-01).
  static const String tituloSuspensoes =
      'Política de suspensão e revisão humana (resumo)';

  /// Resumo para o ecrã da política de suspensão e revisão humana (Diretiva
  /// (UE) 2024/2831, art. 10.º e 11.º; Regulamento (UE) 2019/1150 para as
  /// lojas). Missão fechar-tudo-2026-11-10, E4: fica tudo o que obriga a
  /// Bora — nenhuma suspensão automática, o que cada suspensão tem de ter,
  /// comunicação no mesmo dia, revisão por uma pessoa em 7 dias, correção
  /// quando a Bora erra, registos e revisão anual. Lista à parte de
  /// [seccoes] de propósito: as 7 secções acima são o texto da primeira
  /// página tal como está.
  static const List<(String, List<String>)> suspensoes = [
    (
      '8. Suspender uma conta: sempre uma pessoa, sempre com motivo',
      [
        'A app nunca suspende, bloqueia sem prazo nem encerra uma conta '
            'sozinha. Só uma pessoa da equipa Bora o pode fazer, e o servidor '
            'recusa qualquer suspensão sem motivo escrito e sem o nome de quem '
            'decidiu.',
        'Não são suspensões (e por isso podem ser automáticas): ficar fora das '
            'ofertas por GPS parado ou sem sinal, não poder ficar online com um '
            'documento fora de validade, ou ainda não estar aprovado. Resolve-as '
            'o próprio prestador (ligar o GPS, abrir a app, carregar o documento '
            'novo) e também pode pedir que uma pessoa as reveja.',
        'Cada suspensão fica registada antes de começar a valer, com:',
        '• quem é suspenso e o tipo (temporária com data de fim, sem data, '
            'encerramento ou restrição, por exemplo deixar de receber ofertas de '
            'um tipo de serviço);',
        '• o motivo por escrito, em português simples, com os factos (que '
            'pedido, que dia, o que aconteceu);',
        '• a data e a hora, quem decidiu (uma pessoa da equipa, nunca '
            '"sistema") e até quando, se for temporária.',
        'Recebe o motivo no mesmo dia, na app e por mensagem, até ao momento em '
            'que a decisão começa a valer.',
        'Os avisos automáticos (por exemplo, cancelamentos tardios ou nota '
            'baixa) só põem o caso numa fila para uma pessoa ver. Essa pessoa '
            'olha para o caso, fala consigo se for preciso e só depois decide.',
      ],
    ),
    (
      '9. Como pedir revisão de uma suspensão',
      [
        '• Na app, no ecrã "A minha conta foi suspensa", vê o motivo, a data, '
            'quem decidiu e até quando, e tem o botão "Pedir revisão" para '
            'escrever a sua versão. Também pode pedir pelo WhatsApp da Bora '
            '(+351 937 501 673) ou por email (boraappbora@gmail.com); a equipa '
            'regista o pedido na hora.',
        '• Pode pedir revisão quantas vezes tiver factos novos.',
        '• A revisão é feita por uma pessoa (o responsável da Bora), nunca pela '
            'app nem por um robô. Essa pessoa vê os registos (pedidos, '
            'mensagens, GPS, notas) e, se precisar, fala consigo e com o '
            'cliente.',
        '• Resposta por escrito, com os motivos, no máximo em 7 dias a contar '
            'do pedido (a lei dá 14). A resposta diz se a suspensão fica, se é '
            'reduzida ou se a conta é reativada.',
        '• Se a Bora errou: reativa a conta no mesmo dia, paga o que ficou por '
            'pagar e, se houve prejuízo claro (por exemplo, dias sem poder '
            'trabalhar por erro nosso), compensa.',
        '• A suspensão temporária acaba sozinha na data marcada. A suspensão '
            'sem data e o encerramento só são revertidos por uma pessoa, com '
            'nota escrita do porquê.',
        '• Todas as suspensões, pedidos de revisão, respostas e reativações '
            'ficam registados. Pelo menos uma vez por ano, e sempre antes de '
            'mudar regras automáticas, uma pessoa da Bora revê esses números e '
            'pode mostrá-los à ACT ou à CNPD se pedirem.',
        '• Lojas parceiras: a Bora só termina a parceria com 30 dias de aviso e '
            'as razões por escrito, salvo falta grave. Desligar uma loja da app '
            'conta como suspensão e segue estas regras.',
      ],
    ),
  ];
}

/// Ecrã com o texto inteiro de [ComoOBoraDecide].
///
/// Com [aoLer] (missão fechar-tudo-2026-11-10, E4) aparece em baixo o botão
/// "Li e percebi": é assim que o portão `ComoOBoraDecideGate` o mostra ao
/// prestador uma vez por versão. Sem [aoLer] é só leitura (Sobre /
/// Informação legal, candidaturas, conta suspensa).
class ComoOBoraDecideScreen extends StatefulWidget {
  const ComoOBoraDecideScreen({super.key, this.aoLer});

  /// Grava "Li e percebi". Se falhar (lança), o ecrã fica e diz porquê.
  final Future<void> Function()? aoLer;

  static Future<void> abrir(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ComoOBoraDecideScreen()),
      );

  static const String textoBotaoLi = 'Li e percebi';

  @override
  State<ComoOBoraDecideScreen> createState() => _ComoOBoraDecideScreenState();
}

class _ComoOBoraDecideScreenState extends State<ComoOBoraDecideScreen> {
  bool _aGravar = false;
  String? _erro;

  Future<void> _li() async {
    final aoLer = widget.aoLer;
    if (aoLer == null || _aGravar) return;
    setState(() {
      _aGravar = true;
      _erro = null;
    });
    try {
      await aoLer();
    } catch (e) {
      debugPrint('[ComoOBoraDecide] gravar leitura: $e');
      if (mounted) {
        setState(() => _erro = 'Não foi possível guardar. Verifique a ligação '
            'e tente outra vez.');
      }
    } finally {
      if (mounted) setState(() => _aGravar = false);
    }
  }

  Widget _secao(String titulo, List<String> paragrafos, TextStyle corpo) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: Spacing.xl),
          Text(
            titulo,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          for (final p in paragrafos)
            if (TvdeVisibilidade.aberto || !ComoOBoraDecide.soBoraMotorista(p))
              Padding(
                padding: EdgeInsets.only(
                  bottom: Spacing.sm,
                  left: p.startsWith('• ') ? Spacing.sm : 0,
                ),
                child: Text(p, style: corpo),
              ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    const corpo = TextStyle(
      fontSize: 14,
      color: AppColors.textPrimary,
      height: 1.45,
    );
    final comBotao = widget.aoLer != null;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Como o Bora decide'),
      bottomNavigationBar: !comBotao
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    Spacing.lg, Spacing.sm, Spacing.lg, Spacing.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_erro != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Spacing.sm),
                        child: Text(
                          _erro!,
                          style: const TextStyle(
                              color: AppColors.error, fontSize: 13),
                        ),
                      ),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        key: const ValueKey('como-decide-li-e-percebi'),
                        onPressed: _aGravar ? null : _li,
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary),
                        child: _aGravar
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text(
                                ComoOBoraDecideScreen.textoBotaoLi,
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xxxl),
          children: [
            const Text(
              ComoOBoraDecide.titulo,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                height: 1.3,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            const Text(
              ComoOBoraDecide.introducao,
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary, height: 1.4),
            ),
            for (final (titulo, paragrafos) in ComoOBoraDecide.seccoes)
              _secao(titulo, paragrafos, corpo),
            const SizedBox(height: Spacing.xxl),
            const Divider(color: AppColors.divider),
            const SizedBox(height: Spacing.sm),
            const Text(
              ComoOBoraDecide.tituloSuspensoes,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            for (final (titulo, paragrafos) in ComoOBoraDecide.suspensoes)
              _secao(titulo, paragrafos, corpo),
            const SizedBox(height: Spacing.lg),
            const Text(
              ComoOBoraDecide.versao,
              style: TextStyle(fontSize: 12, color: AppColors.textSubtle),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ligação "Como o Bora decide" para pôr nas candidaturas de prestador
/// (estafeta, limpeza, lavagem, Casa) e no ecrã de conta suspensa.
class LigacaoComoOBoraDecide extends StatelessWidget {
  const LigacaoComoOBoraDecide({super.key, this.margem});

  final EdgeInsetsGeometry? margem;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margem ?? const EdgeInsets.only(bottom: Spacing.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: () => ComoOBoraDecideScreen.abrir(context),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: Spacing.sm),
          child: Row(
            children: [
              Icon(Icons.policy_outlined, size: 20, color: AppColors.primary),
              SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  'Como o Bora decide: o que a app faz sozinha e o que é '
                  'sempre decidido por uma pessoa',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.primaryDark,
                    decoration: TextDecoration.underline,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
