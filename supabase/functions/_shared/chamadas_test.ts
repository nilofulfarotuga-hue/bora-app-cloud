// deno test supabase/functions/_shared/chamadas_test.ts
import { chamarFuncao } from './chamadas.ts';

/** Cliente admin de brincar: guarda o que se escreveu em e2e_log e responde ao invoke como mandarmos. */
function clienteDeBrincar(resposta: () => Promise<{ data: unknown; error: unknown }>) {
  const escritos: Record<string, unknown>[] = [];
  return {
    escritos,
    functions: { invoke: (_nome: string, _opts: unknown) => resposta() },
    from: (tabela: string) => ({
      insert: (linha: Record<string, unknown>) => {
        escritos.push({ tabela, ...linha });
        return Promise.resolve({ error: null });
      },
    }),
  };
}

Deno.test('sucesso nao escreve nada em e2e_log', async () => {
  const c = clienteDeBrincar(() => Promise.resolve({ data: { ok: true }, error: null }));
  const r = await chamarFuncao(c, 'origem', 'destino', {});
  if (!r.ok || c.escritos.length !== 0) throw new Error('sucesso nao devia registar');
});

Deno.test('resposta nao-2xx fica registada com o codigo e o texto', async () => {
  const resposta = new Response('{"error":"unauthorized"}', { status: 401 });
  const c = clienteDeBrincar(() => Promise.resolve({ data: null, error: { message: 'Edge Function returned a non-2xx status code', context: resposta } }));
  const r = await chamarFuncao(c, 'cancel-order-with-choice', 'notify-client', {});
  if (r.ok || r.status !== 401) throw new Error('devia falhar com 401');
  const l = c.escritos[0];
  if (!l || l.tabela !== 'e2e_log' || l.fluxo !== 'edge-chamada-falhou') throw new Error('devia escrever em e2e_log');
  if (l.passo !== 'cancel-order-with-choice -> notify-client') throw new Error('passo errado: ' + l.passo);
  if (!String(l.detalhe).includes('HTTP 401') || !String(l.detalhe).includes('unauthorized')) throw new Error('detalhe sem codigo/texto');
});

Deno.test('excecao fica registada e nao rebenta quem chama', async () => {
  const c = clienteDeBrincar(() => Promise.reject(new Error('rede em baixo')));
  const r = await chamarFuncao(c, 'a', 'b', {});
  if (r.ok || !String(r.erro).includes('rede em baixo')) throw new Error('devia devolver o erro');
  if (c.escritos.length !== 1) throw new Error('devia registar a excecao');
});

Deno.test('200 com ok:false nao e falha de transporte', async () => {
  const c = clienteDeBrincar(() => Promise.resolve({ data: { ok: false, reason: 'no_fcm_token' }, error: null }));
  const r = await chamarFuncao(c, 'a', 'notify-partner', {});
  if (!r.ok || c.escritos.length !== 0) throw new Error('ok:false de negocio nao se regista como falha');
});
