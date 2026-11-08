// Testes da decisão de conta Connect (M7, 08/11/2026). Sem rede, sem chaves.
// deno test supabase/functions/_shared/connect_conta_test.ts
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { decidirContaConnect, ehPapelConnect, tokenConviteValido } from './connect_conta.ts';

Deno.test('sem conta: cria na conta-alvo', () => {
  assertEquals(decidirContaConnect({ id: 'boom' }, 'empresa'), {
    acao: 'criar',
    conta: 'empresa',
    contaAntiga: null,
  });
  assertEquals(decidirContaConnect({ id: 'boom', stripe_account_id: '  ' }, 'pessoal'), {
    acao: 'criar',
    conta: 'pessoal',
    contaAntiga: null,
  });
});

Deno.test('conta antiga sem coluna de dona conta como pessoal e é usada com o interruptor em pessoal', () => {
  assertEquals(decidirContaConnect({ id: 'goola', stripe_account_id: 'acct_1' }, 'pessoal'), {
    acao: 'usar',
    conta: 'pessoal',
    accountId: 'acct_1',
  });
});

Deno.test('conta na pessoal com o interruptor em empresa: cria nova na empresa e guarda a antiga', () => {
  assertEquals(
    decidirContaConnect(
      { id: 'goola', stripe_account_id: 'acct_1', stripe_account_owner: 'pessoal', stripe_account_status: 'enabled' },
      'empresa',
    ),
    { acao: 'criar', conta: 'empresa', contaAntiga: { conta: 'pessoal', accountId: 'acct_1' } },
  );
});

Deno.test('conta já na empresa: usa', () => {
  assertEquals(
    decidirContaConnect({ id: 'boom', stripe_account_id: 'acct_2', stripe_account_owner: 'empresa' }, 'empresa'),
    { acao: 'usar', conta: 'empresa', accountId: 'acct_2' },
  );
});

Deno.test('valor estranho na coluna de dona = pessoal (nunca inventa a empresa)', () => {
  assertEquals(
    decidirContaConnect({ id: 'x', stripe_account_id: 'acct_3', stripe_account_owner: 'EMPRESA ' }, 'pessoal'),
    { acao: 'usar', conta: 'pessoal', accountId: 'acct_3' },
  );
});

Deno.test('papéis aceites', () => {
  assertEquals(['partner', 'provider', 'driver', 'cleaner'].every(ehPapelConnect), true);
  assertEquals(ehPapelConnect('admin'), false);
  assertEquals(ehPapelConnect(undefined), false);
});

Deno.test('token do convite: só hexadecimal com 40 a 128 caracteres', () => {
  assertEquals(tokenConviteValido('a'.repeat(64)), true);
  assertEquals(tokenConviteValido('0123456789abcdef'.repeat(4)), true);
  assertEquals(tokenConviteValido('a'.repeat(39)), false);
  assertEquals(tokenConviteValido('A'.repeat(64)), false);
  assertEquals(tokenConviteValido("x' or 1=1--".padEnd(64, 'a')), false);
  assertEquals(tokenConviteValido(null), false);
});
