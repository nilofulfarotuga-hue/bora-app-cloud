# Graphify — Hermes (VPS) + schema SQL — relatório (2026-07-08)

Continuação de `graphify_instalado.md`. **MODO PROTECÇÃO TOTAL.** Fiz recon read-only e parei
antes de qualquer alteração de produção que se mostrasse arriscada — como o prompt manda
("não insistir em produção", "propor" quando falta o pré-requisito seguro). **Nada de produção
foi alterado.**

---

## ✅ Parte A — Bug do graphify-mcp resolvido

`graphify-mcp` já tinha sido reinstalado com o extra `[mcp]` na sessão anterior. Confirmado agora:
`graphify-mcp --transport http` **arranca sem `ModuleNotFoundError`** (0 ocorrências). Server
sobe: `graphify MCP server (streamable-http) ... - api-key required` + `Uvicorn running`.
Auth verificada: sem chave → **401**; com `x-api-key` → passa (o endpoint MCP responde 400 a um
GET simples de curl, o que é esperado). Header aceite: **`x-api-key: <KEY>`** ou
`Authorization: Bearer <KEY>`.

## ⚠️ Parte B — Hermes NÃO ligado (blocker de rede real, documentado)

Descobri o mecanismo real (o prompt assumia um schema que **não existe** nesta instalação):
- O Hermes é a imagem **gerida da Hostinger** `ghcr.io/hostinger/hvps-hermes-agent`
  (container `hermes-agent-fvnc-hermes-agent-1`, `_config_version: 30`).
- **Não há chave `mcp_servers`** no `config.yaml`. MCP gere-se pela **CLI** `hermes mcp`:
  `add --url <URL> --auth {oauth,header}` · `configure` (seleção de tools) · **`test`** (testa
  ligação sem correr o agente) · `remove` (reversível) · `list`.
- `hermes mcp list` **agora: "No MCP servers configured"** — ou seja, o `cortex-mcp` (container up)
  é exposto via traefik para o claude.ai web, **não** é consumido pelo agente Hermes.

**Blocker (verificado, não é suposição):** o grafo vive **neste PC**; o Hermes está no **VPS**.
Testei a chegada VPS→PC ao `graphify-mcp` (arranquei-o na tailscale IP 100.71.105.7:8899):
- VPS host → PC: **timeout (000)**.  Container Hermes → PC: **timeout (000)**.
- Causa-raiz: o VPS corre `tailscaled --tun=userspace-networking` → **não há interface
  `tailscale0`**, logo nem o host nem o container têm rota para IPs 100.x. O tailnet só funciona
  via **DERP relay** ("direct connection not established"). **O firewall do PC NÃO é a causa**
  (o python tem regras de inbound allow).

**Decisão:** **não liguei** o Hermes a um endpoint que ele não alcança — isso deixaria um MCP
morto no config (latência no discovery a cada sessão). Fazer VPS→PC funcionar exigia
proxy SOCKS userspace / subnet-router / reverse-proxy — mudança de rede de produção arriscada,
de madrugada, numa imagem gerida. Parei (a Trava e a prudência têm prioridade). **Não toquei no
`config.yaml` nem corri `hermes mcp add`.**

### Caminho robusto recomendado (com o "vai" do Danilo, de dia, com rollback)
Em vez de o Hermes (cloud, always-on) depender do portátil aceso + tailscale-relay (frágil),
correr o **graphify-mcp no próprio VPS via stdio** (sem rede, sem firewall, sem tailscale):
1. Instalar graphify no volume persistente do container: `uv tool install "graphifyy[mcp]"`
   em `/opt/data/.local/bin` (padrão já usado p/ o himalaya).
2. Sincronizar `graph.json` para o VPS (ex.: PC→VPS via a ponte existente) e um passo de
   atualização (o `post-commit` do PC reconstrói; falta empurrar p/ o VPS).
3. Ligar por **stdio** (o mais fiável):
   ```
   hermes mcp add graphify --command /opt/data/.local/bin/graphify-mcp \
     --args --graph /opt/data/graph/graph.json --transport stdio
   hermes mcp configure graphify   # (opcional) deixar só query/explain/path — todas já são leitura
   hermes mcp test graphify        # testar sem correr o agente
   ```
   **Nota de segurança:** as 10 tools do graphify-mcp são **todas de leitura**; não há tool de
   escrita para expor. O filtro "só leitura" é garantido por design.

### Se preferires mesmo o PC-over-tailscale (menos fiável)
Servidor pronto no PC: `graphify-mcp --transport http --host 100.71.105.7 --port 8899 --api-key <KEY>`
(chave guardada em `~/.graphify-mcp.key`). Falta: (a) resolver a rota userspace-networking do VPS
(SOCKS/subnet-router) e (b) manter o PC aceso + o server como serviço. Comando final:
`hermes mcp add graphify --url http://100.71.105.7:8899/mcp --auth header` (header `x-api-key`).
**Não recomendado** para um agente de produção.

### B6 — cron do daily-pulse
Não afetado: **não alterei nada** no VPS. O `daily-pulse` (07h) e a consolidação do Córtex
continuam intactos. (Se algum dia se ligar o graphify por stdio-local, não compete por rede.)

## ⚠️ Parte C — Schema SQL: introspecção é segura, falta a role read-only (proposta)

- **Verifiquei o código** (`pg_introspect.py`): consulta **só** `information_schema`
  (tables/views/routines/table_constraints/referential_constraints). **Nunca** faz `SELECT` em
  tabelas de negócio → **não lê dados de linhas** (orders/wallets/ledger). Operação inerentemente
  segura (regra C3 ✅).
- **Mas** (regra C1): **não existe** uma credencial Postgres **read-only** pronta — a única
  password de BD seria privilegiada, e a chave anon do Supabase é PostgREST, não uma DSN Postgres.
  **Não usei credencial de escrita.** Parei e **proponho criar uma role read-only dedicada**:
  ver `graphify_sql_readonly_role.PENDING.sql` (CREATE ROLE `graphify_ro`, só CONNECT, sem SELECT
  em dados). **Não a apliquei** (é mudança na BD de produção, gated pelo Danilo).
- Após aprovação: `graphify extract . --postgres "<DSN read-only>"` junta tabelas/colunas/FK ao
  grafo existente.

## ✅ Parte D — Registado

- Córtex `wiki/codigo/graphify`: proposta **atualizada** com o estado real (Hermes pendente por
  blocker de rede; SQL pendente por falta de role read-only).
- `log.md` de proveniência: entrada adicionada.

---

## ⚠️ Bugs / riscos
- **Blocker de rede (não é bug meu):** VPS em `userspace-networking` do tailscale → sem rota para
  o tailnet no host/container. Documentado acima com o caminho de resolução.
- **Fragilidade arquitetural:** grafo no portátil + agente na cloud = dependência do PC aceso.
  Recomendo o graphify-mcp **no VPS via stdio** como solução definitiva.
- **Assunção errada no prompt:** `mcp_servers` + `mcp_server_filter: whitelist` não existem no
  hvps-hermes-agent; o mecanismo é a CLI `hermes mcp`. As tools do graphify são todas de leitura,
  por isso o requisito "só leitura" cumpre-se sem filtro.
- **Nada de produção foi alterado.** Recon read-only apenas. Servidor de teste do PC já parado.
