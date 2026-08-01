<#
  ram-preflight.ps1 -- PRE-VOO DE RAM do executor do loop (v2, 2026-08-01).

  PORQUE ISTO EXISTE E PORQUE FOI REESCRITO
  -----------------------------------------
  A v1 (dentro do run-claude-loop.cmd) lia Win32_OperatingSystem.FreePhysicalMemory e travava
  abaixo de 800 MB. Estava errada em DUAS coisas ao mesmo tempo:

   (1) METRICA ERRADA. No Windows a memoria "free" (lista de paginas livres/zeradas) e' mantida
       DELIBERADAMENTE baixa -- o gestor de memoria prefere ter as paginas na standby list a
       servir de cache do que paradas a nao fazer nada. Pouca "free" e' o estado NORMAL e saudavel
       de uma maquina Windows; nao diz nada sobre capacidade. A metrica que responde a pergunta
       "cabe mais um processo?" e' AVAILABLE (contador \Memory\Available MBytes = free + zero +
       standby), que e' exactamente o numero que o Gestor de Tarefas mostra como "Disponivel".
       A standby list e' reclamavel na hora: um processo novo pega nela sem ninguem morrer.
   (2) LIMIAR ADIVINHADO. 800 MB nao veio de medicao nenhuma. Consequencia real e observada:
       a ordem-20260801100404-ffc9-aprovado foi recusada com "769MB livres" enquanto o Danilo
       corria 4-5 sessoes interactivas a mao no mesmo PC sem problema -- e um executor completou
       um ciclo inteiro (23 turnos, $1.16) nessas mesmas condicoes as 12:13 do mesmo dia. O gate
       recusava a maquina em que o trabalho estava, nesse instante, a correr.

  O QUE ESTA VERSAO MEDE
  ----------------------
   * AvailableMBytes  -- via Win32_PerfRawData_PerfOS_Memory (MESMO contador que
     \Memory\Available MBytes, mas SEM depender do nome localizado do contador: neste PC o Windows
     esta em PT e "\Memory\Available MBytes" via Get-Counter falha/nao resolve. A classe RawData e'
     estavel em qualquer idioma).
   * CommitLimit / CommittedBytes -- o teto de commit (RAM fisica + pagefile) e quanto ja esta
     prometido. ISTO e' que decide se um processo consegue mesmo ARRANCAR: no Windows um processo
     falha por commit esgotado ("o sistema esta com pouca memoria"), nao por pouca RAM fisica
     disponivel. Pouca Available faz a maquina PAGINAR (fica lenta); commit esgotado faz a
     alocacao FALHAR. Sao duas avarias diferentes e o gate trata-as como tal.

  DOIS TESTES, DOIS SIGNIFICADOS
  ------------------------------
   * TESTE DURO   (commit): headroom de commit < precisa -> a alocacao pode falhar de verdade.
   * TESTE BRANDO (available): abaixo do piso de thrash a maquina ainda arranca o processo, mas
     entra em paginacao patologica. Este piso e' baixo de proposito -- tem de deixar passar as
     condicoes em que o Danilo corre as sessoes dele a mao, senao repetimos o falso-negativo.

  CALIBRACAO (nao adivinhada)
  ---------------------------
  O tamanho do executor vem de medicao real gravada por executor-rss-sampler.ps1 em
  .claude/executor-rss.csv (uma linha por execucao: pico de working set e pico de private bytes do
  claude.exe do executor). Este script usa o MAXIMO das ultimas N execucoes. Sem CSV ainda, usa o
  default abaixo -- e diz na saida que esta sem calibracao, para o log nunca fingir que mediu.

  SAIDA (1 linha, consumida pelo run-claude-loop.cmd):
    PREFLIGHT-RAM: OK|BLOCK motivo=<...> avail=<MB> commit_headroom=<MB> ...
  EXIT CODE: 0 = pode subir o executor / 7 = nao subir.
#>
[CmdletBinding()]
param(
  # Piso de memoria fisica disponivel. Abaixo disto o PC de 4GB entra em paginacao patologica.
  # 300 MB e' deliberadamente BAIXO: em 2026-08-01 o Danilo corria 5 sessoes com Available=618 MB
  # e um executor completou nessas condicoes -- o gate TEM de passar ai.
  [int]$MinAvailableMB = 0,
  # Headroom de commit exigido. 0 = calcular a partir da calibracao (private medido + folga).
  [int]$MinCommitMB = 0,
  # Folga de commit para o resto do sistema, por cima do private medido do executor.
  [int]$CommitSlackMB = 500,
  # Usado so enquanto nao ha medicao real no CSV.
  [int]$DefaultExecutorPrivateMB = 700,
  [string]$CsvPath = "$PSScriptRoot\..\..\..\..\executor-rss.csv",
  [int]$SampleRuns = 20
)

$ErrorActionPreference = 'Stop'

function Get-MemFacts {
  # Win32_PerfRawData_PerfOS_Memory: mesmos contadores de \Memory\*, sem nomes localizados.
  try {
    $m = Get-CimInstance Win32_PerfRawData_PerfOS_Memory -ErrorAction Stop
    return [pscustomobject]@{
      AvailableMB     = [int]$m.AvailableMBytes
      CommitLimitMB   = [int]([double]$m.CommitLimit / 1MB)
      CommittedMB     = [int]([double]$m.CommittedBytes / 1MB)
      Fonte           = 'Win32_PerfRawData_PerfOS_Memory'
    }
  } catch {
    # Fallback so se a classe de contadores falhar. FreePhysicalMemory subestima (ver cabecalho),
    # por isso e' o ULTIMO recurso e fica marcado na saida para o log nao mentir sobre a fonte.
    $os = Get-CimInstance Win32_OperatingSystem
    return [pscustomobject]@{
      AvailableMB     = [int]($os.FreePhysicalMemory / 1024)
      CommitLimitMB   = [int]($os.TotalVirtualMemorySize / 1024)
      CommittedMB     = [int](($os.TotalVirtualMemorySize - $os.FreeVirtualMemory) / 1024)
      Fonte           = 'Win32_OperatingSystem(FALLBACK-subestima)'
    }
  }
}

function Get-ExecutorFootprintMB {
  # Le a calibracao real. Devolve o MAXIMO das ultimas $SampleRuns execucoes (nao a media: o gate
  # tem de aguentar o pior caso observado, nao o caso tipico).
  if (-not (Test-Path -LiteralPath $CsvPath)) {
    return [pscustomobject]@{ PrivateMB = $DefaultExecutorPrivateMB; WsMB = 0; N = 0; Calibrado = $false }
  }
  try {
    $rows = @(Import-Csv -LiteralPath $CsvPath -ErrorAction Stop | Select-Object -Last $SampleRuns)
    if ($rows.Count -eq 0) {
      return [pscustomobject]@{ PrivateMB = $DefaultExecutorPrivateMB; WsMB = 0; N = 0; Calibrado = $false }
    }
    $priv = ($rows | ForEach-Object { [int]$_.peak_private_mb } | Measure-Object -Maximum).Maximum
    $ws   = ($rows | ForEach-Object { [int]$_.peak_ws_mb }      | Measure-Object -Maximum).Maximum
    # O default e' PISO, nao alternativa: a medicao so pode SUBIR a exigencia de commit, nunca
    # baixa-la. Sem isto, uma unica ordem leve (que nunca chega perto do pico) baixava o gate para
    # todos os ciclos seguintes -- a mesma classe de erro do limiar adivinhado, so que ao contrario.
    if ($priv -lt $DefaultExecutorPrivateMB) { $priv = $DefaultExecutorPrivateMB }
    if ($priv -le 0) {
      return [pscustomobject]@{ PrivateMB = $DefaultExecutorPrivateMB; WsMB = $ws; N = $rows.Count; Calibrado = $false }
    }
    return [pscustomobject]@{ PrivateMB = $priv; WsMB = $ws; N = $rows.Count; Calibrado = $true }
  } catch {
    return [pscustomobject]@{ PrivateMB = $DefaultExecutorPrivateMB; WsMB = 0; N = 0; Calibrado = $false }
  }
}

$mem  = Get-MemFacts
$foot = Get-ExecutorFootprintMB

if ($MinAvailableMB -le 0) {
  if ($env:LOOP_MIN_AVAIL_MB -and [int]$env:LOOP_MIN_AVAIL_MB -gt 0) { $MinAvailableMB = [int]$env:LOOP_MIN_AVAIL_MB }
  else { $MinAvailableMB = 300 }
}
if ($MinCommitMB -le 0) {
  if ($env:LOOP_MIN_COMMIT_MB -and [int]$env:LOOP_MIN_COMMIT_MB -gt 0) { $MinCommitMB = [int]$env:LOOP_MIN_COMMIT_MB }
  else { $MinCommitMB = $foot.PrivateMB + $CommitSlackMB }
}

$headroom = $mem.CommitLimitMB - $mem.CommittedMB
$calib = if ($foot.Calibrado) { "medido(n=$($foot.N))" } else { 'SEM-MEDICAO(default)' }
$detalhe = "avail=$($mem.AvailableMB)MB piso_avail=${MinAvailableMB}MB commit_headroom=${headroom}MB piso_commit=${MinCommitMB}MB exec_private=$($foot.PrivateMB)MB calib=$calib fonte=$($mem.Fonte)"

# TESTE DURO primeiro: commit esgotado e' falha real de alocacao, nao lentidao.
if ($headroom -lt $MinCommitMB) {
  Write-Output "PREFLIGHT-RAM: BLOCK motivo=commit-headroom $detalhe"
  exit 7
}
if ($mem.AvailableMB -lt $MinAvailableMB) {
  Write-Output "PREFLIGHT-RAM: BLOCK motivo=available-baixa $detalhe"
  exit 7
}
Write-Output "PREFLIGHT-RAM: OK $detalhe"
exit 0
