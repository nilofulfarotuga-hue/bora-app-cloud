---
id: memoria-claude-ai-digest-2026-10-16-chave-nova-sem-partir
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-16
zona: verde
confianca: alta
estado: atual
---

# Claude Code 16/10 — chave nova sem partir: blocos 1-6 preparados, publicação à espera do token

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-16-chave-nova-sem-partir`, origem `claude-code`, atualizada em 2026-10-16T07:59:11.100714+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 16 chave nova sem partir · memoria claude.ai · claude_ai_memoria

Missão chave-nova-sem-partir-2026-10-16 (Fable 5.1 no PC; ordem recebida na conversa às 08:30 — o ficheiro nunca chegou ao disco). O QUE FUNCIONA AGORA: (1) Cofre: vault.sb_secret_backend = chave secreta default da Supabase, posta pela Edge chaves-semear + RPC vault_semear_chave_servidor, sem passar por ninguém (migrações 20261016070000/071500 aplicadas). (2) Medido: a Supabase já injeta as chaves novas em todas as Edge Functions, até nas variáveis antigas SUPABASE_SERVICE_ROLE_KEY/ANON_KEY; o portão verify_jwt=true aceita a chave nova em Bearer e apikey; a REST aceita apikey+Bearer iguais com a chave nova (só Bearer dá 401) — por isso robôs e CI continuam a funcionar só com a troca do valor. (3) Repo (ramo autonomous-night, commits a11d8b36, bdeb157a, 5eb222ff e o de hoje): _shared/chaves.ts + _shared/keys.ts (secretKey/isSecretApikey/callerOk; 22 testes verdes), secretKey() em 77 funções, portão exigirCallerOk em 11 chamadas pelo banco (3 estavam abertas), analyze-conversations sem aceitar JWT forjado, config.toml com as 17 funções já a false, migração 20261016100000 (banco manda apikey+Bearer com sb_secret_backend em 70 funções + 6 crons, backup em bkp_fn_chave_legada_20261016) PROVADA EM ROLLBACK mas POR APLICAR, distribuir-chave.ps1 (CI/PC/VPS sem mostrar a chave). (4) Publicada e provada do banco só a push-clientes-alvo v2 (legada 400, nova Bearer 400, nova apikey 400, forjado 401). (5) Web publicada já com a publishable (bundle lido); Android/iPhone pelo CI desde 15/10; .dart_defines do PC trocado. COMO SE USA: docs/CHAVES-2026-10-16.md (medições, estado, como desligar/reverter, quem usava a legada) e docs/missoes/2026-10-16-chave-nova-sem-partir-RELATORIO.md (bloco a bloco, propostas recusadas com o que falta). O QUE FALTA: token de administração da Supabase (caixinha COLAR-TOKEN-SUPABASE no PC) para publicar as funções pela CLI e distribuir a chave; aplicar a migração do Bloco 3 depois; aplicar as propostas recusadas pela tranca (refund, finalize-order-from-intent, charge-extra, .github/workflows) e pelo classificador (auto-refund-order, monthly-partner-statement, notify-service-provider, robot-b, weekly-closeout-digest, notify-cleaner) — a ordem já autoriza, falta a tranca em modo seguro; chave com nome backend-2026-10 (usada a default); NÃO desligar as legadas até a Claude.ai decidir (apps < build 671/193 param). ACHADOS: 3 avisos ao admin nunca saíam (PIN 5x, talão pendente, avaliação baixa) — corrigidos pela migração do Bloco 3; update-products corre sem autenticação (fora da missão); robô de fora (OVH) a validar a legada no /auth/v1/health.
