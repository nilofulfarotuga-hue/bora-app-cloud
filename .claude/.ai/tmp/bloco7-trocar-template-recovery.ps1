# Bloco 7 (missao tvde-pacote-mapas-senha, 2026-08-30) — trocar o template do
# email de recuperacao para o fluxo token_hash (a prova de prefetch).
#
# ⚠️ SO CORRER DEPOIS de o web app com suporte a token_hash estar NO AR
# (lib/screens/reset_password_screen.dart desta missao, deployado em
# app.boraguarda.com). Correr antes parte a recuperacao para toda a gente:
# o ecra publicado hoje nao reconhece links token_hash.
#
# O que faz: substitui {{ .ConfirmationURL }} (link /verify de uso unico, que
# o prefetch do Gmail gasta antes do clique humano) por um link directo ao ecra
# com {{ .TokenHash }} — o token so se gasta quando a pessoa carrega em
# "Guardar" (verifyOTP). Prova server-side do fluxo: relatorio
# .claude/.ai/reports/tvde-pacote-mapas-senha-2026-08-30.md (5/5 passos).
#
# Correr da RAIZ do repo: powershell -File .claude\.ai\tmp\bloco7-trocar-template-recovery.ps1
$ErrorActionPreference = 'Stop'
Get-Content .supabase-token.env | ForEach-Object {
  if ($_ -match '^\s*([^#=]+)=(.*)$') { Set-Item -Path ("env:" + $Matches[1].Trim()) -Value $Matches[2].Trim() }
}
$uri = 'https://api.supabase.com/v1/projects/ojykpzwqrtusfeakzrna/config/auth'
$h = @{ Authorization = "Bearer $env:SUPABASE_ACCESS_TOKEN"; 'Content-Type' = 'application/json' }

$cfg = Invoke-RestMethod -Uri $uri -Headers $h
$tpl = $cfg.mailer_templates_recovery_content
$linkNovo = 'https://app.boraguarda.com/#/redefinir-palavra-passe?token_hash={{ .TokenHash }}&type=recovery'
$tplNovo = $tpl.Replace('{{ .ConfirmationURL }}', $linkNovo)
if ($tplNovo -eq $tpl) { throw 'Nada substituido — o template ja foi trocado?' }

# Backup do template actual (regra 3.10 — deixa o artefacto).
$backup = ".claude\.ai\tmp\recovery-template-backup-$(Get-Date -Format yyyyMMddHHmmss).html"
$tpl | Out-File -Encoding utf8 $backup
"Backup em $backup"

Invoke-RestMethod -Method Patch -Uri $uri -Headers $h `
  -Body (@{ mailer_templates_recovery_content = $tplNovo } | ConvertTo-Json -Depth 3) | Out-Null

# Prova 3.1: reler e confirmar que gravou.
$chk = (Invoke-RestMethod -Uri $uri -Headers $h).mailer_templates_recovery_content
if ($chk.Contains('token_hash={{ .TokenHash }}')) { 'TROCADO E CONFIRMADO' } else { throw 'PATCH nao pegou' }
