---
id: memoria-claude-ai-digest-2026-10-15-sistema-sem-travas
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-15
zona: verde
confianca: alta
estado: atual
---

# Claude Code 15/10 — sistema sem travas (chaves, trancas, RAM, pesquisa, receita)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-15-sistema-sem-travas`, origem `claude-code`, atualizada em 2026-10-15T14:11:50.916936+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 15 sistema sem travas · memoria claude.ai · claude_ai_memoria

Missão sistema-sem-travas-2026-10-15 (Claude Code Opus 5.5 no PC, worktree C:\BoraLocal\wt-sem-travas-15-10). O QUE FUNCIONA AGORA: (1) A app usa a chave publicável sb_publishable nas 3 lojas — o CI troca SUPABASE_ANON_KEY no .dart_defines por .github/scripts/chave_publica_supabase.py; web no ar, Android 671/672 com autoteste 3 perfis verde, iPhone do 1.º envio enviado para App Store Connect. As chaves legadas continuam ligadas (apps antigas, vault service_role_key em 58 funções, dispatch_anon_jwt). (2) Segredos fora do código (commit 40d690c4); histórico git não reescrito. (3) Pedir corrida nunca trava (c142aa18) + migração pedido_travado_saude_web aplicada (RPC admin_web_health_eventos, alarme ao 3.º toque em 10 min). (4) Pesquisa única na lupa: atalhos Ir para (motorista só com tvde_access, limpeza, beleza), barbearias de service_providers, regista client_search_history (o painel KPIs de pesquisa estava vazio). (5) Receita do Dia: tabelas receitas_do_dia/receita_avisos/receita_avisos_envios, RPCs client_receita_de_hoje, client_receita_aviso, admin_receita_resumo, cron receita-do-dia-avisos (hora a hora, aviso às 10h Lisboa só a quem ligou o interruptor), 14 receitas com termos testados nos 4 mercados não-parceiros; botão Pôr no carrinho usa assistant_basket_quote e mostra a lista antes; painel admin "Receita do dia". (6) RAM: nano-banana parado, BoraStudioCondutor/Relogio desligadas, AVD emdia 2048 MB, regra ≥3 GB antes de emulador no protocolo-missao-bora. COMO SE USA: docs/SEGURANCA-CHAVES.md (plano para matar a chave roubada), docs/TRANCAS.md (inventário + correções linha a linha), docs/RAM-2026-10-15.md. O QUE FALTA: repo continua PÚBLICO (privado = CI ~300 USD/mês ou pára — decisão do Danilo); chave secreta nova não criada (sb_secret não é JWT, partiria refund e notify-*); correções das trancas exigem --safe-mode pelo Danilo; reembolso ao meio original (Stripe), login Google/Apple (segredos), Goola Leite Ninho e carro ao vivo (prompts de 14/10 inexistentes), prova em emulador (RAM). Achado: assistant_search_products dá confiança alta a produtos absurdos. Córtex MCP sem autorização nesta sessão.
