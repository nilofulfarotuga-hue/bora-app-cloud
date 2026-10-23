---
id: memoria-claude-ai-livro-areas-missao-fable-13-09
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Auditoria de 13/09 depois de 3-4 dias sem Claude (limite esgotado) — o que se achou (Apple aprovou, 2 pedidos com problema, 6 migrações do ChatGPT, VPS/agentes/Córtex) e os 3 prompts entregues (Fable janela 1 app, Fable janela 2 loja GFC, Opus janela 3 motores); ler antes de retomar qualquer um deles

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-missao-fable-13-09`, origem `claude-ai`, atualizada em 2026-10-23T05:34:57.805479+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas missao fable 13 09 · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/missao-fable-13-09.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: missao-fable-13-09
description: Auditoria de 13/09 depois de 3-4 dias sem Claude (limite esgotado) — o que se achou (Apple aprovou, 2 pedidos com problema, 6 migrações do ChatGPT, VPS/agentes/Córtex) e os 3 prompts entregues (Fable janela 1 app, Fable janela 2 loja GFC, Opus janela 3 motores); ler antes de retomar qualquer um deles
sources: [chat]
aliases: [auditoria 13/09, missão fable, janela 1, janela 2, janela 3, prompts de 13 de setembro, 5 horas de Fable]
---

- [stated] 13/09: ficou 3-4 dias sem Claude (11→13/09) por limite esgotado mesmo no plano Max; nesses dias houve problema num pedido da Goola e num "TVDE" que ele remendou com o ChatGPT sem saber se ficou bem; pediu auditoria total, puxar todo o contexto, ver o que ficou por correr, e um sistema de motores para poupar (ver [[buzz-conselho-modelos]] e a REGRA MOTOR nas preferências)
- [stated] Tem só ~5 horas de Fable antes de o plano reduzir; quer as prioridades divididas por janelas separadas; depois disso fica sem Fable
- [stated] Quer que o ChatGPT (e o OpenCode) saibam TUDO o que ele fala comigo, sem exceção, e que leiam o Córtex; quando o limite daqui acabar, usa-me para conversar e eu mando o trabalho para o ChatGPT/OpenCode

O QUE MEDI A 13/09 (Supabase por MCP + Gmail; o Córtex não serviu tools)
- Apple APROVOU a Bora a 12/09 11:23 UTC — ele não sabia; detalhes em [[lancamento-ios]]. Liguei os logos de volta (`ios_hide_nonpartner_logos=false`)
- Pedido `bba0f503` (12/09, enviar encomenda, MB Way 7,07): a cliente cancelou por espera às 17:17:55 e o dispatch continuou — o Valdemir aceitou às 17:21:52 um pedido já cancelado; crédito de reembolso na carteira saiu 3 vezes; ajuste admin do ChatGPT às 17:31 deixou a carteira certa (5,66 + 1,41 tokens = 7,07); ficou no ledger `earning 1,50` (Valdemir) e `commission 1,00` (fictícia). Bugs de código por corrigir: cancelamento não trava dispatch; reembolso sem idempotência; ledger de cancelado
- Pedido `ae711470` (11/09, Goola, MB Way 16,16 pago): 1h35 sem chamar estafeta (`dispatch_calling_since` só às 20:54, entregue 20:57). Ledger fecha em 16,94 contra 16,16 pagos — fórmula do fecho parceiro a rever
- ChatGPT aplicou 6 migrações direto na produção a 12/09, nenhuma no repo (lista em [[buzz-conselho-modelos]]); `match_cortex_knowledge` existe sem tabela
- Migrações de 09/09 por MCP (minhas): grant `anon` em `tvde_calculate_fare`/`tvde_quote_plan` (era o "€-0,01")
- VPS: paga e de pé desde ~15:00 UTC de 13/09, mas as rondas dos agentes falham "Connection error" ([[hermes-agent]]); Córtex sem tools desde 09/09 ([[conectores-claude-ai]]); loop do carteiro vivo no PC (ordem grupos-noite arrancou 13/09 19:06 Lisboa em Opus headless)
- `robot_suggestions` em `nova` (7): combos cobrança duplicada (McMenu, pedido `ef000342` de 10/09), cron mover-pedidos-demo, produtos sem foto/categoria, preço suspeito, no-show, search_path repor_demo_apagar
- Prompts entregues antes de 13/09 que NUNCA correram: `PROMPT_gfc_loja_fundacao_2026-09-09.md`, `PROMPT_habilidades_protocolo_missao_2026-09-10.md`, `PROMPT_talao_nao_parceiro_2026-09-10.md`, `prompt-vina-15km-fixo.md` (11/09; regra: até 15 km = 5,00 € fixos à Vina, motorista normal), `PROMPT_mbway_cliente_nao_fica_no_escuro_2026-09-06.md`, prompt de restauro do Córtex (10/09). Todos ABSORVIDOS nos 3 prompts abaixo — não os reenviar

PROMPTS REGISTADOS 13/09 (entregues como 3 ficheiros; nada disparado por mim)
- `PROMPT_FABLE_1_app_dinheiro_ios_2026-09-13.md` — MOTOR FABLE (Opus se acabar), SESSÃO NOVA pasta bora-app-cloud, sessão `fable-13-09-app`, fluxo e2e_log `fable-13-09`, run_id `fable-2026-09-13-app`. Blocos: 0 estado + espelhar as 6 migrações do ChatGPT no repo · 1 os dois pedidos (causa-raiz + correções + ledger) + auditoria das migrações + robot_suggestions · 2 talão não-parceiro · 3 MB Way cliente não fica no escuro · 4 plano da Vina 5 € até 15 km · 5 pós-aprovação iOS (/baixar, App Store) + PARIDADE Android (unir ramo iOS à produção, autoteste, push, Play) · 6 restos (sentinela −0,01, cron demo) · 7 skills protocolo-missao-bora + dinheiro-idempotente · 8 fecho. Estado: CORREU E FECHOU a 14/09 02:05 (verificado por SELECT a 17/09: e2e_log fluxo `fable-13-09`, 53 linhas) — Android 604 publicado no Play (run #434, autoteste dos 3 perfis verde) e web no ar com a árvore unida; 17 espelhos das migrações; os 2 bugs reais de 12/09 corrigidos; talão do não-parceiro numa só RPC; crédito TVDE; plano da Vina. ⚠️ Não voltar a listar os bugs de dinheiro de 12/09 nem a paridade Android como abertos
- `PROMPT_FABLE_2_gfc_loja_2026-09-13.md` — MOTOR FABLE, SESSÃO NOVA pasta guarda-fc-site, em PARALELO com a 1, sessão `gfc-loja-fundacao`, run_id `gfc-loja-2026-09-13`. Fundação da loja do Guarda FC em cópia de trabalho: pré-encomenda de equipamento + linha casual Printful sandbox, checkout Stripe teste + MB Way teste, painel próprio, configurador 3D three.js + AR model-viewer, org Supabase nova GRÁTIS (dinheiro zero), zero IA nas imagens, mensagem ao Jai pronta e não enviada. Estado: entregue
- `PROMPT_OPUS_3_motores_cortex_chatgpt_2026-09-13.md` — MOTOR OPUS (Pro, não gastar Fable), SESSÃO NOVA pasta QG com Chrome, DEPOIS das 5 h, sessão `motores-13-09`. Blocos: 0 medir VPS/agentes/Córtex · 1 VPS de pé com provas + reautorização do Córtex (clique dele) + renovação automática no hPanel (clique dele) · 2 OpenCode como porta única (OAuth ChatGPT nativo, Go, Zen, Ollama, MCPs, AGENTS.md, atalhos no QG) · 3 ChatGPT Developer Mode com conectores Córtex + Supabase e Project "Bora CEO" · 4 Córtex em vetores no Supabase para os agentes (acaba o `match_cortex_knowledge`) · 5 script de quotas + recuo automático · 6 skill `motores-e-portas` + MOTORES.md. Estado: entregue
- Compromisso meu (regra nas preferências): quando o Córtex voltar a servir tools, exporto a minha memória inteira para páginas `memoria-claude-ai/` no Córtex, uma vez, e passo a escrever digest no fim de cada sessão

