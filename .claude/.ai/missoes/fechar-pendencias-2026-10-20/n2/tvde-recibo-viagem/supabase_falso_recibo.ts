// Base FALSA para simular a Edge tvde-recibo-viagem (N2, 21/10/2026). Quem responde: globalThis.__cenario.
class Consulta {
  op = 'select'
  colunas = ''
  payload: any = null
  filtros: any[] = []
  constructor(public tabela: string) {}
  select(c = '*') { if (this.op === 'select') this.colunas = c; return this }
  upsert(p: any, _o?: any) { this.op = 'upsert'; this.payload = p; return Promise.resolve((globalThis as any).__cenario.responder(this)) }
  eq(...a: any[]) { this.filtros.push(['eq', ...a]); return this }
  maybeSingle() { return Promise.resolve((globalThis as any).__cenario.responder(this)) }
}

export function createClient(_url: string, _chave: string, _opts?: any) {
  const c = (globalThis as any).__cenario
  return {
    from: (tabela: string) => new Consulta(tabela),
    rpc: (nome: string, args: any) => Promise.resolve(c.rpc(nome, args)),
    auth: {
      getUser: () => Promise.resolve(c.utilizador()),
      admin: { getUserById: (id: string) => Promise.resolve(c.utilizadorPorId(id)) },
    },
  }
}
