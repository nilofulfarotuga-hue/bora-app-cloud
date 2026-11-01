# dsh-missao.ps1 — corre UMA tarefa no dsh (perfil headless) na pasta escolhida e grava a resposta.
# Chamado pelo DSH-MISSAO.cmd. Missão dsh-harness-2026-10-29.
# Motor (01/11/2026): o Claude Sonnet pelo PORTEIRO da VPS (Tailscale) primeiro; se a VPS não responder em 8 s,
# Kilo Nemotron, depois kilo-auto e o Gemini grátis. Nos grátis NUNCA segredos nem dados de clientes.
# Pastas (01/11/2026, missão infra-claude-tudo): todas as do mapa ~/.dsh/pastas-dipsy.json (MAPA-DANILO.md).
param([string]$Pasta = 'bora_app')

$mapa = @{}
(Get-Content 'C:\Users\danil\.dsh\pastas-dipsy.json' -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $mapa[$_.Name.ToLower()] = $_.Value }
$chave = $Pasta.ToLower()
if (-not $mapa.ContainsKey($chave)) { Write-Host ("Pasta desconhecida: $Pasta. Usa: " + (($mapa.Keys | Sort-Object) -join ' | ')); exit 2 }

# senha do porteiro da VPS (só na memória deste processo) e teste de vida em 8 s
$senha = ''
try { $senha = ([IO.File]::ReadAllText('C:\Users\danil\.dsh\secrets\porteiro.token')).Trim() } catch { }
[Environment]::SetEnvironmentVariable('DIPSY_PORTEIRO', $senha, 'Process')
$porteiroVivo = $false
try { Invoke-RestMethod -Uri 'http://100.120.181.115:8792/saude' -Headers @{ 'X-Porteiro-Token' = $senha } -TimeoutSec 8 | Out-Null; $porteiroVivo = $true } catch { }
$senha = $null

$prompt = 'C:\Users\danil\Desktop\Bora\prompt-dsh.md'
if (-not (Test-Path $prompt)) { Write-Host "Falta o ficheiro da tarefa: $prompt"; exit 2 }
$saidas = 'C:\Users\danil\Desktop\Bora\dsh-saidas'
New-Item -ItemType Directory -Force $saidas | Out-Null
$ficheiro = Join-Path $saidas ((Get-Date -Format 'yyyy-MM-dd_HHmm') + '.md')

# Credencial anónima pública da piscina grátis da Kilo (não é segredo), lida do ficheiro ao lado.
[Environment]::SetEnvironmentVariable('KILO_ANON_KEY', (Get-Content 'C:\Users\danil\.dsh\kilo-anonima.txt' -Raw).Trim(), 'Process')

# Auto-cura: o AGENTS.md do dsh tem de ser o MESMO ficheiro que o CLAUDE.md global (hardlink).
# Algumas edições (ex.: ferramenta Edit do Claude Code) partem o link; aqui volta a ligar-se.
$global = 'C:\Users\danil\.claude\CLAUDE.md'; $ligado = 'C:\Users\danil\.dsh\AGENTS.md'
if (@(fsutil hardlink list $global 2>$null).Count -lt 2) {
  Remove-Item $ligado -Force -ErrorAction SilentlyContinue
  cmd /c mklink /H $ligado $global | Out-Null
}
Set-Location $mapa[$chave]
$texto = Get-Content -Raw -Encoding UTF8 $prompt

$tentativas = @()
if ($porteiroVivo) { $tentativas += @{ nome = 'porteiro Claude Sonnet 5.5 (padrao)'; patch = $null } }
else { Write-Host 'O porteiro da VPS não respondeu em 8 s: vou pelos motores grátis do PC.' }
$tentativas += @(
  @{ nome = 'kilo nemotron-3-ultra (reserva 1)'; patch = 'C:\Users\danil\.dsh\reserva-kilo-nemotron.patch.yml' },
  @{ nome = 'kilo-auto (reserva 2)';             patch = 'C:\Users\danil\.dsh\reserva-kilo-auto.patch.yml' },
  @{ nome = 'gemini gratis (reserva 3)';         patch = 'C:\Users\danil\.dsh\reserva-gemini.patch.yml' }
)
$resposta = $null; $usado = $null; $segundos = 0
foreach ($t in $tentativas) {
  $argumentos = @('--profile', 'headless')
  if ($t.patch) { $argumentos += @('--patch', $t.patch) }
  $argumentos += '-'
  $inicio = Get-Date
  $saida = $texto | & dsh @argumentos 2> "$ficheiro.erros.txt"
  $rc = $LASTEXITCODE
  $segundos = [int]((Get-Date) - $inicio).TotalSeconds
  if ($rc -eq 0 -and $saida) { $resposta = ($saida -join "`n"); $usado = $t.nome; break }
  Write-Host "[$($t.nome)] falhou (rc=$rc), a tentar a seguinte..."
}
if (-not $resposta) { Write-Host "Nenhum motor respondeu. Ver $ficheiro.erros.txt"; exit 1 }

$cab = "<!-- dsh em $($mapa[$chave]) | motor: $usado | $segundos s | $(Get-Date -Format s) -->`n`n"
Set-Content -Path $ficheiro -Value ($cab + $resposta) -Encoding UTF8
Write-Host "`n=== Resposta (motor: $usado, $segundos s) ===`n"
Write-Host $resposta
Write-Host "`nGravado em: $ficheiro"


