# Sessão Login Facilitado — L2 + L1 + L3 + SEC (2026-06-12)

> Modo: ⚠️ PROTECÇÃO TOTAL · CEO-AI orchestrator · BORA_DNA lido
> Branch: `autonomous-night-2026-04-29` · 4 commits (1 por bloco)
> `flutter analyze`: **0 errors** após cada bloco

## Âmbito

Login facilitado nos **3 papéis** (cliente, estafeta, parceiro). Os ecrãs de
login são separados — aplicado aos 3 ativos:
- `client_login_screen.dart` (cliente)
- `driver_login_screen.dart` (estafeta)
- `partner_login_screen.dart` (parceiro)

`login_screen.dart` (tabs antigas) é **órfão**: só está registado na rota
`/login` e nenhum sítio navega para lá — não foi tocado (cirúrgico).

---

## L2 — Autofill Android — commit `5ccb114`

- `AutofillGroup` à volta do form + `AutofillHints.email` / `.password`
  nos campos, nos 3 ecrãs.
- `TextInput.finishAutofillContext()` após login com sucesso → dispara o
  prompt "Guardar palavra-passe?" (Google Password Manager / Samsung Pass).
- Zero mudança na lógica de autenticação.

## L1 — Lembrar email — commit `61980d0`

- Novo `lib/services/login_prefs.dart` — guarda o **último email** por papel
  (`bora_login.last_email.{client|driver|partner}`) em SharedPreferences.
- Gravado após login com sucesso; pré-preenchido no `initState` do ecrã.
- Link **"Entrar com outra conta"** (aparece só quando veio da memória):
  limpa campos + esquece o email guardado.
- A palavra-passe NUNCA passa pelo L1.

## L3 — Biometria — commit `7b622d6`

**Dependências novas:** `local_auth ^2.3.0` + `flutter_secure_storage ^9.2.2`.
`MainActivity` já era `FlutterFragmentActivity` (requisito do local_auth) —
zero mudança nativa além de 2 permissões no manifest (`USE_BIOMETRIC`,
`USE_FINGERPRINT` p/ Android <9).

**Fluxo (espelha apps de banca):**
1. Login com senha OK → pergunta **uma vez** "Entrar com biometria?"
   (`biometric_enrollment_dialog.dart`; flag asked por papel).
2. Se sim → digital/rosto → refresh token Supabase guardado em
   **flutter_secure_storage** (Android Keystore), por papel.
3. No ecrã de login, botão **"Entrar com biometria"** (aparece só com
   aparelho capaz + token guardado) → `local_auth.authenticate` →
   `AuthStore.restoreSessionWithRefreshToken` (`setSession` + gate de papel
   via `bora_role`) → entra direto.
4. Fallback senha sempre visível. Token inválido/expirado → apaga token,
   esconde botão, snackbar a pedir senha.

**Pontos técnicos importantes:**
- **Rotação de refresh tokens:** o Supabase roda o refresh token a cada
  refresh. `_onAuthStateChange` (signedIn/tokenRefreshed) chama
  `syncRefreshedToken` e mantém o token guardado atual — sem isto o login
  biométrico morria ao fim de ~1h.
- **Estafeta:** pós-login partilhado `_finishDriverLogin` (senha+biometria)
  mantém os gates pending/rejected e chama `refreshApprovalStatus()` —
  sem isso o caminho biométrico deixava `_currentDriverStatus` no default
  `pending` e o estafeta aprovado via o ecrã "Conta em análise".
- **Parceiro:** pós-login partilhado `_finishPartnerLogin` mantém o gate
  restaurante/service_provider (barbearias OK).

**Toggle "Login com biometria"** (`biometric_login_tile.dart`, esconde-se
sem biometria no aparelho):
- Cliente + Estafeta → `profile_screen.dart` (perfil partilhado, role-aware)
- Parceiro restaurante → `partner_dashboard_screen.dart` (junto aos toggles
  de reservas/takeaway)
- Parceiro serviços (barbearia) → `partner_services_hub_screen.dart`

**Logout vs troca de papel:**
- `logout({wipeBiometrics = true})` — "Sair"/"Terminar sessão" explícito
  **apaga** os tokens biométricos (regra de segurança do prompt).
- `wipeBiometrics: false` em: RoleScreen (3×), "Mudar modo", `_handleTestMode`
  (cliente/estafeta/parceiro), limpeza pós-signup estafeta, e bounces de
  aprovação nos logins (pending/rejected/sem-restaurante) — trocar de papel
  não mata o login biométrico dos outros papéis.

## SEC — senha em claro (achado da sessão) — commit `131f9ce`

🚨 **Pré-existente:** o `AuthStore` guardava a **palavra-passe em claro** no
JSON da conta em SharedPreferences (`_persistClient/Driver/Partner`) e usava-a
no `_initFromPrefs` para re-autenticar no arranque — violava diretamente a
regra "Senha NUNCA gravada em claro em lado nenhum" desta sessão.

**Fix (zero mudança de comportamento):** novo
`lib/services/secure_credentials_store.dart` — a password passa a viver no
Keystore; o JSON persiste só dados não-sensíveis. Migração automática no
primeiro arranque (campo legado → secure storage + JSON regravado sem
password). Logout limpa tudo. Auto-login continua igual.

---

## Checklist de teste manual (Samsung A36, build ≥284)

**L2 (autofill):**
- [ ] Login cliente → Android oferece "Guardar palavra-passe?"
- [ ] Logout explícito → reabrir login → toque no campo email → Google
      Password Manager sugere preencher email+senha

**L1 (lembrar email):**
- [ ] Login OK → "Sair" no perfil → ecrã de login com email já preenchido
- [ ] "Entrar com outra conta" limpa e deixa de pré-preencher
- [ ] Repetir como estafeta e parceiro

**L3 (biometria):**
- [ ] Login com senha → diálogo "Entrar com biometria?" (só na 1ª vez)
- [ ] Aceitar → digital → "Login com biometria ativado."
- [ ] Voltar à escolha de perfil → mesmo papel → botão "Entrar com
      biometria" visível → digital → entra direto
- [ ] Estafeta aprovado via biometria → home normal (NÃO ecrã pending)
- [ ] Toggle no perfil desliga → botão desaparece do login
- [ ] "Terminar sessão" (Sair) → botão biometria desaparece (token apagado)
- [ ] Aparelho sem biometria configurada → nada de biometria em lado nenhum

**SEC (migração):**
- [ ] Atualizar de build antigo com sessão guardada → auto-login continua a
      funcionar no primeiro arranque (migração transparente)

## Pendentes / notas
- Validar no aparelho que o prompt do Google Password Manager aparece em
  release (autofill é sensível ao gestor instalado).
- `login_screen.dart` órfão + rota `/login` morta — candidato a remoção em
  limpeza futura (não tocado nesta sessão).
- Warning pré-existente `unused_local_variable 'user'` em
  `profile_screen.dart:374` — já existia em HEAD, não tocado.
- Knowledge: propor entrada em `bora-knowledge` (06-flows) sobre o fluxo de
  login biométrico — aguarda aprovação do Danilo (Knowledge Protocol).
