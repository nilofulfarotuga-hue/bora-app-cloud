# resolve-claude-exe.ps1 — FASE 1.11 (2026-08-01)
# Devolve no stdout o caminho da CLI do Claude Code MAIS RECENTE, ou nada se não existir.
#
# Porquê um ficheiro e não um one-liner dentro do .cmd: dentro de `for /f "usebackq"` o cmd.exe
# interpreta o `|` do pipeline antes do PowerShell o ver; escapá-lo com `^|` passa o `^` literal
# e o Sort-Object rebenta ("não é possível localizar um parâmetro posicional"). O .cmd já usa
# este padrão para os outros helpers (executor-lock.ps1, stale-output-watchdog.ps1).
#
# Ordenação por [version] e NÃO alfabética: alfabeticamente "2.1.9" > "2.1.10", o que escolheria
# uma CLI antiga. Nunca fixar versão — a 27/07 a app saltou para 2.1.219 e o caminho fixo anterior
# (npm global) desapareceu, partindo o loop em silêncio durante 4 dias.
param(
  [string]$Root = "$env:APPDATA\Claude\claude-code",
  [string]$FallbackRoot = 'C:\Users\danil\AppData\Roaming\Claude\claude-code'
)
$ErrorActionPreference = 'SilentlyContinue'

$roots = @($Root, $FallbackRoot) | Select-Object -Unique
foreach ($r in $roots) {
  if (-not (Test-Path -LiteralPath $r)) { continue }
  $cands = Get-ChildItem -Path (Join-Path $r '*\claude.exe') -ErrorAction SilentlyContinue
  if (-not $cands) { continue }
  $best = $cands |
    Sort-Object { try { [version]$_.Directory.Name } catch { [version]'0.0.0' } } |
    Select-Object -Last 1
  if ($best) { Write-Output $best.FullName; exit 0 }
}

# Último recurso: um shim no PATH (existe quando a CLI foi instalada per-user para ESTE utilizador).
$cmd = Get-Command claude -ErrorAction SilentlyContinue
if ($cmd -and $cmd.Source) { Write-Output $cmd.Source; exit 0 }
exit 1
