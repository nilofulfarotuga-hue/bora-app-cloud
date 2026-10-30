---
id: memoria-claude-ai-livro-areas-radar-ia
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-30
zona: verde
confianca: alta
estado: atual
---

# Radar semanal de novidades de IA (bot batedor do Hermes) + vereditos sobre ferramentas (DeepSeek Harness, Jev/TypeSafe) — ler antes de mandar instalar frameworks ou modelos novos (parte 1 de 2 — continua em livro-areas-radar-ia-parte2)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-radar-ia`, origem `claude-ai`, atualizada em 2026-10-30T06:14:57.311561+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas radar ia · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/radar-ia.md), copiada a 30/10/2026 06:15 (Lisboa). A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

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

🔑 ONDE VIVE MESMO A ALMA DO BATEDOR (achado pelo executor 21/08 — a minha ordem apontava para o sítio errado)
- A ordem dizia "edita a alma em `profiles/batedor/`". ERRADO: no contentor o `~` é `/opt/data`, e o perfil só tem um `profile.yaml` com 2 linhas de descrição, workspace vazio, sem AGENTS.md. Editar ali não muda nada — o batedor continuaria a recomendar o Agent-Reach
- A alma vive em **`/opt/data/scripts/radar-ia.sh`** (203 linhas, ~9 KB) na VPS. A tarefa agendada "Radar de IA semanal (batedor)" (id 69cd23e1dcef, cron `0 8,9 * * 0`) tem prompt VAZIO e limita-se a correr esse script. Quem agenda a corrida é que passa o prompt
- É lá dentro que entram as duas correcções: inventário do que ele já tem, e a regra de nunca chamar "poupar dinheiro" ao que exige chave paga
- ✅ Bloco 2 fechado com prova literal por `docker exec`: `/opt/data/radar/` existe, é do hermes e é escrevível; lá dentro `2026-34.md` (16,7 KB, 20/08 20:33), `_execucoes.log` e mais. A semana 33 nunca foi arquivada (o log só tem corridas de 20/08) — único ponto por fechar do bloco 2
- Para testar uma edição do script sem esperar por domingo: `RADAR_FORCE=1`
- Blocos 5 e 6 continuam POR LIGAR, à espera de preço: no 5 (Open Design) o HyperFrames é local e não custa (Chrome headless + FFmpeg), mas a geração de protótipos/decks corre por cima de um modelo e o preço por unidade não está apurado; no 6 o Agent-Reach ESTÁ instalado em `/opt/data/.agent-reach`, e o "sem taxas de API" é afirmação da ordem, não verificação
- DECISÃO minha para desbloquear sem gastar: o bloco 5 só liga se a geração correr por uma chave que ele JÁ tem (o conector higgsfield da Claude.ai, ou o `GEMINI_API_KEY` do projeto sem faturação) — nunca chave nova nem cartão. O bloco 6 apura-se SEM ligar nada: `grep` no código instalado por endpoints e chaves; se só lê páginas com HTTP/Chrome local, é grátis e tapa o buraco do `web_extract`
- ⚠️ ARMADILHA descoberta 21/08 e que não estava em lado nenhum: `RADAR_FORCE=1` **sobrescreve** o `2026-34.md`. Quem correr sem saber apaga o único relatório arquivado. Copiar antes de forçar
- ❌ SEMANA 33 NÃO EXISTE e não se recupera — decidido com prova: o `radar-collect.sh` puxa feeds AO VIVO (hnrss.org/frontpage, simonwillison.net/atom, huggingface.co/blog/feed.xml) sem janela de datas, e o `_execucoes.log` começa a 20/08. Gerar agora e chamar-lhe 2026-33 seria pôr as notícias desta semana com a etiqueta da passada — prova falsa. Isto também desfaz o mal-entendido dos "dois relatórios no Telegram": foram AMBOS da semana 34 (corrida das 21:17 e a forçada das 21:32), não 33 + 34
- 📄 HANDOFF para a sessão nova: `.claude/.ai/reports/ORDEM-sistema-redondo-RETOMAR.md` (commit b878f75, sem push) — leva a correcção do caminho, o bloco 2 fechado com a saída literal, o bloco 1 com `cp -p` de segurança e as três regras (A inventário, B preço, C hardware), o aviso do RADAR_FORCE, e os blocos 3/4/6/5 com a regra de custo

✅ SISTEMA-REDONDO FECHADA 21/08 (sessão nova, Opus; relatório `SISTEMA-REDONDO-2026-08-21.md`, commit 79cf48a, e2e_log id 848) — 5 blocos feitos, 1 decidido sem instalar. DUAS PREMISSAS MINHAS ESTAVAM ERRADAS
- B1 ✅ as TRÊS regras no `radar-ia.sh`, com cópia antes e provadas com saída real: rejeitou Hermes/agent-skills/Supabase por inventário, mandou o HeyGen Avatar IV para fora da gaveta do dinheiro por ser pago, e marcou o LFM2.5-DSpark com "não corre no teu hardware"
- ⚠️ ARMADILHA a guardar: o texto vive dentro de `PROMPT="…"` — aspas duplas no meio fecham a string e rebentam o script. Pior, `bash -n` diz SINTAXE OK porque continua válido com outro significado. Contar as aspas dentro do bloco; repor pela cópia se rebentar
- B3 ✅ já existia (feito 17/08, 5 medidas, 502 ordens fechadas). Ele não ficou pelo relatório: confirmou o M1 ao vivo. FICA POR AUDITAR: ainda há 53 `2>/dev/null` no código, 6 deles no caminho de execução — silenciar erros é o que gera "correu bem" falso
- B4 ✅ o curador do Córtex NÃO estava morto (a minha premissa): corre todos os dias, estava em DRY-RUN — via 445 páginas e não podava nenhuma, e o `_debt.md` só é reescrito no `--apply`, por isso a data velha enganou-me. Aplicado com tarball antes: inbox 649 → 204, 445 movidos para `_descartado` (move, não apaga), soma bate. Seis semanas de dívida podadas
- B6 ❌ NÃO SE LIGA e a minha ideia estava errada: o Agent-Reach **não é extractor de páginas** — é transcrição de áudio ("Whisper via Groq/OpenAI"), com `GROQ_API_KEY` ×16 e endpoints api.openai.com e mcp.exa.ai (Exa já estava na lista de pagos bloqueados)
- ✅ CORRIGIDO por ele 21/08 (testou as alternativas, não é suposição): o extrator NÃO estava em falta — já existe `readpage <url>` em `/usr/local/bin/readpage` (Jina Reader, `curl -s https://r.jina.ai/<url>`, grátis, sem chave), com `trafilatura` (Python, via `uv run`) como reserva; `readability-lxml` está instalado mas é fraco (corpo vazio no Hacker News). SOUL.md do Hermes actualizado com os três, extractor padrão = readpage. O "buraco desde 11/08" que eu tinha dado como aberto era ruído — a ferramenta já existia
- B5 ⏸️ Open Design: passa no DINHEIRO (README tem BYOK explícito, corre com o `GEMINI_API_KEY` que ele já tem, 0 € novos, cloud é opcional) mas FALHA no HARDWARE. O MCP vive dentro de um daemon Next.js 16 + Express, não há modo "só MCP": o PC tem ~300 MB livres e a VPS é onde corre o loop inteiro do Hermes. Fica proposto para janela dedicada — foi a Regra C dele a aplicar-se a si próprio

🔧 DEEPSEEK HARNESS (dsh) — MEU VEREDITO 20/08: interessante, NÃO adotar já
- É um runtime de agentes da DeepSeek, MIT, saiu 13/08/2026 e passou 95 mil estrelas em 2 dias. A ideia: tudo é plugin — o modelo, as ferramentas, o log de sessão, a sandbox e o próprio loop do agente
- Traz ponte para usar Claude Code e Codex como SUBAGENTES (desligados por defeito), cliente MCP, e lê ficheiros AGENTS.md/CLAUDE.md — ou seja, aproveitaria o repo dele como está
- Só tem Web UI local (porta 3080), ainda NÃO tem CLI — logo não serve para o carteiro/executor automático dele, que é tudo linha de comandos
- Está em developer preview e o próprio README avisa de mudanças que quebram compatibilidade; a DeepSeek não aceita pull requests externos
- RAZÃO PRINCIPAL PARA ESPERAR: o sistema dele JÁ É um harness caseiro (Córtex + carteiro + juiz + cadeia de motores + conselho) e acabou de ser estabilizado a 19/08. Trocar o motor de um carro que acabou de pegar é o erro clássico
- Onde encaixaria um dia, se encaixar: na VPS como segundo executor de volume, nunca no PC de 4GB (Node.js + Web UI + agente não cabe, e proxy/router continua proibido)
- Preços DeepSeek subiram 16/08 (V4-Pro de 0,87 para 3,96 USD por milhão de tokens de saída em hora de pico) — o argumento "DeepSeek é barato" deixou de valer; o valor do dsh é o desenho, não o modelo

