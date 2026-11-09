// Bloco E (pendencias-2026-11-09) — guarda de texto da migração da RPC
// `admin_clientes_metodo_login` e das ligações de volta do Google/Apple.
// A lógica da função foi provada em Postgres real (PGlite):
// .claude/.ai/missoes/pendencias-2026-11-09/E-google/provar_admin_metodo_login.mjs
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _sem(String sql) => sql
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('--'))
    .join('\n')
    .toLowerCase();

void main() {
  final sql = _sem(File(
          'supabase/migrations/20261109221500_admin_metodo_login.sql')
      .readAsStringSync());

  test('RPC só de admin: is_admin() e erro 42501 como as outras admin_*', () {
    expect(sql, contains('create or replace function public.admin_clientes_metodo_login('));
    expect(sql, contains('if not public.is_admin() then'));
    expect(sql, contains("raise exception 'admin_required' using errcode = '42501'"));
    expect(sql, contains('security definer'));
    expect(sql, contains('from auth.identities'));
  });

  test('fechada a PUBLIC e a anon; aberta só a authenticated e service_role',
      () {
    expect(sql,
        contains('revoke all on function public.admin_clientes_metodo_login(uuid[]) from public;'));
    expect(sql,
        contains('revoke all on function public.admin_clientes_metodo_login(uuid[]) from anon;'));
    expect(sql, contains('to authenticated, service_role;'));
    expect(RegExp(r'grant[^;]*\banon\b').hasMatch(sql), isFalse);
  });

  test('interruptores: Google ligado, Apple desligada, sem pisar o que existe',
      () {
    expect(sql, contains("('login_google_ativo', 'true'::jsonb"));
    expect(sql, contains("('login_apple_ativo', 'false'::jsonb"));
    expect(sql, contains('on conflict (key) do nothing'));
    // Não mexe em dinheiro nem em tabelas de pedidos.
    for (final t in ['orders', 'wallets', 'ledger', 'bora_tokens', 'drivers']) {
      expect(RegExp('(update|delete from|insert into) public\\.$t\\b').hasMatch(sql),
          isFalse,
          reason: 'a migração não pode escrever em $t');
    }
  });

  test('Android: pt.boraapp.bora://auth nos 3 manifestos por tipo de build e '
      'sem o Flutter a empurrar a ligação como rota', () {
    for (final t in ['debug', 'profile', 'release']) {
      final m = File('android/app/src/$t/AndroidManifest.xml').readAsStringSync();
      expect(m, contains('android:scheme="pt.boraapp.bora" android:host="auth"'),
          reason: t);
      expect(m, contains('android:name="flutter_deeplinking_enabled"'), reason: t);
      expect(m, contains('android:value="false"'), reason: t);
    }
  });

  test('iPhone: esquema pt.boraapp.bora declarado e deep linking do Flutter '
      'desligado', () {
    final p = File('ios/Runner/Info.plist').readAsStringSync();
    expect(p, contains('<string>pt.boraapp.bora</string>'));
    expect(
        RegExp(r'<key>FlutterDeepLinkingEnabled</key>\s*<false/>').hasMatch(p),
        isTrue);
  });
}
