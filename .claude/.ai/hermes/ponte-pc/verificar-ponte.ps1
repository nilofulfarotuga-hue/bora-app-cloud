# verificar-ponte.ps1 -- deteta DRIFT entre a copia versionada no repo e a ponte VIVA do PC.
#
# Porque existe (Parte 3 da missao sistema-redondo-2026-08-01):
# a hermes-bridge vivia so no disco do PC, fora de qualquer controlo de versoes. Consequencia real
# apanhada a 2026-08-01: o fix de negacao do juiz estava no repo e NAO estava vivo -- o
# juiz-mecanico.ps1 da ponte era de 16/07. "Deployar num lado nao e' deployar no outro", e sem
# esta verificacao ninguem dava por isso.
#
#   .\verificar-ponte.ps1             -> so relata (sai 1 se houver drift)
#   .\verificar-ponte.ps1 -Sincroniza -> copia repo -> ponte (com backup datado de cada ficheiro)
#
# NUNCA copia no sentido inverso: o repo e' a fonte da verdade. Se a ponte tiver uma alteracao
# legitima que o repo nao tem, traz-se essa alteracao para o repo a mao e faz-se commit -- senao
# perde-se de novo, que e' exactamente o problema que isto vem resolver.
#
# NOTA DE CODIFICACAO: este ficheiro e' ASCII puro de proposito. O Windows PowerShell 5.1 le
# ficheiros UTF-8 SEM BOM como ANSI e travessoes/acentos partem o parser (apanhado a 2026-08-01).
param([switch]$Sincroniza)

$ErrorActionPreference = 'Stop'
# $PSScriptRoot = ...\.claude\.ai\hermes\ponte-pc  ->  dois niveis acima = ...\.claude\.ai
$repoRaiz = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$deploy   = Join-Path $repoRaiz 'hermes\orquestrador-carteiro\deploy'
$pontePC  = Join-Path $PSScriptRoot 'hermes-bridge'
$vivo     = 'C:\Users\danil\Desktop\produtividade-ia\hermes-bridge'

# ficheiro -> pasta do repo onde vive a copia canonica
$mapa = [ordered]@{
  'juiz-mecanico.ps1'         = $deploy
  'diagnostica-juiz.ps1'      = $deploy
  'run-claude-loop.cmd'       = $deploy
  'run-claude-judge.cmd'      = $deploy
  'bora-live-parser.ps1'      = $deploy
  'resolve-claude-exe.ps1'    = $deploy
  'stale-output-watchdog.ps1' = $deploy
  'executor-lock.ps1'         = $deploy
  'login.cmd'                 = $pontePC
  'run-claude.cmd'            = $pontePC
  'setup-permissions.ps1'     = $pontePC
}

if (-not (Test-Path $vivo)) { Write-Host "!! ponte viva nao encontrada em $vivo" -ForegroundColor Red; exit 2 }

$drift = 0
$faltam = 0
foreach ($f in $mapa.Keys) {
  $r = Join-Path $mapa[$f] $f
  $v = Join-Path $vivo $f
  if (-not (Test-Path $r)) {
    Write-Host ("SO_VIVO   {0,-26} nao esta no repo - traz para o repo a mao" -f $f) -ForegroundColor Yellow
    $faltam++
    continue
  }
  if (-not (Test-Path $v)) {
    Write-Host ("SO_REPO   {0,-26} nao esta na ponte viva" -f $f) -ForegroundColor Yellow
    $faltam++
    continue
  }
  $hr = (Get-FileHash $r -Algorithm SHA256).Hash
  $hv = (Get-FileHash $v -Algorithm SHA256).Hash
  if ($hr -eq $hv) {
    Write-Host ("IGUAL     {0,-26} {1}" -f $f, $hr.Substring(0, 12)) -ForegroundColor Green
    continue
  }

  $drift++
  Write-Host ("DIVERGE   {0,-26} repo={1} vivo={2}" -f $f, $hr.Substring(0, 12), $hv.Substring(0, 12)) -ForegroundColor Red
  if ($Sincroniza) {
    $ts = Get-Date -Format 'yyyyMMddTHHmmssZ'
    Copy-Item $v ("{0}.bak_{1}" -f $v, $ts) -Force
    Copy-Item $r $v -Force
    Write-Host ("          -> sincronizado (backup em {0}.bak_{1})" -f (Split-Path $v -Leaf), $ts) -ForegroundColor Cyan
  }
}

Write-Host ''
# Um ficheiro que so existe de um lado NAO e' "sem drift": ou o mapa esta errado, ou ha trabalho
# vivo por versionar. Conta como problema, senao este relatorio mente ao dizer verde.
if ($faltam -gt 0) {
  Write-Host "$faltam ficheiro(s) so num dos lados - ver acima. Mapa errado ou trabalho por versionar." -ForegroundColor Yellow
}
if ($drift -eq 0 -and $faltam -eq 0) {
  Write-Host 'SEM DRIFT: repo e ponte viva batem certo.' -ForegroundColor Green
  exit 0
}
if ($drift -eq 0) { exit 1 }
if ($Sincroniza) {
  Write-Host "$drift ficheiro(s) sincronizados repo -> ponte." -ForegroundColor Cyan
  exit 0
}
Write-Host "$drift ficheiro(s) com DRIFT. Corre com -Sincroniza para alinhar (ou traz a alteracao da ponte para o repo)." -ForegroundColor Red
exit 1
