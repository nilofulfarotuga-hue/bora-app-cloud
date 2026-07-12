param([Parameter(Mandatory=$true)][string]$Live)
# bora-live-parser.ps1 — FASE 1.4 da reengenharia da esteira (2026-07-12).
# Lê o stream-json do `claude -p` (uma linha JSON por evento), escreve linhas LEGÍVEIS no
# LIVELOG (para o Danilo acompanhar com `assistir.cmd` / Get-Content -Wait) e emite SÓ o
# resultado final no stdout — que volta pela ponte ao carteiro/juiz exatamente como o texto
# de antes (a plumbing crítica não muda). Linhas não-JSON (erros tipo rate-limit) passam
# também para o stdout, para o carteiro as detetar.
$ErrorActionPreference = 'SilentlyContinue'
function TS { (Get-Date).ToString('HH:mm:ss') }
function Trim120([string]$s){ if($null -eq $s){return ''}; $s = ($s -replace '\s+',' ').Trim(); if($s.Length -gt 120){ $s.Substring(0,120)+'…' } else { $s } }
while ($null -ne ($line = [Console]::In.ReadLine())) {
  if ([string]::IsNullOrWhiteSpace($line)) { continue }
  $o = $null
  try { $o = $line | ConvertFrom-Json } catch { $o = $null }
  if ($null -eq $o) {
    Add-Content -LiteralPath $Live -Value "[$(TS)] warn  $line"
    Write-Output $line
    continue
  }
  switch ($o.type) {
    'system'    { Add-Content -LiteralPath $Live -Value "[$(TS)] start sessao iniciada (modelo $($o.model))" }
    'assistant' {
      foreach ($c in $o.message.content) {
        if ($c.type -eq 'text' -and -not [string]::IsNullOrWhiteSpace($c.text)) {
          Add-Content -LiteralPath $Live -Value "[$(TS)] fala  $(Trim120 $c.text)"
        } elseif ($c.type -eq 'tool_use') {
          $det = "$($c.input.command)$($c.input.file_path)$($c.input.pattern)$($c.input.description)"
          Add-Content -LiteralPath $Live -Value "[$(TS)] tool  $($c.name): $(Trim120 $det)"
        }
      }
    }
    'user'      { Add-Content -LiteralPath $Live -Value "[$(TS)] ret   resultado de ferramenta recebido" }
    'result'    {
      Add-Content -LiteralPath $Live -Value "[$(TS)] FIM   (turns=$($o.num_turns) custo=`$$($o.total_cost_usd))"
      if ($o.result) { Write-Output $o.result }
      elseif ($o.error) { Write-Output "ERRO: $($o.error)" }
    }
  }
}
