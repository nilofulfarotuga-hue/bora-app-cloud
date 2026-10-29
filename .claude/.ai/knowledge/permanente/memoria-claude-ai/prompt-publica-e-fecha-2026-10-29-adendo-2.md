---
id: memoria-claude-ai-prompt-publica-e-fecha-2026-10-29-adendo-2
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-29
zona: verde
confianca: alta
estado: atual
---

# Adendo 2 ao prompt publica-e-fecha (29/10 18:55): motores grátis do OpenCode em rotação + link /pedir/boom do site

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `prompt-publica-e-fecha-2026-10-29-adendo-2`, origem `claude-ai`, atualizada em 2026-10-29T18:40:53.219743+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: prompt publica e fecha 2026 10 29 adendo 2 · memoria claude.ai · claude_ai_memoria

ADENDO 2 ao prompt-publica-e-fecha-2026-10-29 (Claude.ai, 29/10 18:55). Ordem literal do Danilo (18:37): "se tiver que pegar mais motores, tem os gratuitos do OpenCode. Vê aí tudo, se dá certo ou não, mas vê mais opções para não ficar travando. Rotaciona do melhor para o pior, mas só pega os melhores."

B.2 (j) — completa o adendo 1: a rotação de motores dos automáticos (assistente-negocio/Hermes, robô do WhatsApp, decisor, radares) fica SÓ com motores grátis, ordenados do melhor para o pior, e só os bons. Candidatos a testar UM A UM com a mesma mensagem de prova (resposta certa, em português, em menos de 30 s): (1) gemini-3-flash-preview grátis (AI Studio, chave grátis já na VPS); (2) os motores grátis do OpenCode (Zen: `opencode models` lista os que estão disponíveis sem pagar — p.ex. os modelos "free" do Zen/OpenRouter que o OpenCode expõe; o plano Go pago está fora); (3) OmniRoute como fonte de rotação (já instalado, ver [[radar-ia]]/digest de 23/10); (4) gemini-3.1-flash-lite; (5) Ollama/Llama local na VPS se existir. Mede cada um (tempo médio em 3 mensagens, taxa de resposta certa) e grava a tabela de resultados na página claude_ai_memoria 'motores-rotacao-2026-10-29' (motor, tempo, certo/errado, mantido sim/não). Fica na cadeia só o que passou, do melhor para o pior; "cai um, rotaciona para o outro". Nada de chaves novas nem créditos. Regista 'B.2j-motores' no e2e_log com a cadeia final.

A.6 — Link curto do WhatsApp da Boom para o QR dos cartazes (site bora-site, que se publica pelo deploy-cloudflare.sh no PC, não pelo git): acrescenta em _redirects a linha `/pedir/boom  https://wa.me/351937501673?text=Ol%C3%A1!%20Quero%20pedir%20na%20Boom!%20Burger  302` (por agora o número da Bora, 937 501 673, para o teste do robô; quando o Danilo disser "troca", passa a ser o número do Emanuel, e o QR impresso continua a valer). Publica o site com o deploy-cloudflare.sh (token no .env do PC, nunca no repo) e prova com curl -I https://www.boraguarda.com/pedir/boom (302 para o wa.me). Confirma também que https://www.boraguarda.com/baixar?de=qr-boom abre a App Store no iPhone e a Play Store no Android (se a página só mostra os dois botões, acrescenta a deteção por user-agent com redirecionamento automático e deixa os botões como fallback). Regista 'A.6-link-pedir-boom' no e2e_log.
