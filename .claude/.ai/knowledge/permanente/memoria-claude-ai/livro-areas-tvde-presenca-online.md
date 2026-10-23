---
id: memoria-claude-ai-livro-areas-tvde-presenca-online
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Regra do Danilo para o estado online do motorista no TVDE do Bora (só o botão desliga) e o estado da regra de GPS parado neutralizada a 23/09 — ler antes de mexer em presença/heartbeat/dispatch

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-tvde-presenca-online`, origem `claude-ai`, atualizada em 2026-10-23T05:34:06.23654+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas tvde presenca online · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/tvde-presenca-online.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: tvde-presenca-online
description: Regra do Danilo para o estado online do motorista no TVDE do Bora (só o botão desliga) e o estado da regra de GPS parado neutralizada a 23/09 — ler antes de mexer em presença/heartbeat/dispatch
sources: [chat]
aliases: [online do motorista, botão online, ficar offline sozinho, presença do motorista, GPS parado]
---
- [stated] REGRA (23/09): o motorista só fica offline quando ELE desliga o botão liga/desliga da app; se o botão está ligado, o servidor tem de o manter online. Ficar offline sem mexer no botão é bug a resolver
- [stated] Incidente 23/09: cliente nova Maria Monteiro pediu 2 corridas (~20:00), ofertas foram ao Danilo 3x e expiraram sem aceitar, ela cancelou; depois o Danilo apareceu offline sem ter desligado o botão
- Causa: regra A10 (missão ronda-fecho-2026-09-22, migration 20260923125722) desligava quem tem GPS sem posição nova >30 min, mas a app só envia posição quando o carro se mexe (heartbeat vivo). Ney no mesmo estado
- FIX por MCP 23/09: `dispatch_gps_fresh_seconds` e `dispatch_gps_offline_seconds` postos a 604800 (regra GPS neutralizada); Danilo reposto online. Registo em e2e_log fluxo incidente-maria-2026-09-23
- PENDENTE (Claude Code): app do motorista enviar posição a cada ~60 s mesmo parado; só depois voltar aos 900/1800. Por confirmar com o Danilo se o push da oferta chegou ao telemóvel às 19:57
- [stated] 22/10/2026: queixou-se que o Valdemir (e os outros) aparece sempre "sinal parado" no painel e quer que se corrija para não ficar assim
- 22/10 prova SQL: Valdemir com botão ligado mas sem batimento nem posição desde 20/10 03:01 (serviço de fundo do telemóvel morreu); nada o acorda nem o avisa; _cron_check_ghost_drivers existe mas não está agendado. Migração por MCP (aviso automático) foi cancelada → PROMPT_sinal_motorista_fantasma_2026-10-22.md entregue (Opus, Claude Code PC, pasta bora_app): aviso a quem fica mudo (10 min, 30/30 min, 6/6 h), app religa o serviço ao receber o aviso/ao abrir, aviso de bateria por fabricante, painel diz "Ligado sem sinal desde…", publicar nas 3. Estado: entregue, por correr

