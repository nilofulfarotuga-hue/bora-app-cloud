// Base falsa para simular o notify-driver sem tocar em produção.
// O mapa de imports (mapa.json) troca o supabase-js verdadeiro por isto.
// Quem responde a cada consulta é globalThis.__cenario (montado no teste).
// Uma consulta fora do previsto rebenta.

class Consulta {
  op = 'select'
  colunas = ''
  payload: any = null
  filtros: any[] = []
  constructor(public tabela: string) {}
  select(c = '*') { if (this.op === 'select') this.colunas = c; return this }
  update(p: any) { this.op = 'update'; this.payload = p; return this }
  insert(p: any) { this.op = 'insert'; this.payload = p; return this }
  eq(...a: any[]) { this.filtros.push(['eq', ...a]); return this }
  is(...a: any[]) { this.filtros.push(['is', ...a]); return this }
  in(...a: any[]) { this.filtros.push(['in', ...a]); return this }
  or(...a: any[]) { this.filtros.push(['or', ...a]); return this }
  order(...a: any[]) { this.filtros.push(['order', ...a]); return this }
  limit(...a: any[]) { this.filtros.push(['limit', ...a]); return this }
  maybeSingle() { return Promise.resolve((globalThis as any).__cenario.responder(this)) }
  then(ok: any, erro: any) {
    return Promise.resolve().then(() => (globalThis as any).__cenario.responder(this)).then(ok, erro)
  }
}

export function createClient(_url: string, _chave: string) {
  return {
    from: (tabela: string) => new Consulta(tabela),
    rpc: (nome: string, args: any) => Promise.resolve((globalThis as any).__cenario.rpc(nome, args)),
    auth: { getUser: (token: string) => Promise.resolve((globalThis as any).__cenario.utilizador(token)) },
  }
}
