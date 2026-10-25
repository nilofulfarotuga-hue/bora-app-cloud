---
name: hermes-remote-delegation-gate
description: >
  Pre-flight gate for delegating work to a remote PC (via pc / Tailscale SSH /
  bridged Claude Code). Verifies the delegation channel is live BEFORE dispatching
  a task; attempts idempotent repair; and when the channel is irreparably offline,
  reports truthfully and proposes alternatives instead of fabricating results.
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
category: devops
metadata:
  hermes:
    tags: [remote-execution, tailscale, ssh, delegation, preflight, fault-tolerance]
    related_skills: [claude-code, remote-command-execution]
---

# Remote Delegation Gate

## When to Use

Whenever a task must run on the **user's remote PC** (not in this container) and the
transport is the user's Tailscale-bridged `pc` command (or raw SSH to the remote
host). This gate exists because dispatching heavy/delegated work to an offline or
unreachable host silently stalls the session and tempts the agent to fabricate a
result.

The canonical trigger: a task is **too heavy for this container** (deep web
research + scraping + asset generation + ZIP output, etc.) and therefore routes
through `pc "<natural language task>"` — which depends on the Tailscale bridge to
the user's laptop/PC being online.

## Core Method

    verify  arrow  attempt-repair  arrow  dispatch  arrow  monitor

1. **VERIFY** the delegation channel is live with a fast round-trip (see Probe step).
2. **ATTEMPT REPAIR** only if down — idempotently restart the bridge from wherever it
   *can* be run (host or PC). Do not loop; bound to one attempt.
3. **DISPATCH** the real task only after a green round-trip.
4. **MONITOR** the dispatched job (use background + notify_on_complete, never block
   silently).

If the channel cannot be brought back, **stop and report the exact state**. Never
proceed as if the work completed.

## Probe (round-trip health check)

For the `pc` bridge (Tailscale SSH to the user's PC), confirm reachability in two layers:

```bash
# Layer 1 — node present & recently seen in Tailscale
tailscale status | grep -E '<nome-do-PC>|<IP-tailscale-do-PC>'
# Expected: a node line; watch for "offline, last seen Xm ago" or no row at all.

# Layer 2 — actual SSH round-trip (the only one that matters)
timeout 25 ssh -o ProxyCommand='tailscale nc %h %p' \
  -o StrictHostKeyChecking=accept-new -o ConnectTimeout=25 \
  hermes@<IP-tailscale-do-PC> 'echo BRIDGE_OK'
# Green iff it prints BRIDGE_OK within ~25s and exits 0.
```

Interpretation:
- `BRIDGE_OK` → channel healthy; safe to dispatch via `pc`.
- `Connection timed out` / `Connection to UNKNOWN port 65535 timed out` /
  100% packet loss on ping → node is **offline or unreachable**; do NOT dispatch.
- Partial state (`active; relay "xxx"; offline, last seen ...`) → still unreachable;
  treat as offline.

## Attempt Repair (bounded; host-side only)

The bridge repair script lives on the **host** (e.g. `/root/bora-bridge-up.sh`) and
must be executed from the **host** or from the **remote PC** — not from inside this
container, where the `hermes` user lacks permission to `/root`.

- Do NOT try to run host repair scripts from inside the container — `Permission denied`
  is expected, not a signal of progress. Instead: surface the need and ask the user to
  run the repair on the host, OR (if the user's PC is the intended executor) route the
  repair through the working transport to the PC.
- Repair is idempotent: safe to invoke once. Do not retry in a loop.

## Dispatch Rules

- **Heavy/long task** discovered after the gate is green →
  `pc "<task>"` with `background=true` **and** `notify_on_complete=true`.
  Then immediately tell the user a job was started and that you'll report back on
  completion. Never leave the session silent mid-job.
- **Short/fast task** the moment the gate is green → may run `pc "<task>"` in
  foreground, but still prefer background + notify for anything that could exceed a
  few minutes.

## Offline Fallback (the truth-telling rule)

When the channel is offline and cannot be repaired in-session:

1. Report the **exact probe output** (node not seen, or `Connection timed out`, etc.).
2. State plainly what you **cannot** do right now and **why** (not "it's slow" —
   "the user's PC is offline on Tailscale").
3. Offer concrete alternatives (e.g., run a lighter fallback in-container, wait for
   the user to bring the PC online and re-issue, or perform a different sub-part).
4. **Never fabricate** a result, a fake ZIP path, or a plausible-looking summary of work
   that never ran. A truthful "blocked on [reason]" beats a fabricated deliverable.

## Pitfalls

1. **Offline ≠ slow.** A Tailscale node in `offline, last seen 52m ago` state will not
   come back by retrying the same SSH command — it comes back when the remote host itself
   is powered on and its Tailscale daemon is up. Retrying wastes the session's turn
   budget and risks sounding like it is "trying again."
2. **Permission boundary on repair scripts.** Scripts under `/root` on the host (or
   anywhere owned by root outside an accessible volume) are **not** writable/executable by
   this container's `hermes` user. Hitting `Permission denied` here is a *durable*
   operating constraint for this session — flag it clearly rather than retrying the same
   command as root.
3. **Ping lies, SSH tells the truth.** A Tailscale node can respond to ICMP (or even show
   as "active") while the SSH service the bridge needs is not reachable. Always do the
   actual SSH round-trip, not just `tailscale status` or `ping`.
4. **Silence kills long jobs.** A backgrounded `pc` job started without
   `notify_on_complete` runs silently; you have no reliable way to learn it finished.
   Always pair `background=true` with `notify_on_complete=true` for any non-trivial
   delegation.
5. **Don't front-load the bridge repair in conversation.** If the bridge is down,
   the highest-leverage action is usually to (a) clearly report it, and (b) ask the
   user to confirm the remote host is on — not to spend turns re-running identical
   probe commands.
6. **The parse-error pattern can have an upstream cause, not just a downstream one.**
   `'ONTE' não é reconhecido` / `<< foi inesperado neste momento` from `pc` can
   be caused by (a) claude.exe failing for an unrelated reason, OR (b) a `<<`
   literal in a `REM` comment line of `run-claude.cmd` that `cmd.exe` mis-parses
   as a redirection **before** recognizing the comment — the latter fires on
   every call regardless of account state or input. Disambiguate with the
   ordered probe in `references/channel-state-diagnostics.md` (Section "Key
   signal"). Only probe 4 there (direct claude.exe ping) tells you whether the
   account is gated; if probe 4 succeeds but `pc` still parse-errors, the
   wrapper has a parsing bug — repair it per
   `references/run-claude-cmd-wrapper-quirks.md`.
7. **Session-limit ≠ offline ≠ broken.** A green SSH round-trip plus a claude.exe
   `session limit` message means the **account** is gated on a clock, not the hardware
   or the wrapper. Running `bora-bridge-up.sh`, switching `BORA_MODEL`, or retrying
   `pc` will not help. Report the reset time from the message and stop. The limit is
   account-wide, not model-specific — `BORA_MODEL=sonnet` does not bypass it.

## Account-Limit vs. Offline (the session gate)

The `pc` bridge transport can be **green at the TCP/SSH layer while the Claude
Code account itself is blocked**. This is a third channel state — not "offline",
not "broken" — and it has its own tell:

- claude.exe prints: `You've hit your session limit · resets 3:10am (Europe/London)`
  (or a similarly phrased rate/usage reset message).
- `run-claude.cmd` may also surface a **wrapper-parse-error pattern** (`'ONTE'
  não é reconhecido`, `'M' não é reconhecido`, `<< foi inesperado neste momento`).
  **Do not assume this is a downstream effect of claude.exe failing** — that
  theory was falsified on 2026-08-11: the real root cause was a `<<` literal
  inside a `REM` comment line of `run-claude.cmd`, which `cmd.exe` parses as a
  redirection operator *before* it recognizes the line is a comment (a known
  cmd.exe quirk). The parse error fired on EVERY `pc` call regardless of input
  or account state, and after the `<<` was removed from the comment, the parse
  error vanished and the real claude.exe message surfaced cleanly. See
  `references/run-claude-cmd-wrapper-quirks.md` for the full diagnosis and the
  base64-transfer repair technique.

### Diagnosing the three states

| Probe | Offline | Account-limited | Wrapper-broken |
|---|---|---|---|
| `ssh ... 'echo BRIDGE_OK'` | timeout / no row in `tailscale status` | `BRIDGE_OK` | `BRIDGE_OK` |
| `ssh ... '<resolved claude.exe> -p "ping" <NUL'` | timeout | session-limit message | works (proves wrapper is the bug) |
| `pc "ping"` | timeout | wrapper-parse-error pattern | wrapper-parse-error pattern |

**Critical:** when the direct claude.exe probe prints a **session-limit message**,
the channel is NOT down and NOT broken — the **account** is out of session. No
amount of bridge repair, `bora-bridge-up.sh`, or wrapper fixing will recover this
state; it resets on a clock (the reset time is in the message, e.g. `3:10am
Europe/London`). Report that exact clock to the user and stop retrying. Attempting
`BORA_MODEL=sonnet` (a different model) does NOT bypass the limit — it is account-
wide, not model-specific.

When the direct claude.exe probe **succeeds**, the account is fine and the fault is
truly in `run-claude.cmd` — proceed to the workaround below.

## Direct Invocation Workaround (when `run-claude.cmd` breaks)

The `pc` command shells out to `run-claude.cmd` on the remote PC. That wrapper
can break — symptoms are cmd.exe parse errors like `'ONTE' não é reconhecido`,
`'M' não é reconhecido`, `<< foi inesperado neste momento`, even on trivial
probes. When this happens, **first run the direct claude.exe probe above to
distinguish account-limit from wrapper-broken**, then if it's truly the wrapper,
**bypass it and invoke `claude.exe` directly over SSH+stdin**. This is durable:
the wrapper has been broken before (it documents its own "4 dias de avaria
silenciosa" history).

### Step 1 — resolve the claude.exe path (via the shared helper)

```bash
CLAUDE_EXE=$(timeout 35 ssh -o ProxyCommand="tailscale nc %h %p" \
  -o StrictHostKeyChecking=accept-new -o ConnectTimeout=25 \
  hermes@<IP-tailscale-do-PC> \
  'powershell -NoProfile -ExecutionPolicy Bypass -File C:\\Users\\danil\\Desktop\\produtividade-ia\\hermes-bridge\\resolve-claude-exe.ps1')
# -> C:\Users\danil\AppData\Roaming\Claude\claude-code\<ver>\claude.exe
```

### Step 2 — pipe the task via stdin to claude.exe directly

```bash
GUARD='Estas a correr em modo headless via ponte SSH remota (Hermes). MODO PADRAO = AGIR. Devolve um RESULTADO claro em PT-BR.'
echo "<tarefa em português>" | timeout 300 ssh -o ProxyCommand="tailscale nc %h %p" \
  -o StrictHostKeyChecking=accept-new -o ConnectTimeout=25 \
  hermes@<IP-tailscale-do-PC> \
  "cd /d C:\\Users\\danil\\Desktop\\projetosflutter\\bora_app && \"$CLAUDE_EXE\" -p --append-system-prompt \"$GUARD\" --output-format text --model opus --dangerously-skip-permissions --max-turns 25"
```

Key flags mirror what `run-claude.cmd` sets: `-p` (print mode, non-interactive),
`--append-system-prompt` for the headless guard, `--output-format text`,
`--model opus`, `--dangerously-skip-permissions` (autonomy), `--max-turns 25`
(cost cap). **Pipe the prompt via stdin** (`echo "..." | ssh ...`) — never pass
it as a positional arg, because cmd.exe mangles positional args with spaces,
quotes, and `--` flags.

### When to use this workaround

- `pc "..."` returns the cmd.exe parse-error pattern above (consistent across
  multiple attempts, not a one-off).
- You need to keep working while the wrapper is being fixed.
- You want to vary flags the wrapper hardcodes (e.g. test a different `--model`).

Do NOT silently switch to this path for routine work — `run-claude.cmd` adds the
GUARD prompt, dynamic exe resolution, and base64 transport that are worth
keeping. Use this as a **fallback**, and flag to the user that the wrapper
needs repair.

## Gateway Go model selection (juiz/orquestrador throughput)

The Hermes inference layer (gateway OpenCode Go) feeds the juiz that gates
orders before they reach the PC. When the juiz model is wrong, the entire
delegation pipeline stalls — `JUIZ-SEM-VEREDITO` and `SAIDA-VAZIA` errors block
orders from ever being dispatched. See `references/gateway-go-model-rules.md`
for the model-selection rules (which models support tools, which give 422,
which need raised `max_tokens`).

## See Also

- `claude-code` — the Claude Code orchestration the `pc` wrapper targets on the remote PC.
- `remote-command-execution` — raw SSH execution pattern; this gate is its pre-flight.
- `references/gateway-go-model-rules.md` — gateway Go model quirks that affect juiz throughput.
- `references/channel-state-diagnostics.md` — ordered probe recipe to distinguish
  OFFLINE / ONLINE-OK / ACCOUNT-LIMITED / WRAPPER-BROKEN states of the `pc` channel.
- `references/run-claude-cmd-wrapper-quirks.md` — root cause and base64-transfer
  repair for the `<<` in `REM` parse-error pattern in `run-claude.cmd` (verified
  2026-08-11).
