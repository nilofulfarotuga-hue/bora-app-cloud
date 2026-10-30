---
id: memoria-claude-ai-prompt-casa-manutencao-2026-10-30
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-30
zona: verde
confianca: alta
estado: atual
---

# Prompt: missão Casa & Manutenção (categoria nova, decisões do Danilo 30/10/2026)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `prompt-casa-manutencao-2026-10-30`, origem `claude.ai`, atualizada em 2026-10-30T21:41:32.246399+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: prompt casa manutencao 2026 10 30 · memoria claude.ai · claude_ai_memoria

⚠️ MODO PROTECÇÃO TOTAL ⚠️ (Claude.ai, 30/10 21:55, pelo Danilo). MOTOR: Opus 5.5. PORTA: sessão NOVA do Claude Code no PC (Remote Control "PC do Danilo", repo bora-app-cloud, ramo autonomous-night-2026-04-29, worktree próprio: há outra sessão a publicar as gorjetas no mesmo repo; nunca tocar na árvore dela). Invoca o orquestrador CEO-AI em .claude/skills/ceo-ai/ e a skill protocolo-missao-bora. Fluxo e2e_log: casa-manutencao-2026-10-30. Idiomas: app PT-PT, painel admin PT-BR.

MISSÃO: construir a categoria "Casa" (Casa & Manutenção, estilo faz-tudo) no Bora, seguindo à letra a proposta da página claude_ai_memoria casa-manutencao-proposta (secções a, b, c, d, e, f) e a pesquisa casa-manutencao-pesquisa-2026-10-29, com as regras de lançamento de categorias (regras-lancamento-categorias) e os 28 pontos do PADRAO_BORA. Modelo a copiar: TaskRabbit nas tarefas pequenas de preço fixo + Airtasker no orçamento com fotos (até 3 profissionais respondem, o cliente escolhe); nunca o modelo de pagar por contacto.

DECISÕES DO DANILO (30/10 21:38, "1 2 3 4 5 eu aceito as suas sugestões"):
1. Fase 1 só com ofícios sem título: montagem de móveis, pendurar/fixar (TV, quadros, prateleiras, cortinas), pequenas reparações, torneira/autoclismo/sifão à vista, jardinagem e quintal, pequenas mudanças com carrinha. Eletricidade, gás, pladur e pintura ficam na fase 2 (só com documento DGEG/IMPIC aprovado pelo admin; deixa a estrutura pronta mas desligada).
2. Comissão ao profissional 15% só em serviço concluído (como a Limpeza); 2 meses sem comissão para os 5 primeiros profissionais (chave nas definições); o cliente não paga taxa extra. Preços dos serviços fixos: pontos de partida da proposta, TODOS nas definições/catálogo editáveis pelo painel, nascem como proposta e só ficam válidos quando o Danilo disser "autorizo" os valores (lista para ele no relatório).
3. Dinheiro em mão aceite até ao limite geral (max_cash_amount_cents, 40 €); acima só cartão ou MB Way, retido na app até o cliente confirmar ou 24 h (modelo da Limpeza).
4. O telefone do cliente só aparece ao profissional depois de o trabalho estar aceite e pago; chat e botão de ligar só a partir daí.
5. Nome do ladrilho na app: "Casa".
Também: cancelamento por escalões (tempos nas definições), garantia de refazer, avaliação só de quem pagou, pedido de orçamento grátis com até 3 respostas, valor extra só com consentimento do cliente na app.

O QUE CONSTRUIR (por ordem; agentes em paralelo quando os ficheiros não chocam; o líder junta e faz os commits por caminho): base de dados e funções (papel novo em user_roles, tabelas de profissionais/pedidos/orçamentos/documentos por ofício, acerto semanal em cêntimos, RLS, rotação de ofertas com as 8 tarefas da Limpeza + expirar orçamentos, push por papel, toque persistente); candidatura do profissional na porta "Quero trabalhar no Bora" com documentos por ofício e aprovação ofício a ofício no painel; fluxo do cliente (ladrilho "Casa", catálogo com "desde X €", perguntas guiadas, até 5 fotos, morada automática, data/hora, pagamento, acompanhar, concluir, avaliar); fluxo do profissional (ofertas, orçamento, a caminho/cheguei/iniciar/fotos antes e depois/concluir, ganhos); painel admin completo (profissionais, pedidos, orçamentos, catálogo e definições com auditoria, interruptor geral que NASCE DESLIGADO, exportar, lupa e faixas da home). Zona de dinheiro (preços, comissões, pagamentos): só proposta e chaves nas definições; nada se aplica sem "autorizo" datado do Danilo.

PROVAS: testes de unidade das funções do servidor, bateria completa flutter test + analyze + Juiz anti-trapaça limpo, provas no emulador Android com as contas demo (cliente pede, profissional orça e aceita, admin aprova) com capturas, web a abrir a categoria desligada sem erro. Commits por caminho no ramo da missão; NÃO publicar hoje: a categoria vai na publicação semanal seguinte (o Danilo diz "publica"), nas 3 lojas. Registar prompt/estado no e2e_log e digest no Córtex (claude_ai_memoria digest-2026-10-30-casa-manutencao). Reporta outros erros em vez de os corrigir calado. Termina com /ctx doctor e /ctx stats.
