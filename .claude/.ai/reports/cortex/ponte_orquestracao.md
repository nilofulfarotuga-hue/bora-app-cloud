# Ponte de orquestração + fecho Graphify — relatório (2026-07-08)

**MODO PROTECÇÃO TOTAL.** Fiz recon real do sistema, executei o que é seguro/aprovado e **staged**
(pronto, mas não ligado) o que exige mudança de produção não-testável de madrugada. Sou explícito
sobre o que está **LIGADO** vs **STAGED** e porquê. **A Trava do banco continua com prioridade
absoluta e intacta.**

---

## Realidade do sistema (recon 2026-07-08) — a base honesta

O desenho do prompt assumia algumas coisas que **não batem** com a instalação real. O que existe:

| Peça | Realidade encontrada |
|---|---|
| Hermes | Imagem **gerida da Hostinger** `hvps-hermes-agent` (container `hermes-agent-fvnc-hermes-agent-1`). |
| `claude` no VPS | **Stub que redireciona para o PC** ("Não chames claude diretamente. A redirecionar para o PC"). Ou seja, **as "mãos" correm no PC**, não no VPS. |
| Cérebro no VPS | **NÃO** sincronizado (ADR `adr-manutencao-cerebro-repo-side`). Hermes lê a fila só via **ponte MCP** (`cortex_ler/listar/escrever`) — que é o que o prompt já preferia. |
| MCP no Hermes | Sem chave `mcp_servers` no config. Mecanismo = **CLI `hermes mcp add/configure/test/remove`**. Hoje: *"No MCP servers configured"*. |
| `cortex-mcp` (a campainha) | `server.mjs` **sem** capacidade de webhook. A "campainha" exige **modificar + redeploy** do MCP de produção. |
| `claude -p` flags | ✅ `--max-budget-usd`, `--max-turns`, `--allowedTools`, `--permission-mode`, `--print` **existem** → **T2/T4 implementáveis**. |

**Conclusão:** o loop completo (Parte 1) precisa de **2 mudanças de produção não-triviais**
(webhook no `cortex-mcp`; juiz que acorda sozinho) + é **auto-commit + gasta tokens** + **não é
testável ponta-a-ponta** nesta sessão não-assistida. Por isso **construí a base segura e deixei a
ATIVAÇÃO staged**, em vez de ligar um loop não-testado que faz commits e gasta dinheiro sozinho.
Isto respeita o próprio envelope do prompt ("não insistir em produção", "cautela extra").

---

## PARTE 1 — Ponte de orquestração

### ✅ A — Cérebro acessível ao Hermes
Decidido pela **via MCP** (não sincronizar `knowledge/` para o VPS — alinhado com o ADR). O Hermes
lê/escreve a fila com `cortex_listar`/`cortex_ler`/`cortex_escrever`. **Sem mudança de produção.**

### 🟡 B — Skill `orquestrador-carteiro` (CONSTRUÍDA, staged)
Ficheiro-fonte: `.claude/.ai/hermes/orquestrador-carteiro/SKILL.md` (neste repo). Encapsula os tetos:
- **T1 (5 tentativas, FIXO):** ao 5.º sem aprovação → `travada` + Telegram + PARA.
- **T2 (custo):** `claude -p ... --max-budget-usd <X> --max-turns <N>` (flags confirmadas). Estouro → `travada`.
- **T3 (zona vermelha NUNCA no loop):** pré-check + **a Trava (`protege-banco.sh`) tem prioridade**;
  se a tarefa toca dispatch/pricing/finalizePurchase/bora_tokens/Stripe/RLS financeira → `zona: vermelha`,
  fila de aprovação do admin, **não executa**.
- **T4 (`--allowedTools` restrito):** só o que a tarefa precisa.
- **T5 (kill switch):** lê `orquestracao_enabled` da fila antes de agir.
**Staged:** o ficheiro NÃO foi deployado ao container do Hermes (deploy = mudança de produção; comando pronto no fim).

### 🟡 C — Claude-juiz (DESENHADO, staged)
O juiz é um **Claude bom que acorda sozinho** — via **Scheduled Task (PC)** ou **cron/Routine**,
acionado quando o Hermes marca uma ordem `respondida`. Lê `saida` vs `tarefa`, aplica a rubrica
(pode reusar o Juiz 0-10), escreve o veredito `aprovada`|`corrigir`+nota. `corrigir` → ordem volta a
`aberta` (+nota) → nova tentativa (respeita T1). Corre no PC (onde o `claude` real vive) com a conta
Max. **Staged:** não configurei a Scheduled Task (é ativação de automação que gasta tokens — precisa
do teu OK para o teto de custo e para acordar sozinho).

### ✅ D — Contrato do chat (claude.ai) documentado
O chat **só dá a primeira ordem** (o Danilo fala; eu monto o prompt e escrevo a ordem inicial no
Córtex). Durante o loop **não participa** (não acorda sozinho). Opcional no fim: "revê o resultado".

### 🟡 E — Aprendizagem noturna (desenhada)
Cada ordem concluída fica no Córtex; a consolidação noturna do Hermes resume padrões (o que falha /
o que passa). Reusa o cron de consolidação já existente. Staged junto com B/C.

### 🟡 F — Admin (fila + kill switch)
Superfície: a **Central do Córtex** lista a pasta `orquestracao/` (estados + travadas) e o
`orquestracao_enabled`. **Proposto** como página de controlo (não implementei UI nova).

### 🔴 A campainha (webhook) e o kill switch — porque NÃO liguei ainda
- **Webhook:** `cortex-mcp` (server.mjs, baked na imagem) **não tem** emissão de webhook. Ligar a
  campainha = **editar + redeploy do MCP de produção**. Não fiz de madrugada, sem teste.
- **`orquestracao_enabled`: deixei `FALSE`.** O prompt pedia `TRUE`, mas o executor (webhook + juiz)
  **não está deployado nem testado** — `TRUE` agora ligaria um loop **meio-ligado, não-testado, que
  faz commits e gasta tokens sozinho**, o que o mandato de proteção proíbe. O switch está **construído
  e pronto para TRUE**; flipa para `TRUE` no minuto em que (1) o webhook estiver no `cortex-mcp`,
  (2) o juiz agendado, e (3) **um dry-run ponta-a-ponta** passar. Tudo está staged para isso ser 1 passo.

---

## PARTE 2 — Graphify (fecho dos pendentes)

### ✅ G2 — Role `graphify_ro` CRIADA e verificada (o que exigia aprovação — FEITO)
Via Supabase MCP. Verificado em produção: `canlogin=true`, `super=false`, `bypassrls=false`,
`createdb/createrole=false`, `member_of=null`. Vê o schema (**158 tabelas · 2494 colunas · 119 FKs**)
mas **`permission denied for table orders`** — **zero leitura de linhas** (regra C1/C3 ✅). Grants:
`USAGE` + **`REFERENCES`** (torna schema visível SEM permitir leitura de dados, independente de RLS).
DSN (pooler): `graphify_ro.ojykpzwqrtusfeakzrna@aws-1-eu-west-1.pooler.supabase.com:5432/postgres`
(password em `~/.graphify_ro.pw`, **fora do repo**). A Trava deixou passar (CREATE ROLE não é DDL financeira).

### 🔴 G3 — Schema no grafo: BLOQUEADO por BUG do Graphify (reportar upstream)
Isolei o problema: `graphify extract --postgres` devolve **"PostgreSQL: 0 nodes"** contra o
Supabase/Supavisor, **apesar** de a mesma DSN + as mesmas queries (`information_schema.tables/...`)
devolverem **164 tabelas** via psycopg puro (testado 3x, incl. o `SET TRANSACTION SERIALIZABLE READ
ONLY DEFERRABLE` exato que o graphify usa). Não é permissão (a role vê tudo) nem password. É
**incompatibilidade graphify 0.9.10 ↔ Supavisor** (provável no node-building após a introspeção).
**Staged:** role pronta + DSN confirmada; falta o schema entrar no grafo (após fix/patch upstream).
**Caveat de persistência:** o `post-commit` corre `graphify update` (só código) — para o schema
persistir, o refresh teria de correr `extract --postgres`, não `update`.

### 🟡 G1 — Ligar Graphify ao Hermes (staged, comandos prontos)
Via **stdio no VPS** (robusto): instalar `graphifyy[mcp]` em `/opt/data/.local/bin`, sincronizar
`graph.json` para `/opt/data`, e:
`hermes mcp add graphify --command /opt/data/.local/bin/graphify-mcp --args --graph /opt/data/graph/graph.json --transport stdio`
`hermes mcp test graphify`. **Não fiz** o install pesado (~40 pacotes tree-sitter num VPS 4GB) +
pipeline de freshness de madrugada — é mudança de produção que merece ser assistida.

### 🟡 G4 — Córtex atualizado
Página `wiki/codigo/graphify` re-proposta com: G2 feito, G3 bloqueado (bug), G1 staged.

---

## 🔴 Confirmações de segurança
- **Zona vermelha fora do loop, sempre** (T3 + Trava com prioridade). **Trava intacta** (não toquei
  `settings.json`; selftest continua 12/12 nas sessões anteriores).
- **Teto de 5 tentativas** codificado na skill. **T2/T4** implementáveis (flags confirmadas).
- **`orquestracao_enabled=FALSE`** — ver acima o porquê (executor não testado). Pronto para TRUE num passo.
- **Nada de produção foi alterado** exceto a criação da role read-only `graphify_ro` (aprovada,
  verificada sem acesso a dados).

## ⚠️ Bugs / riscos
1. **Graphify `extract --postgres` = 0 nodes contra Supavisor** (isolado; reportar em safishamsi/graphify).
2. **Arquitetura frágil** para o loop: "mãos" (claude) no PC via stub, grafo no PC, agente no VPS —
   depende do PC aceso. Robustez real = executor+grafo no mesmo sítio.
3. **A campainha exige redeploy do `cortex-mcp`** — mudança de produção; fallback cron lento é a rede.
4. **Juiz que acorda sozinho gasta tokens (conta Max/API)** — só ligar com teto e OK explícito.

## O que precisa de ti (para ligar o loop, 1 sessão assistida)
1. OK para editar + redeploy `cortex-mcp` com o webhook (a campainha).
2. OK para agendar o Claude-juiz (Scheduled Task) com o teto `--max-budget-usd`.
3. Depois: deploy da skill + `orquestracao_enabled=TRUE` + 1 dry-run → loop LIGADO.
