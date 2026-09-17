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

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `habilidades-propostas`, origem `vigia-habilidades`, atualizada em 2026-09-17T11:00:00.559554+00:00).
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

