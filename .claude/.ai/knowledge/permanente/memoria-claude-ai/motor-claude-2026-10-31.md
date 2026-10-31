---
id: memoria-claude-ai-motor-claude-2026-10-31
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-31
zona: verde
confianca: alta
estado: atual
---

# Motor Claude 31/10 - estado final (Bloco 2 da retoma-geral)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `motor-claude-2026-10-31`, origem `claude-code`, atualizada em 2026-10-31T11:18:24.227671+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: motor claude 2026 10 31 · memoria claude.ai · claude_ai_memoria


Estado a 31/10/2026 11:20 UTC, escrito pelo ajudante do Bloco 2 da retoma-geral-2026-10-31 (Claude Code no PC). Registo detalhado: e2e_log fluxo motor-claude-31-10.

CREDITO (lido na Console 10:45 UTC, perfil Chrome do Danilo): 211,82 USD promocionais = 100,00 (expira 28/11) + 111,82 (expira 02/12). Recarga automatica desligada, sem cartao (Link by Stripe). Proximo credito: 200 USD a 30/11. AVISO: fatura de 01/07 de 1,69 USD vencida ha 91 dias; a Console diz que o acesso a API pode ser restringido. Nao foi paga (decisao do Danilo).

CHAVE: NAO EXISTE AINDA. O classificador recusou o clique em "Criar workspace" (Robos Bora). O formulario ficou preenchido no Chrome do Danilo. Falta: workspace Robos Bora com limite de 200 USD/mes e duas chaves (robos-vps e app-supabase). Depois corre-se ferramentas/vps/porteiro/vigia_chave_claude.ps1 -Destino vps (grava CLAUDE_ROBOS_API_KEY em /opt/segredos/claude.env e reinicia o motor-bora) e -Destino app (grava /opt/segredos/claude-app.env para o segredo ANTHROPIC_API_KEY das Edge Functions).

PORTEIRO (um sitio so decide): /opt/motor-bora/motor_bora/porteiro.py dentro do Motor Bora (127.0.0.1:8792 e 172.16.1.1:8792). Perfis: claude-cliente (P1 Sonnet 5.5), claude-classificar (P1 Haiku 5.5), claude-decisao (P2 Sonnet), claude-agente e claude-volume (P3 Haiku), claude-so-decisao e claude-so-volume (so Claude, para o OmniRoute). Ritmo: parte do dia = (resta + gasto de hoje) / dias ate ao proximo credito (hoje 7,06 USD). P1 enquanto houver credito; P2 ate a parte do dia; P3 ate metade. Sem saldo -> dormido ate 30/11 e acorda sozinho; 401/403/404 pausa 6 h; 429/529/5xx/20 s -> gratis. Estado: GET http://127.0.0.1:8792/porteiro. Livro de gastos: /opt/motor-bora/ia_gastos.jsonl, enviado para public.ia_gastos quando a tabela existir. As Edge Functions seguem a mesma regra pela funcao public.ia_claude_pode.

QUEM JA PASSA PELO PORTEIRO: assistente das lojas (todas as cadeias + classificador), cerebro do WhatsApp da Bora (claude-cliente/agente/volume), 19 perfis do Hermes (claude-agente), OmniRoute agentes/privado/rapido/volume (claude-so-* a frente), logo o Hermes/Emerson, torre, critico, despachante e emerson.py. Enquanto nao houver chave, tudo cai na rotacao gratis (provado: respostas em 0,2 a 0,6 s; hermes -z 41 s).

SUPORTE: o cerebro do WhatsApp da Bora tem regras fixas (cumprimento, consultar antes de responder, conversa humana, falar com uma pessoa, o que nunca se diz) e ja nao diz o nome do Danilo a quem escreve. Corrigido: "oi" a meio da conversa nao cumprimentava; "hoje esta um frio" virava urgencia. Com os motores gratis so 6 de 12 respostas de prova ficaram boas; refazer com o Claude.

LIVRO E LICOES: o porteiro poe em cache o bloco comum (o que nunca se diz + licoes ativas; para P2/P3 tambem regras-do-danilo e erros-aprendidos). Tabela licoes_robos na migracao pendente. Por fazer: escriba a gravar licoes, critico noturno, prova do ciclo.

PARA O PASSO PUBLICAR: ramo motor-claude-2026-10-31 commit 02fc6aa0 (worktree .claude/worktrees/motor-claude-2026-10-31); migracoes supabase/migrations_pendentes/20261031_motor_claude_porteiro.sql e 20261031_decisoes_motor_claude.sql; Edge Functions admin-ai-assistant (primeiro: corrige falha de seguranca), support-chatbot, decidir, robot-b (com _shared/claude.ts); segredo ANTHROPIC_API_KEY. Gateway do Hermes: no proximo arranque perde os fallbacks mortos (nao foi reiniciado).

DIPSY (para a missao dele, nao mexido): para usar o porteiro, base_url http://127.0.0.1:8792/v1 na VPS (ou o OmniRoute) com model perfil:claude-agente (P3) ou perfil:claude-decisao (P2); no PC nao ha porteiro (so na VPS, pela Tailscale).

