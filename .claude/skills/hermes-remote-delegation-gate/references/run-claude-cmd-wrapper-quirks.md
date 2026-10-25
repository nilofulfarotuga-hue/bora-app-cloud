# run-claude.cmd Wrapper Quirks — `<<` in REM parse error & repair

Root cause and repair recipe for the `pc` wrapper-parse-error pattern, verified
2026-08-11. The earlier theory (that the parse error is always downstream of a
claude.exe failure) was **falsified** in that session.

## The bug: `<<` literal inside a `REM` comment line

`run-claude.cmd` (on the remote PC, at
`C:\Users\danil\Desktop\produtividade-ia\hermes-bridge\run-claude.cmd`) contained a
comment line illustrating heredoc usage:

```
REM         ssh ... hermes@PC "C:\...\run-claude.cmd" <<'BORA_TASK'
```

`cmd.exe` analyses redirection operators (`<`, `>`, `<<`, `>>`) **before** it
recognises a line is a `REM` comment. The `<<` inside that `REM` line makes the
parser fail, producing on **every** `pc` call:

```
'ONTE' não é reconhecido como um comando interno
ou externo, um programa operável ou um arquivo em lotes.
'M' não é reconhecido ...
'-' não é reconhecido ...
<< foi inesperado neste momento.
```

This error is **identical regardless of the argument passed to `pc`** and
regardless of the Claude account state — it fires before claude.exe is ever
reached. That uniformity (same 4 lines, same order, for `pc "teste"` and
`pc "diga ola"`) is the tell that it's a parsing bug, not an account failure.

## Disambiguation — run probe 4 first

Before repairing, confirm it's the wrapper (Cause B) and not an account limit
(Cause A) by invoking claude.exe directly over SSH (probe 4 in
`channel-state-diagnostics.md`):

```bash
# Resolve the exe
CLAUDE_EXE=$(timeout 35 ssh -o ProxyCommand="tailscale nc %h %p" \
  -o StrictHostKeyChecking=accept-new -o ConnectTimeout=25 \
  hermes@<IP-tailscale-do-PC> \
  'powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\danil\Desktop\produtividade-ia\hermes-bridge\resolve-claude-exe.ps1')

# Direct ping — pipes a trivial prompt via stdin
echo "say only PONTE OK" | timeout 120 ssh -o ProxyCommand="tailscale nc %h %p" \
  -o StrictHostKeyChecking=accept-new -o ConnectTimeout=25 -T \
  hermes@<IP-tailscale-do-PC> \
  "cd /d C:\\Users\\danil\\Desktop\\projetosflutter\\bora_app && \"$CLAUDE_EXE\" -p --output-format text --model opus --dangerously-skip-permissions --max-turns 3"
```

- Prints `PONTE OK` → wrapper bug (Cause B). Repair below.
- Prints `You've hit your session limit · resets <time>` → account limit (Cause A);
  **do not repair the wrapper** — wait for the clock reset.

## Repair — base64 transfer (avoids BOM and CRLF corruption)

The repair is to remove (or rewrite) any `<<` literal in a `REM` line of
`run-claude.cmd`. Because the file lives on the remote Windows PC and is sensitive
to encoding (a UTF-8 BOM makes cmd.exe choke on the first `@echo off`, and lost
CRLFs collapse the script to one line), the durable technique is:

1. Author the corrected `.cmd` locally in the container (LF endings), then
   `sed -i 's/$/\r/'` to convert to CRLF.
2. `base64 -w0` the file to a single string (no newlines, no padding issues).
3. Transfer and decode on the PC with `[IO.File]::WriteAllBytes` (writes raw bytes,
   **no BOM**, preserves CRLF):

```bash
B64=$(base64 -w0 /tmp/new-run-claude.cmd)
ssh -o ProxyCommand="tailscale nc %h %p" \
  -o StrictHostKeyChecking=accept-new -o ConnectTimeout=25 \
  hermes@<IP-tailscale-do-PC> \
  "powershell -NoProfile -ExecutionPolicy Bypass -Command \"[IO.File]::WriteAllBytes('C:\\Users\\danil\\Desktop\\produtividade-ia\\hermes-bridge\\run-claude.cmd',[Convert]::FromBase64String('$B64')); Write-Output WROTE_OK\""
```

### Critical pitfalls during repair

- **`Set-Content -Encoding UTF8` adds a BOM.** A BOM before `@echo off` makes
  cmd.exe emit `'﻿@echo' não é reconhecido`. Always use `[IO.File]::WriteAllBytes`
  (raw bytes) or `New-Object Text.UTF8Encoding($false)` to avoid the BOM.
- **`Get-Content` + `Set-Content` can collapse CRLFs to a single line** if the
  join/encoding step mishandles `` `r`n ``. After any write, verify with:
  - First 3 bytes are `40 65 63` (`@ec`) — proves no BOM.
  - `(Get-Content $p).Count` equals the expected line count — proves CRLFs
    survived.
  - `findstr /C:"<<" $p` returns nothing — proves the `<<` was removed.
- **Take a backup first.** `Copy-Item $p ($p + '.bak')` before editing. Note:
  the first repair attempt in the 2026-08-11 session failed silently (escaping
  ate the `$p` expansion) so no `.bak` was actually created before the overwrite
  — the original was reconstructed from a `type` capture captured earlier in the
  same session. Always confirm the backup exists (`Test-Path ...bak`) before
  proceeding to overwrite.

## Post-repair verification

After the repair, `pc "diga ola"` should either:
- succeed (claude.exe runs and returns a result), or
- surface the real claude.exe message cleanly (e.g. a session-limit line, with
  no more `'ONTE'` / `<<` parse errors).

If the `'ONTE'` / `<<` pattern disappears, the wrapper parse bug is fixed; any
remaining failure is upstream of the wrapper (account limit, model error, etc.)
and should be diagnosed per `channel-state-diagnostics.md`.

## General rule for `.cmd` files

**Never put `<<` (or `>>`) in a `REM` comment line** — `cmd.exe` parses
redirection operators before it recognizes comments. Use a placeholder like
`<HEREDOC>` or `STDIN-HEREDOC` (plain text, no `<`/`>` duplicates) when
illustrating heredoc syntax in a comment.