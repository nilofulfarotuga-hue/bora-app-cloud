# entrega-prompt.ps1 -- recebe o prompt em base64 por STDIN e grava-o em disco.
#
# PORQUE EXISTE (2026-09-05, sessao fila-ganho-05-09) -- O JUIZ MUDO, CAUSA REAL
# ----------------------------------------------------------------------------
# Ate aqui as pontes (pc-judge-novo / pc-loop-novo) mandavam o prompt em base64
# pelo STDIN de um ficheiro .cmd, e era o proprio .cmd que o lia e descodificava.
# Isso emperra: acima de cerca de dois kilobytes de base64 o pipe entre o ssh e o
# cmd.exe enche, ninguem drena, e a ligacao morre 180 segundos depois com
# "Timeout, server ... not responding". O .cmd nem chegava a escrever o ficheiro
# da tarefa.
#
# Medido por bisseccao a 2026-09-05, com a ponte do juiz:
#   prompt   977 B (base64 ~1,3 KB) -> veredito em 6 s
#   prompt  2249 B (base64 ~3,0 KB) -> emperra
#   prompt  2704 B / 3158 B / 3886 B -> emperra
# Era esta a causa dos JUIZ-SEM-VEREDITO em ordens grandes, e nao o tecto de
# tempo do carteiro: o ssh desiste aos ~180 s, muito antes de qualquer tecto.
#
# A entrega passa portanto a ser feita por AQUI, num processo powershell que le o
# stdin directamente, sem cmd.exe pelo meio. Provado a aguentar 20 KB em 1
# segundo. O .cmd e depois chamado numa segunda ligacao, ja sem stdin, com a
# bandeira --jaentregue.
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('juiz', 'loop')]
  [string]$Qual
)

$ErrorActionPreference = 'Stop'

$b = [Console]::In.ReadToEnd() -replace '[^A-Za-z0-9+/=]', ''
$b = $b.TrimEnd('=')
if ($b.Length -eq 0) {
  Write-Error "ENTREGA-VAZIA: nao chegou base64 nenhum pelo stdin"
  exit 5
}
$b = $b.PadRight([math]::Ceiling($b.Length / 4) * 4, '=')

$nome = if ($Qual -eq 'juiz') { 'bora_judge_task.txt' } else { 'bora_loop_task.txt' }
$destino = Join-Path $env:TEMP $nome

[IO.File]::WriteAllText($destino, [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)))

$tam = (Get-Item -LiteralPath $destino).Length
Write-Output ("ENTREGUE: {0} ({1} bytes)" -f $destino, $tam)
exit 0
