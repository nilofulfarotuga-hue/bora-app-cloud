---
name: usar-deepseek-harness
description: "Como usar o DeepSeek Harness (dsh/Dipsy) no PC: lançar tarefa ou conversa, motores grátis e limites, o que pode e não pode fazer. Usar quando o Danilo falar em dsh, harness, Dipsy ou motor grátis."
---

# Usar o DeepSeek Harness (dsh)

O dsh é um segundo "Claude Code" do PC, feito pela DeepSeek (MIT, pré-lançamento: pode partir compatibilidade). O Danilo
pode mandar uma tarefa ao dsh em vez de ao Claude Code, com um motor GRÁTIS. Instalado a 29-30/10/2026 (missão
`dsh-harness-2026-10-29`), versão 0.2.1-rc.5.

## Como lançar
- **Normal (o Danilo): `DIPSY.cmd`** no Ambiente de Trabalho, duplo clique. Abre a página de conversa no navegador (porta
  3080, só neste PC, o próprio dsh abre o navegador com a chave) e liga a ponte do Telegram. Para parar: uma tecla na
  janela. Guia dele: `~/.dsh/COMO-USAR.md` e página `dsh-como-usar` do livro.
- **Telegram:** a ponte `~/.dsh/telegram/ponte.py` (código nosso, Python, API oficial, só o chat do Danilo) transforma cada
  mensagem dele num pedido ao dsh headless e devolve a resposta. Arranca no login (tarefa `Dipsy-Telegram`) e pelo `DIPSY.cmd`.
  Fotos que ele mande vão para o `ver_imagem`.
- **Tarefa sem conversa (relés do Claude.ai):** escrever a tarefa em `Desktop\Bora\prompt-dsh.md` e correr
  `C:\Users\danil\.dsh\lancadores-antigos\DSH-MISSAO.cmd` (parâmetro opcional: `bora_app`, `BoraStudio`, `jai-site`,
  `bora-site`; sem parâmetro = `bora_app`). A resposta fica em `Desktop\Bora\dsh-saidas\AAAA-MM-DD_HHMM.md`.
  (`DSH-ABRIR.cmd`, o antigo, também está em `lancadores-antigos`; o `DIPSY.cmd` substitui-o.)
- **À mão (PowerShell):** primeiro `[Environment]::SetEnvironmentVariable('DIPSY_PORTEIRO', ([IO.File]::ReadAllText("$HOME\.dsh\secrets\porteiro.token")).Trim(), 'Process')`
  (senha do porteiro; e `KILO_ANON_KEY` de `kilo-anonima.txt` para as reservas), depois `dsh --profile headless "tarefa"`.
  Os lançadores e a ponte fazem isto sozinhos. Pasta: o dsh só ESCREVE na pasta onde arranca (lê tudo);
  `dsh-missao.ps1 <pasta>` aceita as 16 pastas de `~/.dsh/pastas-dipsy.json`; no Telegram `/pasta <nome>`.
- Tudo vive em `~/.dsh` (fora do repo): `cordis.patch.yml` (motores e MCP), `secrets/` (tokens, só o utilizador lê),
  `skills-ponte/` (pontes das skills que o dsh recusa), `AGENTS.md` (hardlink do CLAUDE.md global; o `Edit` parte-o, os
  lançadores voltam a ligá-lo), `profiles/lab` (onde cada plugin entra primeiro).
- O arranque do `headless` demorou 30 a 55 s nas últimas medições, com a RAM livre entre 600 e 1350 MB por causa de outras
  sessões. Em RAM folgada foi ~11 s. O dsh também deixa processos MCP filhos pendurados ao sair.

## Motor (desde 01/11/2026: o Claude primeiro, sem limite, nunca sem motor)
- **Padrão: Claude Sonnet 5.5 pelo PORTEIRO da VPS** (missão infra-claude-tudo; ordem do Danilo 01/11 19:56). Provider
  `porteiro` em `~/.dsh/cordis.patch.yml`: `baseURL http://100.120.181.115:8792/v1` (Tailscale; o `tailscale serve` do
  contentor do Hermes encaminha para a porta fechada `172.16.1.1:8793` do Motor Bora), `apiKeyEnv DIPSY_PORTEIRO` (senha em
  `~/.dsh/secrets/porteiro.token`; na VPS em `/opt/segredos/porteiro.env`). Modelos: `perfil:claude-dipsy` (Sonnet, padrão,
  150 s, esforço medium; no dsh `maxTokens` 64000 desde 08/11, mas o porteiro ainda corta aos 8000 (ver Falta), cache automática da conversa), `perfil:claude-opus` (Opus 5.5, só a pedido:
  `motor-opus.patch.yml` / `/opus` no Telegram), `perfil:claude-volume` (Haiku). **No PC não há chave da Anthropic.**
  **Nunca** o login do plano Claude no dsh.
- **Sem ração:** o porteiro só larga o Claude quando a API diz "sem crédito" (402); aí desce a cadeia grátis da VPS e volta
  sozinho (sonda de 6 em 6 h; crédito novo a 30/11). 429 → 2 min; 401/403 → 6 h.
- **Reservas do PC** (só se a VPS não responder em 8 s): Kilo Nemotron (`reserva-kilo-nemotron.patch.yml`) → `kilo-auto/free`
  → **Gemini grátis** (20 pedidos por dia e por modelo). Provado 01/11: VPS "morta" → Kilo respondeu em 58 s.
- Gastos: cada chamada fica em `public.ia_gastos` (robo `dipsy`). Estado e crédito: `GET http://100.120.181.115:8792/porteiro`
  com o cabeçalho `X-Porteiro-Token` (ou `/motor` no Telegram). A lista branca da guarda tem o IP Tailscale da VPS
  (`~/.dsh/rede-permitida.txt`).
- Contexto ao acordar: a ponte escreve de hora a hora em `~/.agents/AGENTS.md` (marcas LIVRO-DIPSY) o `MAPA-DANILO.md` +
  regras-do-danilo + erros-aprendidos + início do livro-indice; `agent-instructions maxBytes 131072`.
- ⚠️ **Nas reservas (Kilo, Gemini) os pedidos podem ficar guardados.** Nunca meter segredos nem chaves.
  Dados pessoais de clientes (nomes, telefones, moradas): só quando a tarefa precisar deles e nunca em massa (ordem do
  Danilo, 30/10). **Isto inclui o email:** o Gmail ligado ao dsh é lido por um destes modelos.
- 429 é abuso de quota: esperar. 403: região recusada.
- O plugin comunitário `dsh-our-free-model` NÃO foi instalado (copia cabeçalhos do OpenCode, tem login de contas e
  atualizador próprio). Kilo e Gemini foram ligados à mão.

## Motor pago (preparado, sem chave)
O cartão "DeepSeek" existe, SEM chave e sem pagar nada. Só se liga com **"autorizo carregar 5 € na DeepSeek"**.

## O que o Claude Code tem → o que o dsh tem → como se usa
| O Claude Code tem | O dsh tem | Como se usa |
|---|---|---|
| CLAUDE.md global e do repo | `~/.dsh/AGENTS.md` (hardlink) + `AGENTS.md`/`CLAUDE.md` do repo | automático na pasta do repo |
| Linhas `@ficheiro` do CLAUDE.md | NÃO as segue; `~/.agents/AGENTS.md` manda ler `erros.md`, `regras.md` e o AGENTS do repo | automático |
| ~150 skills | 146 visíveis ao modelo (+5 escondidas por `disable-model-invocation`) | pelo nome |
| Skills que o dsh recusa (YAML estrito) | 9 pontes em `~/.dsh/skills-ponte` | pelo nome |
| 42 agentes | skill `agentes-claude-code` | "usa o agente X" |
| Córtex (MCP) | MCP `cortex`, token estático | `cortex_buscar`, `cortex_ler` — **provado** |
| Supabase (conector Claude.ai) | MCP `supabase` **com escrita** (token da organização Bora app, acesso total, sem validade; 22 ferramentas, incluindo `apply_migration` e `deploy_edge_function`) | pelo nome da ferramenta; regras em `~/.agents/AGENTS.md`. **Provado a 30/10:** `SELECT count(*) FROM orders` = 89, igual ao Claude Code |
| Gmail, Drive, Calendar (conectores) | MCP `google` (workspace-mcp 2.2.1): Gmail leitura e **rascunhos, sem enviar**, Drive e Calendar só leitura; as duas contas (Bora e pessoal) autorizadas a 30/10 | `user_google_email` = a conta; ferramentas `search_gmail_messages` e `draft_gmail_message`. **Provado a 30/10:** 3 emails da Bora listados (só cabeçalhos) e 1 rascunho criado e lido de volta pela API, nada enviado. Reautorizar: `~/.dsh/google-autorizar.py` |
| Nano Banana (MCP) | montado e DESLIGADO (chave grátis sem imagens) | `disabled: true` no patch |
| REA (≈300 ferramentas MCP) | NÃO como MCP; pela shell, com o envólucro `~/.dsh/rea-bora.ps1` (corre o REA 6.8.0 já instalado, sem npm) | só no NOSSO APK, sites e Edge Functions; a guarda recusa alvos de terceiros e o `setup`. **Provado a 30/10:** `doctor` corre dentro do dsh; `capture-web-screenshot` do iFood foi barrado |
| Hooks e tranca `bora-tranca` | **Guarda própria** (plugin nosso `dsh-bora` 0.3.0, `ctx.tools.guard`) com DOIS tipos de resposta desde 08/11: **barra** (nunca corre: histórico git, push forçado, ler segredos, apagar dados sem `bkp_`, mudar a própria guarda, comandos codificados, formatar discos, REA a terceiros) e **pergunta** (dinheiro, pedidos, carteiras, tokens, preços, migrações, publicar funções, `git push`, publicar, mensagens para fora, apagar em massa, Stripe, escrever segredos, sistema, instalar): cria um pedido e só corre com o "sim" do Danilo pelo Telegram, uma vez, em 10 min. 314 testes offline (`node --test test/*.mjs`) | automática antes de cada ferramenta; registo em `~/.dsh/guarda.log`; pedidos em `~/.dsh/aprovacoes/`. Não tem os hooks do Claude Code (só isto) |
| Juiz anti-trapaça antes do commit | `~/.dsh/dsh-commit.ps1` + skill `juiz-dsh` (a guarda barra `git commit` à mão) | corre `anti_trapaca.py` e `zonas_diff.py`; recusa se falharem; nunca faz push. **Provado a 30/10** (batota, zona protegida e segredo recusados; commit limpo passou) |
| Pesquisa nas sessões antigas | plugin `dsh-session-search` (dsh + Claude Code, só leitura) | `agent_session_search` — **provado** |
| Olhos (ver imagens e o ecrã) | plugin nosso `dsh-bora`: ferramentas `captura_ecra` (PowerShell) e `ver_imagem` (Gemini) | `ver_imagem` com `origem: "ecra"` ou o caminho de uma imagem. **Provado a 30/10:** descreveu um ecrã de teste com a palavra secreta. A imagem vai para a Google (plano grátis) |
| Auditoria de segurança (skills de segurança) | skill nossa `auditoria-seguranca-bora` (base: Cloudflare `security-audit`) + `auditar-site.mjs` + REA | só nosso site, APK e Edge Functions, só leitura. **Provado a 30/10:** 6 achados em boraguarda.com, 3 registados no `e2e_log` |
| Telegram (canal) | ponte nossa `~/.dsh/telegram/ponte.py` (API oficial, só o chat do Danilo) | o Danilo escreve ao `@dipsy_bora_bot` e o dsh responde; fotos vão para o `ver_imagem`. **Provado a 30/10:** `/start` e "olá" enviados em nome dele, resposta do dsh no Telegram em ~54 s |
| Voz (ouvir e falar) | `voz_dipsy.py` na ponte: `faster-whisper` small em CPU (reserva Gemini) para ouvir; `edge-tts` pt-BR-Francisca para falar (reserva Gemini TTS); tudo em texto E áudio inteiro | **Provado a 30/10:** áudio do Danilo → "Ouvi: …" → resposta em texto e áudio; 3 tamanhos (88, 328 e 1.156 letras) com a duração conferida (mais de 2 s por 100 letras) |
| Tarefas em horário marcado | ferramentas nossas `agendar_tarefa`, `listar_agenda`, `cancelar_tarefa` + relógio na ponte (`~/.dsh/agenda/agenda.json`) | **Provado a 30/10:** o dsh agendou para as 22:29; a ponte disparou às 22:29:07 sozinha e entregou em texto e voz |
| Passar trabalho ao Claude Code | ferramenta nossa `passar_ao_claude_code` (CLI oficial `claude -p`, sem proxy): `so_ler` ou `editar` (cópia nova do repo, sem push) | **Provado a 30/10:** dentro do dsh, 68 s; modo editar num repo de teste, confirmado por `git diff` |
| Equipa de agentes + quadro de tarefas | bundle OFICIAL `@deepseek-ai/dsh-experimental-agent-team-profile` (experimental), nos perfis headless e web | **Provado a 30/10:** `spawn_teammate`, `team_task_create`, `wait_agent`, `team_task_list`; 2 colegas leram partes diferentes. Armadilha: `dsh plugin add` do bundle traz uma versão incompatível; pôr o NOME em `dsh.profile.bundles` |
| Memória própria entre sessões | ferramentas nossas `memorizar`, `lembrar`, `esquecer` + secção no prompt do arranque (`~/.dsh/memoria/memoria.jsonl`) | **Provado a 30/10** no headless: guardar, procurar numa sessão nova e lembrar sem ferramentas |
| Telemetria e saídas de rede | telemetria oficial DESLIGADA; desde 08/11 **proxy local com registo** (`~/.dsh/proxy/proxy.py`, só 127.0.0.1:47900) por onde passa TUDO o que o dsh e os filhos fazem na internet (os lançadores e a ponte põem `HTTPS_PROXY`; o porteiro da VPS vai direto pelo `NO_PROXY`; o Claude Code chamado pelo Dipsy nunca vai pelo proxy). Categorias em `~/.dsh/rede-categorias.yml` (bora, pesquisa, documentação, concorrentes, lojas, lei/Estado, testes, painel Stripe só leitura); `sempre_bloqueado`: bancos, despejo de ficheiros e telemetria nunca; API da Stripe, publicar e mensagens só com um passe de 10 min dado pelo "sim" a uma ação. Sítio novo: o proxy e a guarda criam o pedido "Posso abrir X?" e a resposta fica na lista. Categorias "só leitura" cortam ligações que mandem mais de 1 MB para fora. DNS de reserva (dns.google): o router da NOS diz que example.com não existe | registo em `~/.dsh/proxy/registo.jsonl` (domínio, porta, método, bytes, tempo); resumo diário às 21:00 no Telegram; `/rede`, `/rede abrir <categoria>`, `/rede fechar <categoria>` |
| Pesquisa na internet (WebSearch) | ferramenta nossa `pesquisar_internet` (DuckDuckGo HTML; reserva RSS do Bing), pelo proxy. O `web_search` do próprio dsh só funciona com a DeepSeek paga (sem chave) | "pesquisa X" |
| Perguntar antes de agir | ferramenta nossa `esperar_autorizacao` + ponte do Telegram (`autorizacoes_ponte.py`): pergunta com OPERAÇÃO, VALOR, DESTINO, o SQL/comando exato e a explicação do Dipsy, botões Sim/Não, em texto e voz; "sim" só do chat do Danilo (botão, texto ou áudio), em 10 min; resposta assinada (HMAC, chave em `~/.dsh/secrets/aprovacoes.key`); uso único; e2e_log fluxo `dipsy-autorizacoes` | automático: a guarda diz PERGUNTEI, o Dipsy chama `esperar_autorizacao` e repete a chamada com o SIM |
| Missões grandes | **`DIPSY-MISSAO.cmd`** no Ambiente de Trabalho (`~/.dsh/telegram/missao.py`): lê `Desktop\Bora\prompt-dsh.md` (ou `--prompt`), worktree próprio `C:\BoraLocal\wt-dipsy-<missão>` no ramo `ai/AAAA-MM-DD-dipsy-<missão>`, perfil headless com a guarda e o proxy, até 120 min (`--minutos`), e2e_log com fluxo = nome da missão (linha `MISSÃO DIPSY: <nome>`), fecho pelo porteiro da VPS (fila `porteiro_entrada`, texto e voz) | `DIPSY-MISSAO.cmd em_dia` |
| Respostas compridas | `maxTokens: 64000` nos perfis do porteiro (`cordis.patch.yml`) + a ponte e o DIPSY-MISSAO continuam sozinhos quando o turno acaba em `max-tokens` (até 3 vezes; o plugin `dsh-client-auto-continue` só serve a página web) | automático |
| `/plan` (modo plano) | `/planear` + `/aprovar` no Telegram: o dsh corre com `DIPSY_MODO=planear` e a guarda BARRA escritas (o `/plan` oficial do `dsh-plan-mode` só existe na página e não restringe nada) | **Provado a 31/10:** `write` barrado com a regra `modo-planear`; `/aprovar` continua a mesma sessão |
| `/goal` (objetivo) | `/objetivo` no Telegram: rondas na mesma sessão até a última linha dizer `OBJETIVO CUMPRIDO` / `BLOQUEADO` (máx. 6) | **Provado a 31/10:** cumprido na ronda 1 ("hoje 0, ontem 1", conferido por SELECT) |
| Steer (corrigir a meio) | `/corrigir`: a ponte para o dsh e continua a MESMA sessão (`--session-id`) com a correção | **Provado a 31/10:** poema de 12 versos → "só 2 versos, sobre o Bora" → 2 versos sobre o Bora |
| Rewind (voltar atrás) | `/voltar`: esquece o último pedido (conversa nova com o contexto dos anteriores) e diz que ficheiros esse pedido mudou (não os desfaz) | **Provado a 31/10:** esqueceu "TIJOLO-12" e respondeu "AZULEJO-77" |
| Conversa contínua | a ponte continua a sessão do dsh (`--session-id`) se a última mensagem foi há < 30 min; `/nova` recomeça | **Provado a 31/10:** a mesma sessão nas 2 mensagens |
| Criar as próprias ferramentas | **Creator Mode** (nosso, `lib/criador.js`): `criar_ferramenta` faz uma RECEITA (`consulta_sql` = 1 SELECT corrido com `read_only=true` na API do Supabase; `leitura_web` = 1 GET a sítio nosso), nasce no lab em `~/.dsh/ferramentas/lab`, é testada logo, `promover_ferramenta` só com o teste a passar → `fc_<nome>` | **Provado a 31/10:** "cria uma ferramenta que me diz quantos pedidos houve hoje" → criada, testada `[{"pedidos":0}]`, promovida, `fc_pedidos_hoje` no headless |
| Libertar memória | ferramenta `libertar_memoria` e botão `/libertar`: correm `~/.dsh/limpar-ram.ps1` em modo normal | **Provado a 31/10:** "antes 2910 MB, depois 2924 MB, nada a fazer (>= 500)" |
| Hooks nos executores `claude -p` | `passar_ao_claude_code` passa `--settings` com o hook `scripts/guarda-claude-hook.mjs` (`avaliarExecutor`: apagar em massa, DROP/TRUNCATE/DELETE, push forçado, histórico, matar processos, segredos, hooks/definições) | **Provado a 31/10:** `taskkill` e `Write` em `.dsh/agenda` BARRADOS; `git --version` passou. Limite: no `Read` o deny é ignorado (o hook do context-mode deixa passar) |
| Falha fechada | se o stderr do dsh mostrar que o `dsh-bora` não ligou, a ponte para o dsh (sem guarda não trabalha) | testado offline com a linha real do erro de 31/10 |
| Chrome (extensão) | nada (`dsh-browser` por compilar) | `passar_ao_claude_code` (o Claude Code nunca vai pelo proxy do Dipsy: a ferramenta tira-lhe as variáveis) |
| App de computador (Electron) | NÃO instalada: o canal oficial (GitHub releases) não publica instalador; só se compila do código | — |

## Plugins (auditados com análise estática; nada corre sem passar pelo perfil `lab`)
- **Provado e promovido (headless + web):** `Tieboyh/dsh-session-search` (sha na auditoria) e o **nosso** `dsh-bora`
  (olhos + guarda; código em `ferramentas/dsh-plugins/bora__dsh-bora` e espelho em `.claude/dsh/plugin-dsh-bora`; ao
  editá-lo, copiar os ficheiros para `~/.dsh/profiles/{headless,web,lab}/node_modules/dsh-bora`).
- **Instalados no `lab`, ativam sem avisos, SEM prova funcional:** `dsh-memento`, `dsh-auto-continue`, `dsh-notify-windows`,
  `dsh-tokenledger`, `dsh-taskfold`, `dsh-chat-import`, `dsh-sentinel`. Não estão no `headless` nem no `web`.
- **Só funcionam no perfil `web` (esperam webServer/connection), por provar lá:** `dsh-automation`, `dsh-continue`,
  `dsh-loop`, `dsh-tasks`, `hermes-loop`, `dsh-plugin-mineru`. Removidos do `lab`.
- **Não deu:** `dsh-wikilink` e `dsh-at-file` (`ctx.settings.register is not a function`); `dsh-context-doctor`,
  `dsh-inspect`, `dsh-toolkit`, `dsh-security-audit` (a cerca recusa: incompatíveis com 0.2.1-rc.5, sem exceção);
  `dsh-test-runner` (falha no `pnpm add`); `omdsh-dev/dsh-security-scan` e `official-plugins-port` (repositório não existe).
- **Nunca:** `dsh-claude-compat` (travado pelo filtro de segurança), `dsh-oh-my-claude`, qualquer app desktop do Harness,
  `dsh-purge`, `magpie`, `dsh-data-agent`, canais de conta do free-model.
- **Auditados, por instalar (ver relatório):** os 20 que precisam de compilação e os de visão, Telegram, memória, ponte.

## Regras que nunca se quebram
1. **Nunca** apontar o Claude Code para o dsh como proxy/router (regra de 13/09 e termos da Anthropic de 04/04/2026).
2. **Nunca** meter contas Claude, ChatGPT/Codex, Gemini por cookie nem OpenCode por login no dsh.
3. Desde 08/11/2026 (ordem do Danilo: "Todas as missões que você pode fazer, ele tem que poder fazer tudinho... e seja parte de
   dinheiro, é para ele mexer. Qualquer coisa é só para ele me perguntar: você permite? Sim.") o Dipsy PODE mexer em dinheiro,
   pedidos, carteiras, publicar e fazer push, mas **cada ação** passa pela pergunta no Telegram e só corre com o "sim" dele a
   essa ação (nunca autorização geral). Proibidos mesmo com "sim": cookies de contas Claude/ChatGPT/Gemini no dsh, proxy à
   frente do Claude Code, reescrever histórico git publicado, apagar dados de produção sem `bkp_`, segredos para motores
   grátis, dados pessoais de clientes em massa para motores grátis. Regras escritas em `~/.agents/AGENTS.md`.
4. Engenharia reversa **só** no nosso APK (`pt.boraapp.bora`) e nos nossos sites; apps de terceiros só para comparar o que
   o utilizador vê (regra do Danilo de 13/10).
5. Sem app desktop do Harness. Só `dsh` por npm. Não ligar o encaminhamento local (portas 18899/18900) nem relé de rede.
6. Email para fora sai SEMPRE da conta Bora; pelo dsh só com o "sim" do Danilo (o MCP do Google dele só faz rascunhos).

## Voz: texto E áudio, sempre (regra do Danilo, 30/10/2026)
- **Dipsy (PC):** um único caminho de envio, `Ponte.dizer` em `~/.dsh/telegram/ponte.py`: texto completo logo + áudio do
  texto inteiro por pedaços de até 900 letras em frases inteiras (`partir()` prova que nada se perde), duração conferida
  antes de enviar, fila de áudio em série (ordem certa), registo em `~/.dsh/telegram/voz-dipsy.log.jsonl`. Duração lida no
  próprio OGG (sem `ffprobe`, que com o PC aflito de memória passava do tempo).
- **Hermes (VPS):** `/opt/data/voz/voz.py` v2 é o caminho único (`voz "texto"`, `voz --so-audio`, fila em
  `/opt/data/voz/fila`, trabalhador no cron, servidor `voz-servidor` para o TTS do agente). Os scripts que mandam texto direto
  chamam `audio-add.sh` a seguir (16 foram passados). O agente (BoraHermesbot) fala por `tts.provider: voz`.
- **Causa raiz do áudio pela metade:** regra de "um áudio com resumo de 3 frases" acima de 900 letras no `voz.py` v1; `edge-tts`
  7.2.x recusado pela Microsoft (403) a cair no Piper sem aviso; guarda da voz que contava qualquer nível como OK; TTS do agente
  fixado a `edge-tts==7.2.7` (não subir: a verificação do dsh falha). Limite que fica: o gateway corta o texto do áudio aos 4.000
  caracteres (biblioteca).

## Segurança, sem fingir
- O dsh **lê qualquer ficheiro** do utilizador: o sandbox (workspace-write) só trava escrita. Desde 30/10 a **guarda do
  plugin `dsh-bora`** também barra a leitura e a escrita de segredos pelas ferramentas `read`, `grep`, `pwsh` e `bash`,
  mas lê o TEXTO do comando: quem o esconde (junta letras, codifica) pode escapar. Por isso o sandbox e as regras
  escritas continuam por baixo. O dsh também tem `bash`/PowerShell.
- A ponte do Telegram dá a quem controlar o Telegram do Danilo a mesma força que ele tem no dsh: por isso só aceita o
  chat id dele, em conversa privada, e redige segredos nas respostas. Se o telemóvel dele for comprometido, desligar
  a ponte (`/desligar` ou tecla no DIPSY) e revogar o bot no BotFather.
- **Supabase com escrita e acesso total sem validade (decisão do Danilo, 30/10):** o token está em
  `.supabase-token.env` e o dsh corre como o utilizador, por isso consegue lê-lo; o que o protege são as regras escritas,
  não uma tranca. A Kilo e o Gemini grátis podem guardar o que lhes chega. O MCP não expõe `pause_project` nem
  segredos das Edge Functions, mas o token, usado por fora do MCP, pode tudo o que a organização pode.
- Mitigações reais: modelo pago sem chave, Gmail sem permissão de enviar, tokens só com permissão do utilizador, plugins
  só por cópia de commit auditado.
- **Limites honestos do acesso total (08/11):** o proxy vê o domínio e os bytes, não o conteúdo do HTTPS (sem certificados
  falsos); o corte de uploads é por tamanho (mais de 1 MB por ligação nas categorias de leitura). A guarda continua a ler o
  TEXTO do comando: quem o esconder escapa à pergunta, e um programa que ignore `HTTPS_PROXY` sai sem registo (por isso o
  sandbox de escrita e as regras escritas continuam por baixo). O "sim" é assinado pela ponte (HMAC com uma chave que a guarda
  não deixa o Dipsy ler) e vale uma vez, para a chamada exata (hash do nome e dos argumentos).
- Telemetria do dsh: modo `FEEDBACK_ONLY` para `dsh-otel-collector.deepseeksvc.com`.

## Atualizar
```bash
npm i -g @deepseek-ai/dsh@latest
```
Depois correr o `DSH-MISSAO.cmd` (em `~/.dsh/lancadores-antigos`) com uma tarefa pequena. Plugins: `dsh plugin --profile lab add file:<pasta>` (nunca direto no
`headless`).

## Falta para ser igual ou melhor que o Claude Code (revisto 08/11, missão m3)
- **Conector do Conselho** (`go_conselho`): falta a senha do Conselho em `~/.dsh/secrets/conselho.token`; com ela é um bloco
  `mcp-conselho` (streamable-http, `https://conselho.srv1786862.hstgr.cloud`) igual ao do Córtex.
- **Chrome** (`dsh-browser` por compilar): por agora `passar_ao_claude_code`.
- **Porteiro da VPS:** a 08/11 uma resposta de ~11 mil tokens (1 a 4000, 190 s) passou inteira pelo perfil claude-dipsy, por
  isso o tecto antigo de 8000 já não corta; não se confirmou no código (a trava do modo automático barrou o SSH à VPS na
  sessão m3). Falta também pôr as respostas em fluxo contínuo no `ia_gastos` (essa de 190 s não ficou registada).
- **Rede na shell do Dipsy:** o TLS do Windows (Schannel) não funciona no sandbox do dsh: `curl.exe` dá
  `SEC_E_NO_CREDENTIALS` e o `Invoke-WebRequest` "ligação fechada". O PowerShell 5.1 ignora o `HTTPS_PROXY` (a guarda barra
  o `Invoke-WebRequest` sem `-Proxy`). Na shell, a web faz-se por `python`/`node` (`NODE_USE_ENV_PROXY=1` nos lançadores).
- O corte aos 4.000 caracteres do gateway do Hermes; controlo remoto (login do `claude`, ver `remote-control-duas-sessoes`);
  o Read barrado nos executores `claude -p`; o motor grátis erra contas (31/10 disse 228 tabelas, eram 433).
Voz (31/10): com < 1,5 GB livres vai direto ao Gemini; o whisper local deste PC levou 76 s e errou com 1,55 GB livres.
Armadilha (31/10): o lab apanhou um erro de esquema (`items.required` não existe no DSL do `dsh-tools`) que DESLIGOU o
`dsh-bora` inteiro, e com ele a guarda; validar os esquemas antes de promover (carregar o `index.js` com o `dsh-tools` real)
e o `pnpm add` do mesmo `file:` com a mesma versão não copia nada: copiar à mão para cada perfil (apagar e copiar, para
não partilhar o inode entre lab e headless).
