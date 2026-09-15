---
tarefa: espelho-supabase (ordem-20260718064802-6350)
data: 2026-07-18
estado: parcial — script + cron criados e testados; escrita real bloqueada por credencial em falta
---

# Espelho da fila do carteiro → Supabase (observabilidade)

## Gate de sequência (verificado antes de começar)
A ordem pedia para só arrancar depois da ordem do billing (`prop-c544686d`) fechar.
Confirmado: essa ordem corresponde a `ordem-20260718061709-997f-aprovado.md` (sufixo
`-aprovado` = fechada) — commit mais recente na branch (`6b1caa8 ci: trigger build
pos-diagnostico billing`) confirma o fecho. Podia arrancar.

## O que foi feito

**Passo 1 — script criado:** `/docker/hermes-agent-fvnc/scripts/espelho-supabase.sh`
(bash, 116 linhas, `chmod 700`, `bash -n` sem erros). Faz:
- (a) lê `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` (ou `DATABASE_URL`/`SUPABASE_DB_URL`)
  de `/docker/hermes-agent-fvnc/.env` e `/docker/hermes-agent-fvnc/data/.env`, sem nunca
  imprimir os valores; se faltar, escreve aviso em stderr e sai (`exit 1`) sem tentar nada.
- (b) para cada `orquestracao/ordem-*.md` (só topo do diretório, não entra em `missoes/`
  nem `arquivo/`) extrai `ordem_id`, `estado` (sufixo do nome, senão frontmatter, senão
  "desconhecido"), `tentativa`, `zona`, `mtime`, `resumo` (300 chars), e `relatorio` do
  `.saida.txt` correspondente (limite defensivo de 8000 chars — a VPS tem pouca RAM livre,
  ~146 MB no momento do teste); faz UPSERT em `cortex_ordens_espelho` via REST
  (`Prefer: resolution=merge-duplicates`).
- (c) heartbeat: `pgrep -f carteiro.sh` / `pgrep -f pc-loop` → `vivo`, `ordem_atual` (a
  ordem com `estado: executando`, se houver), `ram_livre_mb` (`free -m`, coluna
  `available`) → UPSERT em `cortex_exec_heartbeat`.

**Passo 2 — cron instalado** (a cada 2 min):
```
*/2 * * * * /docker/hermes-agent-fvnc/scripts/espelho-supabase.sh >/tmp/espelho.log 2>&1 # espelho-supabase-observabilidade
```
Confirmado presente via `crontab -l` (linha final, junto dos outros crons do Hermes).

**Passo 3 — corrido à mão uma vez.** Saída real:
```
[espelho-supabase] creds Supabase ausentes na VPS (falta SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY, ou DATABASE_URL, em /docker/hermes-agent-fvnc/.env / /docker/hermes-agent-fvnc/data/.env) - a parar.
EXIT_CODE=1
```
Comportamento correto e seguro: parou sem escrever nada.

## Passo 4 (PROVA) — bloqueado: creds Supabase ausentes na VPS

Verifiquei os dois `.env` reais na VPS (não os `.env.example`):
- `/docker/hermes-agent-fvnc/.env` → só tem `ADMIN_USERNAME`, `ADMIN_PASSWORD`, `TRAEFIK_HOST`.
- `/docker/hermes-agent-fvnc/data/.env` → tem `SUPABASE_URL` + `SUPABASE_ANON_KEY`, mas
  **não tem** `SUPABASE_SERVICE_ROLE_KEY` nem `DATABASE_URL`/connection string Postgres.

Confirmei ainda, via MCP Supabase, que a `anon key` não serve como alternativa: as duas
tabelas (`cortex_ordens_espelho`, `cortex_exec_heartbeat`) têm RLS **ativo** e os grants
de `INSERT`/`UPDATE` são só para `postgres` e `service_role` — o role `anon` não tem
nenhum privilégio nelas. Ou seja, mesmo que o script usasse a anon key, o REST recusaria
a escrita (RLS). Por isso, por instrução explícita da própria ordem ("se não achar,
escrever no relatório 'creds Supabase ausentes na VPS' e PARAR"), não fabriquei nenhuma
prova — não haveria linhas reais para mostrar.

Confirmação honesta via MCP (não é a "prova via curl com service key" pedida, é só para
mostrar que não há dados fantasma):
```sql
select 'cortex_ordens_espelho' as tabela, count(*) from cortex_ordens_espelho
union all
select 'cortex_exec_heartbeat', count(*) from cortex_exec_heartbeat;
-- cortex_ordens_espelho: 0
-- cortex_exec_heartbeat: 0
```
Zero linhas — coerente com o script nunca ter chegado a escrever.

## Próximo passo (1 frase)

Assim que alguém adicionar `SUPABASE_SERVICE_ROLE_KEY=...` (ou uma `DATABASE_URL` do
Postgres) a `/docker/hermes-agent-fvnc/data/.env`, o cron de 2 em 2 minutos já instalado
vai apanhar a credencial na próxima corrida e começar a espelhar sozinho — não é preciso
correr esta ordem outra vez.

## Reconfirmação (2026-07-18, dispatch duplicado da mesma ordem)

Esta ordem chegou de novo ao executor no mesmo dia. Antes de refazer, verifiquei o estado
real na VPS via SSH e via MCP Supabase — nada mudou desde o relatório acima:
- `ls -la` confirma o script ainda em `/docker/hermes-agent-fvnc/scripts/espelho-supabase.sh`
  (root:root, `700`).
- `crontab -l` confirma a linha `*/2 * * * * .../espelho-supabase.sh ... # espelho-supabase-observabilidade`
  ainda ativa.
- `tail /tmp/espelho.log` mostra a mesma mensagem: creds Supabase ausentes, parou sem escrever.
- `grep -o "^[A-Z_]*=" .env / data/.env` confirma que `SUPABASE_SERVICE_ROLE_KEY` e
  `DATABASE_URL` continuam ausentes dos dois ficheiros.
- `select count(*)` nas duas tabelas via MCP Supabase: `cortex_ordens_espelho=0`,
  `cortex_exec_heartbeat=0` — ainda sem escrita real, coerente com o bloqueio.

Nenhum ficheiro foi alterado na VPS nem em `orquestracao/` nesta reconfirmação. Não há
trabalho novo a fazer até o Danilo adicionar a credencial — ver [[project_espelho_supabase_bloqueado_credencial]].
