---
id: memoria-claude-ai-habilidades-propostas
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-17
zona: verde
confianca: alta
estado: atual
---

# Habilidades propostas pelo vigia (dinheiro/publicacao) — a Claude.ai decide

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `habilidades-propostas`, origem `vigia-habilidades`, atualizada em 2026-09-17T13:29:01.834178+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: habilidades propostas · memoria claude.ai · claude_ai_memoria

PROPOSTAS DO VIGIA 2026-09-17 11:41 (nao ativadas: tocam dinheiro, dispatch, wallet, RLS ou publicacao; quem decide e a Claude.ai)

### criar ganho-motorista-numero-grande — Regra de ouro do motorista (número grande = SEMPRE o que ele ganha) repetida sem nunca ficar corrigida
Falas: 2026-09-05T15:46 / 15:51 / 16:00: [mesmo texto 3x no mesmo dia] REGRA DE OURO DO DANILO — no lado do MOTORISTA o numero grande e SEMPRE o que ELE ganha; o total do cliente aparece so em pequeno, como lembrete de quanto cobrar, e so quando e em dinheiro. (1) lib/screens/driver/tvde/tvde_driver_agenda_screen.dart ~linha 153: a variavel chama-se `ganho` mas le `r.estFareCents` — passar a `r.driverEarnCents ?? 0`... | 2026-09-07T06:33: [mesmo texto] REGRA DE OURO DO DANILO — no lado do MOTORISTA o numero grande e SEMPRE o que ELE ganha... | 2026-09-14T06:31: [mesmo texto] REGRA DE OURO DO DANILO — no lado do MOTORISTA o numero grande e SEMPRE o que ELE ganha... | 2026-09-17T06:31: [mesmo texto] REGRA DE OURO DO DANILO — no lado do MOTORISTA o numero grande e SEMPRE o que ELE ganha...
Descricao proposta: PROPOSTA (toca dinheiro/ganhos — não ativar sozinha, só como sugestão para a Claude.ai/Danilo). Usa esta skill sempre que fores tocar em qualquer ecrã do lado do MOTORISTA/estafeta que mostre valores em euros. Regra fixa do Danilo, repetida 6 vezes sem nunca ficar fechada: o número GRANDE tem de ser SEMPRE o que o motorista/estafeta VAI RECEBER (driverEarnCents/ganho real), nunca o total cobrado ao cliente. O total do cliente só pode aparecer em pequeno, como lembrete de quanto cobrar, e só quando o pagamento é em dinheiro.
Corpo proposto:
## Reforço — regra do ganho do motorista
Origem: correções repetidas do Danilo em 2026-09-05, 07, 14 e 17 (6x), sempre citando `lib/screens/driver/tvde/tvde_driver_agenda_screen.dart` linha ~153, variável chamada `ganho` mas lendo `r.estFareCents` (valor do cliente) em vez de `r.driverEarnCents ?? 0` (valor do motorista).

Antes de tocar em qualquer tela do motorista/estafeta com valores em dinheiro:
1. Localiza TODAS as variáveis chamadas `ganho`/`earn`/`total` nessa tela e confirma que leem o campo de GANHO DO MOTORISTA, nunca o valor cobrado ao cliente.
2. Confirma visualmente (tamanho de fonte, destaque) que o número do motorista é o maior da tela.
3. Se existir um valor do cliente na mesma tela, ele só aparece pequeno, e só quando o pagamento é em dinheiro (nunca em cartão/MB Way, porque aí o motorista não cobra nada).
4. Antes de fechar, grava screenshot mostrando os dois números e qual é o maior — sem essa prova, não declarar corrigido (ver skill prova-fix-cenario-real).


DECISÃO DA CLAUDE.AI (17/09/2026, depois de verificar no Córtex e no e2e_log): ganho-motorista-numero-grande = APROVADA COM CORREÇÃO. Ativar como skill global com o texto abaixo e não voltar a propor.
PORQUÊ A CORREÇÃO: a regra é do Danilo e está certa, mas não foi "repetida 6 vezes sem nunca ficar fechada". Foi dita uma vez a 20/08 e aplicada pela ordem ordem-20260820213614-e205 (estado aprovada). As "falas" que o vigia contou são o texto dessa ordem copiado por sessões automáticas (três vezes no mesmo quarto de hora a 05/09 e sempre às 06:31/06:33 noutros dias) — não são o Danilo a falar. É defeito de fonte do vigia, a corrigir.
TEXTO A ATIVAR:
name: ganho-motorista-numero-grande
description: Usa sempre que fores mexer num ecrã, aviso, notificação ou diálogo do lado do motorista ou do estafeta que mostre euros (agenda de reservas, cartão de oferta, fim de corrida, avisos push). Regra de ouro do Danilo: o número grande é sempre o que o prestador vai receber; o total do cliente só aparece em pequeno, como lembrete de quanto cobrar, e só quando o pagamento é em dinheiro.
corpo:
- Origem: regra dita pelo Danilo a 20/08, aplicada pela ordem e205 (agenda de reservas, cartão de oferta, diálogo de cobrança em dinheiro, avisos do notify-tvde-driver) e no push da fila de 14/09 ("Ganhas €x").
- Antes de mexer: o valor em destaque lê o campo de ganho do prestador (driverEarnCents no TVDE, ou o equivalente da vertical), nunca o valor cobrado ao cliente.
- O valor do cliente só em pequeno e só com pagamento em dinheiro; em cartão ou MB Way não aparece.
- É regra de mostrar, não de calcular: não mexe em preço, comissão, carteira nem acertos.
- Só se dá por feito com captura do ecrã real a mostrar os dois números (skill prova-fix-cenario-real).
