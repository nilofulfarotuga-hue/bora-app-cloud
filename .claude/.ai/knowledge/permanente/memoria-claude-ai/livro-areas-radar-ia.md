---
id: memoria-claude-ai-livro-areas-radar-ia
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-30
zona: verde
confianca: alta
estado: atual
---

# Radar semanal de novidades de IA (bot batedor do Hermes) + vereditos sobre ferramentas (DeepSeek Harness, Jev/TypeSafe) — ler antes de mandar instalar frameworks ou modelos novos (parte 1 de 3 — continua em livro-areas-radar-ia-parte2…)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-radar-ia`, origem `claude-ai`, atualizada em 2026-10-30T20:16:39.932958+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas radar ia · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/radar-ia.md), copiada a 30/10/2026 20:14 (Lisboa). A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: radar-ia
description: Radar semanal de novidades de IA (bot batedor do Hermes) + vereditos sobre ferramentas (DeepSeek Harness, Jev/TypeSafe) — ler antes de mandar instalar frameworks ou modelos novos
sources: [chat, cowork]
aliases: [radar, batedor, novidades de IA, varredura semanal, DeepSeek Harness, dsh, harness, Dipsy, Gipsy, Jev, Jedi, JEV, TypeSafe, decisor]
---

📡 O QUE O DANILO PEDIU (20/08, a partir de um vídeo do CDF Café sobre o DeepSeek Harness)
- [stated] Quer um agente que navegue a internet toda, se mantenha atualizado no mundo da IA, e UMA VEZ POR SEMANA lhe entregue o que há de novo
- [stated] O filtro dele é sempre o mesmo: o que serve ao app Bora, aos sites que vende, ao Bora Studio, e a POUPAR dinheiro
- [stated] Sugeriu ele próprio pôr o Hermes a fazer isso ("pode arrumar o Hermes pra fazer isso daí")
- [stated] É a segunda vez que pede (já tinha pedido varredura mundial de novidades a 19/08) — trata isto como necessidade recorrente, não pedido isolado

⚙️ O QUE FOI FEITO
- Ordem `ordem-20260820185129-46bd-aprovado-chat` criada 20/08 (nasceu vermelha por conter as palavras dinheiro/pagamentos nas regras duras; aprovada por mim — não toca em dinheiro real, a barreira do Telegram continua de pé)
- Desenho: o bot `batedor` (perfil já criado na VPS a 19/08) passa a radar semanal, domingos 09:00 Lisboa, saída em texto simples corrido no Telegram, máx. 5 achados, cada um com "serve para: X", cópia em `/opt/data/radar/AAAA-SS.md` e resumo na caixa do Córtex
- Fontes só grátis: GitHub API pública + `websearch` do Hermes + RSS. NÃO usa `web_extract` (continua sem extractor grátis desde 11/08)
- Modelo: `gemini-3.6-flash` primeiro, `nemotron-3-ultra-free` / `hy3-free` de reserva. PROIBIDOS `deepseek-v4-flash-free` e `mimo-v2.5-free` (429 quando a chamada leva tools)

📬 PRIMEIRO RELATÓRIO (semana 2026-34) — CHEGOU AO TELEGRAM, mas verifiquei achado a achado e o batedor errou metade
- ✅ **Open Design** (`nexu-io/open-design`, 83,6 mil estrelas, Apache-2.0) — REAL e o melhor da lista, muito melhor do que o batedor percebeu. Corre por cima dos CLIs que ele JÁ tem (Claude Code, OpenCode, Hermes) via `od mcp install <agente>`, com 151 sistemas de design e 277 plugins. Toca os três negócios: sites de clientes, mini-sites de parceiros e o Bora Studio (traz HyperFrames, HTML+CSS+GSAP → MP4 real por Chrome headless + FFmpeg). ⚠️ NÃO instalar a app desktop (Electron + Next.js + daemon Node 24 não cabe no PC de 4GB) — o caminho é o servidor MCP dentro do Claude Code, sem GUI
- ❌ **Agent Reach** — ele JÁ TEM instalado no PC desde antes (canais YouTube, GitHub, RSS e web ativos). O batedor recomendou-lhe uma coisa que já é dele. FALHA DE DESENHO MINHA: a alma do batedor não tem inventário do que o Danilo já usa. DE BÓNUS: se o Agent-Reach lê páginas, é candidato a tapar o buraco do `web_extract` do Hermes que eu tinha dado como sem solução grátis
- ❌ **DeepSeek Reasonix** (`esengine/DeepSeek-Reasonix`, 34,9 mil estrelas, MIT) — real, mas o próprio README diz que EXIGE chave PAGA da DeepSeek. O batedor marcou-o como "poupar dinheiro" e é o contrário: criava despesa nova, ainda por cima depois da subida de preços de 16/08. REJEITADO
- ✅ **Qwen 3.8 27B** — verdadeiro e provavelmente a notícia mais importante do mês, que o batedor despachou como ruído. Pontua 52 no índice da Artificial Analysis, o mesmo que o GPT-5.6 Luna e a um ponto do GLM-5.2 (753B) e do DeepSeek V4 Pro (1,7T) — com 27B. ⚠️ O batedor disse "alternativa local": FALSO para ele, 27B não cabe em 4GB de PC nem na VPS. O valor real é ser o candidato natural a substituir o `glm-5.2` como motor nº1 quando aparecer barato ou grátis
- 🔧 DUAS REGRAS A METER NA ALMA DO BATEDOR: (1) inventário do que o Danilo já tem, para não recomendar o que já está instalado; (2) proibido classificar como "poupar dinheiro" o que exige chave paga — se exige, diz o preço e vai para outra gaveta

⚠️ 20/08 A ORDEM DO RADAR ESTÁ A ARDER POR CULPA MINHA: chegou à tentativa 4 de 5 com a nota "o ficheiro `/opt/data/radar/AAAA-SS.md` não existe em disco". O radar FUNCIONA (o relatório chegou mesmo ao Telegram, o Danilo colou-o), mas eu pedi prova de um ficheiro que vive na VPS e o executor corre no PC — a prova nunca podia ser encontrada. LIÇÃO: quando a ordem corre no PC mas o artefacto fica na VPS, a prova tem de ser um `docker exec`/SSH com listagem e timestamp, nunca um caminho de disco local

📬 SEGUNDO RELATÓRIO (mesma semana 2026-34, 20/08) — decidi os 4 por ele
- ❌ **Agent-Reach OUTRA VEZ** — repetiu o achado da manhã, que ele já tem instalado. Confirma que o batedor não tem inventário nem memória do que já recomendou. É a correção nº1
- ❌ **Qwen Code** (`QwenLM/qwen-code`) — real e ativo, mas o batedor disse "totalmente gratuito" e é FALSO: o tier grátis do Qwen OAuth foi DESCONTINUADO em 15/04/2026 (o próprio repo di-lo). E faz o mesmo que o OpenCode e o Claude Code que ele já tem. REJEITADO: terceira ferramenta igual = mais manutenção, zero ganho
- ❌ **awesome-claude-skills** (`ComposioHQ`) — existe, é catálogo curado de skills, não é ferramenta. Nada a instalar; serve como fonte se um dia faltar uma skill
- ❌ **LiteRT/Gemma em Raspberry Pi** — irrelevante: ele não tem Raspberry Pi e o PC é de 4GB
- O veredito do batedor voltou a estar invertido (chamou "ouro" a duas coisas que ele já tem ou que custam dinheiro). Padrão confirmado em duas semanas seguidas

⚙️ 20/08 O QUE FIZ POR MCP (sem lhe pedir nada) E O QUE PASSOU PARA PROMPT MANUAL
- Liguei também o `wallet_overdue_alerts` depois de MEDIR: geraria 0 linhas hoje e o comando tem guarda anti-duplicação de 24h. Os 5 crons desligados estão agora todos ativos e provados
- [stated] Ele pediu explicitamente para PARAR de mandar pelo loop e passar tudo por prompt que ele cola à mão: "eu vou retomar aqui, pelo que eu mando aqui é mais fácil, por aí sempre falha". Respeitar isto — o loop headless falhou-lhe duas vezes seguidas
- Entregue `PROMPT-SISTEMA-REDONDO-2026-08-20.md` (motor OPUS, sessão interativa): B1 alma do batedor (inventário + regra do preço + aviso de hardware) · B2 prova do radar por `docker exec` em vez de caminho de disco · B3 blindagem anti-mentira parada desde 11/08 · B4 `cortex_nightly` parado desde 08/07 · B5 Open Design como servidor MCP (NUNCA a app desktop) · B6 Agent-Reach como extractor para tapar o buraco do `web_extract`. Com lista explícita do que NÃO fazer, para ele não reabrir

