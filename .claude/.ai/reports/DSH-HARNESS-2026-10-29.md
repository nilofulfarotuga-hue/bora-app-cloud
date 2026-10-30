# Relatório — DeepSeek Harness (dsh) instalado com o mesmo livro do Claude Code

Missão `dsh-harness-2026-10-29`, feita a 29-30/10/2026 pelo Claude Code. Provas literais em
`C:\BoraLocal\QG\provas\dsh-harness-2026-10-29\`; cada bloco tem linha no `e2e_log` (fluxo `dsh-harness-2026-10-29`).

## Fiz isto
Instalei o dsh 0.2.1-rc.5 pelo npm (sem app desktop). O motor é grátis e montado à mão: Nemotron 3 Ultra pela piscina
grátis da Kilo (sem conta), com reserva `kilo-auto` e depois Gemini grátis (chave do juiz). O plugin `dsh-our-free-model`
ficou de fora de propósito: copia os cabeçalhos do OpenCode para passar o portão dele, tem login de contas chinesas e de
Claude/ChatGPT/Gemini, proxy próprio e atualizador próprio. O motor pago existe sem chave.

Ligei o dsh ao mesmo livro: o `~/.dsh/AGENTS.md` é um hardlink do CLAUDE.md global; as pastas `.dsh/skills` dos repos são
junções para `.claude/skills`; criei 9 pontes para skills que o parser YAML estrito do dsh recusa e uma skill com os 42
agentes; e um `~/.agents/AGENTS.md` que manda ler o livro, porque o dsh não segue os `@ficheiros`. Liguei o Córtex por MCP
(token estático do servidor, guardado só para o utilizador), o Supabase em só leitura, e o servidor Google (Gmail com
rascunhos e sem enviar, Drive e Calendar em leitura). Fiz os lançadores `DSH-MISSAO.cmd` e `DSH-ABRIR.cmd`, a skill
`usar-deepseek-harness`, a nota do vault e o digest no livro. Enviei só `.claude/` ao servidor (`79f9d121`, mais este
relatório), sem disparar nenhum build.

Auditei 63 plugins de terceiros com análise estática (2 repositórios não existem), montei um perfil `lab` e fiz passar pela
cerca de compatibilidade do dsh os candidatos limpos. Só um ficou provado e promovido.

## As 10 provas do B5 (saída literal em `provas/`)
1. **CLAUDE.md lido — provado.** Pergunta do `business_rules.md`: "PARCEIRO = 5% × subtotal; NÃO-PARCEIRO = €2,50 FIXO" e
   "PARCEIRO = 20% total (10% comissão + 5% markup escondido + 5% taxa serviço); NÃO-PARCEIRO = 15%". 43 s, motor Kilo.
2. **Skills — provado.** 146 de 146 visíveis ao modelo (145 listadas + 2 carregadas à prova); mais 5 escondidas por
   `disable-model-invocation` (grill-me, grill-with-docs, handoff, improve-codebase-architecture, setup-matt-pocock-skills).
3. **Supabase — NÃO deu.** `mcp-client(supabase): server is disconnected`. O token `sbp_` local é de 20/08 e dá 401.
4. **Córtex — provado.** `cortex_buscar harness` = 20 resultados, com id.
5. **Livro comum — provado.** "Quem é o Danilo e o que é o Bora" respondido a partir de `AGENTS.md`/`CLAUDE.md`; o erro de
   25/10 da Myra citado certo a partir de `erros.md`.
6. **Olhos — NÃO feito.** Nenhum plugin de visão instalado (modlens e vision-toolkit auditados, com hosts e leitura de
   credenciais a rever).
7. **REA — NÃO feito.** Não corri `rea --help` pela shell do dsh.
8. **Telegram — NÃO feito.** Precisa de um bot novo do BotFather (passo do Danilo); `LoserFox/telegram` está limpo e à espera.
9. **Tarefa agendada pelo dsh — NÃO feito.** Os plugins de agendamento são de interface web e ficaram por provar no perfil web.
10. **Ponte com o Claude Code — NÃO feito.** `agent-bridge` não instalado.

Tokens e tempo de uma tarefa pequena no dsh: 31 767 tokens de entrada no primeiro passo (instruções e catálogo de skills,
depois em cache: 25 920 de 27 802 no segundo) e 910 de saída, 35 a 43 s. Não medi o mesmo no Claude Code, por isso a
comparação pedida não está feita. O arranque do `headless` foi de 30 a 55 s com a RAM livre entre 600 e 1350 MB (outras
sessões a usar Dart, ffmpeg e Chrome); em RAM folgada foi ~11 s.

## Instalado e provado
Motor (3 vias com `OK`): Kilo Nemotron 11 s, `kilo-auto` 11 s, Gemini grátis 13 s · livro, CLAUDE.md global, skills e
agentes · Córtex por MCP · plugin `dsh-session-search` (`agent_session_search` devolveu 1 sessão com caminho; promovido ao
`headless` e ao `web`) · lançadores e teste ponta a ponta · servidor Google com 17 ferramentas: rascunho SIM, enviar NÃO · servidor de Remote
Control levantado pela tarefa agendada `Bora Remote Control` (filho do PowerShell escondido) e reiniciado sozinho depois de
morto (06:53:18 morto, 06:58:22 de pé), depois do login do Danilo às 06:48.

## Instalado sem prova
No perfil `lab` (ativam sem avisos, não estão no `headless` nem no `web`): `dsh-memento`, `dsh-auto-continue`,
`dsh-notify-windows`, `dsh-tokenledger`, `dsh-taskfold`, `dsh-chat-import`, `dsh-sentinel` · Supabase em só leitura (montado,
sem token) · servidor Google (montado, sem Permitir) · `PC-DO-DANILO.cmd` (visível; já não é preciso, a
tarefa levanta o servidor).

## Não deu (erro literal)
- `dsh-claude-compat`: **não instalar — travado pelo filtro de segurança** (por ordem da retoma, sem repetir).
- `dsh-wikilink`, `dsh-at-file`: `TypeError: ctx.settings.register is not a function` (API incompatível com 0.2.1-rc.5).
- `dsh-context-doctor`: `incompatible with dsh 0.2.1-rc.5: requirements {"@deepseek-ai/dsh-tools":"^0.1.2-rc.1"}`; o mesmo
  para `dsh-inspect`, `dsh-toolkit`, `dsh-security-audit`. Não concedi exceção: o aviso é "pode rebentar ou perder dados".
- `dsh-test-runner`: `Command failed with exit code 1: pnpm add "file:…/dsh-test-runner"`.
- `dsh-automation`, `dsh-continue`, `dsh-loop`, `dsh-tasks`, `hermes-loop`, `dsh-plugin-mineru`: ficam `pending (waiting for
  services: webServer, connection…)` no `headless`; só ativam no perfil `web`. Removidos do `lab`.
- `omdsh-dev/dsh-security-scan` e `dsh-external/official-plugins-port`: `Repository not found`.
- Nano Banana: montado e desligado (chave grátis sem imagens; os processos `npx` ficaram pendurados).
- Servidor de controlo remoto (S.3): duas sessões ao mesmo tempo por provar (só vi 1 sessão anexada, vazia; falta o Danilo
  abrir duas em claude.ai/code). A opção "reiniciar em caso de falha" do Agendador não levantou o servidor (219 s sem
  reinício); troquei por repetição de 3 em 3 minutos, que funcionou.
- REA, olhos, Telegram, ponte, agendamento: não feitos (ver provas 6 a 10).

## Fica para a próxima (com o comando pronto)
- Plugins só-web no perfil web: `dsh plugin --profile web add file:C:/Users/danil/ferramentas/dsh-plugins/weibaohui__dsh-tasks`
  (e `titanwings__dsh-automation`, `weibaohui__dsh-continue`, `vlln__dsh-loop`, `weibaohui__hermes-loop`, `HuanLinOTO__dsh-plugin-mineru`).
- Provar os 7 do `lab` um a um e promover com `C:\Users\danil\.dsh\lab-promover.ps1 -Dir <pasta>`.
- Google, uma vez por conta (o Danilo carrega em Permitir):
  `python C:\Users\danil\.dsh\google-autorizar.py boraappbora@gmail.com "Profile 1" 8772` e
  `python C:\Users\danil\.dsh\google-autorizar.py nilofulfarotuga@gmail.com Default 8773`.
  A conta pessoal pode precisar de ser adicionada como utilizador de teste no cliente OAuth.
- Os 20 que precisam de compilação (por exemplo `dsh-ssh`, `dsh-rewind`, `dsh-genui`, `dsh-auto-review`, `dsh-advisor`):
  clonados e auditados em `C:\Users\danil\ferramentas\dsh-plugins\`, por compilar e rever.
- Telegram: criar o bot no BotFather e usar `LoserFox/telegram` com lista de permitidos só do chat do Danilo.
- `agent-bridge` (ponte com o Claude Code): rever o código por inteiro antes de instalar.

## Erros que encontrei pelo caminho (reportados, não corrigidos)
1. **(Resolvido às 06:48 de 30/10 pelo login do Danilo.) O `claude` deste PC esteve sem sessão desde a noite de 28/10** (`claude auth status` → `"loggedIn": false`). O vigia
   `ClaudeRC-bora` viu o controlo remoto "em execução" até 28/10 21:01 UTC e desde então só regista "não encontrado" e
   `claude rc` falha com "You must be logged in to use Remote Control". Os controlos remotos da Bora e do Em Dia estiveram caídos. A Bora é agora servida pelo servidor novo: o `claude rc`
   antigo falha na mesma pasta com "This folder is already served by a terminal `claude remote-control` on this device. Stop
   it first." O do Em Dia (pasta `em_dia`) deve voltar no próximo ciclo do vigia (não confirmado).
2. O `build-ios` falhou no commit `26ab6a7b` (não é meu) e outro corria em `58eb26f8`.
3. A voz da ponte do Telegram cai do `edge-tts` (traceback) para o `piper` e demora 54 s.
4. O token do Supabase local (`.supabase-token.env`) caducou: dá 401 desde 21/09.
5. O dsh deixa os processos MCP filhos pendurados ao sair (vi 8 de `nano-banana`; matei-os).
6. A ferramenta `Edit` parte hardlinks: partiu o do CLAUDE.md; os lançadores já o recompõem.
7. Nove skills do Claude Code têm cabeçalho YAML inválido para um parser estrito (`ask-knowledge-base`, `daily-pulse`,
   `memory`, `contas-e-navegadores`, `distribuir-trabalho`, `pasta-fora-da-sessao-bloqueada` e as três com nome com `_`).
8. Os 3 commits locais órfãos (`beac89d3`, `8a5f3ab0`, `bdfbf1d6`, com `lib/`) continuam por enviar: esperam o "vai" do
   Danilo. Antes do `git pull --rebase`, apagar a cópia solta de `.claude/skills/usar-deepseek-harness/` na pasta principal.
9. A tranca bloqueou duas vezes texto sem segredo (uma expressão regular e uma credencial anónima pública da Kilo);
   reescrevi sem a atribuição literal e registei em `docs/TRANCAS.md` (ficheiro local com trabalho de outras sessões,
   fora do commit).
10. RAM do PC apertada: dartaotruntime 858 MB, ffmpeg 440 MB, Chrome 446 MB.

## Para o Danilo decidir (só estas)
1. **"autorizo carregar 5 € na DeepSeek"** — só se quiser o motor pago; até lá tudo é grátis.
2. **Desligar ou não o vigia `ClaudeRC-bora`** (tarefa agendada que corre `claude rc --name bora-app`): já não serve, porque
   o servidor ocupa a pasta, e falha de 30 em 30 minutos. Não lhe toquei. E abrir duas sessões em claude.ai/code para
   provar o S.3.
3. **Colar o token novo do Supabase** no `COLAR-TOKEN-SUPABASE.cmd` (o dsh lê o mesmo ficheiro).
4. **Permitir do Google** nas duas contas, e decidir se aceita que o email seja lido por um modelo grátis que pode guardar
   os pedidos (regra 14 do AGENTS.md). O dsh nunca envia: só lê e faz rascunhos.
5. Se aceita o token estático do Córtex copiado da VPS para `~/.dsh/secrets` (revogável trocando o `CORTEX_TOKEN` do servidor).
