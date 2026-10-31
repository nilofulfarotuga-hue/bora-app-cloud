// _shared/chamadas.ts — chamadas entre Edge Functions que nunca falham em silêncio.
// Missão chaves-varredura-2026-10-31 (bloco A10). Ler docs/SEGURANCA-CHAVES.md antes de mexer.
//
// Porquê: desde a troca de chaves (16/10) várias funções chamavam outras, recebiam 401/400 e
// engoliam o erro num try/catch — o pagamento de 31/10 ficou sem pedido e ninguém soube. Agora
// cada falha (resposta não-2xx ou exceção) fica escrita em e2e_log (fluxo 'edge-chamada-falhou'),
// que o painel e os vigias leem.
//
// Como se usa (cliente admin feito com secretKey(); o supabase-js manda a chave em `apikey` E em
// `Authorization: Bearer`, que é o padrão da Supabase):
//   const r = await chamarFuncao(admin, 'cancel-order-with-choice', 'notify-client', { clientId, title, body })
//   if (!r.ok) ... (já ficou registado; quem chama decide se isso trava ou não)

// deno-lint-ignore no-explicit-any
type ClienteAdmin = any;

export type ResultadoChamada = { ok: boolean; status: number | null; dados: unknown; erro: string | null };

/** Escreve a falha em e2e_log. Nunca rebenta quem chama. */
export async function registarFalhaDeChamada(
  admin: ClienteAdmin,
  origem: string,
  destino: string,
  status: number | null,
  detalhe: string,
): Promise<void> {
  try {
    await admin.from('e2e_log').insert({
      fluxo: 'edge-chamada-falhou',
      passo: `${origem} -> ${destino}`,
      estado: 'erro',
      detalhe: `HTTP ${status ?? '?'} · ${detalhe}`.slice(0, 1000),
      device: 'edge',
    });
  } catch {
    // o registo é melhor-esforço: a função que chamou continua
  }
  console.error(`[${origem}] chamada a ${destino} falhou: HTTP ${status ?? '?'} · ${detalhe.slice(0, 300)}`);
}

/** functions.invoke + registo da falha. Resposta 200 com { ok:false } não é falha de transporte. */
export async function chamarFuncao(
  admin: ClienteAdmin,
  origem: string,
  destino: string,
  corpo: unknown,
): Promise<ResultadoChamada> {
  try {
    const { data, error } = await admin.functions.invoke(destino, { body: corpo });
    if (error) {
      const contexto = (error as { context?: Response })?.context;
      const status = typeof contexto?.status === 'number' ? contexto.status : null;
      let detalhe = String((error as { message?: string })?.message ?? error);
      try {
        const texto = contexto && typeof contexto.text === 'function' ? await contexto.text() : '';
        if (texto) detalhe += ` · ${texto.slice(0, 300)}`;
      } catch {
        // corpo já lido ou indisponível
      }
      await registarFalhaDeChamada(admin, origem, destino, status, detalhe);
      return { ok: false, status, dados: null, erro: detalhe };
    }
    return { ok: true, status: 200, dados: data, erro: null };
  } catch (e) {
    const detalhe = String((e as Error)?.message ?? e);
    await registarFalhaDeChamada(admin, origem, destino, null, detalhe);
    return { ok: false, status: null, dados: null, erro: detalhe };
  }
}
