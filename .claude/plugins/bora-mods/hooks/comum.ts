// =============================================================================
// bora-mods · comum.ts — peças PURAS partilhadas pelos cinco mods.
// Regra do motor: o `$` só se usa no ficheiro onde o gancho vive, nunca passa
// por um import. Por isso aqui só há funções que recebem e devolvem dados; a
// leitura/escrita de ficheiros e os pedidos à rede ficam em cada mod.
// =============================================================================

/** Raiz do repositório a partir da pasta do plugin (.claude/plugins/bora-mods). */
export function raizDe(pastaPlugin: string): string {
  return pastaPlugin.replace(/\\/g, '/').replace(/\/\.claude\/plugins\/bora-mods\/?$/i, '')
}

/** Caminho de um log em .claude/.ai/mods/. */
export function caminhoLog(pastaPlugin: string, ficheiro: string): string {
  return `${raizDe(pastaPlugin)}/.claude/.ai/mods/${ficheiro}`
}

/** Os argumentos de uma chamada de ferramenta, sem o envelope. */
export function argsDe(e: object): Record<string, unknown> {
  const { tool: _t, tool_use_id: _id, agentId: _a, ...resto } = e as Record<string, unknown>
  return resto
}

/** Conteúdo novo do log: o antigo + uma linha JSON (guarda as últimas 2000). */
export function juntarLinha(antigo: string, registo: Record<string, unknown>, agoraIso: string): string {
  const linhas = antigo.split('\n').filter(l => l.trim() !== '')
  linhas.push(JSON.stringify({ ts: agoraIso, ...registo }))
  return linhas.slice(-2000).join('\n') + '\n'
}

export type Pedido = { url: string; init: { method: string; headers: Record<string, string>; body: string } }

/** Pedido REST que insere uma linha no e2e_log (a chave anon só insere). */
export function pedidoE2e(
  defines: Record<string, string>,
  linha: { passo: string; estado: string; detalhe: string; run_id?: string },
): Pedido | null {
  const url = defines.SUPABASE_URL
  const chave = defines.SUPABASE_ANON_KEY
  if (!url || !chave) return null
  return {
    url: `${url}/rest/v1/e2e_log`,
    init: {
      method: 'POST',
      headers: { apikey: chave, Authorization: `Bearer ${chave}`, 'Content-Type': 'application/json', Prefer: 'return=minimal' },
      body: JSON.stringify({
        fluxo: 'bora-mods',
        passo: linha.passo,
        estado: linha.estado,
        detalhe: linha.detalhe.slice(0, 2000),
        device: 'pc-danilo',
        run_id: linha.run_id ?? 'bora-mods',
      }),
    },
  }
}

/** Pedido ao Telegram do Danilo. */
export function pedidoTelegram(token: string, chat: string, texto: string): Pedido {
  return {
    url: `https://api.telegram.org/bot${token}/sendMessage`,
    init: { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ chat_id: chat, text: texto }) },
  }
}

/** Um 200 com "ok":false também é falha (anti-falso-positivo). */
export function telegramEntrou(ok: boolean, corpo: string): boolean {
  return ok && /"ok"\s*:\s*true/.test(corpo)
}
