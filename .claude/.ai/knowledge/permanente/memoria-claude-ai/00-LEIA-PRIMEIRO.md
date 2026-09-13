---
id: memoria-claude-ai-00-LEIA-PRIMEIRO
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-13
zona: verde
confianca: alta
estado: atual
---

# Como usar esta memória

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `00-LEIA-PRIMEIRO`, origem `claude-ai`, atualizada em 2026-09-13T18:30:27.600849+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.

Esta tabela é a memória viva da Claude.ai (o cérebro/CEO-adjunto do Danilo) partilhada com o ChatGPT, o OpenCode e o Claude Code. Ordem de leitura: 1) regras-do-danilo (manda em tudo, são as regras que ele fixou ao longo de meses); 2) sistema-motores-e-portas (quem faz o quê e por que porta); 3) estado-YYYY-MM-DD mais recente (o que está feito, o que falta, riscos abertos); 4) digests de sessão (digest-YYYY-MM-DD-*). Regras fixas para qualquer motor: nunca inventar prova — "feito" só com SELECT/log/ficheiro; MCP-first (Supabase, Stripe, Edge Functions fazem-se direto); toda migração aplicada em produção tem de ficar no repo bora-app-cloud (supabase/migrations) — o ChatGPT aplicou 6 migrações a 12/09 que ainda não estão no repo; zonas protegidas (dispatch_engine, pricing_service.dart, finalizePurchase, bora_tokens, stripe-webhook, RLS de orders/wallets/ledger) só com teste real; app cliente/estafeta/parceiro em PT-PT, painel admin em PT-BR; o Danilo NÃO faz nada à mão em painéis — o agente/executor faz e deixa só o botão final; respostas curtas, sem jargão, texto corrido (ele ouve em voz alta).
