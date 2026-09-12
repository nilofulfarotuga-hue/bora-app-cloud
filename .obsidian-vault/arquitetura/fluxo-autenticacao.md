# Fluxo de Autenticação — Bora App

> Como o app gere sessões, roles e login para os 3 tipos de utilizador.

---

## Arquitectura de Auth

```
Supabase Auth (email/password)
  + SharedPreferences (demo/offline accounts)
  + AuthStore (state management global)
  + SessionStore (role persistence)
```

### Dupla camada de autenticação
A app tem dois sistemas de auth em paralelo:
1. **Supabase Auth** — produção, utilizadores reais
2. **SharedPreferences** — contas de demonstração offline (para testes sem internet)

---

## Fluxo de Login por Role

### Cliente
```
SplashScreen
  → RoleScreen (escolher: Cliente / Driver / Parceiro)
  → ClientLoginScreen
    ├─ Email/Password → Supabase Auth → session_store salva role
    └─ Registo → RegisterClientScreen → Supabase signUp
  → ClientMainScreen (home)
```

### Driver
```
RoleScreen → DriverLoginScreen
  ├─ Login → Supabase Auth → verifica `driver_status` na tabela
  │   ├─ `approved` → DriverHomeScreen
  │   ├─ `pending` → DriverPendingScreen (aguarda aprovação admin)
  │   └─ `rejected` → DriverRejectedScreen
  └─ Registo → DriverSignupScreen → Supabase signUp + upload docs
```

### Parceiro
```
RoleScreen → PartnerEntryScreen
  ├─ Login → PartnerLoginScreen → Supabase Auth → PartnerDashboardScreen
  └─ Registo → RegisterPartnerScreen → Supabase signUp + dados do negócio
```

### Admin
```
LoginScreen (ecrã separado, sem RoleScreen)
  → Verifica email contra allowlist (`admin_emails` no Supabase)
  → AdminDashboardScreen
  
⚠️ BUG-004: A allowlist de emails admin pode não estar configurada correctamente
```

---

## AuthStore (lib/auth/auth_store.dart)

**Responsabilidades:**
- Subscrever ao stream `supabase.auth.onAuthStateChange`
- Persistir role do utilizador
- Expor `currentUser`, `isLoggedIn`, `userRole`
- Fazer logout (limpa SharedPreferences + Supabase session)

**State:**
```dart
String? userId
String? userRole  // 'client' | 'driver' | 'partner' | 'admin'
bool isAuthenticated
```

---

## SessionStore (lib/stores/session_store.dart)

**Responsabilidades:**
- Verificar se existe sessão activa ao iniciar o app
- Navegar para o ecrã correcto com base no role
- Gerir persistência offline (SharedPreferences)

**Lógica de arranque do app:**
```
main() → inicializar Supabase
  → SessionStore.checkSession()
    ├─ Existe sessão Supabase → verificar role → navegar
    ├─ Existe sessão SharedPreferences (demo) → navegar
    └─ Sem sessão → RoleScreen
```

---

## Problemas Identificados

### BUG-007 (já documentado): Edge cases de persistência de sessão
- Token Supabase pode expirar sem o app detectar
- Em modo demo (SharedPreferences), sem validação de token real
- Refresh do token não tratado explicitamente

### Segurança dos Roles
- O role é guardado localmente — um utilizador técnico poderia alterar o SharedPreferences
- Em produção, o role devia ser validado no servidor (via RLS policies do Supabase)
- Confirmar que as tabelas `drivers`, `partners`, `clients` têm RLS activa por `auth.uid()`

---

## Tabelas Supabase Envolvidas

| Tabela | Utilizada por | Notas |
|--------|--------------|-------|
| `auth.users` | Todos | Gerida pelo Supabase Auth |
| `clients` | ClientFlow | Dados do perfil do cliente |
| `drivers` | DriverFlow | Inclui `status`: pending/approved/rejected |
| `partners` | PartnerFlow | Dados do negócio, localização |
| `admin_emails` | AdminFlow | Allowlist de emails admin |
