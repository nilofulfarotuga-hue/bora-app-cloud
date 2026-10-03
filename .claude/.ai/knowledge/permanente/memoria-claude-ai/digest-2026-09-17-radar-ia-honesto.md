---
id: memoria-claude-ai-digest-2026-09-17-radar-ia-honesto
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-17
zona: verde
confianca: alta
estado: atual
---

# radar-ia.sh ganhou a mesma regra de honestidade do radar-dinheiro.sh (titulo sozinho nao basta)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-17-radar-ia-honesto`, origem `Claude Code`, atualizada em 2026-09-17T20:53:05.280027+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 17 radar ia honesto · memoria claude.ai · claude_ai_memoria

Missao radar-ia-honesto-17-09 (17/09, PC, Sonnet). O radar-dinheiro.sh ja tinha sido corrigido para nao deixar o modelo opinar sobre um video que so tem titulo (sem legenda nem descricao). O radar-ia.sh (corre aos domingos 09h Lisboa, tarefa agendada 69cd23e1dcef) nao tinha essa correcao e nao processa videos -- o material dele vem de GitHub API (repos, com descricao ou "sem descricao") e feeds RSS/Atom (so titulo+data+link, nunca corpo do artigo). Acrescentei REGRA D ao prompt: proibido concluir o que um repo ou item de feed faz a partir so do titulo/nome; so pode escrever sobre isso depois de confirmar por websearch, senao nao gasta um dos 5 achados. Mantive as regras A (inventario do que ele ja tem), B (nao chamar poupar ao que exige chave paga) e C (aviso de hardware 4GB) intactas -- confirmei linha a linha depois da edicao. Backup em radar-ia.sh.bak_antes-radar-ia-honesto-17-09 na VPS. bash -n passou no PC e na VPS, e fui alem disso: avaliei a variavel PROMPT de facto com material de teste para confirmar que nenhuma aspa nova cortou o texto a meio (essa e a armadilha ja registada: bash -n nao apanha PROMPT="..." partido por uma aspa). Corri de verdade com RADAR_FORCE=1 dentro do container hermes: recolheu material, tentou os 3 modelos da cadeia e falhou honesto (Gemini com quota 429 esgotada, os dois fallbacks OpenCode Zen sem resposta) -- fail-closed correto, sem relatorio inventado. Confirmei que esse teste nao deixou residuo: nao criou 2026-38.md (a mesma semana ISO do domingo real 20/09), nao mexeu no ledger de links ja enviados, nao criou ficheiro no inbox do Cortex -- a corrida real de domingo corre normalmente. Nao ficou provado um caso real onde o modelo aplicou a REGRA D (quota esgotada no momento), so que o prompt chega inteiro e correto ao modelo. Prova em e2e_log fluxo=radar-ia-honesto-17-09 id=1993.
