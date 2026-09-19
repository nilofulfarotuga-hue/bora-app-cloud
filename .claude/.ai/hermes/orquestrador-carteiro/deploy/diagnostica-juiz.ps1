# diagnostica-juiz.ps1 -- decide o que o run-claude-judge.cmd devolve ao carteiro.
#
# Porque existe (Parte 5 da missao sistema-redondo-2026-08-01):
# o juiz corria 2x e a 2a tentativa SOBRESCREVIA o ficheiro de saida da 1a; no fim fazia-se
# `type` do que sobrou. Quando nenhuma das duas devolvia VEREDITO, o carteiro recebia texto cru
# (ou nada) e registava "juiz nao devolveu VEREDITO" -- sem nunca dizer PORQUE. A causa real
# (sessao expirada, rate-limit, teto de custo, teto de turnos) ficava perdida. E' a mesma familia
# da licao licao-parser-mudo: silencio lido como outra causa.
#
# REGRA QUE NAO SE QUEBRA: se o juiz nao se pronunciou, NAO se inventa veredito. Reprovar por
# falha de infraestrutura seria um gate falso -- mataria trabalho bom por causa de um glitch de
# auth. Aqui so se NOMEIA a causa; a politica de "concluida com revisao pendente" continua a ser
# do carteiro.
param(
  [Parameter(Mandatory = $true)][string]$A,   # saida da 1a tentativa
  [string]$B                                   # saida da 2a tentativa (pode nao existir)
)

function Conteudo([string]$p) {
  if ([string]::IsNullOrWhiteSpace($p)) { return '' }
  if (-not (Test-Path -LiteralPath $p)) { return '' }
  try { return (Get-Content -LiteralPath $p -Raw -ErrorAction Stop) } catch { return '' }
}

$txtA = Conteudo $A
$txtB = Conteudo $B

# 1) Alguma das tentativas pronunciou-se? Ganha a primeira linha VEREDITO encontrada.
foreach ($t in @($txtA, $txtB)) {
  if ([string]::IsNullOrWhiteSpace($t)) { continue }
  $linha = ($t -split "`r?`n") | Where-Object { $_ -match 'VEREDITO:' } | Select-Object -First 1
  if ($linha) { Write-Output $linha.Trim(); exit 0 }
}

# 2) Nenhuma se pronunciou -> nomear a causa a partir do que ficou nos dois ficheiros.
$tudo = ($txtA + "`n" + $txtB)
$causa = switch -Regex ($tudo) {
  'not logged in|please log ?in|authentication|unauthoriz|invalid api key|OAuth|session expired|credential' { 'auth'; break }
  'rate.?limit|429|overloaded|too many requests|capacity'                                                   { 'rate-limit'; break }
  'max.?budget|budget exceeded|spending limit|usage limit'                                                  { 'teto-custo'; break }
  'max.?turns|turn limit'                                                                                   { 'teto-turnos'; break }
  'ENOENT|not recognized|nao encontrado|not found|cannot find'                                              { 'binario-ausente'; break }
  'timed? ?out|ETIMEDOUT|ECONNRESET|network|getaddrinfo'                                                    { 'rede'; break }
  default { if ([string]::IsNullOrWhiteSpace($tudo)) { 'saida-vazia' } else { 'desconhecido' } }
}

$bytesA = $txtA.Length
$bytesB = $txtB.Length
# excerto curto e numa so linha, para caber na nota da ordem sem partir o frontmatter
$excerto = ($tudo -replace '\s+', ' ').Trim()
if ($excerto.Length -gt 240) { $excerto = $excerto.Substring(0, 240) + '...' }

Write-Output ("JUIZ-MUDO: causa={0} tentativas=2 bytes1={1} bytes2={2} :: {3}" -f $causa, $bytesA, $bytesB, $excerto)
exit 0
