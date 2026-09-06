---
id: licao-ponte-loop-nao-devolve-output
tipo: licao
origem: [sessão 2026-07-10: ordens 16h+ presas em 'aberta', tentativa 0→3, "executor não forneceu saída"]
ultima_confirmacao: 2026-07-10
zona: verde
confianca: auto
---

# Lição — "a ponte do loop não devolve output" (o executor nem ARRANCA para tarefas grandes)

**Sintoma.** Ordens de orquestração ficam `aberta`, a `tentativa` sobe (0→…→5→`travada`), e o
Juiz escreve *"executor não forneceu saída — tarefa incompleta"*. Ordens **leves** passam
(`aprovada`, tentativa 0); ordens **pesadas** falham **todas**. `*.saida.txt` = **1 byte** (só `\n`).
Parece uma ponte VPS↔PC morta — **não é.**

## Causa-raiz REAL (confirmada por reprodução) — argumento base64 grande

O `pc-loop` (no container) entregava a tarefa ao PC assim:
`ssh … hermes@PC "run-claude-loop.cmd --b64 <BASE64_DA_TAREFA>"` — ou seja, a tarefa **inteira em
base64 como ARGUMENTO de linha de comando** do comando remoto do ssh.

- Tarefa pequena (b64 curto) → o `.cmd` corre, `claude.exe` arranca, devolve output. ✅
- Tarefa real (≥~1 KB → b64 ≥~1500 chars) → o **OpenSSH do Windows falha em executar o `.cmd`**
  com um argumento remoto grande: o `.cmd` **nunca corre** (o ficheiro temporário
  `%TEMP%\bora_loop_task.txt` não é actualizado, **não há `cmd.exe` nem `claude.exe` no PC**), o
  `ssh` fica **pendurado** até o `timeout` da carteiro o matar → **0 bytes**. ❌

Prova (2026-07-10): mesma tarefa de 1183 bytes → via **arg** `--b64` = 0 bytes, `claude.exe` nunca
arranca; via **STDIN** `--b64stdin` = devolve output normal. Tarefa de 47 bytes via arg = funciona.
⇒ **é o tamanho do argumento, não o transporte** (o leg `container→PC` via `tailscale nc`+ssh está
vivo: `ssh … "echo PONG"` volta na hora).

**Fix (o que resolve):** passar o base64 por **STDIN**, não como argumento.
- `pc-loop`: `printf '%s' "$*" | base64 | tr -d '\n=' | ssh … "run-claude-loop.cmd --b64stdin"`.
- `run-claude-loop.cmd`: novo ramo `--b64stdin` lê o b64 de `[Console]::In.ReadToEnd()`, descodifica
  para `%TEMP%\bora_loop_task.txt`, e corre `claude -p … < ficheiro`. Sem limite de tamanho.

## Causa secundária (defensiva, também corrigida) — timeout × `--output-format text`

Mesmo quando o executor ARRANCA, `claude -p --output-format text` **só emite o texto no FIM**
(nada nos turnos de tool-use). Se a tarefa não acabar dentro do `timeout` da carteiro, o kill devolve
**0 bytes** — outra vez indistinguível de ponte morta. Por isso subiu-se também:
`timeout 320→900s` (carteiro) · `--max-turns 20→40`, `--max-budget-usd 5→10` (`run-claude-loop.cmd`).
E adicionou-se log **`⚠️ SAIDA VAZIA`** no carteiro (separa "não acabou" de "transporte partido").

> Nota honesta: a 1.ª leitura desta sessão culpou o `timeout` (o `respondida ~320s` parecia claude a
> correr 320s). O teste directo mostrou que era o `ssh` **pendurado** 320s à espera de um `.cmd` que
> **nunca corria** — o teto de tempo era sintoma, não causa. A causa é o argumento grande.

## Como diagnosticar (ordem útil, para a próxima)
1. **Transporte primeiro:** `docker exec -u hermes $C sh -lc 'ssh -o ProxyCommand="tailscale nc %h %p" … hermes@PC "echo PONG"'`. Volta "PONG"? → transporte OK, **não** é Tailscale/SSH.
2. **O `.cmd` chega a correr no PC?** No PC: `Get-Item $env:TEMP\bora_loop_task.txt` (mtime recente?) +
   `Get-CimInstance Win32_Process -Filter "Name='claude.exe'"` filtrando `--output-format text`.
   **Ficheiro velho + 0 `claude.exe` + `ssh`/`pc-loop` vivo no container = o `.cmd` NÃO arranca** →
   suspeitar do **tamanho do argumento** (ou de ter voltado ao `--b64` em vez de `--b64stdin`).
3. **Reproduzir por tamanho:** correr `pc-loop` com tarefa pequena (funciona) vs ~1 KB (falha via arg).
4. `respondida` cai a **~Xs exactos** (X=`timeout`)? Pode ser (a) ssh pendurado (arg grande) **ou**
   (b) claude a correr sem acabar. Distinguir pelo passo 2 (há `claude.exe`? o temp actualizou?).
5. Órfãos no PC: confirmar **CommandLine** (`Get-CimInstance Win32_Process`), **não** o nome — o Claude
   **Desktop** (`WindowsApps\Claude_1.18286…`) também é `claude.exe`; não matar às cegas.

## Gotchas
- **Nunca** passar payloads grandes como argumento de comando remoto de ssh no Windows → usar STDIN.
- `--output-format text` é tudo-ou-nada: kill a meio = 0 bytes.
- O executor corre no **mesmo working tree** (`bora_app`) que a sessão interactiva → **committar/limpar
  antes** de deixar o loop correr, senão o executor varre as tuas mudanças num `git add`.
- Um **gap** (reset da sessão) pode reabrir ordens antigas `travada`; verificar a fila (`grep -l 'estado: aberta'`)
  antes de religar o kill switch, para não gastar slots do executor em ordens fora da lista.
- Ver também: [[docker-exec-user-hermes]], [[verificar-estado-antes-de-reexecutar]], [[onde-vive-a-trava]].
