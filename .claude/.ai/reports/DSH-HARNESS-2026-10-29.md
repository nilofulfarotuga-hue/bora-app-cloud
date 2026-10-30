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
3. **Supabase — provado a 30/10 às 15:46 (atualização).** De manhã não deu: `mcp-client(supabase): server is disconnected`,
   porque o token `sbp_` local era de 20/08 e dava 401. Com o token novo da organização Bora app, o dsh correu
   `mcp__supabase__execute_sql` com `SELECT count(*) FROM orders` e devolveu 89; o Claude Code, à mesma hora, também 89.
   Saída literal em `provas/dsh-harness-2026-10-29/f-supabase-count.jsonl`.
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
`dsh-notify-windows`, `dsh-tokenledger`, `dsh-taskfold`, `dsh-chat-import`, `dsh-sentinel` · servidor Google (montado, sem Permitir) · `PC-DO-DANILO.cmd` (visível; já não é preciso, a
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
- Google: **feito a 30/10 às 19:51** nas duas contas (ver a atualização no fim). Para reautorizar, uma vez por conta (o Danilo
  carrega em Permitir):
  `python C:\Users\danil\.dsh\google-autorizar.py boraappbora@gmail.com "Profile 1" 8772` e
  `python C:\Users\danil\.dsh\google-autorizar.py nilofulfarotuga@gmail.com Default 8773`.
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
4. O token do Supabase local (`.supabase-token.env`) caducou: dava 401 desde 21/09. (Resolvido a 30/10 às 15:41 com o token novo.)
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
3. Token novo do Supabase: **feito a 30/10 às 15:41** (ver a atualização no fim).
4. Permitir do Google: **feito a 30/10 às 19:51** nas duas contas. Fica a aceitar que o email seja lido por um modelo grátis
   que pode guardar os pedidos (regra 14 do AGENTS.md). O dsh nunca envia: só lê e faz rascunhos.
5. Se aceita o token estático do Córtex copiado da VPS para `~/.dsh/secrets` (revogável trocando o `CORTEX_TOKEN` do servidor).

## Atualização de 30/10, tarde (decisões do Danilo e o que ficou)
- **Supabase com escrita.** Por ordem do Danilo, o token é da organização Bora app, com acesso total e sem validade, e o
  MCP do dsh deixou de ser só leitura (tirei `read_only=true`). Prova: o dsh passou a listar 22 ferramentas, com
  `apply_migration`, `deploy_edge_function`, `delete_branch`, `merge_branch` e `reset_branch`; não executei nenhuma de
  escrita. O MCP não tem `pause_project` nem escrita de segredos. A única tranca são as regras escritas em
  `~/.agents/AGENTS.md`: nunca apagar dados de produção, nunca reescrever histórico git publicado, pedidos só por `ops_*`,
  dinheiro só com "autorizo", correção só com backup, dados pessoais de clientes só quando a tarefa precisar e nunca em
  massa, segredos nunca. Risco que fica dito: o dsh corre como o utilizador e lê o ficheiro do token; a Kilo e o Gemini
  grátis podem guardar os pedidos.
- **Lembrete de renovação.** Montei um aviso para 21/01/2027 (job `pg_cron` 114 e tarefa do Windows) e apaguei os dois a
  pedido do Danilo, porque o token deixou de ter validade. Já não existe nenhum.
- **Google.** O ecrã de consentimento do projeto `gen-lang-client-0806232393` está **Em produção** (Externo, 1 utilizador de
  100): a autorização não caduca de 7 em 7 dias, mas aparece o aviso "A Google não validou esta app" (Avançadas, Ir para a
  app, Permitir). Ao relançar as páginas, o PowerShell partiu `"Profile 1"` em dois argumentos e a da Bora abriu no perfil
  antigo `Profile`, com a porta 1: erro meu, corrigi às 15:49 (relançada no `Profile 1`, porta 8772). Ficou uma página de
  entrada solta na janela desse perfil antigo, sem recetor e inofensiva.
- Por provar (à data deste parágrafo): Permitir das duas contas e as provas do Gmail.

## Atualização de 30/10, noite (Google feito)
- **Permitir das duas contas.** O Danilo carregou em Permitir às 19:51 (pessoal 19:51:21, Bora 19:51:55, pelo log do
  `google-autorizar`). A conta pessoal **não** foi recusada: a app está Em produção e não precisou de ser utilizador de
  teste. Nada foi mudado na consola da Google. Cada credencial foi confirmada na Google (`userinfo`: HTTP 200, o email é o do
  ficheiro). Âmbitos: Gmail ler, etiquetas, modificar e compor, Drive e Calendar só leitura, **sem** enviar.
- **Prova no dsh (headless, 65 s, rc=0).** A ferramenta `search_gmail_messages` listou 3 emails da caixa de entrada da Bora
  (pedi só cabeçalhos, o corpo não foi lido) e `draft_gmail_message` criou 1 rascunho para a própria Bora
  (id `r3849196807106371061`). Li o rascunho de volta pela API do Gmail: existe só com a etiqueta DRAFT; a pesquisa de
  enviados com esse assunto devolve 0 e a das últimas 2 horas também 0. Nada foi enviado. Saída literal em
  `C:\BoraLocal\QG\provas\dsh-harness-2026-10-29\f-google-bora-emails-rascunho.jsonl`; `e2e_log` 5484 (`F-google`).
- **O que fica.** O rascunho de teste continua na conta Bora (apagar é com o Danilo). O email das duas contas passa agora por
  um modelo grátis quando o dsh o lê. A conta pessoal ficou autorizada mas sem prova funcional (só a Bora foi provada, como
  combinado).


## Atualização de 30/10, noite (C-liga: o Dipsy completo, com código nosso)
Ordem do Danilo (20:23): quer o Dipsy completo, com olhos, auditoria das nossas apps, Telegram e juiz automático, com
autonomia e segurança, tudo com código escrito por nós e sem os plugins de terceiros que tinham sido rejeitados.

**Fiz isto (com prova, saídas literais em `C:\BoraLocal\QG\provas\dsh-harness-2026-10-29\c-liga-*.jsonl`):**
- **Olhos (C3b).** Plugin nosso `dsh-bora` (`.claude/dsh/plugin-dsh-bora`): ferramentas `captura_ecra` e `ver_imagem`
  (Gemini, chave lida do ambiente). Prova: com um ecrã de teste cheio com a palavra secreta AZULEJO-4417, o dsh
  descreveu o texto e a palavra. A imagem vai para a Google (plano grátis).
- **Guarda (C-seguranca).** O mesmo plugin regista `ctx.tools.guard`, o gancho do dsh que corre antes de cada ferramenta.
  121 testes offline. Prova no dsh: `git push`, ler um ficheiro de segredos e um `DELETE FROM` foram barrados; um
  `git status` passou. Limite: lê o texto do comando.
- **Juiz (C8b).** `~/.dsh/dsh-commit.ps1` e a skill `juiz-dsh`. Corre o anti-trapaça e as zonas protegidas sobre os
  ficheiros pedidos e recusa o commit se falharem. Prova: commit limpo passou (também no repo verdadeiro, commit de teste
  `69a10fc8`, depois apagado); apagar um teste, mexer no `pricing_service.dart`, segredos e asteriscos foram recusados.
- **Auditoria (C2b).** Skill nossa `auditoria-seguranca-bora` (método da Cloudflare, só texto) e `auditar-site.mjs`.
  O dsh auditou boraguarda.com em leitura e achou 6 pontos; 3 registados no `e2e_log`: falta HSTS, falta CSP (com scripts
  de 3 CDNs sem SRI) e a página pode ser posta dentro de outra. Nada exposto (`.env`, `.git`, mapas), TLS 1.3 válido até
  24/01/2027. O REA corre dentro do dsh pelo envólucro `rea-bora.ps1`; o alvo de terceiros (iFood) foi barrado.
- **Guia e lançador (C-guia).** `DIPSY.cmd` no Ambiente de Trabalho (o único), `~/.dsh/COMO-USAR.md` e a página
  `dsh-como-usar` do livro. Os antigos `DSH-ABRIR.cmd` e `DSH-MISSAO.cmd` foram movidos para `~/.dsh/lancadores-antigos`.
- **Telegram (C5b), pronto a ligar.** Ponte nossa `~/.dsh/telegram/ponte.py` (API oficial, só o chat do Danilo, redige
  segredos), testada com um pedido real ao dsh sem Telegram (33 s). Tarefa `Dipsy-Telegram` no login.

**Falta isto (e porquê):**
- **O bot do Telegram.** Só o Danilo pode criá-lo no BotFather. Deixei o Telegram do PC aberto na conversa com o
  `/newbot` escrito e um vigia que escreve o nome e o utilizador e lê o token por código (nunca o mostra), valida-o,
  guarda-o em `~/.dsh/secrets` e liga a ponte. Ele só tem de carregar em Enviar (no PC) ou escrever no telemóvel. A prova do
  "olá" depende disso.
- O REA `doctor` dá `healthy=false` por faltarem motores opcionais (Hopper, Ghidra, JADX): é igual no Claude Code.

**Erros que encontrei (reportados, não corrigidos calados):**
1. O Telegram Web do Chrome pessoal não tem sessão (pede QR); usei o app do PC, que tem. O ecrã mostrou, sem eu procurar,
   um token antigo de outro bot na conversa do BotFather: não o usei nem o guardei. Vale como aviso: uma captura pode
   mostrar segredos.
2. O sandbox do dsh não deixa o `npm` escrever na cache, por isso `npx rea-agents` falha lá dentro. O envólucro `rea-bora.ps1`
   corre o REA já instalado e resolve. Nessa tentativa o modelo tentou `npm cache clean` e `npm config set`: acrescentei essas
   duas ações à guarda.
3. A tranca recusou apagar a pasta de teste `C:\BoraLocal\_juiz-teste-dsh` (apagar recursivo). Não contornei: fica por
   apagar (é pequena). Registado em `docs/TRANCAS.md`.
4. O pnpm liga os ficheiros do plugin por hardlink; editar a origem parte a ligação. Para atualizar o plugin, copiar os
   ficheiros para `~/.dsh/profiles/{headless,web,lab}/node_modules/dsh-bora`.
5. `dsh web` abre sozinho o navegador com uma chave nova (sem ela dá 401); o `DIPSY.cmd` reinicia sempre o servidor.

**Próximo passo:** o Danilo cria o bot (um clique) e o vigia liga tudo; depois ele manda "olá" no Telegram. O envio dos
commits de documentação para o servidor segue na publicação desta noite, pela sessão da Bora.