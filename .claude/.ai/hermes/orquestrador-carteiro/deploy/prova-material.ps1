# prova-material.ps1 -- PROVA MATERIAL de que uma ordem do loop fez mesmo trabalho.
#
# PORQUE EXISTE (2026-08-11, ENTREGAS FANTASMA):
# A ordem-20260811143542-1fa4 fechou como `concluida` com 5 marcos e NAO entregou nada: a rotina
# nunca foi criada e nao chegou mensagem ao Telegram. Dois defeitos somados:
#   (A) o salto de plano chamava um modelo por TEXTO (sem ferramentas) -> ele DESCREVIA o trabalho;
#   (B) o juiz morreu ("[juiz] ERRO: base64 vazio") e o carteiro fechou a ordem na mesma.
# Marcos extraidos de TEXTO nao provam nada. Isto prova: ficheiro em disco ou commit no git.
#
# DESENHO: burro de proposito. Sem LLM, sem rede, sem depender do juiz -- foi exatamente o juiz
# que falhou no caso que originou isto. So mede o relogio do sistema de ficheiros e o git log.
#
# Uso:   powershell -File prova-material.ps1 -Inicio <epoch-utc-segundos>
# Saida: uma linha PROVA-MATERIAL: ... + ate 12 caminhos. Exit 0 = ha prova, 1 = nao ha.
param(
  [Parameter(Mandatory=$true)][long]$Inicio,
  [int]$MaxListar = 12
)
$ErrorActionPreference = 'SilentlyContinue'

$desde = [DateTimeOffset]::FromUnixTimeSeconds($Inicio).LocalDateTime

# Onde o trabalho real do Bora aterra. Nao e' exaustivo de proposito: sao os sitios onde uma
# ordem legitima DEIXA marca. Se uma ordem trabalhar so fora daqui, o operador ve `ficheiros=0`
# e vai ler a saida -- prefiro um falso "incompleta" a um falso "concluida".
$raizes = @(
  # Acer (reserva): caminhos do Desktop.
  'C:\Users\danil\Desktop\projetosflutter\bora_app',
  'C:\Users\danil\Desktop\ferramentas',
  'C:\Users\danil\Desktop\produtividade-ia\hermes-bridge',
  'C:\Users\danil\Desktop\projetosflutter\bora_app\.obsidian-vault',
  # PC NOVO 2026-08-31: caminhos reais (o Desktop e junction e a sessao SSH de rede nao a
  # atravessa). Test-Path salta os que nao existem, por isso os dois PCs convivem sem partir.
  'C:\BoraLocal\projetosflutter\bora_app',
  'C:\BoraLocal\Desktop-PC-antigo\ferramentas',
  'C:\BoraLocal\Desktop-PC-antigo\produtividade-ia\hermes-bridge',
  'C:\BoraLocal\projetosflutter\bora_app\.obsidian-vault'
)

# RUIDO que muda sozinho a cada corrida e NAO prova trabalho nenhum: logs do proprio loop,
# telemetria do sampler, flags de pausa, ficheiros de fila/estado e o proprio ficheiro de marcos
# (esse e' contabilidade, nao entrega -- contar com ele reabria a porta a entrega fantasma).
$ruido = @(
  '\.git\', '\node_modules\', '\build\', '\.dart_tool\', '\__pycache__\',
  'bora-live.log', 'bora-marcos-corrente.txt', 'executor-rss.csv', 'executor.lock',
  '\orquestracao\', '\fila\', 'carteiro.log', '.pausa', 'auto-limpeza-ram.log',
  'bora_loop_task.txt', 'bora_rss', '\AppData\', '\.claude\projects\', '\.claude\todos\',
  '\.claude\shell-snapshots\', '\.claude\statsig\', '\.claude\history'
)

$achados = New-Object System.Collections.ArrayList
foreach ($r in $raizes) {
  if (-not (Test-Path -LiteralPath $r)) { continue }
  Get-ChildItem -LiteralPath $r -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $desde } |
    ForEach-Object {
      $p = $_.FullName
      $sujo = $false
      foreach ($n in $ruido) { if ($p -like "*$n*") { $sujo = $true; break } }
      if (-not $sujo) { [void]$achados.Add($p) }
    }
}
$achados = @($achados | Sort-Object -Unique)

# Commits novos no repo do Bora desde o arranque (fonte de verdade: git log, nunca o texto).
$commits = @()
# PC NOVO 2026-08-31: usa o caminho real se o do Desktop nao existir (junction nao atravessavel).
$repoGit = 'C:\Users\danil\Desktop\projetosflutter\bora_app'
if (-not (Test-Path -LiteralPath $repoGit)) { $repoGit = 'C:\BoraLocal\projetosflutter\bora_app' }
Push-Location $repoGit
# BUG 6 (2026-09-05): so contam os commits ASSINADOS pelo executor do loop.
# Antes contava qualquer commit desde o arranque, e por isso uma ordem trivial
# que so escrevia um ficheiro de 24 bytes foi dada por provada com 46
# ficheiros e 3 commits de uma sessao manual que corria ao mesmo tempo.
$MARCA_LOOP = 'loop@bora.local'
$gl = & git log --all --committer="$MARCA_LOOP" --oneline --since="@$Inicio" 2>$null
Pop-Location
if ($gl) { $commits = @($gl | Where-Object { $_ -and $_.Trim() -ne '' }) }

$nf = $achados.Count
$nc = $commits.Count
$ok = ($nf -gt 0) -or ($nc -gt 0)

Write-Output ("PROVA-MATERIAL: ficheiros=$nf commits=$nc desde=" + $desde.ToString('yyyy-MM-dd HH:mm:ss') + " veredito=" + $(if ($ok) { 'HA-PROVA' } else { 'SEM-PROVA' }))
foreach ($p in ($achados | Select-Object -First $MaxListar)) { Write-Output ("PROVA-FICHEIRO: " + $p) }
foreach ($c in ($commits | Select-Object -First 5)) { Write-Output ("PROVA-COMMIT: " + $c) }
if ($nf -gt $MaxListar) { Write-Output ("PROVA-MATERIAL: (+" + ($nf - $MaxListar) + " ficheiros nao listados)") }

if ($ok) { exit 0 } else { exit 1 }
