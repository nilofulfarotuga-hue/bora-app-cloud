# Regressao de Get-CommitIntent (deteccao manda/proibe commit-push) do juiz-mecanico.ps1.
# Fonte UNICA: extrai a funcao real do ficheiro (bloco entre os marcadores) -- zero duplicacao
# de logica, tal como _zona_fn_test.sh faz para o carteiro.sh.
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'juiz-mecanico.ps1'
$txt = [IO.File]::ReadAllText($src)
$m = [regex]::Match($txt, '(?s)# ---FUNC:Get-CommitIntent-START---.*?# ---FUNC:Get-CommitIntent-END---')
if (-not $m.Success) { Write-Output 'FALHA: marcador Get-CommitIntent nao encontrado em juiz-mecanico.ps1'; exit 1 }
Invoke-Expression $m.Value

$fails = 0
function Check([string]$esperado, [string]$campo, [string]$t) {
  $r = Get-CommitIntent $t
  $got = $r.$campo
  $ok = ($got -eq [bool]::Parse($esperado))
  if ($ok) { Write-Output "OK   [$campo=$got] $t" }
  else { Write-Output "FALHA esp=$campo=$esperado got=$got :: $t"; $script:fails++ }
}

Write-Output '== mandato explicito (sem negacao) -> Manda=True =='
Check 'True'  'Manda' 'Termina o trabalho e faz commit das alteracoes no final.'
Check 'False' 'Proibe' 'Termina o trabalho e faz commit das alteracoes no final.'

Write-Output ''
Write-Output '== proibicao colada (negacao imediatamente antes) -> Proibe=True, Manda=False =='
Check 'True'  'Proibe' 'NUNCA facas git commit nem git push a menos que a tarefa peca explicitamente.'
Check 'False' 'Manda'  'NUNCA facas git commit nem git push a menos que a tarefa peca explicitamente.'

Write-Output ''
Write-Output '== bug real 2026-08-01 (ordem 228a): negacao com GAP LARGO antes do termo -> Proibe=True =='
Check 'True'  'Proibe' 'Faz so o diagnostico. Nao deves, em circunstancia nenhuma, fazer commit ou push do que encontrares.'
Check 'False' 'Manda'  'Faz so o diagnostico. Nao deves, em circunstancia nenhuma, fazer commit ou push do que encontrares.'

Write-Output ''
Write-Output '== negacao DEPOIS do termo (fora da janela antiga, so-para-tras) -> Proibe=True =='
Check 'True'  'Proibe' 'Investiga a fundo o problema; commit e push aqui nao sao permitidos de forma alguma.'
Check 'False' 'Manda'  'Investiga a fundo o problema; commit e push aqui nao sao permitidos de forma alguma.'

Write-Output ''
Write-Output '== negacao NOUTRA clausula (mas) nao apaga mandato genuino na clausula seguinte -> Manda=True =='
Check 'True'  'Manda'  'Nao faças push agora, mas faz commit das alteracoes no final da tarefa.'

Write-Output ''
Write-Output '== sem qualquer mencao a commit/push -> Manda=False, Proibe=False =='
Check 'False' 'Manda'  'Le o pricing_service e explica como a taxa e calculada.'
Check 'False' 'Proibe' 'Le o pricing_service e explica como a taxa e calculada.'

Write-Output ''
if ($fails -eq 0) { Write-Output 'TODOS OK (11/11)' } else { Write-Output "$fails FALHA(S)"; exit 1 }
