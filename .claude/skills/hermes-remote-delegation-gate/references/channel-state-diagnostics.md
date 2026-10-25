# Channel State Diagnostics — `pc` / Tailscale / Claude Code

Session recipe for distinguishing the four channel states of the `pc` delegation
path. Run these in order; stop at the first conclusive result.

## Probes (in order)

### 1. Tailscale node presence
```bash
tailscale status | grep -E '<nome-do-PC>|<IP-tailscale-do-PC>'
```
- No row / `offline, last seen Xm ago` → **OFFLINE**. Stop; bridge repair won't help
  until the host is powered on.
- Row present and `active` → continue to probe 2.

### 2. SSH round-trip (the only one that matters at the transport layer)
```bash
timeout 25 ssh -o ProxyCommand='tailscale nc %h %p' \
  -o StrictHostKeyChecking=accept-new -o ConnectTimeout=25 \
  hermes@<IP-tailscale-do-PC> 'echo BRIDGE_OK'
```
- Timeout / `Connection to UNKNOWN port … timed out` → **OFFLINE** (Tailscale state
  lies; SSH tells the truth).
- Prints `BRIDGE_OK` → transport is green; continue to probe 3.

### 3. Resolve claude.exe (shared helper)
```bash
CLAUDE_EXE=$(timeout 35 ssh -o ProxyCommand="tailscale nc %h %p" \
  -o StrictHostKeyChecking=accept-new -o ConnectTimeout=25 \
  hermes@<IP-tailscale-do-PC> \
  'powershell -NoProfile -ExecutionPolicy Bypass -File C:\\Users\\danil\\Desktop\\produtividade-ia\\hermes-bridge\\resolve-claude-exe.ps1')
# -> C:\Users\danil\AppData\Roaming\Claude\claude-code\<ver>\claude.exe
```
- Empty / `CLI-NAO-ENCONTRADA` → **WRAPPER-BROKEN at resolve step** (or claude-code
  uninstalled). Surface to user; don't dispatch.
- Resolves to a path → continue to probe 4.

### 4. Direct claude.exe ping (account gate)
```bash
timeout 120 ssh -o ProxyCommand='tailscale nc %h %p' \
  -o StrictHostKeyChecking=accept-new -o ConnectTimeout=25 -T \
  hermes@<IP-tailscale-do-PC> \
  "$CLAUDE_EXE -p 'say only PONTE OK' --output-format text --model opus --dangerously-skip-permissions --max-turns 3 <NUL"
```
- Prints `PONTE OK` (or similar) → account is fine; if `pc` still fails, the fault is
  in `run-claude.cmd` → **WRAPPER-BROKEN** → use the Direct Invocation Workaround in
  SKILL.md and flag the wrapper for repair.
- Prints `You've hit your session limit · resets <time> (Europe/London)` (or similar
  rate/usage message) → **ACCOUNT-LIMITED**. Stop. No repair helps; report the reset
  clock to the user and stop retrying. Do NOT try `BORA_MODEL=sonnet` — the limit is
  account-wide, not model-specific.

## State → response matrix

| State | Transport | Account | `pc` behaviour | Right response |
|---|---|---|---|---|
| OFFLINE | down | n/a | timeout | Report offline; ask user to power on PC. |
| ONLINE-OK | up | ok | works | Dispatch via `pc` (background + notify for heavy tasks). |
| ACCOUNT-LIMITED | up | gated | `'ONTE' não é reconhecido` parse-error pattern | Report reset clock; **do not retry**; offer in-container fallback if any. |
| WRAPPER-BROKEN | up | ok | `'ONTE' não é reconhecido` parse-error pattern | Direct claude.exe invocation (workaround in SKILL.md); flag wrapper for repair. |

## Key signal — the parse-error pattern has TWO possible root causes

`'ONTE' não é reconhecido`, `'M' não é reconhecido`, `<< foi inesperado neste momento`
from `pc` are emitted by **cmd.exe**. There are **two** very different root causes
that produce the identical pattern, and only probe 4 disambiguates them:

### Cause A — DOWNSTREAM of a claude.exe failure (ACCOUNT-LIMITED)
claude.exe printed a session-limit/rate message and exited non-zero; `run-claude.cmd`
then falls through and cmd.exe tries to execute the literal
`--append-system-prompt "%GUARD%"` remainder as a command → parse error.
- **Probe 4 result:** session-limit message.
- **Right response:** wait for the clock reset; do NOT repair the wrapper.

### Cause B — UPSTREAM wrapper parsing bug (WRAPPER-BROKEN, verified 2026-08-11)
A `<<` literal appears inside a `REM` comment line of `run-claude.cmd` (the
`copy-pc-heredoc-example` comment). `cmd.exe` analyses redirection operators
(`<`, `>`, `<<`, `>>`) **before** it recognizes a line is a `REM`, so the `<<`
inside the comment makes the parser fail **on every call, regardless of input or
account state**. The parse error fires even when claude.exe is perfectly healthy.
- **Probe 4 result:** `PONTE OK` (claude.exe is fine).
- **Right response:** repair `run-claude.cmd` — remove the `<<` from the comment
  (or replace the example with a non-`<<` form). See
  `references/run-claude-cmd-wrapper-quirks.md` for the base64-transfer repair
  technique that avoids BOM and CRLF corruption.

**Diagnostic rule:** run probe 4 (direct claude.exe ping) before choosing a
response. If probe 4 succeeds and `pc` still parse-errors, it's Cause B
(wrapper bug), not Cause A (account limit) — repair the wrapper, do not wait.