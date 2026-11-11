---
id: memoria-claude-ai-digest-2026-11-10-fechar-tudo
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-11
zona: verde
confianca: alta
estado: atual
---

# Digest fechar-tudo 10/11 (sessão do PC)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-11-10-fechar-tudo`, origem `claude-code`, atualizada em 2026-11-11T16:36:20.659434+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 11 10 fechar tudo · memoria claude.ai · claude_ai_memoria

Missão fechar-tudo-2026-11-10 (Claude Code no PC, sessão de 10/11 ~17:00-19:00; continuada e fechada pela sessão de 11/11, ver digest-2026-11-11-fechar-tudo e docs/relatorio-fechar-tudo-2026-11-11.md). Worktree C:\BoraLocal\wt-fechar-2026-11-10, ramo ai/2026-11-10-fechar-tudo.

Adendo 1 (segurança, feito 10/11 17:05-17:14 por sessão própria na janela das travas): stripe_extrato_resumo, stripe_extrato_cruzar_base e fecho_mensal_prestadores deixavam qualquer conta com sessão ler a Stripe e os estafetas com NIF/email/ganhos (guarda current_user dentro de SECURITY DEFINER). Corrigido para session_user='postgres' (a app liga como authenticator), mais fecho do contabilista (01), NIF sem ramo da Bora (03) e as 3 funções de embeddings (04). Varredura de todas as SECURITY DEFINER: só essas 3 eram exploráveis. Edge fecho-mensal-contabilista e monthly-partner-statement publicadas.

Bloco A (17:37-17:49): prova PGlite refeita contra as definições do dia (52/52) — achado: o git do PC grava .sql em CRLF e as âncoras multi-linha falham; aplicar sempre de git show HEAD:. PARTE 1, PARTE 2 do depósito Volta (ordem do Danilo "Aplica tu" para a parte de dinheiro), catálogo marcado (Burger King 0), 132 preços do KFC a subir, ocr-receipt v22, push 55918273: web no ar com Depósito Volta, Android 724.

Bloco B: causa do GPS parado provada (Valdemir online com posição de 4 h: o serviço de fundo usava o token de 1 h); função driver_posicao_segredo (segredo do batimento, passa por driver_update_location) e app a mandar a posição por ela; janela 172800 mantém-se até prova (rotina trig_014xPRvaizTtkJAeKGKuHSBX de 14/11).

Blocos C, E, F, G, H, I, J: feitos por agentes e juntados (Juiz: anti_trapaca CLEAN, analyze 0 erros, 3418+2 corrigidas = 3420 verdes; juiz de visão do check-in sem vermelhos); publicados pela sessão de 11/11. Apple: Services ID pt.boraapp.bora.web registado (falta configurar domínio/volta, chave .p8 e segredo). Chave de teste da Stripe da empresa gravada (STRIPE_TEST_SECRET_KEY_EMPRESA) por script a partir da área de colar, sem a mostrar. Chave do Google Maps (AIzaSyBYLjK1…) pertence ao projeto 676550614753, a que nenhuma das contas do Danilo tem acesso: risco, não restringível. Hermes 0.23.1 no ar com cópia no PC e VOLTAR-0.17.sh. Missões J1-J4 do Dipsy em fila.

Erro desta sessão: a janela das travas aberta às 18:40 ficou aberta até 11/11 de manhã (regra nova em erros-aprendidos).

