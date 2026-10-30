---
name: usar-deepseek-harness
description: "Como usar o DeepSeek Harness (dsh) no PC do Danilo: lançar uma tarefa ou uma conversa, que motor grátis usa e os seus limites, a frase que liga o motor pago, o que o dsh sabe do Claude Code (CLAUDE.md, skills, livro, Córtex, Google), que plugins estão provados, o que ele NÃO pode fazer e como se atualiza. Usar sempre que o Danilo falar em dsh, harness, Dipsy ou pedir uma tarefa para o motor grátis."
---

# Usar o DeepSeek Harness (dsh)

O dsh é um segundo "Claude Code" do PC, feito pela DeepSeek (MIT, pré-lançamento: pode partir compatibilidade). O Danilo
pode mandar uma tarefa ao dsh em vez de ao Claude Code, com um motor GRÁTIS. Instalado a 29-30/10/2026 (missão
`dsh-harness-2026-10-29`), versão 0.2.1-rc.5.

## Como lançar
- **Tarefa sem conversa:** escrever a tarefa em `Desktop\Bora\prompt-dsh.md` e abrir `DSH-MISSAO.cmd` (parâmetro opcional:
  `bora_app`, `BoraStudio`, `jai-site`, `bora-site`; sem parâmetro = `bora_app`). A resposta fica em
  `Desktop\Bora\dsh-saidas\AAAA-MM-DD_HHMM.md`.
- **Conversar:** `DSH-ABRIR.cmd` e usar `http://127.0.0.1:3080` (só neste PC).
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
| Gmail, Drive, Calendar (conectores) | MCP `google` (workspace-mcp 2.2.1): Gmail leitura e **rascunhos, sem enviar**, Drive e Calendar só leitura | falta o Permitir de cada conta (`~/.dsh/google-autorizar.py`) |
| Nano Banana (MCP) | montado e DESLIGADO (chave grátis sem imagens) | `disabled: true` no patch |
| REA (≈300 ferramentas MCP) | NÃO como MCP; pela shell (`npx rea-agents`) | só no NOSSO APK e sites; comando não provado |
| Hooks e tranca `bora-tranca` | **NÃO tem** | a única tranca são as regras escritas em `~/.agents/AGENTS.md` (secção "Supabase com escrita") |
| Pesquisa nas sessões antigas | plugin `dsh-session-search` (dsh + Claude Code, só leitura) | `agent_session_search` — **provado** |
| Chrome (extensão) | nada ainda (`dsh-browser` por compilar) | usar o Claude Code |

## Plugins (auditados com análise estática; nada corre sem passar pelo perfil `lab`)
- **Provado e promovido (headless + web):** `Tieboyh/dsh-session-search` (sha na auditoria).
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

## Segurança, sem fingir
- O dsh **lê qualquer ficheiro** do utilizador: o fence só trava escrita. "Não ler `.env*`, `*.pem`, `~/.claude.json`…" está
  só escrito nas instruções, não é tranca. O dsh também tem `bash`/PowerShell.
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
Depois correr `DSH-MISSAO.cmd` com uma tarefa pequena. Plugins: `dsh plugin --profile lab add file:<pasta>` (nunca direto no
`headless`).

## Falta para ser igual ou melhor que o Claude Code
Permitir do Google nas duas contas; conector do Conselho; olhos (visão: nenhum plugin instalado);
Telegram (precisa de um bot novo do BotFather); controlo remoto (login do `claude`, ver `remote-control-duas-sessoes`);
tranca e hooks (o dsh não tem; só o Claude Code).
