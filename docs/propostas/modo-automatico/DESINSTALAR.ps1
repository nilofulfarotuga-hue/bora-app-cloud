# Desliga a trava do modo automatico e volta as guardas antigas ao que eram.
param(
  [string]$Casa = $env:USERPROFILE,
  [string]$Repo = 'C:\BoraLocal\projetosflutter\bora_app'
)
$pasta = $PSScriptRoot
$settings = Join-Path $Casa '.claude\settings.json'
$gancho = Join-Path $Casa '.claude\hooks\trava-modo-automatico.mjs'
$patch = Join-Path $pasta 'guardas-ramo-ai.patch'

Copy-Item $settings "$settings.bak-antes-de-desligar-$(Get-Date -Format yyyyMMdd-HHmmss)" -ErrorAction Stop
node (Join-Path $pasta 'registar-gancho.mjs') $settings $gancho --tirar
if ($LASTEXITCODE -ne 0) { Write-Host 'FALHOU: nao consegui tirar a trava dos settings.'; exit 1 }
Remove-Item $gancho -ErrorAction SilentlyContinue

if (Test-Path $Repo) {
  git -C $Repo apply --check --reverse --ignore-whitespace $patch 2>$null
  if ($LASTEXITCODE -eq 0) { git -C $Repo apply --reverse --ignore-whitespace $patch }
}
Write-Host 'Trava desligada. Vale para as sessoes abertas a partir de agora.'
