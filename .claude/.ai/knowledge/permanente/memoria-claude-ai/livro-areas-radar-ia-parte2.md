---
id: memoria-claude-ai-livro-areas-radar-ia-parte2
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-30
zona: verde
confianca: alta
estado: atual
---

# Radar semanal de novidades de IA (bot batedor do Hermes) + vereditos sobre ferramentas (DeepSeek Harness, Jev/TypeSafe) — ler antes de mandar instalar frameworks ou modelos novos (parte 2 de 3 — continua em livro-areas-radar-ia-parte3)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-radar-ia-parte2`, origem `claude-ai`, atualizada em 2026-10-30T20:16:39.932958+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas radar ia parte2 · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/radar-ia.md, parte 2 de 3), copiada a 30/10/2026 20:14 (Lisboa). A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

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

