# juiz-mecanico.ps1 - CHAO DETERMINISTICO do CLAUDE-JUIZ (2026-07-15, missao "religar com verificacao real")
# Corre ANTES do juiz textual (Haiku). NUNCA aprova - so pode REPROVAR ou deixar passar ao textual.
# Motivo de existir: o juiz textual aprovava trabalho INVENTADO (executor alegou commit 05050db,
# porta-vai.sh e autorizado_por que nunca existiram; o juiz de grep carimbou APROVADA).
# Regra: prova = git + disco. NUNCA o texto do executor. NUNCA o e2e_log.
#
# Input : $args[0] = caminho do ficheiro com o input do juiz (TAREFA: / SAIDA DO EXECUTOR: / META_JUIZ:)
# Output: linhas "PROVA-JUIZ: [comando] -> resultado" (auditoria) e, em reprova, linha final
#         "VEREDITO: CORRIGIR: ..." (o carteiro apanha a 1a linha com VEREDITO:).
# Exit  : 0 = chao OK (segue para o juiz textual) | 2 = REPROVADO (veredito ja impresso) | outro = erro (fail-closed no .cmd)

$ErrorActionPreference = 'Continue'
# PC NOVO 2026-08-31: caminho real (o Desktop e junction e a sessao SSH de rede nao a atravessa).
# Sincronizado com a copia viva em hermes-bridge (bloco-d1d2, 2026-09-05) -- a master aqui tinha
# ficado parada no caminho antigo desde a mudanca de PC.
$Proj = 'C:\BoraLocal\projetosflutter\bora_app'
Set-Location $Proj

$inFile = $args[0]
if (-not $inFile -or -not (Test-Path $inFile)) {
  Write-Output 'VEREDITO: CORRIGIR: juiz-mecanico sem ficheiro de input (erro de infra do juiz, nao do executor)'
  exit 2
}
$txt = [IO.File]::ReadAllText($inFile, [Text.Encoding]::UTF8)

# ---- parse TAREFA / SAIDA / META ----
$tarefa = ''; $saida = ''
$mTar = [regex]::Match($txt, '(?s)TAREFA:\s*(.*?)\s*SAIDA DO EXECUTOR:')
if ($mTar.Success) { $tarefa = $mTar.Groups[1].Value } else { $tarefa = $txt }
$mSai = [regex]::Match($txt, '(?s)SAIDA DO EXECUTOR:\s*(.*)$')
if ($mSai.Success) { $saida = $mSai.Groups[1].Value }
$inicio = $null
$mMeta = [regex]::Match($txt, 'META_JUIZ:.*?inicio_epoch=(\d+)')
if ($mMeta.Success) { $inicio = [int64]$mMeta.Groups[1].Value }

# Remove diacriticos (nao -> nao, possivel -> possivel) para as regex serem 100% ASCII,
# imunes ao encoding com que o proprio .ps1 e lido (PS 5.1 sem BOM le ANSI e mangla acentos).
function DeAccent([string]$s) {
  $n = $s.Normalize([Text.NormalizationForm]::FormD)
  -join ($n.ToCharArray() | Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne [Globalization.UnicodeCategory]::NonSpacingMark })
}

function Proof([string]$cmd, [string]$out) {
  $o = ($out -replace '\r?\n', ' | ')
  if ($o.Length -gt 220) { $o = $o.Substring(0,220) + '...' }
  Write-Output ("PROVA-JUIZ: [" + $cmd + "] -> " + $o)
}
function Reprova([string]$motivo) {
  Write-Output ("VEREDITO: CORRIGIR: " + $motivo)
  exit 2
}

# python: a conta SSH da ponte nao tem python no PATH (descoberto 2026-07-15 na 1a corrida real)
# -> resolve por candidatos, incluindo caminho absoluto da instalacao do Danilo.
$pyExe = $null
foreach ($cand in @('python', 'py', 'C:\Users\danil\AppData\Local\Programs\Python\Python312\python.exe', 'C:\Users\danil\AppData\Local\Programs\Python\Launcher\py.exe')) {
  $c = Get-Command $cand -ErrorAction SilentlyContinue
  if ($c) { $pyExe = $c.Source; break }
}

# base para os checks de diff: o commit em que o repo estava quando a ordem arrancou
$base = 'HEAD'
if ($inicio) {
  $b = (git rev-list -1 --before="@$inicio" HEAD 2>$null)
  if ($b) { $base = $b.Trim() }
}

# ---- (d) anti_trapaca.py - SEMPRE primeiro, chao deterministico (se existir e aplicavel) ----
$at = Join-Path $Proj '.claude\juiz\anti_trapaca.py'
if ((Test-Path $at) -and $pyExe) {
  $atOut = (& $pyExe $at --base $base 2>&1) -join ' | '
  $atRc = $LASTEXITCODE
  Proof "python anti_trapaca.py --base $base (rc=$atRc)" $atOut
  if ($atRc -eq 2) { Reprova "anti_trapaca REJEITA (batota de teste detetada por git diff; base=$base)" }
  if ($atRc -eq 1) { Proof 'anti_trapaca' 'ATENCAO rc=1 - precisa olho humano (nao bloqueia sozinho, juiz textual decide)' }
} else {
  Proof 'anti_trapaca' 'saltado (python ou script ausente nesta maquina)'
}

# ---- (e) zonas protegidas (13c da missao religar-loop): o diff COMMITADO desde o arranque da
# ordem NUNCA pode tocar a Lista Vermelha. O aprovador-vermelho julga a INTENCAO (Balde A/B);
# aqui o Juiz confere o DIFF real. head=HEAD (so commits) para nao apanhar ruido da working tree.
$zd = Join-Path $Proj '.claude\juiz\zonas_diff.py'
if ((Test-Path $zd) -and $pyExe -and $inicio) {
  $zdOut = (& $pyExe $zd --base $base --head HEAD 2>&1) -join ' | '
  $zdRc = $LASTEXITCODE
  Proof "python zonas_diff.py --base $base --head HEAD (rc=$zdRc)" $zdOut
  if ($zdRc -eq 2) { Reprova 'o diff commitado desde o arranque da ordem toca ZONA PROTEGIDA (Lista Vermelha) - nada disso passa pelo loop; volta para decisao humana' }
}

# ---- de-acentuar tarefa+saida e padroes de ESCAPE/DIAGNOSTICO (defeitos A+B, 2026-07-16) ----
$saidaAscii  = DeAccent $saida
$tarefaAscii = DeAccent $tarefa

# ESCAPE-CLAUSE na ORDEM: a propria ordem preve "se nao for possivel, reporta / para e diz /
# diz o que falta". Quando existe, uma impossibilidade REPORTADA COM DIAGNOSTICO e resposta
# valida (nao se pune a honestidade que a ordem pediu). Regex ASCII sobre texto de-acentuado.
$escapeRe1 = '(?is)\bse\b[^.!?\n]{0,80}?\b(nao (for|e|seja) possivel|nao consegu\w*|nao der|nao houver|falha\w*|bloquea\w*|correr mal|houver (problema|erro|bloqueio)|precisar|impossivel)\b[^.!?\n]{0,80}?\b(reporta\w*|report|para e|parar e|diz\w*|avisa\w*|explica\w*|pede|pedir|indica\w*|escreve\w*|documenta\w*|sinaliza\w*)\b'
$escapeRe2 = '(?is)\b(diz\w*|reporta\w*|indica\w*|escreve\w*|explica\w*|avisa\w*)\b[^.!?\n]{0,50}?\bo que\b[^.!?\n]{0,50}?\b(falta|faltou|falhou|bloqueou|tem de|tem que|precisa\w*|e preciso|fazer|resolver)\b'
$escapeRe3 = '(?i)\bpara e (reporta|diz|avisa|explica)\w*\b|\bparar e (reportar|dizer|avisar)\w*\b|\bnad[ao] (for|e|seja) possivel\b|\bnada disso for possivel\b'
$temEscape = ($tarefaAscii -match $escapeRe1) -or ($tarefaAscii -match $escapeRe2) -or ($tarefaAscii -match $escapeRe3)

# DIAGNOSTICO na SAIDA: a saida EXPLICA a impossibilidade (nao e so "nao deu"). Token explicativo
# OU corpo substancial (>=200 chars uteis). "nao deu" cru -> sem diagnostico -> continua a reprovar.
$diagRe = '(?i)\b(porque|porqu\w*|devido|falta\w*|precis\w*|necessari\w*|erro|falhou|credencial|permissao|token|bloquead\w*|motivo|causa|nao existe|em falta|tens de|tem de|tem que|e preciso|configura\w*|instala\w*|autoriza\w*|aprova\w*|manualmente|o danilo|passo\b|passos\b)\b'
$saidaUtil = ($saida -replace '\s+', ' ').Trim()
$temDiag = ($saidaAscii -match $diagRe) -or ($saidaUtil.Length -ge 200)

$recusaValida = $false

# ---- (a) recusa/impossibilidade declarada pelo executor (regex ASCII sobre texto de-acentuado) ----
# DEFEITO B (2026-07-16): se a ORDEM tem escape-clause E o executor reportou COM diagnostico,
# a impossibilidade e resposta valida -> passa ao juiz textual. Mantem CORRIGIR quando a ordem
# NAO previa escape OU o executor so diz "nao deu" sem diagnostico. (Mentira de trabalho
# inexistente continua a ser apanhada nos blocos b1/b2 - intocados.)
$recusaRe = '(?im)^[\s>*#-]*nao (foi possivel|consegui|consigo|executei|fiz)\b|^[\s>*#-]*(impossivel|recuso|recusei|recusada|falhei|desisti)\b|^[\s>*#-]*nao deu\b(?!\s+(erro|problema|falha|falhas|conflito|conflitos|bug|bugs|mal|nada))|^[\s>*#-]*(sem sucesso|nao rolou)\b|confirmacao necessaria|preciso de confirmacao'
$mRec = [regex]::Match($saidaAscii, $recusaRe)
if ($mRec.Success) {
  Proof 'regex recusa na SAIDA' ("match: '" + $mRec.Value.Trim() + "'")
  Proof 'escape-clause na ORDEM' "$temEscape"
  Proof 'diagnostico na SAIDA'   "$temDiag"
  if ($temEscape -and $temDiag) {
    $recusaValida = $true
    Proof 'recusa VALIDA' 'a ordem previa escape e o executor reportou com diagnostico -> segue para o juiz textual'
  } else {
    Reprova 'o executor declara recusa/falha/impossibilidade e a ordem nao previa escape (ou faltou diagnostico) - nada a aprovar'
  }
} else {
  Proof 'regex recusa na SAIDA' 'sem declaracao de recusa/falha'
}

# ---- (b) ordem pedia commit/push -> exigir commit REAL no repo (negacao por CLAUSULA) ----
# DEFEITO A (2026-07-16): so exigir commit quando a ordem MANDA commitar/pushar. Se a mencao
# a commit/push esta dentro de uma PROIBICAO ("NAO commitar", "sem push", "nao facas push"),
# nao se exige nada; se a ordem PROIBE e o executor committou algo atribuivel, isso e violacao.
#
# FIX 2026-08-01 (missao sistema-redondo, ordem-20260801072105-228a): a janela fixa de 24
# caracteres SO PARA TRAS do termo perdia negacao mais distante ("nao deve, em circunstancia
# nenhuma, fazer commit") ou DEPOIS do termo ("faz o diagnostico; nao faças commit nem push").
# ---FUNC:Get-CommitIntent-START--- (extraida p/ ser testavel isolada -- _juiz_mecanico_commit_test.ps1)
function Get-CommitIntent([string]$tarefaAscii) {
  $kwRe  = '(?i)\b(commit|commits|committ\w*|commitar|commites|commitares|comit|comita|comitar|comitei|commitei|commitou|push|pushar|pushes|pusha|pushei)\b'
  $negRe = '(?i)\b(nao|sem|nunca|jamais|proibid[oa]|evita\w*|nada de|nem)\b'
  # clausula = fronteira de frase OU conjuncao contrastiva (reinicia a polaridade dentro do
  # mesmo periodo) -- negacao conta em QUALQUER ponto da MESMA clausula, antes ou depois do
  # termo, sem limite de distancia. Negacao noutra clausula nao apaga termo genuino a seguir.
  $clauseSplitRe = '[.!?\n]+|\b(mas|porem|porém|contudo|entretanto)\b'
  $manda = $false; $proibe = $false
  foreach ($cl in [regex]::Split($tarefaAscii, $clauseSplitRe)) {
    if ($cl -notmatch $kwRe) { continue }
    if ($cl -match $negRe) { $proibe = $true } else { $manda = $true }
  }
  [pscustomobject]@{ Manda = $manda; Proibe = $proibe }
}
# ---FUNC:Get-CommitIntent-END---
$intent = Get-CommitIntent $tarefaAscii
$mandaCommit = $intent.Manda; $proibeCommit = $intent.Proibe

if ($recusaValida) {
  Proof 'commit-check' 'dispensado: recusa valida (a ordem previa escape e o executor reportou)'
} elseif ($mandaCommit) {
  # b1: hash alegado na SAIDA (linhas que falam de commit) - so AUDITORIA (Proof), NUNCA motivo
  # de reprova sozinho. FIX 2026-07-18 (falso-alarme ordem b439): o executor escreveu
  # "commit 29636612139" no TEXTO do relatorio (erro de transcricao/digitacao - o commit real
  # era 458326c) e o juiz reprovava so por esse hash de texto nao bater no repo, mesmo havendo
  # commit real e novo no git log. Quem decide agora e SEMPRE o git log real (b2), nunca o texto.
  $claimed = @()
  foreach ($ln in ($saida -split "`n")) {
    if ($ln -match '(?i)commit') {
      foreach ($m in [regex]::Matches($ln, '\b[0-9a-f]{7,40}\b')) { $claimed += $m.Value }
    }
  }
  $claimed = $claimed | Select-Object -Unique -First 5
  $hashExisteOk = $false
  $hashNovoOk = $false
  foreach ($h in $claimed) {
    $t = (git cat-file -t $h 2>&1); $rc = $LASTEXITCODE
    Proof "git cat-file -t $h (rc=$rc)" "$t"
    if ($rc -ne 0) {
      Proof 'hash alegado diverge do git' "$h nao bate no repo - pode ser erro de digitacao/transcricao do executor; nao reprova sozinho, decide o git log real na b2"
      continue
    }
    $hashExisteOk = $true
    if ($inicio) {
      $ct = [int64]((git show -s --format=%ct $h 2>$null) | Select-Object -First 1)
      Proof "git show -s --format=%ct $h" "committer_epoch=$ct (inicio=$inicio)"
      if ($ct -ge $inicio) { $hashNovoOk = $true }
    }
  }
  # b2: PROVA REAL - tem de haver commit NOVO desde o arranque da ordem no git log (fonte unica
  # de verdade), OU um hash alegado verificado com committer-date >= inicio (cinto extra contra
  # falso-negativo do --since), OU (sem META inicio_epoch) pelo menos um hash alegado que exista
  # mesmo no repo.
  if ($inicio) {
    $novo = (git log --all --oneline --since="@$inicio" 2>&1) -join ' | '
    Proof "git log --all --oneline --since=@$inicio" $(if ($novo) { $novo } else { '(vazio)' })
    if ((-not $novo) -and (-not $hashNovoOk)) { Reprova 'a ordem pedia commit/push e NAO ha nenhum commit novo desde o arranque da ordem (prova = git log real, nunca o texto do executor)' }
  } else {
    $novo = (git log --all --oneline --since='3 hours ago' 2>&1) -join ' | '
    Proof "git log --all --oneline --since='3 hours ago' (sem META inicio_epoch)" $(if ($novo) { $novo } else { '(vazio)' })
    if ((-not $novo) -and (-not $hashExisteOk)) { Reprova 'a ordem pedia commit/push, sem commit novo nas ultimas 3h e sem hash alegado verificavel no repo (prova = git log real, nunca o texto do executor)' }
  }
} elseif ($proibeCommit) {
  # ordem PROIBE commit/push: violacao SO se o executor committou algo ATRIBUIVEL (hash alegado
  # na saida que existe e e novo). Nao uso git-log cru para nao apanhar commits de executores
  # concorrentes no mesmo working dir (licao commit_concorrente_colateral 2026-07-14).
  $claimedP = @()
  foreach ($ln in ($saida -split "`n")) {
    if ($ln -match '(?i)commit') {
      foreach ($m in [regex]::Matches($ln, '\b[0-9a-f]{7,40}\b')) { $claimedP += $m.Value }
    }
  }
  $claimedP = $claimedP | Select-Object -Unique -First 5
  $violou = $false; $badH = ''
  foreach ($h in $claimedP) {
    $t = (git cat-file -t $h 2>&1); $rc = $LASTEXITCODE
    if ($rc -eq 0) {
      $ct = if ($inicio) { [int64]((git show -s --format=%ct $h 2>$null) | Select-Object -First 1) } else { 0 }
      Proof "git cat-file -t $h (ordem PROIBE commit)" "existe; committer_epoch=$ct (inicio=$inicio)"
      if ((-not $inicio) -or ($ct -ge $inicio)) { $violou = $true; $badH = $h }
    }
  }
  if ($violou) { Reprova "a ordem PROIBIA commit/push mas o executor committou $badH (existe no repo)" }
  Proof 'ordem PROIBE commit/push' 'sem commit atribuivel na saida - conforme a proibicao'
}

# ---- (c) ordem pedia criar/escrever ficheiro -> tem de existir em disco ----
# FIX 2026-07-18 (falso-alarme ordens 7ab2/02ec/ebcc): a ordem referia so "inbox/relatorio-x.md"
# (caminho curto) mas o executor grava sempre sob o espelho do cortex ".claude\.ai\knowledge\...".
# O caminho literal extraido da ordem nao existe na raiz do repo -> falso "NAO existe em disco"
# mesmo com o relatorio commitado. Agora aceita: (1) caminho literal (como ja fazia), (2) o mesmo
# caminho sob ".claude\.ai\knowledge\" (espelho do cortex), (3) na falta de disco, um commit REAL
# desde o arranque da ordem cujo diff toca um ficheiro com o mesmo nome (git, nunca o texto).
if ($recusaValida) {
  Proof 'ficheiro-check' 'dispensado: recusa valida (a ordem previa escape e o executor reportou)'
} elseif ($tarefa -match '(?i)\b(cria|criar|escreve|escrever|gera|gerar|adiciona|adicionar)\b') {
  # BUG 2026-09-04 (bloco-d1d2): a regex original nao incluia ":" na classe de caracteres,
  # por isso um caminho absoluto do Windows como "C:\Users\danil\...\x.txt" perdia a letra
  # da unidade -- o match comecava depois do "C:\" (em "Users\danil\..."). O Test-Path
  # seguinte fazia Join-Path $Proj "Users\danil\...", um caminho que nunca existe, e o juiz
  # reprovava trabalho real (prova: ordem 9d32, 8h queimadas em reabertura). Agora a regex
  # captura opcionalmente o prefixo de unidade ("C:\" ou "\\servidor\partilha\") ANTES do
  # resto do caminho, e o Test-Path usa o caminho absoluto diretamente em vez de o colar a
  # $Proj quando ja e um caminho absoluto (Join-Path nao normaliza dois caminhos absolutos).
  $paths = @()
  foreach ($m in [regex]::Matches($tarefa, '(?<![\w:])(?:[A-Za-z]:[\\/]|\\\\[A-Za-z0-9_.\-]+[\\/][A-Za-z0-9_.\-]+[\\/])?(?:[A-Za-z0-9_.\-]+[/\\])+[A-Za-z0-9_.\-]+\.[A-Za-z0-9]{1,10}')) { $paths += $m.Value }
  $paths = $paths | Select-Object -Unique -First 5
  foreach ($p in $paths) {
    $pp = $p -replace '/', '\'
    $isAbs = [System.IO.Path]::IsPathRooted($pp)
    $target = if ($isAbs) { $pp } else { Join-Path $Proj $pp }
    $ex = Test-Path $target
    Proof "Test-Path $pp" "$ex"
    if ($ex) { continue }

    if (-not $isAbs) {
      $ppMirror = Join-Path '.claude\.ai\knowledge' $pp
      $exMirror = Test-Path (Join-Path $Proj $ppMirror)
      Proof "Test-Path $ppMirror (espelho cortex)" "$exMirror"
      if ($exMirror) {
        Proof 'ficheiro-check' "$p nao esta no caminho literal mas existe no espelho do cortex ($ppMirror) - divergencia de caminho, nao trabalho em falta"
        continue
      }
    }

    $exGit = $false
    if ($inicio) {
      $bn = Split-Path $p -Leaf
      $gitOut = (git log "$base..HEAD" --name-only --pretty=format: -- "*$bn" 2>&1) -join ' | '
      $exGit = ($gitOut.Trim().Length -gt 0)
      Proof "git log $base..HEAD --name-only -- *$bn" $(if ($exGit) { $gitOut } else { '(vazio)' })
    }
    if ($exGit) {
      Proof 'ficheiro-check' "$p nao esta em nenhum caminho literal mas ha commit real desde o arranque da ordem que toca um ficheiro *$bn - divergencia de caminho, nao trabalho em falta"
      continue
    }

    Reprova "a ordem pedia criar/alterar o ficheiro $p e ele NAO existe em disco (nem no caminho literal, nem no espelho do cortex) nem ha commit real que o toque"
  }
}

Write-Output 'PROVA-JUIZ: chao mecanico OK - segue para o juiz textual'
exit 0
