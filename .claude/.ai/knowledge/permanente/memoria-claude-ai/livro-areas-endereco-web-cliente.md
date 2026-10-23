---
id: memoria-claude-ai-livro-areas-endereco-web-cliente
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Campo de morada do cliente na WEB do [[bora-app]] — cliente presa sem conseguir escrever endereço (31/08), causa achada e prompt entregue por rodar

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-endereco-web-cliente`, origem `claude-ai`, atualizada em 2026-10-23T05:41:51.734424+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas endereco web cliente · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/endereco-web-cliente.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: endereco-web-cliente
description: Campo de morada do cliente na WEB do [[bora-app]] — cliente presa sem conseguir escrever endereço (31/08), causa achada e prompt entregue por rodar
sources: [chat]
aliases: [campo de endereço, morada na web, autocomplete de morada, site não deixa pôr endereço]
---

- [stated] 31/08: cliente que pede PELA WEB ligou ao Danilo a dizer que escreve no campo de morada e não aparece nada — não conseguiu fazer a corrida. Já é a 2.ª vez com a mesma pessoa (é a mesma cliente do MB Way que falhou a 30/08).
- [stated] Suspeita dele: browser dela pesado/lento ou versão velha em cache. Quer a web mais leve e que o browser do cliente se atualize sozinho de tempos a tempos quando sai versão nova.
- [stated] Pediu explicação do que aconteceu + o prompt (só o prompt — nada de mandar trabalho para o PC por iniciativa própria).

Causa (achada por leitura do repo, 31/08 — não repetir a investigação)
- `web/index.html:30` carrega o Google Maps em `<script async>` e ninguém espera por ele; `place_autocomplete_service_web.dart` faz `if (!_init()) return []` e `address_autocomplete_field.dart:174` esconde o overlay quando a lista vem vazia → script bloqueado/lento = campo morto em SILÊNCIO, sem erro nem sugestões, e sem forma de escrever a morada à mão (viola a regra "LOCALIZAÇÃO NUNCA TRAVA" de 24/08). Atinge todos os ecrãs com `AddressAutocompleteField`, não só a corrida. `web/index.html` também não tem verificação de versão/cache.
- Base de dados e Edge Functions estavam limpas — o problema é só no cliente web.
- Não deu para eu abrir o site ao vivo (a sandbox não alcança pages.dev nem maps.googleapis.com) — confirmação ao vivo vai na prova exigida ao executor.

PROMPT entregue 31/08 (OPUS, janela Claude Code Pro): `PROMPT_endereco_web_nunca_morre_2026-08-31.md` — Bloco A campo nunca morre em silêncio + modo manual; B Edge `places-proxy` como plano B com a chave do lado do servidor; C verificação de versão + auto-atualização da cache; D web mais leve com medição antes/depois; E evento no painel admin quando o autocomplete falha. ESTADO: entregue, POR RODAR.

14/10/2026 — caso Stela Neves (cliente TVDE, Android, ligou ao Danilo: "pus a localização e quando vou finalizar não vai")
- Logs: abriu o Bora Motorista às 17:44 (Lisboa), nunca chegou a calcular preço (sem tvde_calculate_fare) → recolha ou destino sem coordenadas; botão cinzento sem explicar. Google Places/Directions a responder, outros clientes pediram corridas no mesmo dia. Já tinha "sem_resultados" a 15/09 e 17/09 ao escrever a morada com número
- PROMPT lançado por mim (OPUS, Remote Control no PC, sessão claude.ai/code/session_017wfLr8mKhtX1aVTHss5VS1 "Localização travada em pedido de corrida"): morada escrita aceite sem tocar na lista, pesquisa sem número da porta, chips "Casa"/recentes, botão diz o que falta, timeout no reverseGeocode, evento pedido_travado no painel "Saúde da Web" + alerta. Mandado parar ANTES de enviar para o servidor/publicar — à espera do sim do Danilo. ESTADO: a correr
- A sessão antiga "PC do Danilo" (session_01L5D1vJBvUdq63dn5EJETd3) morreu ("ambiente excluído"); o caminho que funcionou: claude.ai/code → Novo → Escolher ambiente → Remote Control → bora-app-cloud → colar por evento paste → Enter

