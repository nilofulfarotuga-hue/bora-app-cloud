# Teste de regressao do diagnostica-juiz.ps1 (Parte 5 da missao sistema-redondo-2026-08-01).
# ASCII puro de proposito (o PowerShell 5.1 le UTF-8 sem BOM como ANSI).
$ErrorActionPreference = 'Stop'
$alvo = Join-Path $PSScriptRoot 'diagnostica-juiz.ps1'
$tmp = Join-Path $env:TEMP ('juizdiag-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null

$fails = 0
function Check([string]$nome, [bool]$cond, [string]$detalhe) {
  if ($cond) { Write-Host ("  OK   | " + $nome) -ForegroundColor Green }
  else { Write-Host ("FALHA  | " + $nome + "  -> " + $detalhe) -ForegroundColor Red; $script:fails++ }
}
function Corre([string]$a, [string]$b) {
  $pa = Join-Path $tmp 'a.txt'; $pb = Join-Path $tmp 'b.txt'
  if ($null -eq $a) { Remove-Item $pa -EA SilentlyContinue } else { Set-Content -LiteralPath $pa -Value $a -Encoding UTF8 }
  if ($null -eq $b) { Remove-Item $pb -EA SilentlyContinue } else { Set-Content -LiteralPath $pb -Value $b -Encoding UTF8 }
  return (& powershell -NoProfile -ExecutionPolicy Bypass -File $alvo -A $pa -B $pb) -join "`n"
}

try {
  $r = Corre "VEREDITO: APROVADA" $null
  Check '1a tentativa com veredito -> devolve-o' ($r.Trim() -eq 'VEREDITO: APROVADA') $r

  $r = Corre "Error: rate limit exceeded" "VEREDITO: CORRIGIR: faltou o teste"
  Check '1a falha, 2a com veredito -> devolve o da 2a' ($r.Trim() -eq 'VEREDITO: CORRIGIR: faltou o teste') $r

  # o mais importante: a 2a tentativa ja NAO apaga a 1a, e a causa e' nomeada
  $r = Corre "Invalid API key provided" "Invalid API key provided"
  Check 'ambas falham por auth -> JUIZ-MUDO causa=auth' ($r -match 'JUIZ-MUDO: causa=auth') $r

  $r = Corre "429 Too Many Requests" "overloaded_error"
  Check 'rate-limit fica nomeado' ($r -match 'causa=rate-limit') $r

  $r = Corre "max-budget-usd reached" "max-budget-usd reached"
  Check 'teto de custo fica nomeado' ($r -match 'causa=teto-custo') $r

  $r = Corre "" ""
  Check 'saida vazia fica nomeada (nao fica em silencio)' ($r -match 'causa=saida-vazia') $r

  $r = Corre "blah blah coisa estranha" "blah blah coisa estranha"
  Check 'causa desconhecida ainda assim reporta e cita o texto' (($r -match 'causa=desconhecido') -and ($r -match 'coisa estranha')) $r

  # NUNCA inventar veredito quando o juiz nao se pronunciou
  $r = Corre "Invalid API key provided" "Invalid API key provided"
  Check 'falha de infra NAO gera VEREDITO (gate falso)' ($r -notmatch 'VEREDITO:') $r

  # saida sempre numa unica linha (senao parte o frontmatter da ordem)
  $r = Corre "linha um`nlinha dois`nlinha tres" "outra`ncoisa"
  Check 'diagnostico sai numa unica linha' (($r -split "`n").Count -eq 1) ("linhas=" + ($r -split "`n").Count)

  $r = Corre $null $null
  Check 'ficheiros inexistentes nao rebentam' ($r -match 'JUIZ-MUDO') $r
}
finally { Remove-Item $tmp -Recurse -Force -EA SilentlyContinue }

Write-Host ''
if ($fails -eq 0) { Write-Host 'TODOS OS CASOS PASSARAM' -ForegroundColor Green; exit 0 }
Write-Host "$fails CASO(S) FALHARAM" -ForegroundColor Red
exit 1
