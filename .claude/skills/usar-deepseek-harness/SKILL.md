---
name: usar-deepseek-harness
description: "Como usar o DeepSeek Harness (dsh) no PC do Danilo: lançar uma tarefa ou uma conversa, que motor grátis usa e os seus limites, a frase que liga o motor pago, o que o dsh sabe do Claude Code (CLAUDE.md, skills, livro, Córtex, Google), que plugins estão provados, o que ele NÃO pode fazer e como se atualiza. Usar sempre que o Danilo falar em dsh, harness, Dipsy ou pedir uma tarefa para o motor grátis."
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
- **À mão (PowerShell):** primeiro `[Environment]::SetEnvironmentVariable('KILO_ANON_KEY', (Get-Content "$HOME\.dsh\kilo-anonima.txt" -Raw).Trim(), 'Process')`,
  depois `dsh --profile headless "tarefa"`. Os lançadores fazem isto sozinhos.
- Tudo vive em `~/.dsh` (fora do repo): `cordis.patch.yml` (motores e MCP), `secrets/` (tokens, só o utilizador lê),
  `skills-ponte/` (pontes das skills que o dsh recusa), `AGENTS.md` (hardlink do CLAUDE.md global; o `Edit` parte-o, os
  lançadores voltam a ligá-lo), `profiles/lab` (onde cada plugin entra primeiro).
- O arranque do `headless` demorou 30 a 55 s nas últimas medições, com a RAM livre entre 600 e 1350 MB por causa de outras
  sessões. Em RAM folgada foi ~11 s. O dsh também deixa processos MCP filhos pendurados ao sair.

## Motor (o que é grátis e os limites)
- Padrão: **Nemotron 3 Ultra** pela piscina grátis da **Kilo** (sem conta). Reserva 1: `kilo-auto/free`. Reserva 2: **Gemini
  grátis** (chave do juiz, sem faturação: 20 pedidos por dia e por modelo). Os lançadores tentam por esta ordem.
- ⚠️ **A Kilo pode guardar os pedidos.** O Gemini grátis também pode treinar com eles. Nunca meter segredos nem chaves.
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
| Hooks e tranca `bora-tranca` | **Guarda própria** (plugin nosso `dsh-bora`, `ctx.tools.guard`): barra push, apagar em massa, segredos, SQL perigoso, escrita nas regras/Juiz/CI, funções de dinheiro; 121 testes offline | automática antes de cada ferramenta; registo em `~/.dsh/guarda.log`. **Provado a 30/10:** `git push`, ler um segredo e `DELETE FROM` foram barrados no dsh. Não tem os hooks do Claude Code (só isto) |
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
| Telemetria e saídas de rede | telemetria oficial DESLIGADA (patch comum e do web); guarda de `web_fetch`/`web_search` | **Medido a 30/10:** num pedido com Córtex, Supabase e agenda só 3 ligações (Kilo, Supabase, Córtex); o collector da DeepSeek não apareceu |
| Chrome (extensão) | nada (`dsh-browser` por compilar) | usar o Claude Code |

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
3. Dinheiro, dispatch, carteira, RLS, push e publicação **nunca** se delegam ao dsh: ele prepara e não aplica sem o
   "autorizo" do Danilo. Desde 30/10 o dsh ESCREVE na base (ordem do Danilo), com as regras de `~/.agents/AGENTS.md`:
   nunca apagar dados de produção, nunca reescrever histórico git publicado, pedidos só por `ops_*`, correção só com
   backup, dados pessoais de clientes só quando a tarefa precisar e nunca em massa, segredos nunca.
4. Engenharia reversa **só** no nosso APK (`pt.boraapp.bora`) e nos nossos sites; apps de terceiros só para comparar o que
   o utilizador vê (regra do Danilo de 13/10).
5. Sem app desktop do Harness. Só `dsh` por npm. Não ligar o encaminhamento local (portas 18899/18900) nem relé de rede.
6. Email para fora sai SEMPRE da conta Bora, e nunca pelo dsh (não tem a permissão de enviar).

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
- Telemetria do dsh: modo `FEEDBACK_ONLY` para `dsh-otel-collector.deepseeksvc.com`.

## Atualizar
```bash
npm i -g @deepseek-ai/dsh@latest
```
Depois correr o `DSH-MISSAO.cmd` (em `~/.dsh/lancadores-antigos`) com uma tarefa pequena. Plugins: `dsh plugin --profile lab add file:<pasta>` (nunca direto no
`headless`).

## Falta para ser igual ou melhor que o Claude Code
Conector do Conselho; a prova da voz com um áudio REAL do Danilo; o corte aos 4.000 caracteres do gateway do Hermes; controlo remoto (login do
`claude`, ver `remote-control-duas-sessoes`); os hooks do Claude Code (o dsh só tem a guarda do plugin `dsh-bora`).
