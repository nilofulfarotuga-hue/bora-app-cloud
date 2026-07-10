---
id: licao-ponte-loop-nao-devolve-output
tipo: licao
origem: [sessão 2026-07-10: ordens 16h+ presas em 'aberta', tentativa 0→3, "executor não forneceu saída"]
ultima_confirmacao: 2026-07-10
zona: verde
confianca: auto
---

# Lição — "a ponte do loop não devolve output" (quase sempre é TIMEOUT, não transporte partido)

**Sintoma.** Ordens de orquestração ficam `aberta`, a `tentativa` sobe (0→…→5→`travada`), e o
Juiz escreve notas do tipo *"executor não forneceu saída — tarefa incompleta"*. Ordens **leves**
passam (`aprovada`, tentativa 0); ordens **pesadas** falham todas. Parece uma ponte morta
(VPS↔PC) — **mas quase nunca é.**

**O que REALMENTE parte.** O transporte está vivo. O elo fraco é o **wall-timeout × formato de saída**:

1. O executor no PC (`run-claude-loop.cmd`) corre `claude -p --output-format text`.
   `--output-format text` **só emite o texto FINAL** — durante os turnos de tool-use (Read/Bash/
   flutter analyze/git) não imprime nada.
2. A `carteiro.sh` embrulha o executor em `timeout 320 pc-loop` (era 320s).
3. Tarefa pesada (ex.: "3 bugs de crash + analyze + push") **não termina em 320s** → o `timeout`
   mata o processo **antes** do texto final → **0 bytes** (o `saida.txt` fica com 1 byte = só `\n`).
4. `clean()` no carteiro ainda remove as linhas de arranque (`Permission deny rule … matches no
   known tool`), por isso o pouco que existia também desaparece → saída **vazia**.
5. Juiz vê vazio → "sem saída" → reabre → repete até `travada`. **Ciclo infinito silencioso.**

Pista decisiva: cada `respondida` cai a **~320s exactos** depois de `executando` = o `timeout` a
disparar (não é aleatório). A 1.ª tentativa às vezes **produz** output porque bate no `--max-turns`
**antes** dos 320s (sai com resultado parcial); as seguintes batem no wall-timeout (mata a meio → nada).

**Como se diagnosticou (ordem util).**
1. Tailscale dos 2 lados — PC `tailscale status` vê `bora-vps` *active/direct*; no container
   `docker exec -u hermes … tailscale status` vê o PC. **Estava UP.** (transporte OK)
2. Testar o executor **isolado**, direto no PC: correr `run-claude-loop.cmd --b64 <b64 de "responde PONG">`
   com timeout curto → **respondeu "PONG" em ~28s.** ⇒ headless `claude.exe` **funciona**; não é auth,
   não é lock, não é transporte.
3. Ler o `carteiro.log`: veredito da 1.ª tentativa foi *"atingiu limite de turnos (20)"* (⇒ houve
   output!) e as seguintes *"sem saída"*. Tamanhos de `*.saida.txt`: **1 byte** nas falhas vs 1414/2061
   bytes nas que passaram. Diferença = **a tarefa acabou ou não dentro do teto.**
4. Confirmar que os `claude.exe` "acumulados" no PC eram o **Claude Desktop app**
   (`WindowsApps\Claude_1.18286…`), **não** executores órfãos — via `Get-CimInstance Win32_Process`
   + `CommandLine`. (Não matar às cegas por nome!)

**Fix aplicado (2026-07-10).**
- `carteiro.sh`: `timeout 320 → 900` no `pc_exec` (dá espaço à tarefa pesada acabar e emitir o texto final).
- `run-claude-loop.cmd`: `--max-turns 20 → 40`, `--max-budget-usd 5 → 10`.
- `carteiro.sh`: **novo log `⚠️ SAIDA VAZIA`** quando o output vem vazio — para NUNCA MAIS confundir
  "tarefa não acabou (timeout)" com "transporte partido". A ponte viva + saída vazia = subir o teto
  ou partir a tarefa, **não** mexer em Tailscale/SSH.
- Provado ponta-a-ponta: `pc-loop` (executor) → `saida` → `pc-judge` (`VEREDITO: APROVADA`) →
  `hermes send -t telegram` (**entregue**).

**Como detetar no futuro (checklist rápido).**
- `respondida` cai **~Xs exactos** depois de `executando` (X = valor do `timeout`)? → é **timeout**, não ponte.
- `*.saida.txt` == 1 byte + log **`SAIDA VAZIA`**? → tarefa não terminou dentro do teto. Sobe o teto ou parte a tarefa.
- Antes de culpar o transporte: `run-claude-loop.cmd --b64 <PONG>` no PC. Volta "PONG"? → transporte OK, o problema é o teto/tarefa.
- Órfãos no PC? Confirmar **CommandLine** (`Get-CimInstance Win32_Process`), não o nome — o Claude **Desktop** também é `claude.exe`.

**Gotchas.**
- `--output-format text` é **tudo-ou-nada**: kill a meio = 0 bytes. Se um dia se quiser output parcial,
  mudar para `stream-json` + tee p/ ficheiro (mais código; para estas tarefas o que interessa é **acabar**).
- O executor corre no **mesmo working tree** (`bora_app`) que uma sessão interactiva. Antes de deixar
  o loop correr, **committar/limpar** as tuas mudanças — senão o executor pode varrê-las num `git add`.
- Ver também: [[docker-exec-user-hermes]] (·`-u hermes`), [[verificar-estado-antes-de-reexecutar]],
  [[onde-vive-a-trava]].
