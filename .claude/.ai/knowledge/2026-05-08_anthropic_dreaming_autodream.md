---
id: memoria-claude-ai-missao-noite-2026-10-07
tipo: conceito
origem: [claude-ai]
zona: verde
---
# Missão da noite 07/10/2026 — lançada

- **Sessão**: session_01BCmxekmygUAgLbBzhqVBgZ ("Bora Assistente night mission"), Claude Code no PC do Danilo, motor Fable 5.1, repo bora-app-cloud, branch autonomous-night-2026-04-29. Lançada às 21:36 (Lisboa) pela Claude.ai via Chrome (perfil pessoal 5b260cdd).
- **Autorização**: Danilo, 07/10 21:18 — "faça tudo, missão da noite, prioridade para o agente virtual do cliente, acaba com o resto tudo"; às 21:27 reforçou: "autorizo sem me pedir permissão, vou dormir, toma decisão por mim".
- **Scope**: Bloco A = Bora Assistente; Bloco B = fechar +18 (staged_maiores_18_20261007); Bloco C = pendências auditoria (Gmail OAuth, Apple Time Sensitive, GPS da corrida, CONTINUAR-auditoria); Bloco D (21:28) = vídeos de propaganda Bora/Em Dia/Semente da Luz; Bloco E (21:57, enviado 22:00 como adendo, FICOU EM FILA na sessão) = rastreio em tempo real igual à Uber em todas as categorias + ordem de CONSERTAR já qualquer erro do mapa/rastreio encontrado (sem mexer em valores de dinheiro). Publicar e provar nas 3 plataformas.
- **Zona vermelha**: SQL grande vai para platform_settings chave staged_<nome>_20261007 estado "por_aplicar"; a Claude.ai aplica por MCP e muda para "aplicado". NÃO usar conectores Supabase da Claude.ai dentro do Claude Code (apply migration prendeu 2h à tarde).
- **⚠️ ESTADO 22:05**: a sessão criou 20261007220000_bora_assistente.sql (+1026 linhas) e ficou PRESA numa chamada "claude ai Supabase: execute sql" com 24+ min — confirmei por pg_stat_activity que NÃO há SQL nenhum a correr na base: a chamada está morta do lado do conector. O adendo Bloco E está em fila e entra quando a chamada morrer/acabar. O classificador bloqueou a Claude.ai de clicar "Enviar agora" e de colar nota nova nesta altura. PRÓXIMO CHECK-IN (22:15, trigger trig_012FwtmWpWXKJERuTGUd5v9d): 1º ver se a sessão destravou sozinha e se o adendo entrou; se ainda presa, tentar outra vez clicar "Enviar agora" ou parar a chamada e mandar nota curta: usar o caminho staged_bora_assistente_20261007 (partes _p1/_p2 se grande) e seguir com Flutter/Edge Fn; a Claude.ai aplica. Verificar também staged_% em platform_settings e aplicar o que houver.
- **Estado**: EM CURSO.
