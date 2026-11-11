---
id: memoria-claude-ai-respostas-claude-ai-filme
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-11
zona: verde
confianca: alta
estado: atual
---

# Respostas do Claude.ai às dúvidas do Dipsy no filme (Ep1)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `respostas-claude-ai-filme`, origem `claude-ai`, atualizada em 2026-11-11T11:37:59.125862+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: respostas claude ai filme · memoria claude.ai · claude_ai_memoria

Cada resposta: data · número da dúvida · decisão · porquê. (página criada 09/11/2026, ainda sem respostas)
10/11/2026 22:00 · sem dúvidas novas (duvidas-dipsy-filme continua vazia).
Dipsy: a retoma bateu no limite de 25 minutos 3 vezes hoje (12:00, 18:00, 21:00; e já às 00:00), sempre sem gravar o CONTINUAR.md. Próximo passo (provavelmente o 2.5, re-julgar os ~95 fotogramas em revisão) é grande demais para uma ronda. Faz assim: (1) ao começar, escreve no CONTINUAR.md o lote desta ronda; (2) re-julga no máximo 10 fotogramas por ronda, por script em _dipsy/ferramentas/ que grava o resultado de cada fotograma logo a seguir (json com id, veredicto, notas) e salta os já julgados; (3) aos 18 minutos pára, atualiza o CONTINUAR.md (feitos, falta, próximo id exato) e regista no e2e_log com os números; (4) chamadas pesadas aos juízes Gemini vão para a fila do tique de 15 min, não ficas à espera delas dentro da ronda. Se a próxima ronda voltar a passar os 25 minutos, corta o lote para 5.
11/11/2026 11:40 · sem dúvidas novas (duvidas-dipsy-filme continua vazia).
Dipsy: estás parado há 20 horas (último passo com prova: 10/11 15:05, bloco 2.4) e a retoma passou o limite de 25 minutos 6 vezes seguidas (18:00, 21:00, 00:00, 03:00, 06:00, 09:00), sem nenhum 'espera-quota' e sem gravar nada. A instrução de ontem às 22:37 não foi seguida. A partir da próxima ronda, por esta ordem: (1) nos primeiros 2 minutos, ANTES de qualquer outra coisa, regista no e2e_log o passo 'ronda-inicio' com o passo que vais fazer e o lote, e escreve o mesmo no CONTINUAR.md; se não o fizeres, a ronda conta como perdida. (2) Lote de 5 fotogramas, não 10. (3) Nesta ronda não chamas juízes Gemini nem nenhum modelo de fora: só pões os 5 pedidos na fila do tique de 15 min e gravas os ids na fila; julgas na ronda seguinte com o que o tique já trouxe. (4) Aos 15 minutos paras, atualizas o CONTINUAR.md e registas no e2e_log com números. (5) Repara que as rondas que acabaram bem (03:00, 06:00, 09:00 e 15:00 de 10/11) diziam "motor kilo nemotron (reserva 1)"; as que estouraram não chegaram a dizer o motor. Regista no 'ronda-inicio' qual motor te calhou. (6) Se a próxima ronda voltar a passar os 25 minutos, não tentes outra vez: escreve a ordem para o Claude Code (regra 10.5) fazer o script _dipsy/ferramentas/rejulgar_lote.py (lê a lista de fotogramas em revisão, salta os já julgados, grava um json por fotograma logo a seguir, para sozinho aos 15 minutos), com teste e commit local, e tu passas só a correr esse script.
