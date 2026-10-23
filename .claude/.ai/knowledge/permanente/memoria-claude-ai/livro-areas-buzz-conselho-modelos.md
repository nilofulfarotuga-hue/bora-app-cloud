---
id: memoria-claude-ai-livro-areas-buzz-conselho-modelos
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Conselho de modelos (local e remoto), motores do plano Go, app Buzz e robôs Gemini do app — estado atual e regras

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-buzz-conselho-modelos`, origem `claude-ai`, atualizada em 2026-10-23T05:37:43.314624+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas buzz conselho modelos · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/buzz-conselho-modelos.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: buzz-conselho-modelos
description: Conselho de modelos (local e remoto), motores do plano Go, app Buzz e robôs Gemini do app — estado atual e regras
sources: [chat]
aliases: [Buzz, conselho de modelos, go_conselho, motores-go, debate de IAs]
---

🔴 REGRA: CONSULTAR O CONSELHO (Danilo, firme, 11/08 — depois de me apanhar a palpitar em vez de perguntar)
- Antes de qualquer análise ou decisão do Bora, verificar se o conselho está acessível (`tool_search` por "Conselho Bora"). Se não estiver, dizer-lhe logo e mandar corrigir — nunca continuar a adivinhar calado
- O conselho decide melhor do que eu sozinho quando a escolha é discutível. O veredito continua a ser meu, mas a consulta não é opcional
- Aviso que respeito: os modelos do conselho NÃO correm comandos — confirmar no código antes de aplicar o que afirmam

🗳️ O CONSELHO — como está montado
- LOCAL no PC: MCP `motores-go` (Python, biblioteca padrão, 12–24 MB), âmbito de utilizador, ferramentas `go_modelos`, `go_perguntar`, `go_conselho`
- REMOTO na VPS: `https://conselho.srv1786862.hstgr.cloud`, contentor `conselho-mcp` (20,6 MB), Traefik + Let's Encrypt, arranca sozinho após reinício. Ligado à Claude.ai como conector "Conselho Bora", senha `[REMOVIDO]`. Na VPS não há disco do PC → o campo é CONTEXTO (cola-se o texto, entregue numerado por linha)
- HERMES é a 4ª VOZ, ligado por `docker exec -z/--oneshot` (nunca pelo `/v1/chat/completions`, que está atrás de sessão com cookie — recusámos guardar a senha de admin noutro serviço). Provado nas duas pontas: PC 83s, VPS 177s. É o único que responde com factos do projeto; os outros três não conhecem o Bora
- Defesas embutidas: contexto numerado por linha (citações verificáveis) + instrução para dizer "não sei" em vez de inventar. Teste anti-mentira passou. UTF-8 forçado (no Windows o Python escreve cp1252 e um "ã" partia o canal)

⚙️ MOTORES DO PLANO GO (validados com prova de execução real)
- `qwen3.8-max` (mais forte p/ código), `qwen3.7-max`, `qwen3.7-plus`, `minimax-m3`, `minimax-m2.7`, `glm-5.2`
- `glm-5.2` NÃO serve de motor do Claude Code (422 com tools no endpoint Anthropic) mas ACEITA tools no endpoint OpenAI — por isso é o motor nº1 do Hermes
- Armadilhas do gateway Go: `/v1/messages` exige `x-api-key` e `/chat/completions` exige `Bearer` (trocado dá 401); Cloudflare bloqueia Python sem User-Agent (403/1010); modelos reasoning com max_tokens baixo devolvem resposta VAZIA; a quota é SEMANAL e partilhada por tudo, com limite adicional de 5h por janela
- TESTE ANTI-MENTIRA que fica de regra: pôr ficheiro com nome esquisito na pasta; se o modelo não disser o nome, não correu nada (o minimax-m2.5 inventou o resultado de um comando que nunca correu)
- Menu único Anthropic+Go é IMPOSSÍVEL sem router (doc oficial: `ANTHROPIC_BASE_URL` muda para onde vai o pedido, não quem responde). Não reabrir sem informação nova. Proxy/router continua proibido no PC 4GB

🐝 APP BUZZ — 4/5, e o QR não existe
- Relay Nostr próprio na VPS (imagem pública `ghcr.io/block/buzz:latest`, 89 MB; só Postgres é obrigatório), com `BUZZ_REQUIRE_AUTH_TOKEN=true`. Comunidade criada, 2 agentes em systemd, debate com discordância guardado, respostas persistem
- App de desktop instalado no PC (desktop-v0.5.8, de `block/buzz/releases`; exige Git para Windows). `BUZZ_GIT_CONFORMANCE_PROBE` precisa `"false"`; a verificação S3/MinIO foi desligada (só será precisa se um dia usarmos git/ficheiros do Buzz)
- **NÃO HÁ QR NEM APP MÓVEL** — verificados os 7 binários e todos os subcomandos. A ideia de acompanhar pelo telemóvel via QR não é possível hoje; a janela do Danilo é o Telegram
- Lição que ficou: página de marketing não é fonte primária, o repositório é. E quando o Danilo insiste que algo existe, procurar mais fundo antes de o contrariar (ele tinha razão sobre o Buzz existir)

🤖 ROBÔS GEMINI DO APP (produção)
- Três funções liam o mesmo campo `support_settings.gemini_model` (robot-b, support-chatbot e analyze-conversations) — foi criada coluna separada
- Estado: **Robot B = `gemini-3-flash-preview`** (pensa e escreve diagnósticos), **support-chatbot e analyze-conversations = `gemini-3.1-flash-lite`** (volume simples)
- Prova da subida: com o prompt real, o modelo antigo devolvia `payload_execucao: null` (o loop não conseguia executar); o novo devolveu ação concreta atacando a causa
- ⚠️ VIGIAR: `gemini-3-flash-preview` é PREVIEW num robô que corre de hora a hora — passar ao Flash estável quando sair de preview
- DECIDIDO: robôs NÃO vão para o plano Go (quota pessoal partilhada a servir tráfego comercial)

🌐 GPT / GEMINI / GROK
- Gemini grátis: chave do AI Studio (Flash), é a via legítima — usada no nível 3 da cadeia do Hermes
- Codex está incluído no ChatGPT Free (tier permanente, limite por janela de 5h + semanal) — serviria para o Buzz
- Grok/xAI é pago. Não contornar logins de web
- [stated] 12/08 ⚠️ QUOTA DO PLANO GO ESGOTADA (mensal): go_conselho devolveu 429 "Monthly usage limit reached" nos 3 modelos (glm-5.2, qwen3.7-max, minimax-m3), reset em ~27 dias. CONSEQUÊNCIAS: (1) o conselho fica sem as 3 vozes Go até ao reset — resta o hermes (nível Gemini Flash com chave própria); (2) a cadeia de motores do loop perde os fallbacks Go — ordens caem direto do Claude Pro para o Hermes; (3) o juiz-go (qwen3.8-max) deixa de funcionar — vereditos podem falhar. Avisar o Danilo antes de mandar trabalho pesado ao loop este mês
- [stated] 30/08 PC novo: Danilo instalou o app desktop do Buzz, o Ollama e o Gemini CLI. A conta BuilderLab (nuvem do Buzz) NÃO fecha — o email de confirmação nunca chega, testado com 2 emails; decisão: abandonar a conta deles e ligar o app ao relay próprio da VPS (Fase 2 da [[missao-voar]])

💸 13/09 PLANOS E PORTAS (decisão dele depois de 3-4 dias sem Claude por limite esgotado, mesmo no plano Max)
- [stated] Vai CANCELAR o plano Max e ficar com Claude Pro 20 $; mantém ChatGPT Plus 20 $, OpenCode Go 10 $ e Google AI Plus. Quer um sistema em que só troca o motor (Opus / ChatGPT / GLM) e diz que a tentativa de fazer isso dentro do Claude Code "não deu"; ouviu dizer que o OpenCode é feito para isso
- APURADO POR MIM (pesquisa 13/09, fonte primária: ToS Anthropic 19/02/2026 + bloqueio total 04/04/2026): a assinatura Claude Pro/Max só funciona no Claude Code e na Claude.ai; o OpenCode removeu o login Claude em março por pedido legal da Anthropic. Logo o menu único com Claude é impossível por regra, não por técnica. O que É possível: OpenCode ≥ v1.15.7 tem login OAuth NATIVO da conta ChatGPT Plus (`/connect` → openai, modelos gpt-5.x/codex incluindo Luna) e já tem o plano Go nativo — porta única para tudo menos Claude. Codex CLI (OpenAI) também serve a conta Plus e aceita MCP, mas é uma terceira ferramenta a manter — não adotar já
- ChatGPT Plus tem Developer Mode (Definições > Apps & Connectors > Advanced) que aceita conectores MCP remotos por HTTPS com OAuth — serve para ligar o Córtex (cortex.srv1786862.hstgr.cloud) e o Supabase MCP ao ChatGPT. Não há stdio: só servidores remotos
- 12/09 o ChatGPT dele aplicou 6 migrações direto na produção (fix_partner_order_lifecycle, finalize_driver_lifecycle, harden_driver_accept_idempotency, order_lifecycle_error_log, tvde_one_ride_goodwill_credits, match_cortex_knowledge) — a última é um começo de "Córtex em vetores no Supabase" (função existe, tabela não). Nenhuma está no repo → auditar e espelhar (ver [[missao-fable-13-09]])

🎯 14/09 UM SÓ COMANDO — CLAUDE CODE CHAMA O CODEX/OPENCODE POR DENTRO, SEM SEGUNDA JANELA
- [stated] Pedido do Danilo, para gravar e não errar mais: ele continua a abrir SÓ o Claude Code, como sempre; sou EU que analiso cada tarefa e decido/aviso qual motor usar (Claude, ChatGPT/Codex, GLM/Qwen) — ele não escolhe motor nem abre o OpenCode à parte
- Mecanismo provado 13/09 (b3, portas-2-13-09): `opencode run -m openai/gpt-5.5 "<prompt>"` corre e devolve resposta real (leu o Córtex, respondeu certo ao pedido mínimo). Como o Claude Code tem bash, o próprio prompt de Claude Code manda correr esse comando por dentro da mesma sessão — nunca precisa de duas janelas
- Passa a ser o formato por defeito para trabalho que rende mais a ChatGPT/GLM/Qwen (código médio, refactors, testes, UI) dentro de um repo: entrega-se o prompt ao Claude Code como sempre, ele chama `opencode run -m <modelo>` para o trabalho pesado, relê o resultado com contexto limpo, testa, e só ele mexe em git/produção — mesmo padrão já usado no Bora Studio com o Codex a 13/09

💸 16/09 PLANOS — considerou a ChatLLM da Abacus.AI (vídeo) e REJEITOU
- [stated] Depois de pedir análise, chegou a pensar em cancelar o ChatGPT Plus e o Google AI Plus para trocar pela Abacus.AI, mas disse que não gostou da ideia e que não é boa ideia cancelar nada — fica com o stack atual (Claude Pro, ChatGPT Plus, OpenCode Go, Google AI Plus) sem mudar nada

💸 18/09 PLANO GO RENOVADO — CORRIGIDO POR ELE (chateado: "você está desatualizado, puxa o contexto antes de fazer as coisas")
- [stated] O plano Go FOI RENOVADO e tem saldo outra vez a 18/09. SUPERA as linhas de "Go sem saldo"/"quota esgotada" — não voltar a escrever isso em prompts sem verificar
- [stated] REGRA DE MOTOR QUE ELE FIXOU PARA AS MISSÕES A PARTIR DE 18/09: gastar o MÍNIMO possível do limite do Claude Code. O trabalho pesado vai para o GLM (o mais avançado disponível no plano Go), chamado por dentro com `opencode run -m ...`; as IMAGENS vão para o Gemini (sessão paga do navegador). O Claude Code fica só de maestro — decide, verifica, mexe em git/produção — e não escreve código a metro
- [stated] 18/09 o ChatGPT Plus estava ESGOTADO (repõe 19/09 09:08); ele disse que mesmo assim se pode usar o que lá for grátis, se for preciso
- [stated] CONTABILISTA (18/09): NÃO quer contabilista metida no meio agora. O que quer é que no FECHO DE CADA MÊS eu lhe entregue, já pronto, o que ele tem de passar à contabilista — do Bora e do Em Dia, separados. Ele passa e ela resolve. Nada de emails a contabilistas escritos por nós sem ele pedir

