# Cadastro de parceiro — 3 bugs (verificação, não reinvestigação)

Este pedido literal (login reinicia wizard / erro genérico no submit / scroll
cortado no passo 4 / verificar campo senha) já tinha sido resolvido e
reconfirmado **6+ vezes** pelo loop autónomo em 2026-07-14, antes desta
rodada. Ver memórias:
- `project_login_parceiro_reinicia_wizard_resolvido`
- `project_erro_submissao_iban_generico_resolvido`
- `project_cadastro_parceiro_scroll_resolvido`
- `project_cadastro_parceiro_senha_ja_resolvido_5x`

Seguindo a própria instrução dessas memórias ("a partir da 4ª/6ª+ vez, sem
diff novo, não reescrever tudo — só confirmar"), esta rodada fez apenas
verificação rápida, sem reescrever código:

## BUG 1 — login reinicia wizard
`register_partner_screen.dart:72-75` já lê `context.read<AuthStore>().currentPartner`
no `initState` e pré-preenche email; `partner_login_screen.dart` já não expulsa
o login quando falta `restaurants`. **Sem alteração necessária.**

## BUG 2 — erro genérico no submit (causa real: IBAN)
Causa raiz (regex `^PT\d{21}$` em vez de `^PT\d{23}$` na Edge Function
`register-partner`) já corrigida e deployed em prod (v5, confirmado
anteriormente via MCP Supabase). App já usa `resumePartnerRegistrationAsync`
+ mensagem de erro real em vez do genérico. **Sem alteração necessária.**

## BUG 3 — scroll cortado no passo 4
`register_partner_screen.dart:508` já tem
`physics: const NeverScrollableScrollPhysics()` no `Stepper` dentro do
`SingleChildScrollView`. **Sem alteração necessária.**

## Campo senha / email duplicado
`_passwordController` existe (linha 51), validação min. 6 caracteres
(linha 277), campo visível no passo "Conta de Acesso" (linha 734) — oculto
apenas quando `currentPartner != null` (retomada). Email duplicado já trata
com mensagem clara. **Sem alteração necessária.**

## Verificação desta rodada (o que mudou vs. rondas anteriores)
- `git diff 3c19043 HEAD` nos 4 ficheiros: **vazio** — zero regressão.
- `flutter analyze` nos 3 ficheiros Flutter: **0 erros**, mesmos 6
  warnings/infos pré-existentes (imports não usados, `_formKey` não usado,
  1 `deprecated_member_use`) já documentados nas rondas anteriores.
- **NOVIDADE desta rodada:** `git branch -r --contains 3c19043` agora inclui
  `origin/autonomous-night-2026-04-29` — o push que estava bloqueado por
  Lista Vermelha (dispara `build_android.yml` = build de produção) **já
  aconteceu** (por outra sessão/executor, ver `git log` no topo do branch:
  `f00cba4`, `5b6d52a`, `d3adc5d`). Isto fecha a última pendência residual
  registada em `project_login_parceiro_reinicia_wizard_resolvido` — o fix já
  está no repositório remoto, só falta confirmar se já subiu numa build nova
  para as lojas (fora do escopo desta verificação).
- Paridade admin: `lib/screens/admin/admin_partners_pending_screen.dart`
  já existe (ecrã de aprovação de parceiros pendentes) — gatilho de
  paridade já satisfeito, sem ação necessária.

## Recomendação
Não há mais nada a corrigir no código para estes 3 bugs. Se o Danilo voltar
a ver o sintoma em dispositivo real, a causa mais provável agora é o APK
instalado ser de uma build anterior ao commit `3c19043` — confirmar a
versão/data de build antes de reabrir investigação de código.

## Ronda adicional — 2026-07-15 (7ª+ reconfirmação)
O mesmo pedido literal voltou a chegar ao loop autónomo, agora em
2026-07-15. Verificação rápida (conforme instruído em
`project_cadastro_parceiro_senha_ja_resolvido_5x`):
- `HEAD` = `d3adc5d` (branch avançou com trabalho do Hermes, não do wizard).
- `git diff 3c19043 HEAD -- lib/screens/register_partner_screen.dart
  lib/screens/partner_login_screen.dart lib/auth/auth_store.dart` → **vazio**.
- Marcadores dos 3 fixes confirmados por grep no ficheiro atual:
  `currentPartner` (retoma sem reiniciar), `NeverScrollableScrollPhysics`
  (scroll do passo 4), `_passwordController` + `resumePartnerRegistrationAsync`
  (senha + retomada sem recriar conta).
- `flutter analyze` nos 3 ficheiros: **0 erros**, mesmos 6 warnings/infos
  pré-existentes (imports não usados, `_formKey` não usado, 1
  `deprecated_member_use` em `value`→`initialValue`) — idênticos às rondas
  anteriores, sem regressão.

**Sinal para o orquestrador:** esta é a 7ª+ vez que o loop recebe este
pedido idêntico sem sintoma novo (sem print de erro real, sem passo exato,
sem email/conta específica). Recomenda-se que o carteiro/CEO-AI pare de
reenviar esta tarefa como está e, se o Danilo continuar a ver o problema,
peça um sintoma concreto (screenshot, versão do APK instalado, email
usado) em vez de repetir o mesmo texto — ver
`project_zona_vermelha_gate_pressure_pattern` para o padrão análogo de
pedido repetido ao loop.

## Ronda adicional — 2026-07-15 (8ª+ reconfirmação)
Pedido literal idêntico chegou de novo ao loop autónomo. Verificação:
- `HEAD` = `d3adc5d` — **exatamente o mesmo commit** da ronda 7ª+ acima. Zero
  commits novos tocaram o wizard de parceiro entre as duas rondas.
- `git status --porcelain` nos 4 ficheiros (`register_partner_screen.dart`,
  `partner_login_screen.dart`, `partner_entry_screen.dart`,
  `auth/auth_store.dart`): **vazio**, sem alterações locais pendentes.
- Confirmado (via `git branch -r --contains 3c19043`) que o fix está em
  `origin/autonomous-night-2026-04-29` — não é só local.
- Reconfirmados por leitura direta do código (não só grep): `_alreadyAuthenticated`
  → `resumePartnerRegistrationAsync` (BUG 1, não recria conta), `specificError ??`
  com fallback genérico só quando `result['error']` é nulo + `isDuplicateEmail`
  volta ao passo 2 (BUG 2), `SingleChildScrollView` envolvendo `Stepper` com
  `NeverScrollableScrollPhysics` (BUG 3), `_passwordController` com validação
  min. 6 chars visível no passo "Conta de Acesso" (campo senha).
- `flutter analyze` nos 4 ficheiros: **0 erros**, mesmos 6 warnings/infos
  pré-existentes, sem regressão.
- Painel admin: `admin_partners_pending_screen.dart` já existe — paridade OK.
- Dispositivos ligados nesta máquina (`23028RN4DG`, `SM A366B`) permitiriam
  teste manual end-to-end, mas não há ferramenta de automação de UI/toque
  disponível nesta sessão headless para dirigir o fluxo sem o Danilo — o
  teste E2E manual completo (criar conta → submeter → logout → login)
  continua por fazer neste ambiente; o que É verificável sem dispositivo
  (código, commit, push, analyze, paridade admin) está tudo confirmado OK.

**Isto é agora a 8ª+ vez, com HEAD idêntico à ronda anterior — confirma que
não há nenhum estado novo a investigar.** Nenhuma alteração de código feita
nesta ronda (nada para mudar). Recomendação mantém-se: só reabrir com
sintoma concreto e novo (screenshot, versão do APK, email usado no teste).
