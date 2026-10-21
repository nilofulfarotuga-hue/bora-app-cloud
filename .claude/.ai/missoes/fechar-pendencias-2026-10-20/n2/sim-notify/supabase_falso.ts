// Base de dados FALSA para simular a Edge notify-tvde-driver (N2, 21/10/2026).
// O mapa de imports (mapa.json) troca o supabase-js verdadeiro por isto.
// Quem responde é globalThis.__cenario. Tabela ou operação fora do previsto rebenta.
// Nenhum pedido sai para a base verdadeira nem para o Firebase verdadeiro.

class Consulta {
  op = 'select'
  colunas = ''
  payload: any = null
  filtros: any[] = []
  constructor(public tabela: string) {}
  select(c = '*') { if (this.op === 'select') this.colunas = c; return this }
  update(p: any) { this.op = 'update'; this.payload = p; return this }
  insert(p: any) { this.op = 'insert'; this.payload = p; return Promise.resolve((globalThis as any).__cenario.responder(this)) }
  eq(...a: any[]) { this.filtros.push(['eq', ...a]); return this }
  order(...a: any[]) { this.filtros.push(['order', ...a]); return this }
  maybeSingle() { return Promise.resolve((globalThis as any).__cenario.responder(this)) }
  then(ok: any, erro: any) {
    return Promise.resolve().then(() => (globalThis as any).__cenario.responder(this)).then(ok, erro)
  }
}

export function createClient(_url: string, _chave: string) {
  return {
    from: (tabela: string) => new Consulta(tabela),
    rpc: (nome: string, args: any) => Promise.resolve((globalThis as any).__cenario.rpc(nome, args)),
  }
}
