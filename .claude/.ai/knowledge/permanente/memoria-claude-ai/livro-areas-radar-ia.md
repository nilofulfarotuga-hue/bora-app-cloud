---
id: memoria-claude-ai-livro-areas-radar-ia
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Radar semanal de novidades de IA (bot batedor do Hermes) + vereditos sobre ferramentas (DeepSeek Harness, Jev/TypeSafe) — ler antes de mandar instalar frameworks ou modelos novos

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-radar-ia`, origem `claude-ai`, atualizada em 2026-10-23T05:46:25.282991+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas radar ia · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/radar-ia.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: radar-ia
description: Radar semanal de novidades de IA (bot batedor do Hermes) + vereditos sobre ferramentas (DeepSeek Harness, Jev/TypeSafe) — ler antes de mandar instalar frameworks ou modelos novos
sources: [chat, cowork]
aliases: [radar, batedor, novidades de IA, varredura semanal, DeepSeek Harness, dsh, harness, Jev, Jedi, JEV, TypeSafe, decisor]
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

🎬 23/08 ACHADO TRAZIDO POR ELE (transcrição de vídeo sobre o "Comfy MCP") — veredito meu, registado no Córtex em `radar-ia-2026-34`
- [stated] Colou a transcrição e perguntou se dá para encaixar no sistema dele e se é grátis; pediu para NÃO fazer prompt, só deixar guardado o que há a fazer para quando se mexer no Studio
- O QUE É (fonte primária): `comfy-mcp` da Comfy Org, lançado 11/08/2026, MCP oficial aberto que deixa Claude Code/Desktop/Cursor/ChatGPT conduzir o ComfyUI — instala modelos, valida e corre workflows, gera imagem/vídeo/áudio/3D/upscale. Docs em docs.comfy.org/agent-tools/mcp
- ❌ NÃO ADOTAR, por duas razões independentes: (1) HARDWARE — o servidor local exige ComfyUI vivo com GPU em 127.0.0.1:8188; o PC é Celeron 4GB sem placa, e o autor do vídeo corre numa RTX 3050 8GB dizendo que está "no mínimo". A única variante sem placa é a Comfy Cloud e EXIGE SUBSCRIÇÃO PAGA (créditos avulso não chegam). (2) DESENHO — o Studio já faz isto headless no Kaggle/Colab/Lightning com Wan 2.2 e relógio de 15 min; ComfyUI é GUI de nós, era reintroduzir trabalho manual. Mesmo raciocínio que arquivou o VoiceBox a 04/08: interessa o motor, nunca a janela
- ❌ NANO BANANA (segundo achado da mesma mensagem): já é dele, é o operador de imagem do Studio. O "Nano Banana Video" com conector MCP (nanobananavideo.com/mcp) existe mas gera por créditos e o uso comercial sem marca de água é pago — rejeitado pela regra do preço. FACTO a não voltar a confundir: o Nano Banana é modelo de IMAGEM, não gera vídeo
- ✅ O ÚNICO PEDAÇO QUE VALE E É GRÁTIS: upscale em DUAS passadas, a segunda dedicada só ao rosto — é ordem de operações, não ferramenta, e faz-se nos kernels grátis sem ComfyUI. Detalhe e condições em [[filme-animacao]]

💰 02/09 RADAR-DINHEIRO (segundo radar do batedor)
- [stated] Danilo colou transcrição de vídeo brasileiro (Pulso Social, postagem automática em grupos do Facebook) e pediu: analisar, pôr o sistema a ver mais vídeos deste estilo para achar formas de ele ganhar dinheiro, usar o grupo de WhatsApp para anunciar o Bora, e mais jeitos de ganhar além dos sites (só teve um resultado até agora); "preciso ganhar dinheiro de algum jeito"; quer modo automático, ele só confirma
- Veredito meu: NÃO instalar Pulso Social (afiliado + robô de Facebook = risco de bloqueio da conta do Bora); única ideia aproveitável = 3 imagens + 3 textos diferentes, um por grupo
- [stated] PROMPT REGISTADO: `PROMPT_radar_dinheiro_2026-09-02.md`, entregue 02/09, MOTOR OPUS, janela Pro, sessão `radar-dinheiro`. Scope: script `/opt/data/scripts/radar-dinheiro.sh` copiado do radar-ia.sh, quarta 09:00 Lisboa, yt-dlp legendas + readpage, regras duras a rejeitar ferramenta paga/afiliado/robô de redes, saída Telegram + `/opt/data/radar-dinheiro/AAAA-SS.md` + Córtex. Estado: entregue como ficheiro; nada disparado

🎥 17/09 RADAR DOS VÍDEOS DO HISTÓRICO DELE (3.ª vez que pede varredura de vídeos)
- [stated] Quer que o sistema veja os vídeos do HISTÓRICO do YouTube dele (falou de 500 a 1000), faça um resumão e diga o que FALTA no sistema dele; pediu também para "inventar alguma coisa". CRYPTO/Bitcoin fica FORA por ordem expressa dele. Temas que quer: IA, agentes, Claude Code/ChatGPT/Gemini, vender sites, ganhar dinheiro
- [stated] Disse que tinha começado a correr um prompt meu e parou por acabarem os créditos, e esqueceu-se de retomar
- ✅ VERIFICADO por mim no Córtex (caixa `hermes-reporte`): o `radar-dinheiro.sh` do prompt de 02/09 FOI instalado e ESTÁ VIVO — correu 16/09 (semana 2026-38, gemini-3.6-flash, 9 vídeos, 4 artigos, entregue no Telegram). A linha acima "entregue como ficheiro; nada disparado" está SUPERADA
- 🚨 BURACO REAL DOS DOIS RADARES: a corrida de 16/09 diz "9 vídeos vistos (0 com legenda real)" — estão a opinar pelo TÍTULO. Causa: correm na VPS e o YouTube recusa legendas a IP de datacenter sem cookies
- SOLUÇÃO desenhada: correr no PC dele com `yt-dlp --cookies-from-browser chrome` — histórico pelo atalho `:ythistory`, legendas por `--write-auto-subs`; grátis e sem chave nenhuma
- DESENHO QUE BAIXA O CUSTO (o que faz isto ser possível com mil vídeos): "nomes primeiro, resumo só do que é novo" — extrair só nomes de ferramentas/repos/modelos das legendas, cruzar com `INVENTARIO.md` (o que ele já tem e o que já foi rejeitado), e só os candidatos NOVOS vão a modelo (Ollama local, de noite). Claude entra só no veredito final
- [stated] PROMPT REGISTADO: `PROMPT_radar_video_historico_2026-09-17.md`, entregue 17/09, MOTOR SONNET, SESSÃO NOVA no Claude Code, pasta bora-app-cloud, run_id `radar-video-2026-09-17`. Scope: B0 inventário com hardware MEDIDO (não assumir os 4 GB do PC velho) · B1 histórico por yt-dlp+cookies · B2 filtro de tema · B3 legendas a sério · B4 extração de nomes · B5 leitura a fundo só dos novos, teto 200/noite, retomável · B6 relatório com máx. 10 achados + 3 ideias novas + nota de voz no Telegram · B7 tarefa agendada 02:00 e corrigir os dois radares da VPS para dizerem "sem legenda" em vez de opinar. Estado: entregue como ficheiro, por colar

🎬 17/09 VEREDITO DO VÍDEO QUE ELE COLOU ("10 skills e ferramentas para o agente Hermes") — ⚠️ o Hermes do vídeo é o da Nous Research, NÃO é o Emerson dele
- ✅ ADOTADOS (só registados como proposta no Córtex, cada um espera janela própria): (1) WORKTREE/pasta por missão, ideia tirada do Superpowers — dor provada: o mesmo prompt colado em duas janelas custou meia sessão, e a missão de 19/08 apareceu com 106 ficheiros mexidos por outros processos; entra como reforço de skill que já existe, nunca como plugin · (2) ACABAR O CÓRTEX EM VETORES no Supabase — a função `match_cortex_knowledge` foi criada pelo ChatGPT dele a 12/09 direto na produção e ficou SEM TABELA; é o mesmo valor do "Codebase Memory MCP" do vídeo mas com infra que ele já paga · (3) 5-6 SKILLS DE MARKETING EM PORTUGUÊS (página que converte, SEO local, email frio, anúncios) — nunca importar pacotes de 49 skills em inglês
- ✅ JÁ DELE mas mal explicado no vídeo: o Agent-Reach é TRANSCRIÇÃO de áudio, não extractor (confirma o achado de 21/08) — e é isso que resolve os vídeos sem legenda, com o `faster-whisper` LOCAL do PC (áudio por `yt-dlp -x`, teto 30/noite, NUNCA Groq/OpenAI pagos)
- ❌ REJEITADOS com motivo, para não voltar a discutir: **Caveman** (só corta a SAÍDA, o próprio vídeo admite que não toca input nem raciocínio; e é pior para ele, que OUVE as respostas) · **GJ Code** (3.ª ferramenta igual às duas que já tem, e o argumento principal — entrar com a conta Claude por fora — é proibido pelos ToS da Anthropic desde 04/04/2026, foi por isso que o OpenCode perdeu esse login) · **Open Montage** (mesma armadilha do ComfyUI: GPU + modelos pagos; a única parte boa, pré-visualização com custo antes de gastar, faz-se de graça no Studio) · **Defuddle** (já há readpage/Jina + trafilatura desde 21/08) · **humanizadores em inglês** (faz-se em casa, em PT) · **marketplace de APIs pago** do fim do vídeo
- ⚠️ REGRA PARA ESTES VÍDEOS: os números de estrelas do GitHub vinham inflacionados e o próprio autor admitiu não ter testado uma das skills — confirmar na fonte primária antes de dar valor a um achado de vídeo
- ESTADO CORRIGIDO da missão radar-video: ele JÁ tinha colado o prompt principal quando eu lhe mandei o ficheiro atualizado, e ficou chateado com isso ("você tinha que mandar só um adendo"). O resto seguiu como ADENDO em texto literal para a MESMA janela: whisper local no B3, os 3 achados a registar por `cortex_propor`, e a lista de já-rejeitados para o `INVENTARIO.md` do B0

🧠 24/09 JEV (TypeSafe AI) — o "Jedi"/"JEV" do voice-to-text é isto; não voltar a procurar outro nome
- [stated] Viu vários vídeos (Facebook/YouTube) sobre o Jev e quer incluí-lo no Hermes e "no sistema todo" se for útil; pediu a minha opinião e o ponto de situação antes de mexer
- Estado real (verificado por SELECT em e2e_log e digest no Córtex, 23/09): missão `jev-decisor-2026-09-23` correu em sessão cloud e fechou — Edge Function `decidir` (Jev → Gemini de reserva), tabela `decisoes`, 4 regras em SOMBRA (`platform_settings decisor_*_modo`), cron `decisor-varrer`, ecrã admin "Decisões (Jev)" em `/admin/decisoes`. FALTA: a chave da TypeSafe (acesso antecipado limitado; conta a criar no Chrome dele — ordem `.claude/.ai/inbox/CONTINUAR-jev-decisor-2026-09-23.md`) e a reserva Gemini do Supabase está morta (quota/503, derruba também o Robot B)
- Veredito meu: adotar só onde a tarefa é DECIDIR (Porteiro do Telegram, despachante de bots, triagem IG/WhatsApp, as 4 regras em sombra, filtro dos radares) — nunca para código, texto, reels ou juiz; Gemini fica sempre de reserva

📹 24/09 RADAR DIÁRIO DE CRESCIMENTO NAS REDES (4.ª vez que pede vídeos; irritado por "nunca ter tido resposta")
- [stated] Quer ~20 vídeos NOVOS do YouTube por dia sobre como crescer/viralizar no Instagram/Facebook e como ganhar dinheiro/marketing, guardados num sítio, e que isso vire regras que os robôs de conteúdo do Bora e do Em Dia seguem para melhorar sozinhos; disse que não tem muitos contactos em Portugal, por isso o crescimento tem de vir disto, não da rede pessoal dele
- Missão `radar-videos-crescimento-2026-09-24` colada na sessão "PC do Danilo" (recolha no PC por causa das legendas, tabela radar_videos, playbook-redes no Córtex, robôs e fiscal a ler o playbook, Telegram 20:00). Estado: na fila, por provar

📹 04/10 RADAR DE VÍDEOS (5.ª vez que pede)
- [stated] 04/10: disse que não via resultado nenhum do agente de vídeos; quer que procure também como ganhar dinheiro com IA, projetos e automação — tudo o que ele conversa com o Claude — e a partir das sugestões da página inicial do YouTube dele ("o YouTube já sabe os vídeos de que eu gosto")
- [stated] 04/10 noite: regra permanente — tudo o que ele conversa com o Claude vira tema para o radar pesquisar vídeos; quer o radar a ver vídeos de como fazer desenho animado com IA de graça, sem placa de vídeo, por várias formas (para acabar o filme das filhas, [[filme-animacao-v3]], "mais de dois meses a tentar e sai sempre uma bosta")
- [stated] 04/10 noite: o Jev "pode deixar, depois nós vemos" — fica para depois (o banco recusou o cartão para o crédito da TypeSafe)

🔍 17/10 RADAR CALOU O REA (6.ª reclamação de vídeos)
- [stated] 17/10: queixou-se de que o radar não lhe falou da moda da engenharia reversa (REA)
- Causa provada por SELECT em radar_videos: >10 vídeos REA nota 8-9 entre 12/10 e 17/10; um ficou "novo" a 13/10 (reduzido a "auditar o nosso APK") e os restantes foram marcados "ja_temos" sem nada feito; o passo "aprende" deixava de fora por ter 70 termos. Prompt da tarefa agendada "Radar de vídeos: o que presta hoje" (trig_01HyoFVDdR2xe42uYRbZVuhN) reescrito a 17/10: veredito novo 'pendente'; 'ja_temos' só com prova; regra da MODA (3+ vídeos nota ≥8 em 7 dias vão sempre na mensagem, com estado feito/pendente); troca de termo quando há 70; lente de engenharia reversa (ferramenta paga → procurar equivalente grátis no GitHub)

🔎 21/10 VERIFICAÇÃO DO RADAR (7.ª vez que pede: "vai a fundo no GitHub, ferramentas pagas copiadas de graça")
- MEDIDO em radar_videos: o radar corre todos os dias (20-41 vídeos/dia, quase todos com legenda real) e desde 17/10 já usa o veredito "pendente". Pendentes fortes que continuam SEM nada feito: REA (npx rea-agents setup, só no NOSSO APK/site — proposta de 13/10), rececionista de voz por IA para PMEs (13/10), Claude Dashboards/Motion (11/10), Orca (09/10), Jev alternativa aberta (08/10), Flow "último fotograma"/Extend e ferramenta no Flow (filme)
- CONFIRMADO NA FONTE 21/10 (dois "clones grátis" do radar): (1) **OmniRoute** (github.com/diegosouzapw/OmniRoute, `npm i -g omniroute`, porta 20128, junta 40+ fornecedores com tier grátis e roda sozinho quando um cai) — é proxy/router → PROIBIDO no Claude Code pela regra ferramenta de 13/09 e ToS; único encaixe possível é na VPS para os agentes automáticos (regra 26/09 "cai um, rotaciona para o outro"); por decidir, não instalado. (2) **DeskcommCRM** (github.com/melgarafael/DeskcommCRM, MIT, do Rafael Melgaço): CRM + agentes de IA no WhatsApp, white-label por variáveis de ambiente, instala numa VPS com 1 comando, 7 contentores, 2-4 GB RAM, WhatsApp por QR (WAHA, risco de bloqueio) ou API oficial da Meta, precisa chave de IA (OpenRouter/Anthropic/OpenAI). Candidato real para o pacote "atendente WhatsApp" vendido a PMEs — pendente de janela própria, não cabe junto do Hermes sem medir RAM da VPS
- Pippit (Story Studio, créditos grátis diários) entrou como degrau novo a medir no prompt do filme de 21/10
- [stated] 23/10/2026: pediu o OmniRoute "geral" (Claude Code, Hermes, talvez robô do Bora) porque fica parado quando acaba o limite. Decidido por mim: OmniRoute na VPS só com chaves de API/grátis sem conta, para Hermes, 5 bots, torre e juiz; reserva do PC = OpenCode apontado ao OmniRoute (lançador SEM-LIMITE.cmd); fora: conta Claude, ChatGPT/Codex por login e Gemini por cookie (termos, risco de banir contas), Claude Code intocado, robôs do app só relatório. PROMPT REGISTADO: `PROMPT_omniroute_2026-10-23.md`, MOTOR OPUS, app Claude no PC › Code › bora_app › Ignorar permissões, fluxo e2e_log `omniroute-23-10`. Estado: entregue

