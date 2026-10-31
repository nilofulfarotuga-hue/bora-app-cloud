# dsh-commit.ps1 - o UNICO caminho de commit do Dipsy (dsh). Corre o Juiz antes e RECUSA o commit se ele falhar.
# Codigo nosso, missao C-liga (30/10/2026). Nunca faz push. A guarda do Dipsy barra "git commit" a mao.
#
# Uso (pelo pwsh do dsh ou a mao):
#   powershell -NoProfile -File C:\Users\danil\.dsh\dsh-commit.ps1 -Mensagem "docs: nota X" -Caminhos docs/a.md,docs/b.md [-Repo <pasta>] [-Tarefa feature|fix]
#
# O que faz, por esta ordem:
#   1. valida a mensagem e os caminhos (sem asteriscos, sem segredos, dentro do repo);
#   2. monta um indice temporario SO com esses caminhos (o trabalho de outras sessoes nunca entra no julgamento);
#   3. corre o Juiz anti-trapaca (.claude/juiz/anti_trapaca.py) e o das zonas protegidas (zonas_diff.py) sobre essa mudanca;
#   4. se qualquer um sair com codigo diferente de 0 (batota, zona protegida, precisa de olho humano, juiz em falta):
#      NAO faz commit e diz porque;
#   5. so se ambos passarem, faz "git commit --only" desses caminhos e regista tudo em ~/.dsh/juiz-dsh.log.
param(
  [Parameter(Mandatory = $true)][string]$Mensagem,
  [Parameter(Mandatory = $true)][string[]]$Caminhos,
  [string]$Repo = (Get-Location).Path,
  [ValidateSet('feature', 'fix')][string]$Tarefa = 'feature'
)
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$log = Join-Path $env:USERPROFILE '.dsh\juiz-dsh.log'

function Registar([string]$estado, [string]$detalhe) {
  try {
    $linha = @{ quando = (Get-Date).ToString('s'); estado = $estado; repo = $Repo; caminhos = ($Caminhos -join ','); detalhe = $detalhe } | ConvertTo-Json -Compress
    Add-Content -Path $log -Value $linha -Encoding UTF8
  } catch { }
}
function Recusar([string]$motivo) {
  Registar 'recusado' $motivo
  Write-Output "COMMIT RECUSADO: $motivo"
  exit 1
}

# 1. validacoes
$Caminhos = @($Caminhos | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($Mensagem.Trim().Length -lt 8) { Recusar 'a mensagem do commit e curta demais (minimo 8 letras).' }
if ($Caminhos.Count -eq 0) { Recusar 'diz que ficheiros queres commitar (-Caminhos), um a um.' }
$raiz = (& git -C $Repo rev-parse --show-toplevel) 2>$null
if (-not $raiz) { Recusar "isto nao e um repositorio git: $Repo" }
$raiz = ($raiz | Select-Object -First 1).Trim()
$segredos = '(^|[\\/])\.env(?![\w-])(?!\.(example|sample|template))|\.supabase-token|\.dart_defines|(^|[\\/])(secrets|_segredos)([\\/]|$)|\.credentials|id_(rsa|ed25519|ecdsa)|\.(pem|pfx|p12|jks|keystore)$|aviso\.conf|\.claude\.json'
foreach ($c in $Caminhos) {
  if ($c -match '[*?]' -or $c -eq '.' -or $c -eq '..' -or $c -match '^\.\.[\\/]') { Recusar "caminho nao permitido (asteriscos, ponto ou fora do repo): $c" }
  if ($c -match $segredos) { Recusar "isto e segredo, nunca entra num commit: $c" }
  $abs = if ([IO.Path]::IsPathRooted($c)) { $c } else { Join-Path $raiz $c }
  $noHead = (& git -C $raiz ls-files --error-unmatch -- $c 2>$null)
  if (-not (Test-Path -LiteralPath $abs) -and -not $noHead) { Recusar "o ficheiro nao existe: $c" }
}

$juiz = Join-Path $raiz '.claude\juiz\anti_trapaca.py'
$zonas = Join-Path $raiz '.claude\juiz\zonas_diff.py'
if (-not (Test-Path $juiz) -or -not (Test-Path $zonas)) { Recusar 'o Juiz nao esta neste repositorio (.claude/juiz): sem Juiz nao ha commit.' }
$py = (Get-Command python -ErrorAction SilentlyContinue)
if (-not $py) { Recusar 'nao encontro o Python para correr o Juiz: sem Juiz nao ha commit.' }

# 2. indice temporario so com os caminhos pedidos
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("dsh-indice-" + [guid]::NewGuid().ToString('N') + '.idx')
$env:GIT_INDEX_FILE = $tmp
try {
  & git -C $raiz read-tree HEAD
  if ($LASTEXITCODE -ne 0) { Remove-Item Env:GIT_INDEX_FILE; Recusar 'nao consegui ler o HEAD.' }
  foreach ($c in $Caminhos) { & git -C $raiz add -- $c 2>$null | Out-Null }
  $arvore = ((& git -C $raiz write-tree) | Select-Object -First 1).Trim()
} finally {
  Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
if (-not $arvore) { Recusar 'nao consegui montar a mudanca para o Juiz.' }
& git -C $raiz diff --quiet HEAD $arvore
if ($LASTEXITCODE -eq 0) { Recusar 'nada para commitar: esses ficheiros nao mudaram.' }

# 3. o Juiz
Push-Location $raiz
$s1 = (& python $juiz --base HEAD --head $arvore --task $Tarefa) | Out-String
$rc1 = $LASTEXITCODE
$s2 = (& python $zonas --base HEAD --head $arvore) | Out-String
$rc2 = $LASTEXITCODE
Pop-Location
$resumo = ("anti_trapaca rc=$rc1; zonas rc=$rc2")
if ($rc1 -ne 0) { Recusar ("o Juiz anti-trapaca nao deixou passar ($resumo). " + (($s1 -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 6) -join ' | ')) }
if ($rc2 -ne 0) { Recusar ("o Juiz das zonas protegidas nao deixou passar ($resumo): mexe em zona de dinheiro ou despacho, so com o autorizo do Danilo. " + (($s2 -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 6) -join ' | ')) }

# 4. commit so desses caminhos (git add dos caminhos pedidos; --only deixa de fora tudo o resto que esteja preparado)
foreach ($c in $Caminhos) { & git -C $raiz add -- $c 2>$null | Out-Null }
& git -C $raiz commit -q -m $Mensagem -m 'Commit do Dipsy (dsh): passou no Juiz (anti-trapaca e zonas protegidas).' --only -- $Caminhos
if ($LASTEXITCODE -ne 0) { Recusar "o git recusou o commit (codigo $LASTEXITCODE)." }
$hash = ((& git -C $raiz rev-parse --short HEAD) | Select-Object -First 1).Trim()
Registar 'commitado' ("$hash; $resumo")
Write-Output "PASSOU NO JUIZ ($resumo). Commit $hash feito so com: $($Caminhos -join ', '). Nao fiz push."
exit 0
