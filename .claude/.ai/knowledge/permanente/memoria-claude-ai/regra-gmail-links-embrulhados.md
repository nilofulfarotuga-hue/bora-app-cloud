---
id: memoria-claude-ai-regra-gmail-links-embrulhados
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-01
zona: verde
confianca: alta
estado: atual
---

# REGRA para todos os agentes: emails com links NUNCA pelo conector Gmail (embrulha os links em google.com/url)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `regra-gmail-links-embrulhados`, origem `claude-ai`, atualizada em 2026-11-01T19:06:56.079521+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: regra gmail links embrulhados · memoria claude.ai · claude_ai_memoria

Provado 28/10 e 01/11 (e2e_log 5004 e fluxo radar-jai-fila-01-11). O conector Gmail (create_draft, update_draft, reply, send_message) reescreve TODOS os endereços do texto novo — até "jaiagarwala.com" sem https — para https://www.google.com/url?q=<endereço>&source=gmail&ust=...&sa=E, no texto simples e no HTML, mesmo com <a href> escrito à mão; só o histórico citado fica intacto. É isso que o destinatário recebe. Todos os emails de imprensa do Jai enviados desde 31/08 saíram assim (NDTV, Telangana Today, Assam Tribune, New Indian Express, Nagaland Post, Tripura Star News, MaisBeiras, Diário de Viseu, Sportskeeda, Sports Adda, averdade, Brunel 26/10...). REGRA: (1) email que leve endereço de site sai pelo Gmail web no Chrome (compor e enviar na página do Gmail da conta certa) ou por SMTP — nunca pelo conector; (2) pelo conector só emails SEM endereços; (3) depois de enviar, ler a mensagem enviada e confirmar que não há google.com/url nem safelinks no corpo; (4) quem redige pedidos de link (radar-jai) recusa rascunho com google.com/url ou safelinks.
