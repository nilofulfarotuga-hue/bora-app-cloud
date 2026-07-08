# Cortex MCP — a ponte Claude.ai ↔ Hermes (um cérebro só)

Servidor MCP (JSON-RPC sobre HTTP) que expõe o **Córtex** (`.claude/.ai/knowledge/`) como ferramentas.
Claude.ai e o Hermes leem/escrevem o **mesmo** cérebro. **Só mexe no Córtex** — nunca DB, dinheiro ou shell.

## Ferramentas
`cortex_buscar(query)` · `cortex_ler(id)` · `cortex_listar(filtro)` · `cortex_debt()` ·
`cortex_escrever(id, conteudo)` (só zona verde, pode estar desligado) · `cortex_propor(id, conteudo)` (fila do admin).

## Segurança (no servidor, não no prompt)
- **Token obrigatório** (`Authorization: Bearer <TOKEN>` ou `x-api-key`). Sem token → **401**.
- **HTTPS** via traefik + letsencrypt (`cortex.srv1786862.hstgr.cloud`).
- **Zona 🔴 recusada no servidor** (`cortex_escrever` a página `zona: vermelha` ou conteúdo com padrões de dinheiro → recusa → manda `cortex_propor`).
- **Dial cauteloso:** `CORTEX_WRITE_ENABLED=false` por defeito → escrita desligada; **read/propose live**. Ligar só quando confiares.
- **Sem segredos:** só lê `.md` dentro do brain (sem path traversal); nunca lê `.env`/`.secrets`; sem shell arbitrário; rate-limit 60/min/IP; toda escrita/proposta regista em `log.md`.

## Deploy (no VPS)
1. `docker exec -u hermes <hermes> sh /opt/data/cortex-mcp/sync-brain.sh`  → espelha o cérebro em `/opt/data/cortex-brain` (B0).
2. `bash /root/cortex-mcp/deploy.sh`  → build + traefik + TLS + token; verifica 401/200.
3. Ligar escrita (quando quiseres): re-run com `-e CORTEX_WRITE_ENABLED=true -e CORTEX_GIT_PUSH=true` e montar o brain `rw`.

## ⚠️ claude.ai custom connector — ler antes
O conector **web** do claude.ai (Definições → Conectores → Adicionar personalizado) normalmente exige
**OAuth**, não um bearer estático colado num header. Este servidor autentica por **token** — funciona
já com clientes MCP que aceitam header (Claude Desktop via config, chamadas API, etc.). Para o conector
**web** do claude.ai, falta a camada **OAuth 2.1** (fica como próximo passo — ver `reports/cortex/ponte_mcp.md`).

## B4 — o passo do Danilo (quando o OAuth/token estiver aceite pelo cliente)
claude.ai → Definições → Conectores → **Adicionar conector personalizado** → URL `https://cortex.srv1786862.hstgr.cloud`.
O token vive em `/root/cortex_mcp_token` no VPS (600) e no relatório local seguro — **nunca** no chat.
