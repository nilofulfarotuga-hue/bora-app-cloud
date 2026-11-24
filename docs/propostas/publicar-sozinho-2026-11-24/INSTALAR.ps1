# "Quem faz a missao publica" (ordem do Danilo, 24/11/2026 07:47). Corre pelo duplo clique do Danilo em
# ATIVAR-PUBLICAR-SOZINHO.cmd: nenhum agente muda as proprias travas (regra da casa).
# Muda tres coisas, cada uma com copia antes e testes; se os testes falharem, volta essa parte atras sozinho:
#   1. a trava global do Claude Code (~\.claude\hooks\trava-modo-automatico.mjs) passa a v2;
#   2. a bora-tranca da pasta principal deixa de recusar publicar (o dinheiro continua recusado);
#   3. a guarda do Dipsy (dsh-bora 0.4.0) deixa de perguntar para publicar.
param(
  [Parameter(Mandatory = $true)][string]$Fonte,
  [string]$Casa = $env:USERPROFILE,
  [string]$Repo = 'C:\BoraLocal\projetosflutter\bora_app'
)
$ErrorActionPreference = 'Continue'
$pasta = Join-Path $Fonte 'docs\propostas\publicar-sozinho-2026-11-24'
$dipsyFonte = Join-Path $Fonte '.claude\dsh\plugin-dsh-bora'
$carimbo = Get-Date -Format yyyyMMdd-HHmmss
$registo = Join-Path $Casa '.claude\publicar-sozinho-instalacao.log'
$estado = [ordered]@{ quando = (Get-Date -Format s); trava = 'por fazer'; tranca = 'por fazer'; dipsy = 'por fazer' }

function Diz($texto) {
  Write-Host $texto
  Add-Content -Encoding utf8 -Path $registo -Value "$(Get-Date -Format s) $texto"
}

# ---------- 1) trava global v2 ----------
$settings = Join-Path $Casa '.claude\settings.json'
$gancho = Join-Path $Casa '.claude\hooks\trava-modo-automatico.mjs'
$copiaS = "$settings.bak-publicar-$carimbo"
$copiaG = "$gancho.bak-publicar-$carimbo"
Copy-Item $settings $copiaS -ErrorAction Stop
if (Test-Path $gancho) { Copy-Item $gancho $copiaG }
try {
  New-Item -ItemType Directory -Force (Split-Path $gancho) | Out-Null
  Copy-Item (Join-Path $pasta 'trava-modo-automatico.mjs') $gancho -Force -ErrorAction Stop
  node (Join-Path $pasta 'registar-gancho.mjs') $settings $gancho
  if ($LASTEXITCODE -ne 0) { throw 'nao consegui registar a trava nos settings' }
  $env:TRAVA_ALVO = $gancho
  node (Join-Path $pasta 'trava-modo-automatico.test.mjs')
  $falhou = $LASTEXITCODE
  Remove-Item Env:TRAVA_ALVO
  if ($falhou -ne 0) { throw 'os testes da trava falharam' }
  $estado.trava = 'v2 ligada e testada'
  Diz '1/3 Trava nova ligada e testada: publicar passa; apagar, forcar, segredos e dinheiro continuam travados.'
} catch {
  Copy-Item $copiaS $settings -Force
  if (Test-Path $copiaG) { Copy-Item $copiaG $gancho -Force }
  $estado.trava = "falhou: $_ (voltou a antiga)"
  Diz "1/3 FALHOU a trava: $_. Voltei a trava antiga."
}

# ---------- 2) bora-tranca na pasta principal ----------
$patch = Join-Path $pasta 'tranca-quem-faz-publica.patch'
if (-not (Test-Path $Repo)) {
  $estado.tranca = "pasta $Repo nao existe"
  Diz "2/3 AVISO: nao encontrei $Repo."
} else {
  git -C $Repo apply --check --reverse --ignore-whitespace $patch 2>$null
  if ($LASTEXITCODE -eq 0) {
    $estado.tranca = 'ja estava'
    Diz '2/3 A tranca ja deixava publicar.'
  } else {
    git -C $Repo apply --check --ignore-whitespace $patch 2>$null
    if ($LASTEXITCODE -ne 0) {
      $estado.tranca = 'nao aplica: a tranca do PC nao esta como a de 05/11'
      Diz '2/3 AVISO: a tranca do PC nao esta como esperado; nao mexi. A trava nova ja funciona sozinha.'
    } else {
      $t = Join-Path $Repo '.claude\plugins\bora-mods\hooks\tranca.ts'
      Copy-Item $t "$t.bak-publicar-$carimbo"
      git -C $Repo apply --ignore-whitespace $patch
      if ($LASTEXITCODE -eq 0) {
        $estado.tranca = 'publicar deixa de ser recusado'
        Diz '2/3 Tranca: publicar deixa de ser recusado; o que e dinheiro continua recusado.'
      } else {
        $estado.tranca = 'falhou ao aplicar'
        Diz '2/3 FALHOU ao mudar a tranca; ficou como estava.'
      }
    }
  }
}

# ---------- 3) guarda do Dipsy (dsh-bora 0.4.0) ----------
Push-Location $dipsyFonte
node --test test/guarda.test.mjs test/autorizacoes.test.mjs test/criador.test.mjs
$testesDipsy = $LASTEXITCODE
Pop-Location
if ($testesDipsy -ne 0) {
  $estado.dipsy = 'testes falharam: nao mexi'
  Diz '3/3 FALHOU: os testes da guarda nova do Dipsy falharam; a antiga ficou.'
} else {
  $alvos = @(
    (Join-Path $Casa 'ferramentas\dsh-plugins\bora__dsh-bora'),
    (Join-Path $Casa '.dsh\profiles\headless\node_modules\dsh-bora'),
    (Join-Path $Casa '.dsh\profiles\web\node_modules\dsh-bora'),
    (Join-Path $Casa '.dsh\profiles\lab\node_modules\dsh-bora')
  ) | Where-Object { Test-Path $_ }
  $feitos = 0
  foreach ($alvo in $alvos) {
    Copy-Item $alvo "$alvo.bak-publicar-$carimbo" -Recurse
    foreach ($parte in 'lib', 'scripts') {
      Copy-Item (Join-Path $dipsyFonte $parte) $alvo -Recurse -Force
    }
    Copy-Item (Join-Path $dipsyFonte 'package.json') $alvo -Force
    $feitos++
  }
  $estado.dipsy = "guarda 0.4.0 em $feitos sitios"
  Diz "3/3 Guarda do Dipsy 0.4.0 copiada para $feitos sitios (com copia antes)."
}

$estado | ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $Casa '.claude\publicar-sozinho-estado.json')
Diz 'Pronto. Vale para as sessoes abertas a partir de agora. Para voltar atras: DESATIVAR-PUBLICAR-SOZINHO.cmd.'
