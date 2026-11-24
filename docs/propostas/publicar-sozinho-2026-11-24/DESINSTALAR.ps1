# Volta ao modo de 05/11 (os agentes nao publicam): repoe as copias que o INSTALAR.ps1 guardou.
param(
  [string]$Casa = $env:USERPROFILE,
  [string]$Repo = 'C:\BoraLocal\projetosflutter\bora_app'
)
function UltimaCopia($ficheiro) {
  Get-ChildItem -Path (Split-Path $ficheiro) -Filter "$(Split-Path $ficheiro -Leaf).bak-publicar-*" -ErrorAction SilentlyContinue |
    Sort-Object Name | Select-Object -Last 1
}
$gancho = Join-Path $Casa '.claude\hooks\trava-modo-automatico.mjs'
$c = UltimaCopia $gancho
if ($c) { Copy-Item $c.FullName $gancho -Force; Write-Host "Trava antiga reposta ($($c.Name))." }

$t = Join-Path $Repo '.claude\plugins\bora-mods\hooks\tranca.ts'
$c = UltimaCopia $t
if ($c) { Copy-Item $c.FullName $t -Force; Write-Host 'Tranca antiga reposta.' }
$teste = Join-Path $Repo '.claude\plugins\bora-mods\hooks\tranca.test.ts'
git -C $Repo checkout -- $teste 2>$null

foreach ($alvo in @(
    (Join-Path $Casa 'ferramentas\dsh-plugins\bora__dsh-bora'),
    (Join-Path $Casa '.dsh\profiles\headless\node_modules\dsh-bora'),
    (Join-Path $Casa '.dsh\profiles\web\node_modules\dsh-bora'),
    (Join-Path $Casa '.dsh\profiles\lab\node_modules\dsh-bora'))) {
  $c = Get-ChildItem -Path (Split-Path $alvo) -Filter "$(Split-Path $alvo -Leaf).bak-publicar-*" -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name | Select-Object -Last 1
  if ($c) {
    Copy-Item (Join-Path $c.FullName '*') $alvo -Recurse -Force
    Write-Host "Guarda do Dipsy reposta em $alvo."
  }
}
Write-Host 'Feito. Vale para as sessoes abertas a partir de agora.'
