---
id: memoria-claude-ai-digest-2026-10-03-caca-clientes
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-03
zona: verde
confianca: alta
estado: atual
---

# Claude Code FABLE 03/10 — caça-clientes: tudo montado, falta o Permitir do Gmail

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-03-caca-clientes`, origem `claude-code`, atualizada em 2026-10-03T10:16:36.159896+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 03 caca clientes · memoria claude.ai · claude_ai_memoria

Caça-clientes a 03/10 às 11h15. O que funciona: a base tem 193 negócios (136 ativos) da Guarda e de Gouveia, com concelho preenchido e pontuação pela regra da ordem; 15 têm email verificado; 14 emails estão prontos, escritos por molde fixo (o motor grátis foi reprovado: inventava elogios) e cada um leva um link único — as duas maquetes premium (Herdade do Mondego, Quinta do Rio Noémi) ou uma página simples em boraguarda.com/avenca/<token>/. O carteiro vive na VPS em /opt/data/rotinas/carteiro_caca.py (modos redigir, enviar, ler, resumo, teste, teste-responder, teste-ler) e tem cron com guarda de fuso: enviar às 09h40 de Lisboa em dias úteis, leitor de hora a hora, resumo às 09h50, redator às 08h00. Quem decide o que sai é a base (RPC carteiro_fila): interruptor platform_settings.caca_clientes_enabled, máximo 5 novos por dia útil, janela 09h30-11h30, seguimentos aos 3 e 7 dias. O painel admin tem o ecrã Caça-clientes (versão 640). O que falta: o Danilo carregar em Continuar e Permitir na página do Google aberta no Chrome do perfil Bora; dois scripts no PC (autorizar_gmail.py e depois_do_permitir.py, em bora_app/.claude/.ai/provas/caca-clientes-2026-10-03/pc) esperam até às 16h54, gravam o token na VPS, correm o email de teste com leitura de volta e só então ligam o interruptor e os bots vendedor (RPC carteiro_ligar; prova no e2e_log, passo c5-ligar). A primeira onda só sai segunda 05/10 às 09h40, porque hoje é sábado. Atenção: a app OAuth Bora Carteiro (Google Cloud da conta Bora, projeto Default Gemini Project) está em modo de teste e o token caduca em 7 dias — é preciso preencher o branding e publicar a app antes de 10/10. Não feito: Covilhã e Seia (o Overpass público não respondeu), captura do ecrã admin, loja em rascunho na tabela restaurants, texto de convite para cabeleireiros (Christinnne em pausa). Regras: emails assinam Bora App — Guarda, sem preço, link único, opt-out no rodapé; restaurantes fora da Guarda vão como site, não como parceiro. Relatório: bora_app/.claude/.ai/reports/FABLE-2026-10-03-caca-clientes.md; continuação: .claude/.ai/inbox/CONTINUAR-caca-clientes-2026-10-03.md.
