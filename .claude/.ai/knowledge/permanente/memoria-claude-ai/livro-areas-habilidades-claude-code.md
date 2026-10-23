---
id: memoria-claude-ai-livro-areas-habilidades-claude-code
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Sistema de habilidades formais (.claude/skills/) do Danilo nos repos do Bora — quais existem, onde vivem, e o histórico de criação/reforço

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-habilidades-claude-code`, origem `claude-ai`, atualizada em 2026-10-23T05:38:59.319019+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas habilidades claude code · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/habilidades-claude-code.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: habilidades-claude-code
description: Sistema de habilidades formais (.claude/skills/) do Danilo nos repos do Bora — quais existem, onde vivem, e o histórico de criação/reforço
sources: [chat]
aliases: [habilidades, skills, .claude/skills, protocolo-missao-bora]
---

- [stated] Skills já existentes antes de 10/09: `ceo-ai` (orquestrador, repo bora-app-cloud) e `site-premio` (método de sites premium, repo bora-site, criada 29/08 e reforçada no mesmo dia com o nível 4 sistema)
- [stated] `PADRAO_BORA.md` (raiz do bora-app-cloud) funciona como habilidade viva para lançar categoria/loja/serviço novo — os 11 pontos fixos — ligado no CLAUDE.md, na skill ceo-ai e no gancho de arranque do executor autónomo
- [stated] 10/09: Danilo pediu para rever toda a conversa desde o início e transformar em habilidades formais o que já se repete e já foi corrigido várias vezes, para não repetir os erros; mandou gravar em memória que sempre que eu achar que algo deve virar habilidade, já proponho/crio
- [stated] 10/09: entregue `PROMPT_habilidades_protocolo_missao_2026-09-10.md` (motor OPUS, Claude Code janela Pro, repo bora-app-cloud) — cria a skill nova `protocolo-missao-bora` (formato de prompt, escolha de motor/janela, MCP-first, autonomia total, lei do pré-voo, observabilidade, painel admin, autonomia do executor, prompt completo e fechado, digest Hermes, idiomas, CI/build) e audita o PADRAO_BORA.md contra 4 regras recentes (pedido mínimo/taxa pequena, loja fechada não bloqueia ao clique, cartão já provado não reprova, prova sempre pela web). Estado: prompt entregue, a aguardar execução no Claude Code
- [stated] Pendente, fora do prompt de hoje: copiar `protocolo-missao-bora` e `site-premio` para os outros repos com missões Claude Code (bora-site, borastudio) — fica para prompt à parte nesses repos
- [stated] 24/09: Danilo mandou criar skill `navegadores-e-contas` (repo bora-app-cloud, .claude/skills/) porque eu e o Claude Code "estamos errando muito" a mandar tarefas para o navegador errado — conteúdo: dois perfis do Chrome por deviceId (Bora d9e862e0… para painéis da Bora; pessoal nilofulfarotuga 5b260cdd… para claude.ai/code, Gemini, ChatGPT), nomes "Browser 1/2" não são de confiança. Estado: gravado na memória (preferences), skill no repo por criar
- [stated] 02/10: Danilo mandou adotar os Mods do Claude Code (extensões em código que mudam o comportamento/interface do próprio agente, lançadas pela Anthropic a 01/10/2026, v2.1.287+) em TODO o sistema dele — "faz tudo de uma vez, um mod perfeito, puxa contexto de tudo (Córtex, Obsidian, memória)". PROMPT REGISTADO: `PROMPT_MODS_BORA_2026-10-02.md`, motor OPUS 5.5, sessão `mods-bora-2026-10-02`, repo bora-app-cloud, colado por mim no claude.ai/code (Controlo Remoto, ambiente "bora-app-cloud · Danilo"); scope: plugin `bora-mods` com 5 mods (tranca = bloqueio por código das zonas vermelhas/push forçado/CI/segredos + aprovação automática do que é leitura; vigia = alerta de missão presa 15 min; contador = contexto e limite do plano; painel do CI; contexto = entra a saber a branch) + skill `mods-bora` + a skill `navegadores-e-contas` pendente de 24/09. Regra que fixei e ele aceitou: só mods nossos, nunca de terceiros (correm com as permissões dele). Estado 02/10 08:55: ARRANCOU — ele autorizou pelo telemóvel ("eu tô te autorizando") e com isso o Enter passou; sessão `session_016HSKCqxi96tyDijz9Matf6` ("Mods bora 2026-10-02") a correr no PC dele, motor Opus 5.5. Ficou em modo Manual: o clique em "Automático" dentro da sessão é bloqueado para mim mesmo com autorização dele — pedido a ele na app do telemóvel
FINAL WRITE
- [stated] 02/10 regra do Danilo sobre a tranca dos mods: quando ele mandar mexer em código de dinheiro, "tem que mexer" — a tranca não pode impedir uma ordem dele; ele autorizou também gravar no PC a chave do Telegram e o login do GitHub para os mods
- [stated] 15/10/2026: "Protocolo Danilo" (identidade, navegadores por deviceId, regras de ouro, relatório em texto corrido, modo cético/defensivo/observador + secção 6 com as decisões de 15/10) é a memória permanente do Claude Code — vai para o CLAUDE.md do bora-app-cloud (secção "Protocolo Danilo"), para ~/.claude/CLAUDE.md do PC (vale em todas as pastas) e para .claude/skills/danilo-como-trabalhar/SKILL.md. Colado pelo próprio Danilo na sessão nova da missão sistema-sem-travas-2026-10-15

