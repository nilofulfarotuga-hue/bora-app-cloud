# Ponte Bora — Hermes (VPS) → PC → Claude Code (worker headless)

Comandar o Claude Code do PC por voz/Telegram. Fluxo:

```
Danilo fala (Telegram) → Hermes (VPS) → SSH no PC (user hermes)
   → run-claude.cmd "<pedido>" → Claude Code headless executa → output volta
```

## Estado atual (2026-06-28) — ✅ PONTE FECHADA E PROVADA E2E

Fluxo completo testado de ponta a ponta: **VPS → container Docker do Hermes →
`tailscale nc` → SSH `hermes`@PC → `run-claude.cmd` → Claude Code** — devolveu os
5 ficheiros do `bora_app` em PT-BR (exit 0).

| Componente | Estado |
|---|---|
| Claude CLI no PC (`v2.1.193`) + modo headless | ✅ funciona |
| Login OAuth (resolveu o 401) | ✅ feito pelo Danilo |
| `run-claude.cmd` testado no contexto REAL do `hermes` | ✅ "HERMES PONTE OK" |
| Auth partilhada (CONFIG_DIR `.claude`) + ACLs hermes (incl. claude.exe no npm) | ✅ aplicadas |
| SOUL.md do Hermes ensinado (instrução + recuperação) | ✅ `/docker/hermes-agent-fvnc/data/SOUL.md` |
| Tailscale VPS→PC | ✅ reativado (estava em baixo) |
| Teste E2E real desde a VPS | ✅ passou |

### Arquitetura da VPS (importante)
- Hermes corre num **container Docker**: `hermes-agent-fvnc-hermes-agent-1`.
- O `tailscale` vive **dentro do container**; o Hermes chama o PC via `ssh bora-pc`
  (config em `/opt/data/.ssh/config`, ProxyCommand `tailscale nc`).
- A chave SSH do container está autorizada em `C:\Users\hermes\.ssh\authorized_keys`.

### ⚠️ Durabilidade (única fraqueza conhecida)
O `tailscaled` **não auto-arranca** se o container do Hermes reiniciar. Se a ponte
falhar com timeout/erro de ligação, correr na VPS:
```bash
ssh root@srv1786862.hstgr.cloud "bash /root/bora-bridge-up.sh"
```
(reativa o Tailscale do container e testa a ligação ao PC). O SOUL.md já instrui o
Hermes a pedir isto ao Danilo quando necessário.

## Decisão de arquitetura (auth hermes vs danil)

**Escolhido: config partilhada via `CLAUDE_CONFIG_DIR`**, apontando a invocação do
`hermes` para `C:\Users\danil\.claude`.

Porquê (vs. copiar credenciais para o hermes, ou correr via `runas`):
- As credenciais são um ficheiro portável (`.claude\.credentials.json`), e ficam
  **no mesmo sítio** que o data-dir default do danil. Resultado: **um único ponto
  de login** — quando o token renova, serve danil E hermes (sem cópias a divergir).
- `runas`/Scheduled Task exigiriam a password do `danil`, mas o `danil` é conta
  **Microsoft online** (sem password local fiável) — foi por isso que o `hermes`
  foi criado. Logo, runas está fora.
- O `hermes` recebeu ACL *Modify* em `C:\Users\danil\.claude` (lê a config e grava
  o refresh do token). Risco aceitável: `hermes` é a conta de acesso remoto do
  próprio Danilo.

## Ficheiros

- `run-claude.cmd` — **a ponte**. O hermes/VPS chama isto. Modo seguro por defeito;
  `set BORA_BRIDGE_FULL=1` para autonomia total.
- `login.cmd` — corre 1x (como danil) para fazer o `/login` no config-dir certo.
- `setup-permissions.ps1` — corre 1x **como admin** (traverse + ACL recursivo +
  opcional chave SSH de teste com `-InstallTestKey`).
- `hermes-soul-snippet.md` — colar no SOUL.md do Hermes na VPS.

## PASSOS PARA FICAR 100% (faltam estes 3)

### 1. Login (obrigatório — resolve o 401)
Duplo-clique ou no terminal:
```
C:\Users\danil\Desktop\produtividade-ia\hermes-bridge\login.cmd
```
→ aceita o trust, escreve `/login`, faz o OAuth, depois `/exit`.

Testar logo a seguir (deve responder "PONTE OK"):
```
run-claude.cmd responde apenas: PONTE OK
```

### 2. Permissões do hermes (1x, como ADMIN)
```
powershell -ExecutionPolicy Bypass -File "C:\Users\danil\Desktop\produtividade-ia\hermes-bridge\setup-permissions.ps1"
```
(adiciona `-InstallTestKey` se quiseres testar `ssh hermes@100.71.105.7` sem password)

### 3. Ensinar o Hermes (na VPS, quando voltar online)
A VPS `bora-vps` está **offline** no Tailscale e não tenho credenciais SSH para ela
aqui. Quando estiver online, colar o conteúdo de `hermes-soul-snippet.md` no SOUL.md
do Hermes (`ssh root@srv1786862.hstgr.cloud`), para a instrução ser **persistente**.

## Teste end-to-end (depois dos passos acima)
Da VPS, como o Hermes faria:
```bash
ssh -o ProxyCommand="tailscale nc %h %p" hermes@100.71.105.7 \
    'run-claude.cmd "lista os ficheiros do projeto bora"'
```

## Segurança
- Modo **seguro por defeito** (sem bash destrutivo). Autonomia total só com
  `BORA_BRIDGE_FULL=1`.
- A guarda de segurança é injetada em **todos** os pedidos: nada destrutivo,
  financeiro (Stripe/dinheiro) ou da Lista Vermelha sem `CONFIRMAÇÃO NECESSÁRIA:`
  ao Danilo primeiro.
- Credenciais/senhas nunca aparecem em output/logs.
