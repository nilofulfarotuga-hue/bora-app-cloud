/* Service worker da Vigia Bora v7: faz as chamadas ao cerebro local (127.0.0.1:8790).
 * Corre com host_permissions -> sem CSP da pagina e sem CORS. O content.js pede por mensagem. */
const SERVIDOR = 'http://127.0.0.1:8790';

function comTimeout(ms) {
  const ac = new AbortController();
  const t = setTimeout(() => ac.abort(), ms);
  return { signal: ac.signal, fim: () => clearTimeout(t) };
}
async function get(caminho, ms) {
  const to = comTimeout(ms || 8000);
  try { const r = await fetch(SERVIDOR + caminho, { signal: to.signal }); return r.json(); }
  finally { to.fim(); }
}
async function post(caminho, corpo, ms) {
  const to = comTimeout(ms || 30000);
  try {
    const r = await fetch(SERVIDOR + caminho, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(corpo), signal: to.signal });
    return r.json();
  } finally { to.fim(); }
}

chrome.runtime.onMessage.addListener((req, _sender, sendResponse) => {
  (async () => {
    try {
      if (!req || !req.tipo) return sendResponse({ erro: 'pedido desconhecido' });
      if (req.tipo === 'saude') return sendResponse(await get('/saude', 6000));
      if (req.tipo === 'pendentes') return sendResponse(await get('/pendentes', 6000));
      if (req.tipo === 'evento') return sendResponse(await post('/evento', req.evento, 60000));
      if (req.tipo === 'enviado') return sendResponse(await post('/enviado', req.dados, 8000));
      if (req.tipo === 'censo') return sendResponse(await post('/censo', req.dados, 60000));
      if (req.tipo === 'log') return sendResponse(await post('/log', { linha: req.linha, versao: req.versao }, 5000));
      if (req.tipo === 'responder') return sendResponse(await post('/responder', { numero: req.numero, msg: req.msg, grupo: false }, 50000));
      if (req.tipo === 'lembretes') return sendResponse(await get('/lembretes', 8000));
      sendResponse({ erro: 'pedido desconhecido: ' + req.tipo });
    } catch (e) {
      sendResponse({ erro: e.message || String(e) });
    }
  })();
  return true;
});
