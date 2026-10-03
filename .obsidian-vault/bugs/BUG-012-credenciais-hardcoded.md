---
prioridade: CRÍTICA 🔴
ficheiro: lib/main.dart
bug_id: BUG-012
---

# BUG-012 — Credenciais API hardcoded no source code

## Descrição
As credenciais do Supabase e Stripe estão literalmente no `main.dart`, expostas no APK compilado e no repositório git.

## Localização
**Ficheiro:** `bora_app/lib/main.dart`

```dart
const String _supabaseUrl = 'https://ojykpzwqrtusfeakzrna.supabase.co';
const String _supabaseAnonKey = 'eyJ...'; // chave completa exposta
Stripe.publishableKey = 'pk_test_51T8MG0GmiUUEIr722bf8...';
```

## Risco
- Qualquer pessoa com o APK pode extrair as chaves com ferramentas como `apktool`
- A `anonKey` do Supabase permite acesso directo à base de dados (limitado pelas RLS policies, mas mesmo assim)
- A Stripe `publishableKey` em modo `pk_test_` está a ser usada — isto significa que os pagamentos em produção ainda estão em modo de teste

## Solução Proposta
1. Usar `flutter_dotenv` ou `--dart-define` no build para injectar variáveis de ambiente
2. A Stripe publishableKey deve mudar para `pk_live_` antes do lançamento
3. Para Supabase, a anonKey pode ficar no cliente (é pública por design), mas confirmar que as RLS policies estão todas activas

## Acções Imediatas
- [ ] Trocar `pk_test_` por `pk_live_` antes de lançar
- [ ] Confirmar que todas as tabelas Supabase têm RLS activa
- [ ] Adicionar `--dart-define=SUPABASE_KEY=xxx` no pipeline de CI/CD
