---
id: memoria-claude-ai-livro-areas-talao-nao-parceiro
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-28
zona: verde
confianca: alta
estado: atual
---

# Ecrã do talão do estafeta em pedidos não-parceiros do [[bora-app]] — o que o Danilo exige do fluxo e o prompt entregue a 10/09 para o corrigir

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-talao-nao-parceiro`, origem `claude-ai`, atualizada em 2026-10-28T18:15:07.754796+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas talao nao parceiro · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/talao-nao-parceiro.md), copiada a 28/10/2026 18:14 (Lisboa). A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: talao-nao-parceiro
description: Ecrã do talão do estafeta em pedidos não-parceiros do [[bora-app]] — o que o Danilo exige do fluxo e o prompt entregue a 10/09 para o corrigir
sources: [chat]
aliases: [talão do estafeta, foto do talão, registar talão, talão não-parceiro, finalizar compra]
---

- [stated] 10/09: o ecrã do talão não fecha em loja não-parceira — tira a foto, escreve o valor, carrega em confirmar e volta ao mesmo ecrã sem dizer porquê. Tentou umas dez vezes no McDonald's; no Continente, a 09/09, só passou à terceira
- [stated] O que ele quer do fluxo: uma foto, escrever o preço, confirmar, e seguir DIRETO para a navegação até à morada do cliente — sem voltar atrás nem ecrã intermédio
- [stated] 10/09: mandou corrigir para TODO o não-parceiro (mercado, restaurante, loja) e em TODOS os meios de pagamento, incluindo cartão e MB Way — não vale arranjar só o dinheiro
- [stated] 10/09: entregue `PROMPT_talao_nao_parceiro_2026-09-10.md` (motor OPUS, sessão nova no Claude Code, repo bora-app-cloud) — função única com autorização para mexer no dinheiro em todo o não-parceiro, robot do talão ligado no fim, ecrã do estafeta a mostrar o erro real em vez de o engolir, e correspondência no painel admin. Estado: prompt entregue, a aguardar execução
- [stated] 25/10/2026: lojas sem talão (ex. Fuku Sushi cobrou menos que os 9,90 do catálogo, sem nota) — o estafeta escreve quanto pagou de facto e a Bora reembolsa-lhe ESSE valor (ex. 7,50), a diferença fica lucro da Bora; o cliente paga sempre o preço da app. E o nome do cliente tem de aparecer claro em todos os ecrãs do estafeta. Prompt posto na fila da sessão "bora-app" do Claude Code (PC), run_id nome-cliente-e-valor-caixa-2026-10-25. Estado: na fila
- [stated] 28/10/2026 (pedido Auchan do Divan, ele próprio a entregar): o Confirmar do talão não fazia nada; quando é de uma loja (ex. Auchan) o estafeta tem de ver o nome da loja e a morada, não só a morada; quer que ao carregar em Confirmar saia logo para "a caminho"; disse "investiga tudo, conserta as coisas que tá errado". Destravado por MCP às 17:47; RPC do dinheiro a cobrar corrigida às ~18:00. PROMPT REGISTADO: página `prompt-talao-confirmar-loja-saldo-2026-10-28` em claude_ai_memoria (Opus 5.5, Claude Code do PC, fluxo e2e_log talao-auchan-divan-2026-10-28; blocos A Confirmar, B nome da loja, C dinheiro a cobrar, D tokens nos cancelamentos, E outros erros). Estado: por colar — o Claude Code do PC está sem sessão desde ~12h (precisa de voltar a entrar)

