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
$patch = Join-Path $pasta 'guardas-ramo-ai.patch'

function Diz($texto) {
  Write-Host $texto
  Add-Content -Encoding utf8 -Path $registo -Value "$(Get-Date -Format s) $texto"
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

# As guardas antigas passam a aceitar os ramos de ensaio ai/ (correm da arvore principal).
git -C $Repo apply --check --reverse --ignore-whitespace $patch 2>$null
if ($LASTEXITCODE -eq 0) {
  Diz 'As guardas antigas ja aceitavam os ramos ai/.'
} else {
  git -C $Repo apply --ignore-whitespace $patch
  if ($LASTEXITCODE -ne 0) { Diz 'FALHOU: nao consegui mudar as guardas antigas. A trava fica ligada; os push de ensaio continuam presos.'; exit 1 }
  Diz 'Guardas antigas: ramos ai/ aceites.'
}

# O CI e as guardas entram no ramo de ensaio e seguem no pedido de revisao, sem publicar.
Copy-Item (Join-Path $pasta 'revisao.yml') (Join-Path $Ensaio '.github\workflows\revisao.yml') -Force
git -C $Ensaio apply --check --reverse --ignore-whitespace $patch 2>$null
if ($LASTEXITCODE -ne 0) { git -C $Ensaio apply --ignore-whitespace $patch }
git -C $Ensaio add .github/workflows/revisao.yml .claude/hooks/git-guardrails.py .claude/plugins/bora-mods/hooks/regras.ts .claude/plugins/bora-mods/hooks/tranca.test.ts
git -C $Ensaio diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
  git -C $Ensaio commit -q -m 'ci(revisao): testes em cada pedido de revisao e ramos ai/ nas guardas'
  if ($LASTEXITCODE -ne 0) { Diz 'FALHOU: nao consegui gravar o CI no ramo de ensaio.'; exit 1 }
}
git -C $Ensaio push origin "${Ramo}:${Ramo}"
if ($LASTEXITCODE -ne 0) { Diz 'FALHOU: o GitHub recusou o envio do CI. O resto ficou ligado.'; exit 1 }
Diz 'CI enviado no ramo de ensaio. Nada foi publicado.'
Diz 'Pronto.'
