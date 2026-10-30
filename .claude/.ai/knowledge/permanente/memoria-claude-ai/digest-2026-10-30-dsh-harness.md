---
id: memoria-claude-ai-digest-2026-10-30-dsh-harness
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-30
zona: verde
confianca: alta
estado: atual
---

# Claude Code 30/10 — DeepSeek Harness (dsh) instalado com o mesmo livro do Claude Code

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-30-dsh-harness`, origem `claude-code`, atualizada em 2026-10-30T06:04:03.525892+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 30 dsh harness · memoria claude.ai · claude_ai_memoria

O dsh 0.2.1-rc.5 está instalado por npm (sem app desktop), missão dsh-harness-2026-10-29. Motor grátis montado à mão no ~/.dsh/cordis.patch.yml: Nemotron 3 Ultra pela piscina grátis da Kilo (sem conta; a Kilo pode guardar os pedidos, por isso nunca segredos nem dados de clientes), reserva kilo-auto e depois Gemini grátis (chave do juiz, 20 pedidos por dia). O plugin dsh-our-free-model NÃO foi instalado: copia cabeçalhos do OpenCode, tem login de contas e atualizador próprio. O pago fica sem chave até o Danilo dizer "autorizo carregar 5 € na DeepSeek".

O dsh lê o mesmo livro: ~/.dsh/AGENTS.md é um hardlink do CLAUDE.md global (a ferramenta Edit parte o link; os lançadores voltam a ligá-lo), junções .dsh/skills nos repos, 9 pontes para skills que o parser YAML estrito do dsh recusa, skill agentes-claude-code (42 agentes) e ~/.agents/AGENTS.md que manda ler erros.md e regras.md, porque o dsh não segue os @ficheiros. Provado: 146 skills visíveis ao modelo, CLAUDE.md global citado, erro de 25/10 da Myra citado, e o business_rules.md respondido com 10+5+5 % e 15 % + 2,50 €.

MCP no dsh: Córtex provado (cortex_buscar harness = 20 resultados; token estático do servidor guardado em ~/.dsh/secrets só para o utilizador), nano-banana a arrancar; Supabase em SÓ LEITURA montado mas sem ligar (token sbp_ de 20/08 caducou: falta um clique no COLAR-TOKEN-SUPABASE.cmd). O dsh não tem a tranca bora-tranca nem hooks e lê qualquer ficheiro: segredos só em ~/.dsh/secrets, base só em leitura.

Lançadores: Desktop DSH-MISSAO.cmd (tarefa de Desktop\Bora\prompt-dsh.md) e DSH-ABRIR.cmd (porta 3080). Medido: 35-43 s por tarefa pequena, 31,8 mil tokens de entrada no primeiro passo (instruções e catálogo, depois em cache). Skill usar-deepseek-harness no repo. Falta: Supabase (token), Gmail/Drive/Calendar das duas contas (OAuth), plugins dos adendos C1-C10, servidor Remote Control (S.1-S.4).
