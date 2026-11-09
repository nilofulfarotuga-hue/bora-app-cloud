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

  static const String versao = 'Versão em vigor desde 1 de novembro de 2026.';

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
}

/// Ecrã com o texto inteiro de [ComoOBoraDecide].
class ComoOBoraDecideScreen extends StatelessWidget {
  const ComoOBoraDecideScreen({super.key});

  static Future<void> abrir(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ComoOBoraDecideScreen()),
      );

  @override
  Widget build(BuildContext context) {
    const corpo = TextStyle(
      fontSize: 14,
      color: AppColors.textPrimary,
      height: 1.45,
    );
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Como o Bora decide'),
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
            for (final (titulo, paragrafos) in ComoOBoraDecide.seccoes) ...[
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
                if (TvdeVisibilidade.aberto ||
                    !ComoOBoraDecide.soBoraMotorista(p))
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: Spacing.sm,
                      left: p.startsWith('• ') ? Spacing.sm : 0,
                    ),
                    child: Text(p, style: corpo),
                  ),
            ],
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
