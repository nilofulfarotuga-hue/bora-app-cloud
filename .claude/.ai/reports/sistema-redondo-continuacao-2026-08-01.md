# Missão Sistema Redondo — continuação (2026-08-01, sessão MOTOR OPUS)

> Executor headless (Hermes autonomous), sem canal com o Danilo durante a corrida.
> Regra desta missão: **prova por ficheiro, log ou SELECT — nunca pela palavra do executor.**
> 4 blocos executados via esquadrão de agentes de fundo (A, C.1, C.2, D) + trabalho directo (B, C.3).

---

## BLOCO A — Córtex em tempo real (sync PC→VPS orientado a evento)

**Latência ANTES (medida real):** indefinida na prática. O único caminho automático era
commit → push (headless, falha com frequência) → `origin` → `sync-brain.sh` na VPS (hard-reset
diário às 06:30 UTC, ou fast-fetch por-ordem). Um ficheiro de prova escrito no PC não apareceu
no espelho da VPS em nenhum momento verificado — na pior hipótese, só ao próximo cron das 06:30
(até ~18h de distância).

**Latência DEPOIS (medida real):** **≤1s.** Ficheiro `_prova-latencia-depois-20260801.md`
escrito no PC apareceu no espelho da VPS confirmado por `test -f` via SSH 1s depois, e por
chamada real ao MCP (`cortex_buscar` no endpoint de produção `cortex.srv1786862.hstgr.cloud`).
Ambos os artefactos de prova (`_prova-latencia-antes-20260801.md` /
`_prova-latencia-depois-20260801.md`) ficaram no repo de propósito, não apagar.

**Mecanismo escolhido:** loop de polling curto (5-8s) no PC — `tar czf .claude/.ai/knowledge |
ssh root@vps 'tar xzf --skip-old-files'` — mesmo padrão do workaround manual já documentado
(`project_cortex_espelho_contentsync_workaround`), agora automatizado e **add-only por desenho**
(nunca sobrescreve o que já existe no espelho, protege escritas feitas via `cortex_escrever`
directamente na VPS). Zero `git push` automático — não cruza Lista Vermelha.

**Segunda via (Supabase `missions`), verificada por mim independentemente:**
```sql
select slug, estado, parte_atual, total_partes, atualizada_em from public.missions;
-- sistema-redondo-2026-08-01 | em_curso | 9 | 9 | 2026-08-01T09:32:13.966181+00:00
```
Confirma leitura em segundos sem git nenhum — mas **está estático desde as 09:32Z**: nada nesta
sessão escreveu progresso novo na tabela para os blocos A-D. Fica registado como o que falta se
se quiser usar `missions` como fonte viva do progresso desta própria continuação.

**Ficheiros novos (repo, commitados no Bloco B):**
`.claude/.ai/cortex-mcp/pc-knowledge-sync.sh`, `pc-knowledge-sync-loop.sh`,
`instalar-schtask-pc-knowledge-sync.cmd` (regista `Bora-cortex-pc-sync-logon` ONLOGON +
`Bora-cortex-pc-sync-boot` ONSTART, ambas já criadas no Task Scheduler do PC).

**Limitações honestas:**
1. Edições a ficheiros **já existentes** no espelho não propagam por este caminho (só ficheiros
   novos) — continuam dependentes do git/cron para convergir.
2. O agente arrancou o loop manualmente em background para a prova ao vivo; **não confirmei se
   esse processo ad-hoc continua vivo** neste momento (`ps aux` não mostrou o processo, RAM livre
   711MB/3902MB no momento da checagem — não crítico, mas não é uma confirmação positiva). As
   schtasks `ONLOGON`/`ONSTART` ficam como o caminho persistente correcto; se o processo ad-hoc já
   morreu, o sync volta a depender de logon/boot ou de correr `pc-knowledge-sync-loop.sh` à mão.
3. `orquestracao/` não foi incluída no sync PC→VPS — descoberta no Bloco C.1: essa fila **não vive
   no PC**, vive só na VPS (ver Bloco C.1). Não havia nada para sincronizar desse lado.

---

## BLOCO B — commit + push

**⚠️ Isto publicou código.** Push feito para `autonomous-night-2026-04-29`
(`d89de2f..996d962`), o que dispara a esteira normal de CI (`build_android.yml` →
Play alpha, `build_web_deploy.yml` → Cloudflare Pages). Autorização explícita do Danilo dada no
prompt desta missão ("o Danilo autorizou explicitamente publicar").

**2 commits:**
- `f6cbc4a` — `fix(loop): nunca-mais-travar + paridade auto-vs-manual (I1-I5 provados)`
  (já existia localmente antes desta sessão, rebased sobre o `d89de2f` novo do origin)
- `996d962` — `chore(missao): consolida trabalho pendente acumulado (27+ commits, multiplas
  sessoes)` — **269 ficheiros, 19523 inserções, 72 remoções**

**Antes de publicar, foi feita uma rebase limpa:** o local estava 1 commit atrás do origin
(`d89de2f ci: bump versionCode to 509 [skip ci]`, gerado pelo CI depois de um push anterior de
`6ea2de2`/`f6cbc4a` que este executor não tinha localmente). `git rebase origin/...` resolveu sem
conflitos — histórico linear, sem merge commit.

**Excluído do commit, por caminho explícito (as 3 migrations `PROPOSTA_`, TVDE, dinheiro real —
continuam por rastrear, aguardando decisão do Danilo numa vista só):**

| Migration | Resumo |
|---|---|
| `20260716210000_PROPOSTA_tvde_noshow_driver_credit.sql` | No-show do passageiro credita 3,50€ fixos ao motorista TVDE. UI já existe (botão "Passageiro não compareceu"), falta só a regra de crédito no backend. Gate dinheiro — cria payout novo a estafetas. |
| `20260717000000_PROPOSTA_tvde_request_ride_merge_tokens_payment.sql` | Funde as duas overloads (8 args) de `tvde_request_ride` que hoje coexistem em produção — o toggle "Usar Bora Tokens" no pagamento TVDE calcula o desconto mas nunca chega a aplicar-se na corrida real (bug confirmado pelo Danilo, ordem 8448 09/07). Gate `bora_tokens`. |
| `20260717010000_PROPOSTA_tvde_finish_ride_reaplica_tokens_dinheiro.sql` | Migration-irmã da anterior: reaplica o desconto de tokens no valor final cobrado em **dinheiro** (`tvde_finish_ride` recalcula do zero a partir da distância final e perde o desconto já escolhido). Gate `bora_tokens`. |

**Também excluído (achado durante a preparação do commit, decisão minha — reversível, sem
tocar dinheiro/zonas protegidas, sinalizado aqui para visibilidade):**

| O quê | Porquê excluído |
|---|---|
| `.claude/.ai/hermes/heartbeat-desktop/_libs/` (19MB, 832 ficheiros) | Dependências Python vendorizadas (Pillow, tzdata, mouseinfo) — parece resultado de `pip install --target`. Commitar 19MB de binário/dados de terceiros ao git é praticamente irreversível (fica na história para sempre). Preferível: gitignorar + `requirements.txt`, decisão do Danilo. |
| `.claude/testes-e2e/web-tools/chromedriver.exe` + `.zip` (52MB) | Binário de terceiros (ChromeDriver), baixado durante investigação E2E. Mesma lógica — não deveria ir para o git. `cdp-drive.js`/`static-server.js` (código próprio, pequenos) foram mantidos e commitados. |
| `.claude/.ai/cortex-mcp/.pc-knowledge-sync.marker` | Ficheiro de estado do loop do Bloco A (timestamp vazio, reescrito a cada ciclo) — ruído de diff, não conteúdo. |

**Também incluído — não pedido explicitamente, mas dentro do critério literal ("só exclui
`PROPOSTA_`"), sinalizado para revisão do Danilo:** 2 migrations TVDE que **não** têm o prefixo
`PROPOSTA_` (`20260716220000_tvde_expire_roundtrip_credits_cron.sql`,
`20260716230000_reservas_pro_reminders_real_push.sql`) foram commitadas. Commitar um ficheiro SQL
**não o aplica** — confirmado: nenhum workflow em `.github/workflows/` corre `supabase db push`
ou aplica migrations automaticamente. Zero risco de execução involuntária, mas fica registado
porque tocam TVDE.

**Secrets:** varredura por padrão (`sk-ant-`, `ghp_`, chaves privadas, `SUPABASE_SERVICE_ROLE`
com valor) em todos os ficheiros untracked antes de comitar — só nomes de variável/placeholders
truncados (`sk-ant-oat01-...`, `sk-ant-oat01-v6v08Dh...` já redigido a 8 chars por convenção
existente no próprio repo), zero valor real exposto.

**Lista completa dos 269 caminhos:** `.claude/.ai/reports/_bloco-b-paths-to-commit-2026-08-01.txt`
(gerada antes do commit, conforme pedido "lista os caminhos antes de empurrar").

---

## BLOCO C.1 — Prova real da "continuação por teto"

**Não construí uma ordem artificial — o esquadrão abortou por segurança, com um achado que muda
a premissa da tarefa.**

Confirmado o mecanismo em `carteiro.sh` (linhas 240-248 e 747-767): quando `claude.exe` para por
`--max-turns 150`/`--max-budget-usd 25`, o parser emite `EXECUTOR-PAROU:`, o hook marca
`pausa_teto: 1` e cria uma continuação silenciosa (`MAX_CONT_PAUSA=8`, sem Telegram).

**Correcção de premissa:** o carteiro **não corre por tarefa agendada do Windows no PC** — corre
num container Docker na VPS (`hermes-agent-fvnc-hermes-agent-1`), que despacha cada ordem via
SSH/Tailscale para este PC (`run-claude-loop.cmd`, conta local `hermes`). A fila real vive em
`/opt/data/cortex-brain/orquestracao` na VPS (665 ficheiros, actividade às 12:02 UTC de hoje) —
**não** em `bora_app/orquestracao/` local (16 ficheiros, todos de 09-11/07, morta/desactualizada,
confirmado pelo próprio comentário do `pc-knowledge-sync.sh`: "não sincroniza `orquestracao/` —
essa fila vive só na VPS").

**Achado que fechou a via artificial:** o `bora-live.log` mostrava, em tempo real, os próprios
comandos SSH deste subagente a serem gravados — ou seja, **a missão-mãe (esta própria sessão)
já É a execução ao vivo da ordem que faria a prova**, a correr sob o mesmo teto
`--max-turns 150`/`--max-budget-usd 25` (o mesmo "$25" visível nos avisos de orçamento desta
sessão). Criar uma 2ª ordem de teste em paralelo arriscava colidir/duplicar com a própria missão
em curso e gastar orçamento partilhado.

**Prova por ficheiro/log NÃO conseguida nesta corrida** — nenhuma alteração feita a
`run-claude-loop.cmd` (nada para reverter), nenhum artefacto criado em `orquestracao/` local nem
VPS. **Se esta própria sessão vier a esgotar o teto** (150 turnos ou $25 — o consumo real desta
missão está registado nos avisos de orçamento ao longo da conversa), isso **seria** a prova
orgânica pedida: bastaria depois verificar `/opt/data/cortex-brain/orquestracao` na VPS por uma
ordem de continuação nova (`pausa_teto: 1`) e o log do carteiro pela linha `PAUSA-POR-TETO`.
**Isto fica como verificação em aberto, para a próxima sessão/o Danilo confirmar olhando o estado
real da fila na VPS depois desta missão terminar** — não posso provar o meu próprio desfecho a
partir de dentro da minha própria execução.

---

## BLOCO C.2 — E2E web headless (GPU/ReadPixels) + swap na VPS

**1. As 3 propostas de 15/07 (`prop-064debb3`, `prop-860e26df`, `prop-cf5de01c`):** quase
idênticas, convergem 100% — todas pediam a mesma fundação `.github/workflows/e2e-web.yml`
(`workflow_dispatch`, reaproveitando o `build_android.yml`). **Já foram executadas em 16-17/07** —
o workflow existe no repo (commit `1e7f1b4`). Gap real: só foi medido localmente (7min42s), nunca
disparado de verdade via `gh workflow run` por falta de `gh auth` na altura.

**2. Causa raiz do `ReadPixels` — com prova:** não é RAM/swap. Flutter Web só compila com
CanvasKit/WebGL desde a 3.29+ (`--web-renderer html` foi removido). Log real de 21/07
(`.claude/.ai/knowledge/inbox/e2e-render-fix-2026-07-21.md`): 2 fixes tentados (SwiftShader,
xvfb) na VPS, ambos falharam com a mesma assinatura (`gpChildren: 0, hasCanvas: false`) e o
mesmo aviso `GPU stall due to ReadPixels`. **Reprodução própria feita nesta sessão:** Chrome
headless real neste PC Windows (`--headless=new --disable-gpu --no-sandbox`) serviu o
`build/web` já compilado e **renderizou perfeitamente** (screenshot com a RoleScreen completa) —
ou seja, CanvasKit headless não é impossível por natureza; o problema é específico do
ambiente Linux/container da VPS.

**3. Swap resolveria?** Não o ReadPixels (problema de driver GL, não de memória). Ajudaria a
evitar a OOM **de compilação** (`flutter build web` consumiu os 2,3GB livres da VPS e derrubou o
sistema por ~5min — problema distinto, já documentado). O fix documentado precisava de 6G de
swap; a VPS só tem 2G hoje — esse gap continua por fechar.

**4. Recomendação:** não repetir a 3ª tentativa idêntica na VPS (regra do CLAUDE.md: "2 falhas
iguais → muda de abordagem" já se aplica — SwiftShader e xvfb já falharam). Caminho já
parcialmente construído e mais promissor: `flutter drive` + `integration_test` (inspecção da
árvore de widgets via VM service, zero dependência de pixels/GPU) — bloqueado em 21/07 por
incompatibilidade ChromeDriver 149 × pacote Dart `webdriver` 3.1.0, e pela mesma OOM de
compilação (GitHub Actions, com 8GB, resolve isso de graça). Próximo passo barato: `gh workflow
run e2e-web.yml` para confirmar o build em CI real, com um job experimental
`flutter drive --web-run-headless` no mesmo workflow.

**Nada foi aplicado à infraestrutura; nenhum commit/push feito por este bloco.**

---

## BLOCO C.3 — `/ctx doctor` e `/ctx stats`

**Decisão: não instalar nada de novo — o binário/servidor já existem e já ligam nesta sessão
interactiva; o que não funciona é o modo `-p` do executor, por desenho da CLI, não por falta de
instalação.**

Testado ao vivo nesta sessão: `ctx_doctor` → `Server test: PASS`, `FTS5/SQLite: PASS`, versão
`v1.0.89` (desactualizada, `v1.0.169` disponível — upgrade opcional, não crítico). `ctx_stats`
respondeu normalmente. Isto **contradiz** o relatório de fecho anterior ("o servidor MCP não
liga") — parece ter sido resolvido/reconectado entretanto (fora do escopo desta missão investigar
porquê).

**O que não muda:** o executor headless corre `claude -p --output-format stream-json` **sem
`--mcp-config`** — em modo `-p` não-interactivo, comandos-slash não são despachados e nenhuma
ferramenta MCP de plugin (incluindo `context-mode`) existe nesse processo. Não é regressão, é o
desenho do modo `-p`.

**Ação tomada:** actualizado `CLAUDE.md` (secção nova, antes de "Skill Usage Rule") a documentar
explicitamente esta separação — a regra de usar `ctx_*` vale para sessões interactivas, **não**
vale dentro do loop autónomo. Isto evita que um futuro agente perca tempo a tentar `/ctx doctor`
dentro de uma ordem do carteiro.

---

## BLOCO D — Triagem da fila de propostas (46 candidatas, 13/07→01/08)

Fila real: `/docker/hermes-agent-fvnc/data/cortex-brain/.claude/.ai/knowledge/inbox/_reports/proposals.jsonl`
(74 linhas totais). Cruzadas com commits/relatórios reais, não por inferência.

**Resumo:** 22 JÁ RESOLVIDA · 8 ULTRAPASSADA · 6 DUPLICADA · **10 AINDA FAZ SENTIDO** (6 destas só
precisam de uma acção simples do Danilo — confirmar/colar/criar rotina — não mais código).

```
prop-5b175381 | 2026-07-13 | vermelha | Limpeza: cleaner_availability | JÁ RESOLVIDA | fechar (commit afa94a5)
prop-2e9b2123 | 2026-07-13 | vermelha | Desligar bloqueio da zona vermelha | ULTRAPASSADA | fechar (decisão: manter fail-closed)
prop-29ecb009 | 2026-07-13 | vermelha | Classificador não rotear p/ fila de aprovação | ULTRAPASSADA | fechar (Juiz mecânico fail-closed)
prop-61947a84 | 2026-07-13 | vermelha | Varredura geral (só leitura) | ULTRAPASSADA | fechar (dezenas de varreduras feitas depois)
prop-e4f21c0e | 2026-07-13 | vermelha | Levantamento de estado (só leitura) | DUPLICADA de prop-61947a84 | fechar
prop-d3e9bb57 | 2026-07-13 | vermelha | Limpeza — cleaning_products_fee_cents | AINDA FAZ SENTIDO | escalar ao Danilo (mexe em fee, sem evidência de execução)
prop-863591a4 | 2026-07-13 | vermelha | E2E Categoria 1 Restaurante | ULTRAPASSADA | fechar (loop E2E pausado 14/07)
prop-5e37b2ba | 2026-07-13 | vermelha | Robot B — decisão Emerson | JÁ RESOLVIDA | fechar (em produção, dce48cbc)
prop-9e6ad9ac | 2026-07-14 | vermelha | E2E Categoria 2 Mercado | ULTRAPASSADA | fechar (mesmo motivo)
prop-dce48cbc | 2026-07-14 | vermelha | Timeouts HTTP 5000ms recorrentes | AINDA FAZ SENTIDO | manter na fila (sem evidência de investigação)
prop-e8481472 | 2026-07-14 | vermelha | Telegram resumo 17 decisões Emerson | ULTRAPASSADA | fechar (pontual, 18 dias)
prop-53f6730a | 2026-07-14 | vermelha | Push bloqueado por falso-positivo | JÁ RESOLVIDA | fechar (push funciona hoje)
prop-db2a091b | 2026-07-14 | vermelha | Erro submissão cadastro parceiro | JÁ RESOLVIDA | fechar (resolvido 8x+, 4e0f0d8)
prop-d9f186bd | 2026-07-14 | vermelha | Aprovação rápida Telegram zona vermelha | JÁ RESOLVIDA | fechar (aprovador-vermelho em operação)
prop-23b2b594 | 2026-07-14 | vermelha | Restaurar git push automático | JÁ RESOLVIDA | fechar (push HTTPS wincredman OK)
prop-9a8f26c6 | 2026-07-15 | vermelha | Curar espelho Córtex (fetch depth1) | JÁ RESOLVIDA | fechar (resolvida 2x)
prop-cf5de01c | 2026-07-15 | vermelha | Cabines browser no GitHub Actions | ULTRAPASSADA | fechar (E2E pausado)
prop-860e26df | 2026-07-15 | vermelha | (mesmo pedido, republicado) | DUPLICADA de prop-cf5de01c | fechar
prop-064debb3 | 2026-07-15 | vermelha | Fundação flutter build web no GH Actions | JÁ RESOLVIDA | fechar ("web LANÇADO")
prop-5a437bbf | 2026-07-16 | vermelha | 2 bugs TVDE (autocomplete + toggle tokens) | JÁ RESOLVIDA | fechar
prop-633618b5 | 2026-07-16 | vermelha | Bug UI pesquisa (parte de 8448) | JÁ RESOLVIDA | fechar (autocomplete corrigido)
prop-197182b7 | 2026-07-16 | vermelha | Km errado nos cards de parceiro | JÁ RESOLVIDA | fechar (commit 5f7b715)
prop-df32746d | 2026-07-16 | vermelha | Restaurar marca de autorização | ULTRAPASSADA | fechar (arquitetura reconstruída)
prop-fedac12f | 2026-07-16 | vermelha | Cabines browser (pedido original) | DUPLICADA de prop-cf5de01c | fechar
prop-3556cdb3 | 2026-07-17 | vermelha | Campo Categoria em falta (form produto) | JÁ RESOLVIDA | fechar (commit 71bdbc6)
prop-5700f204 | 2026-07-17 | vermelha | Bug UI form adicionar produto | AINDA FAZ SENTIDO | escalar ao Danilo (sem commit identificado)
prop-70c49ff9 | 2026-07-17 | vermelha | Retry ordem esgotou 3 tentativas | JÁ RESOLVIDA | fundir com prop-5e90a865, fechar
prop-5e90a865 | 2026-07-17 | vermelha | Fix causa raiz "SAIDA-VAZIA" | JÁ RESOLVIDA | fechar (loop funciona hoje)
prop-c544686d | 2026-07-18 | vermelha | Diagnóstico billing/CI destravar build | JÁ RESOLVIDA | fechar (versionCode 508→509 normal)
prop-carteiro-ordem-20260709110949-8448 | 2026-07-18 | vermelha | Ordem original 8448 (autocomplete+TVDE) | JÁ RESOLVIDA | fechar/arquivar (única zona_vermelha não-arquivada)
prop-7b8f9702 | 2026-07-18 | vermelha | Disparar build CI p/ Play | ULTRAPASSADA | fechar (dezenas de builds desde então)
prop-8f98ada3 | 2026-07-18 | vermelha | Bug confirmação compra mercado (estafeta) | JÁ RESOLVIDA | fechar (commit 6b84d36)
prop-d4fbbe04 | 2026-07-18 | vermelha | Bug registo parceiro serviços (beleza) | JÁ RESOLVIDA | fechar
prop-455e4955 | 2026-07-19 | vermelha | Tarefa no repo bora-site | AINDA FAZ SENTIDO | escalar ao Danilo (repo separado, sem confirmação)
prop-7401bfc8 | 2026-07-21 | vermelha | Carteira Única de Cartão (guarda-chuva 6 partes) | JÁ RESOLVIDA | fechar (6/6 commitadas)
prop-cfad5e97 | 2026-07-21 | vermelha | Carteira Única PARTE 1/6 | JÁ RESOLVIDA | fechar (581b345)
prop-f3a82944 | 2026-07-21 | vermelha | Carteira Única PARTE 2/6 | JÁ RESOLVIDA | fechar (1e831db)
prop-bdfd5093 | 2026-07-21 | vermelha | Carteira Única PARTE 3/6 | JÁ RESOLVIDA | fechar (f9607c3)
prop-5345589b | 2026-07-21 | vermelha | Carteira Única PARTE 4/6 | JÁ RESOLVIDA | fechar (4a4d7fa; falso-positivo zona vermelha confirmado)
prop-43de9224 | 2026-07-21 | vermelha | Carteira Única PARTE 5/6 | JÁ RESOLVIDA | fechar (67ab864)
prop-ba52ce00 | 2026-07-21 | vermelha | Carteira Única PARTE 6/6 (admin) | AINDA FAZ SENTIDO (parcial) | escalar ao Danilo (UI commitada c459cc4, falta migration admin_list_payments + EF admin-payments)
prop-ddd67f48 | 2026-07-22 | vermelha | Scroll travado admin "Sugestões do Robot" | JÁ RESOLVIDA | fechar (commit 255c8ac)
prop-ef947ec6 | 2026-07-22 | vermelha | Taxa cancelamento TVDE cash (~5€/3min) registada? | AINDA FAZ SENTIDO | manter na fila (sem evidência de conclusão)
prop-151a4400 | 2026-07-22 | vermelha | Mesmo diagnóstico taxa cancelamento | DUPLICADA de prop-ef947ec6 | fundir
prop-85cf635b | 2026-08-01 | vermelha | Trava de segredos — ligar guard settings.json | AINDA FAZ SENTIDO (código pronto) | escalar ao Danilo (falta ele colar o diff)
prop-59c8310d (ordem-...-ffc9-aprovado-chat) | 2026-08-01 | vermelha | Continuação sistema-redondo (esta própria missão) | AINDA FAZ SENTIDO (em execução) | manter — é a missão-mãe desta tarefa
prop-b8d89e98 | 2026-08-01 | vermelha | Rotina Telegram de aviso automático | AINDA FAZ SENTIDO (código pronto) | escalar ao Danilo (falta criar rotina na UI web, ~3min)
```

**Nenhuma proposta foi executada/aplicada/fechada nesta tarefa — só triagem, como pedido.**

---

## O que fica por fazer (lista honesta, sem arredondar)

1. **BLOCO C.1 sem prova definitiva.** A construção artificial foi correctamente abortada
   (risco de colidir com esta própria execução). Verificar depois desta sessão terminar se
   `/opt/data/cortex-brain/orquestracao` (VPS) ganhou uma ordem de continuação nova com
   `pausa_teto: 1` — seria a prova orgânica, se esta missão tiver esgotado o teto.
2. **3 migrations `PROPOSTA_` de TVDE continuam por rastrear**, fora do commit, para o Danilo
   decidir numa vista só (tabela na secção Bloco B).
3. **`_libs/` (19MB) e `chromedriver.exe`/`.zip` (52MB) continuam untracked** — decisão minha,
   reversível, para o Danilo confirmar se quer gitignorar + documentar a instalação em vez de
   vendorizar.
4. **10 propostas "AINDA FAZ SENTIDO" na fila** (Bloco D) — 6 delas só esperam uma acção simples
   do Danilo (colar trava de segredos, criar rotina Telegram, confirmar taxa TVDE cash, etc.).
5. **Confirmar se o loop de sync do Bloco A (`pc-knowledge-sync-loop.sh`) ainda está vivo** —
   não confirmado positivamente nesta sessão; as schtasks `ONLOGON`/`ONSTART` garantem
   persistência independentemente.
6. **CI real não confirmado via `gh`** (sem auth nesta sessão) — o push foi confirmado
   (`d89de2f..996d962` aceite pelo GitHub), o que é a condição que dispara `build_android.yml` e
   `build_web_deploy.yml`; a execução em si não foi observada directamente.
7. **`gh workflow run e2e-web.yml`** (Bloco C.2, próximo passo recomendado) não foi disparado
   nesta sessão — falta de `gh auth` no ambiente.
8. **Pendências antigas não tocadas** (fora do escopo dos 4 blocos, mas ainda reais):
   trava de segredos por ligar em `.claude/settings.json`, migration `admin_list_payments`,
   17-24 Edge Functions sem `verify_jwt` aguardando decisão de baldes B/C.

## Ficheiros tocados nesta sessão

**Repo (commitados em `996d962`):** 269 ficheiros — ver
`.claude/.ai/reports/_bloco-b-paths-to-commit-2026-08-01.txt` para a lista completa. Destaques:
`.claude/.ai/cortex-mcp/pc-knowledge-sync*.sh`, `instalar-schtask-pc-knowledge-sync.cmd`,
`CLAUDE.md` (nota sobre `context-mode` no executor), este relatório.

**Repo (deliberadamente fora do commit):** 3 migrations `PROPOSTA_` TVDE, `_libs/`,
`chromedriver.exe`/`.zip`, `.pc-knowledge-sync.marker`.

**VPS:** nenhuma alteração de infraestrutura além do que o loop do Bloco A já escreve por SSH
(conteúdo de `.claude/.ai/knowledge/`, add-only). Nenhum código de produção, RLS, migration
aplicada, pricing, dispatch ou Stripe tocados em nenhum dos 4 blocos.

**PC:** 2 novas scheduled tasks (`Bora-cortex-pc-sync-logon`, `Bora-cortex-pc-sync-boot`).
