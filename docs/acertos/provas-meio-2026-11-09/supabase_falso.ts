// Base falsa para correr a Edge settlement-receipt sem tocar na Supabase.
// Só responde ao que a despacharFila usa; qualquer outra consulta rebenta (assim um caminho
// inesperado não passa calado). A fila e o registo das escritas vivem em globalThis.__base.
// deno-lint-ignore-file no-explicit-any

export function createClient(_url: string, _key: string) {
  const base = (globalThis as any).__base
  return {
    rpc(nome: string, args: any) {
      base.chamadas.push({ rpc: nome, args })
      if (nome === 'settlement_subject_user_id') return Promise.resolve({ data: 'uid-' + args.p_subject_id, error: null })
      throw new Error('rpc inesperada na base falsa: ' + nome)
    },
    from(tabela: string) {
      const q: any = { tabela, filtros: [] as any[], acao: 'select', valores: null }
      const fim = () => {
        base.chamadas.push({ from: tabela, acao: q.acao, filtros: q.filtros, valores: q.valores })
        if (tabela === 'platform_settings') return { data: { value: base.boraMbway }, error: null }
        if (tabela === 'settlement_receipts' && q.acao === 'select') return { data: base.fila, error: null }
        if (tabela === 'settlement_receipts' && q.acao === 'update') {
          const id = q.filtros.find((f: any) => f[0] === 'eq' && f[1] === 'id')?.[2]
          base.atualizacoes.push({ id, ...q.valores })
          return { data: null, error: null }
        }
        if (tabela === 'provider_push_tokens') return { data: [{ fcm_token: 'token-falso-' + q.filtros[0]?.[2] }], error: null }
        if (tabela === 'users') return { data: null, error: null }
        throw new Error('tabela inesperada na base falsa: ' + tabela + ' ' + q.acao)
      }
      const enc: any = {
        select() { return enc },
        update(v: any) { q.acao = 'update'; q.valores = v; return enc },
        eq(c: string, v: any) { q.filtros.push(['eq', c, v]); return enc },
        in(c: string, v: any) { q.filtros.push(['in', c, v]); return enc },
        lt(c: string, v: any) { q.filtros.push(['lt', c, v]); return enc },
        order() { return enc },
        limit() { return enc },
        maybeSingle() { return Promise.resolve(fim()) },
        then(ok: any, ko: any) { return Promise.resolve(fim()).then(ok, ko) },
      }
      return enc
    },
  }
}
