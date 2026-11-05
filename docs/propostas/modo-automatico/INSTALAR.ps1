# Liga o modo automatico seguro neste PC. Quem o corre e o Danilo, com duplo clique em
# ATIVAR-MODO-AUTOMATICO.cmd: a tranca nao deixa nenhum agente mudar ganchos, settings ou CI.
# Faz copia antes e, se os testes falharem, volta tudo atras sozinho.
param(
  [string]$Casa = $env:USERPROFILE,
  [string]$Repo = 'C:\BoraLocal\projetosflutter\bora_app',
  [string]$Ensaio = 'C:\BoraLocal\wt-modo-auto-05-11',
  [string]$Ramo = 'ai/2026-11-05-modo-automatico-seguro',
  [switch]$SoGancho
)
$pasta = $PSScriptRoot
$settings = Join-Path $Casa '.claude\settings.json'
$gancho = Join-Path $Casa '.claude\hooks\trava-modo-automatico.mjs'
$registo = Join-Path $Casa '.claude\modo-automatico-instalacao.log'
$remendos = 'guardas-ramo-ai.patch', 'guardas-sem-pergunta.patch' | ForEach-Object { Join-Path $pasta $_ }

function Diz($texto) {
  Write-Host $texto
  Add-Content -Encoding utf8 -Path $registo -Value "$(Get-Date -Format s) $texto"
}

# O ultimo remendo ja aplicado quer dizer que estao todos.
function AplicaGuardas($dir) {
  git -C $dir apply --check --reverse --ignore-whitespace $remendos[-1] 2>$null
  if ($LASTEXITCODE -eq 0) { return $true }
  foreach ($p in $remendos) {
    git -C $dir apply --check --reverse --ignore-whitespace $p 2>$null
    if ($LASTEXITCODE -eq 0) { continue }
    git -C $dir apply --ignore-whitespace $p
    if ($LASTEXITCODE -ne 0) { return $false }
  }
  return $true
}

$copia = "$settings.bak-modo-automatico-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item $settings $copia -ErrorAction Stop
Diz "Copia de seguranca: $copia"

try {
  New-Item -ItemType Directory -Force (Split-Path $gancho) -ErrorAction Stop | Out-Null
  Copy-Item (Join-Path $pasta 'trava-modo-automatico.mjs') $gancho -Force -ErrorAction Stop
  node (Join-Path $pasta 'registar-gancho.mjs') $settings $gancho
  if ($LASTEXITCODE -ne 0) { throw 'nao consegui registar a trava nos settings' }
  $env:TRAVA_ALVO = $gancho
  node (Join-Path $pasta 'trava-modo-automatico.test.mjs')
  $falhou = $LASTEXITCODE
  Remove-Item Env:TRAVA_ALVO
  if ($falhou -ne 0) { throw 'os testes da trava falharam' }
  Diz 'Trava ligada e testada. Vale para as sessoes abertas a partir de agora.'
} catch {
  Copy-Item $copia $settings -Force
  Remove-Item $gancho -ErrorAction SilentlyContinue
  Diz "FALHOU: $_. Voltei tudo atras."
  exit 1
}
if ($SoGancho) { exit 0 }

# As guardas antigas correm da arvore principal: aceitam os ramos ai/ e deixam de perguntar ao publicar.
if (-not (AplicaGuardas $Repo)) { Diz 'FALHOU: nao consegui mudar as guardas antigas. Um Permitir ainda pode publicar.'; exit 1 }
Diz 'Guardas antigas: ramos ai/ aceites e publicar recusado sem pergunta.'

# O CI e as guardas entram no ramo de ensaio e seguem no pedido de revisao, sem publicar.
Copy-Item (Join-Path $pasta 'revisao.yml') (Join-Path $Ensaio '.github\workflows\revisao.yml') -Force
if (-not (AplicaGuardas $Ensaio)) { Diz 'FALHOU: nao consegui pôr as guardas no ramo de ensaio.'; exit 1 }
git -C $Ensaio add .github/workflows/revisao.yml .claude/hooks/git-guardrails.py .claude/plugins/bora-mods/README.md .claude/plugins/bora-mods/hooks/regras.ts .claude/plugins/bora-mods/hooks/tranca.ts .claude/plugins/bora-mods/hooks/tranca.test.ts
git -C $Ensaio diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
  git -C $Ensaio commit -q -m 'fix(tranca): publicar nega sem perguntar'
  if ($LASTEXITCODE -ne 0) { Diz 'FALHOU: nao consegui gravar o CI no ramo de ensaio.'; exit 1 }
}
git -C $Ensaio push origin "${Ramo}:${Ramo}"
if ($LASTEXITCODE -ne 0) { Diz 'FALHOU: o GitHub recusou o envio do CI. O resto ficou ligado.'; exit 1 }
Diz 'CI enviado no ramo de ensaio. Nada foi publicado.'
Diz 'Pronto.'
