# Inventário dos projetos do Danilo

> Fase 0 da missão `modo-automatico-seguro-2026-11-05`. Feito por leitura das pastas, do Git e do
> Supabase a 05/11/2026. Nada foi mudado para fazer este inventário.
> Quando aparecer um projeto novo, acrescenta-se aqui uma entrada.

## O que vale em todas as pastas

- **Tranca `bora-mods`:** carregada pela variável de utilizador `CLAUDE_CODE_PLUGIN_DIRS`, a partir de
  `bora_app\.claude\plugins\bora-mods`. Corre em todas as sessões, em qualquer pasta. Decide por
  código e protege-se a si própria: ganchos, settings, CI e o próprio plugin só mudam pela mão do Danilo.
- **Ganchos globais** (`~/.claude/settings.json`): só dois, de arranque (`SessionStart`). Não havia
  nenhum `PreToolUse` global antes desta missão.
- **Ganchos do projeto** (`protege-dinheiro.sh`, `protege-banco.sh`, `git-guardrails`): só existem no
  `bora_app` e nas suas cópias. Os outros projetos só têm a tranca.
- **Skills:** `~/.claude/skills` tem as pastas reais, válidas em qualquer projeto. O `dsh` lê as mesmas.
- **Modo sem caixas:** `skipDangerousModePermissionPrompt` ligado; escolhe-se por sessão na app.
- **Bases de dados de produção:** Bora `ojykpzwqrtusfeakzrna` e Em Dia `tgdmgtmknbwhcqoxtjbs`.

## Projetos ativos

### bora_app (o app Bora)
- Pasta: `C:\BoraLocal\projetosflutter\bora_app`. Repositório: `nilofulfarotuga-hue/bora-app-cloud`.
- Ramo principal: `autonomous-night-2026-04-29`. Um envio para lá publica Android, web e iPhone.
- Tecnologia: Flutter, Supabase, Edge Functions, painel admin.
- Regras: `CLAUDE.md`, `AGENTS.md`, `PADRAO_BORA.md`, `.claude/skills`, ganchos, Juiz, tranca.
- CI: `build_android`, `build_ios`, `build_web_deploy`, `build_ios_emdia`, `olho_golden`, `e2e-web`,
  `testlab_robo`, `dart`. **Nenhum corre analyze e testes em cada pedido de revisão** (o `dart` só
  corre no ramo `main`, que não é o de trabalho; o `build_ios` corre em revisões mas só se mexerem em
  `lib`, `ios` ou `pubspec`).
- Estado: a pasta principal está 439 commits atrás do servidor e tem 443 ficheiros por gravar. Os
  ganchos correm dela. O trabalho faz-se em pastas `wt-*`: 32 em `C:\BoraLocal`, 60 worktrees no total.

### em_dia (app Em Dia)
- Pasta: `projetosflutter\em_dia`. Repositório: `em-dia-app`. Ramo principal: `main`.
- Flutter e Supabase. Tem `CLAUDE.md` e `AGENTS.md`. Cinco fluxos de CI; o envio para `main` publica.
- Estado: no ramo `redes-pessoas-2026-09-29`, 24 ficheiros por gravar, 3 commits à frente e 1 atrás.

### BoraStudio (o filme)
- Pasta: `C:\BoraLocal\BoraStudio`. Repositório: `borastudio`, ramo `master`.
- Python e SQLite (`producao.db`). Tem `AGENTS.md` e `.claude/skills`. Sem CI, sem testes de revisão.
- Estado: 1557 ficheiros por gravar e 284 commits por enviar. Sete tarefas agendadas dependem dele.
- Intocável: `producao.db`, canon, bíblias, clipes e vozes.

### bora-site (site do Bora)
- Pasta: `projetosflutter\bora-site`. Repositório: `bora-site`. HTML, publica por `deploy-cloudflare.sh`.
- Sem CI. Estado: no ramo `fechar-bora-motorista-2026-11-04`, 14 ficheiros por gravar.

### jai-site (site do Jai)
- Pasta: `projetosflutter\jai-site`. **Sem repositório remoto.** Ramo `main`. HTML, publica por `deploy.ps1`.
- Sem CI possível enquanto não tiver GitHub. Estado: 8 ficheiros por gravar. Pessoa real e pública.
- Intocável: verificação do Search Console, `MARCOS_*.md`, `i18n/`.

### guarda-fc-site (site do clube)
- Pasta: `projetosflutter\guarda-fc-site`. Repositório: `guarda-fc-site`. HTML, Cloudflare.
- Sete fluxos de CI, incluindo tarefas agendadas e atualizações automáticas.
- Estado: no ramo `loja-2026-09-14`, 7 ficheiros por gravar. Cópias de trabalho: `-b6`, `-fotos`,
  `-trabalho`, `-v7` (esta última com repositório próprio).
- Intocável: `provas/`, `media/bruto/`, `agentes/`.

### Sites de clientes e demonstrações
- `goola-site`, `leonidas-site`, `sites\misternavalha`: HTML, Cloudflare, sem repositório remoto.
- `partsflow_demo`: Node e Vercel, repositório `partsflow-demo`. `florchic_demo`: Node e Vercel, sem remoto.
- `propostas`: repositório `propostas`.

### Cofre Obsidian
- Pasta: `C:\Users\danil\Desktop\Bora` (junção para `C:\BoraLocal\Bora`). Sem Git.
- Fonte das regras de negócio. **Ler, não reorganizar.** Teste possível: ligações e estrutura.

### QG e orquestração
- `C:\BoraLocal\QG` (junção no Ambiente de Trabalho): mapa, vigias e radares. Sem Git.
- `Desktop\produtividade-ia` e `Desktop\ferramentas`: ponte do Hermes e MCP. Não mover.

## Cópias e arquivo (não são projetos)

`bora-envio-botao`, `bora-envio-sm`, `bora-f2-fecho`, `bora-melhorias` (cópias do bora_app),
`em_dia_wt_medir`, `delivery_kit_codester`, `radar-jai-ANTIGO-NAO-USAR`, `radar-jai-vps-copia`,
`gibi-tuca` (vazia), `prospecao-clubes`, `provas`, `_archive`, `_backup_knowledge_2026-05-31`, `_wt-prod`.

## Riscos encontrados

- O comando `git worktree add -b ramo origin/principal` deixa o ramo novo a seguir o ramo de
  produção. Um `git push` sem destino pode ir parar lá. Criar sempre com `--no-track`.
- A aprovação automática da tranca passa por cima do "não" de outros ganchos. Provado com leitura de
  `.env` e com um envio para `main`: ver `docs/propostas/modo-automatico/LEIA.md`. Corrigido a 06/11.
- O `git-guardrails` do bora_app recusava enviar para qualquer ramo que não fosse o principal, o que
  impedia o ramo de ensaio. Corrigido a 05/11.
- `gh` no PC não tem a permissão `workflow`: pode impedir o envio de um ficheiro de CI.
- Só têm GitHub, logo só podem ter CI: bora_app, em_dia, BoraStudio, bora-site, guarda-fc-site,
  partsflow_demo, propostas. Os restantes só têm testes locais.
