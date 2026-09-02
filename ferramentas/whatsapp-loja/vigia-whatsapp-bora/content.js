/* Vigia do WhatsApp da loja (Bora) v7 — a PORTA do PC. Corre dentro da sessao associada do
 * web.whatsapp.com. Le cada mensagem nova das conversas INDIVIDUAIS (grupos: nunca -- o portao e o
 * JID da mensagem, "@g.us"), inclui contactos GUARDADOS COM NOME (o v6 so lia titulos-numero),
 * apanha AUDIOS e IMAGENS (blob -> base64), entrega tudo ao cerebro (127.0.0.1:8790) como eventos
 * com o id do WhatsApp, e vem buscar as respostas a fila de saida, enviando com "a escrever..."
 * e uma espera proporcional. Se o Danilo responder a mao, avisa o cerebro (que cala 2 h).
 * v7  2026-09-02 — missao "de 'vou verificar' para agente que resolve".
 */
(function () {
  if (window.__vigiaBora) { console.log('[VigiaBora] ja ativa'); return; }
  window.__vigiaBora = true;

  const VERSION = 'v7-2026-09-02-agente';
  // Marcador no DOM: a versao e o carimbo da ultima varredura ficam em <html data-vigia-*>, legiveis por
  // qualquer ferramenta que veja a pagina -- a consola do browser nao se ve de fora.
  const marca = (k, v) => { try { document.documentElement.setAttribute('data-vigia-' + k, String(v)); } catch {} };
  marca('bora', VERSION);
  const ENVIO_DESLIGADO = false;        // MISSAO 02/09: 2a tranca; a 1a e o cerebro (ENVIO_DESLIGADO + whatsapp_settings)
  const OWN = '351937501673';
  const VARRER_MS = 6000;              // olha para a lista de 6 em 6 s
  const PENDENTES_MS = 4000;           // vai buscar respostas de 4 em 4 s
  const KEY_HANDLED = 'bora_vigia_handled_v7';
  const KEY_ENVIADAS = 'bora_vigia_enviadas_v7';
  const KEY_CENSO = 'bora_vigia_censo_v7e';   // v7e: leitura das mensagens pelo carimbo + icone de visto (build 02/09)
  // A consola do browser nao se ve de fora: cada linha vai tambem para o cerebro (/log), para um
  // erro de arranque da vigia nunca mais ficar invisivel (custou uma hora a 02/09).
  const logRemoto = (linha) => { try { chrome.runtime.sendMessage({ tipo: 'log', linha: String(linha).slice(0, 300), versao: VERSION }, () => { void chrome.runtime.lastError; }); } catch {} };
  const log = (...a) => { console.log('[VigiaBora]', ...a); logRemoto(a.map(x => (typeof x === 'string' ? x : JSON.stringify(x))).join(' ')); };
  window.addEventListener('error', (e) => logRemoto('ERRO JS: ' + (e.message || e)));
  window.addEventListener('unhandledrejection', (e) => logRemoto('PROMESSA REJEITADA: ' + (e.reason && e.reason.message || e.reason)));
  const espera = ms => new Promise(r => setTimeout(r, ms));
  const soDigitos = s => ((s || '').match(/\d/g) || []).join('');
  const ehNumero = t => /^\+?\d[\d\s]{6,}$/.test((t || '').trim());

  function setDe(key) { try { return new Set(JSON.parse(localStorage.getItem(key) || '[]')); } catch { return new Set(); } }
  function guardaSet(key, s, cap) { try { localStorage.setItem(key, JSON.stringify([...s].slice(-(cap || 1500)))); } catch {} }
  const handled = setDe(KEY_HANDLED);
  const enviadas = setDe(KEY_ENVIADAS);

  // --- cerebro (pelo service worker: sem CSP/CORS da pagina) --------------
  function bg(msg) {
    return new Promise((resolve, reject) => {
      try {
        chrome.runtime.sendMessage(msg, (resp) => {
          const err = chrome.runtime.lastError;
          if (err) return reject(new Error(err.message));
          if (resp && resp.erro) return reject(new Error(resp.erro));
          resolve(resp);
        });
      } catch (e) { reject(e); }
    });
  }

  // --- DOM ----------------------------------------------------------------
  function linhas() {
    const pane = document.querySelector('#pane-side');
    if (!pane) return [];
    let rows = [...pane.querySelectorAll('[role="row"]')];
    if (!rows.length) { const g = pane.querySelector('[role="grid"]'); if (g) rows = [...g.children]; }
    return rows;
  }
  const tituloDaLinha = row => { const s = row.querySelector('span[title]'); return s ? (s.getAttribute('title') || s.textContent || '').trim() : ''; };
  const temNaoLida = row => [...row.querySelectorAll('span[aria-label]')].some(s => /não lida|nao lida|unread/i.test(s.getAttribute('aria-label') || ''));
  function alvoDoComposer() {
    const c = document.querySelector('footer div[contenteditable="true"]');
    if (!c) return null;
    const m = (c.getAttribute('aria-label') || '').match(/para\s+(.*)$/i);
    return m ? m[1].trim() : null;
  }
  function tituloAberto() {
    const h = document.querySelector('#main header');
    if (!h) return '';
    const s = h.querySelector('span[title]') || h.querySelector('span[dir="auto"]');
    return s ? (s.getAttribute('title') || s.textContent || '').trim() : '';
  }
  // JID da conversa aberta pelo data-id das mensagens: "false_351937402120@c.us_ABC" / "@g.us" = grupo
  // NESTE BUILD DO WHATSAPP WEB (02/09/2026) o data-id e so um hexadecimal ("2A4FF2FF1922...") sem JID,
  // e as classes sao ofuscadas ("x1n2onr6"). O que e fiavel: o carimbo [hora, data] REMETENTE: nas
  // mensagens de texto, o icone de "visto" (check) que so existe nas mensagens de SAIDA, o destinatario
  // do composer para o NUMERO, e o cabecalho para saber se e GRUPO.
  function contextoAberto() {
    const h = document.querySelector('#main header');
    if (!h) return null;
    const titulo = tituloAberto();
    const linhas = (h.innerText || '').split('\n').map(s => s.trim()).filter(Boolean);
    const grupo = !!h.querySelector('[data-icon*="group"], [data-icon*="community"]')
      || linhas.slice(1).some(l => /(^|, )(você|you)(,|$)/i.test(l) || (l.split(',').length >= 3 && !/\d{3}\s?\d{3}\s?\d{3}/.test(l)));
    const alvo = alvoDoComposer();
    const numero = (alvo && ehNumero(alvo)) ? soDigitos(alvo) : (ehNumero(titulo) ? soDigitos(titulo) : '');
    return { titulo, grupo, numero, chave: numero || (titulo ? 'nome:' + titulo : '') };
  }
  // As mensagens so aparecem uns segundos depois de abrir a conversa: espera-se ate 6 s pelo composer
  // e por pelo menos uma mensagem, e so entao se le o contexto.
  async function esperarContexto(ms) {
    const fim = Date.now() + (ms || 6000);
    let c = null;
    while (Date.now() < fim) {
      c = contextoAberto();
      if (c && (c.numero || c.titulo) && document.querySelector('#main div[data-id], #main [data-pre-plain-text]')) return c;
      await espera(250);
    }
    return c;
  }
  const ehGrupo = c => !!(c && c.grupo);

  function mensagensAbertas() {
    const out = [];
    for (const m of document.querySelectorAll('#main div[data-id]')) {
      const id = m.getAttribute('data-id') || '';
      const pre = m.querySelector('[data-pre-plain-text]');
      const meta = pre ? (pre.getAttribute('data-pre-plain-text') || '') : '';
      const rem = (meta.match(/\]\s*(.*?):\s*$/) || [])[1] || '';
      // SAIDA: o icone de visto (check) so existe nas mensagens que a loja enviou; nas de texto o carimbo
      // tambem diz o remetente (a propria conta aparece como "," ou vazio em algumas versoes).
      const visto = !!m.querySelector('[data-icon="msg-check"],[data-icon="msg-dblcheck"],[data-icon="msg-time"],[aria-label*="Enviada"],[aria-label*="Entregue"],[aria-label*="Lida"]');
      const dir = (visto || (meta && (soDigitos(rem) === OWN || rem === ',' || rem === ''))) ? 'saida' : 'entrada';
      const texto = (m.querySelector('.copyable-text span.selectable-text, .selectable-text')?.innerText || pre?.innerText || '').trim();
      const audio = !!m.querySelector('[data-icon="audio-play"],[data-icon="ptt-status"],[data-icon="audio-download"],audio');
      const img = !!m.querySelector('img[src^="blob:"]') && !audio;
      const tipo = audio ? 'audio' : (img ? 'imagem' : 'texto');
      const th = meta.match(/^\[(\d{1,2}:\d{2}),\s*(\d{2})\/(\d{2})\/(\d{4})\]/);
      const ts = th ? `${th[4]}-${th[3]}-${th[2]}T${th[1].padStart(5, '0')}:00` : null;
      if (!texto && !audio && !img) continue;     // avisos de sistema, datas, etc.
      out.push({ id, dir, texto, tipo, ts, el: m });
    }
    return out;
  }

  async function blobParaBase64(url) {
    const r = await fetch(url);
    const b = await r.blob();
    const b64 = await new Promise((res, rej) => { const fr = new FileReader(); fr.onload = () => res(fr.result.split(',')[1]); fr.onerror = rej; fr.readAsDataURL(b); });
    return { b64, mime: b.type || 'application/octet-stream', bytes: b.size };
  }
  async function apanharAudio(el) {
    // o <audio> so aparece depois de carregar/tocar: clica em play, espera o blob, pausa.
    let a = el.querySelector('audio[src^="blob:"]');
    if (!a) {
      const btn = el.querySelector('[data-icon="audio-play"]')?.closest('button,[role="button"]') || el.querySelector('[data-icon="audio-download"]')?.closest('button,[role="button"]');
      if (btn) { btn.click(); }
      for (let i = 0; i < 12 && !a; i++) { await espera(500); a = el.querySelector('audio[src^="blob:"]') || document.querySelector('audio[src^="blob:"]'); }
      if (a) { try { a.pause(); a.currentTime = 0; } catch {} }
      const pausa = el.querySelector('[data-icon="audio-pause"]')?.closest('button,[role="button"]'); if (pausa) pausa.click();
    }
    if (!a) return null;
    try { return await blobParaBase64(a.src); } catch (e) { log('audio blob falhou', e.message); return null; }
  }
  async function apanharImagem(el) {
    const img = el.querySelector('img[src^="blob:"]');
    if (!img) return null;
    try { return await blobParaBase64(img.src); } catch (e) { log('imagem blob falhou', e.message); return null; }
  }

  async function abrir(row) {
    const alvoEl = row.querySelector('span[title]') || row;
    alvoEl.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
    alvoEl.click();
    await espera(1300);
  }
  async function abrirPorNumero(numero) {
    const row = linhas().find(r => soDigitos(tituloDaLinha(r)) === numero);
    if (row) { await abrir(row); const c = await esperarContexto(4000); if (c && c.numero === numero) return true; }
    // contacto guardado com nome ou fora do ecra: procura pela caixa de pesquisa
    const busca = document.querySelector('#side div[contenteditable="true"]');
    if (!busca) return false;
    busca.focus();
    document.execCommand('selectAll', false, null);
    document.execCommand('insertText', false, '+' + numero.replace(/^(\d{3})(\d{3})(\d{3})(\d{3})$/, '$1 $2 $3 $4'));
    await espera(1500);
    const cand = linhas()[0];
    if (cand) { await abrir(cand); }
    busca.focus(); document.execCommand('selectAll', false, null); document.execCommand('delete', false, null);
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
    await espera(400);
    const c = await esperarContexto(4000);
    return !!(c && c.numero === numero);
  }

  // --- enviar (so o que vem da fila do cerebro) -----------------------------
  function botaoEnviar() {
    return document.querySelector('footer button[aria-label="Enviar"]')
        || document.querySelector('footer [data-icon="wds-ic-send-filled"]')?.closest('button')
        || document.querySelector('footer [data-icon="send"]')?.closest('button') || null;
  }
  async function enviar(texto, numeroEsperado) {
    if (ENVIO_DESLIGADO) { log('ENVIO DESLIGADO (missao 02/09): NAO envio para', numeroEsperado); return false; }
    const cAberta = contextoAberto();
    if (!cAberta || cAberta.numero !== numeroEsperado || cAberta.grupo) { log('ABORTAR: conversa aberta nao e', numeroEsperado); return false; }
    const c = document.querySelector('footer div[contenteditable="true"]');
    if (!c) return false;
    c.focus();
    try { const r = document.createRange(); r.selectNodeContents(c); const s = getSelection(); s.removeAllRanges(); s.addRange(r); } catch {}
    document.execCommand('insertText', false, texto);   // com texto no composer o WhatsApp mostra "a escrever..." ao outro lado
    await espera(300);
    if (!(c.innerText || '').trim()) {
      const dt = new DataTransfer(); dt.setData('text/plain', texto);
      c.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
      await espera(200);
    }
    await espera(Math.min(4000, 1000 + texto.length * 25));   // espera proporcional ao tamanho (1-4 s)
    const btn = botaoEnviar();
    if (btn) btn.click();
    else c.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true }));
    await espera(800);
    const saiu = !(c.innerText || '').trim();
    if (saiu) { const ult = mensagensAbertas().filter(m => m.dir === 'saida').slice(-1)[0]; if (ult) { enviadas.add(ult.id); guardaSet(KEY_ENVIADAS, enviadas); } }
    return saiu;
  }

  // --- varredura: mensagens novas -> eventos ---------------------------------
  let ocupada = false;
  async function varrer() {
    if (ocupada) return; ocupada = true;
    try {
      const rows = linhas();
      const candidatas = rows.filter(r => temNaoLida(r) && !/^(WhatsApp|Meta AI)$/i.test(tituloDaLinha(r)));
      if (candidatas.length) log('varredura: linhas=' + rows.length, 'nao lidas=' + candidatas.length);
      for (const row of candidatas) {
        const titulo = tituloDaLinha(row);
        await abrir(row);
        const ctx = await esperarContexto(6000);
        if (!ctx) { log('sem contexto, salto', titulo); continue; }
        if (ehGrupo(ctx)) { log('GRUPO, nunca:', titulo); continue; }
        const numero = ctx.numero;
        if (!numero) { log('sem numero (contacto guardado com nome?), salto por agora', titulo); continue; }
        if (numero === OWN) continue;
        const nomeGuardado = ehNumero(titulo) ? null : titulo;
        const msgs = mensagensAbertas();
        const novas = msgs.filter(m => !handled.has(m.id)).slice(-8);   // no maximo as 8 ultimas (baseline em cima do resto)
        for (const m of msgs) handled.add(m.id);
        guardaSet(KEY_HANDLED, handled, 3000);
        for (const m of novas) {
          if (m.dir === 'saida') {
            if (!enviadas.has(m.id) && m.texto) {           // saida que NAO foi nossa = o Danilo a mao
              try { await bg({ tipo: 'evento', evento: { numero, msg_id: m.id, dir: 'saida-danilo', tipo: 'texto', texto: m.texto, ts: m.ts } }); } catch {}
            }
            continue;
          }
          const ev = { numero, msg_id: m.id, dir: 'entrada', tipo: m.tipo, texto: m.texto, ts: m.ts, nome_guardado: nomeGuardado, grupo: false };
          if (m.tipo === 'audio') { const a = await apanharAudio(m.el); if (a) { ev.audio_b64 = a.b64; ev.mime = a.mime; } }
          if (m.tipo === 'imagem') { const im = await apanharImagem(m.el); if (im) { ev.imagem_b64 = im.b64; ev.mime = im.mime; } }
          try { const r = await bg({ tipo: 'evento', evento: ev }); log('evento', numero, m.tipo, '->', r && r.acao); }
          catch (e) { log('cerebro offline?', e.message); handled.delete(m.id); }
        }
        await espera(500);
      }
    } catch (e) { log('erro na varredura', e); marca('erro', (e && e.message) || e); }
    finally { ocupada = false; marca('varrida', new Date().toISOString()); }
  }

  // --- fila de saida ---------------------------------------------------------
  let ocupadoEnvio = false;
  async function despachar() {
    if (ocupadoEnvio || ENVIO_DESLIGADO) return; ocupadoEnvio = true;
    try {
      const r = await bg({ tipo: 'pendentes' });
      for (const item of (r && r.mensagens) || []) {
        const numero = soDigitos(item.numero);
        const ok = (await abrirPorNumero(numero)) && (await enviar(item.texto, numero));
        try { await bg({ tipo: 'enviado', dados: { id: item.id, numero, texto: item.texto, ok, erro: ok ? null : 'nao consegui abrir/enviar' } }); } catch {}
        log('enviado', numero, ok, item.motivo);
        await espera(1500);
      }
    } catch (e) { log('despachar falhou', e.message); }
    finally { ocupadoEnvio = false; }
  }

  // --- censo: fichas a partir do historico, sem responder --------------------
  async function censo() {
    if (localStorage.getItem(KEY_CENSO)) return;
    log('CENSO: a percorrer todas as conversas individuais (sem responder)');
    // 1) esperar pela lista: 8 s depois do arranque o WhatsApp Web ainda esta a carregar e
    //    #pane-side nao existe -- a 1a versao saia aqui em silencio, uma vez so (02/09).
    let pane = null;
    for (let i = 0; i < 90 && !pane; i++) { pane = document.querySelector('#pane-side'); if (!pane) await espera(1000); }
    if (!pane) { log('censo: lista nao apareceu em 90 s; tento no proximo arranque'); return; }
    // 2) a lista e VIRTUALIZADA: so as linhas visiveis existem no DOM. Processa-se cada conversa
    //    a medida que o scroll a mostra, em vez de recolher titulos e voltar ao topo.
    const feitos = new Set();
    let n = 0;
    pane.scrollTop = 0;
    for (let passo = 0; passo < 80; passo++) {
      const rows = linhas().filter(r => { const t = tituloDaLinha(r); return t && !feitos.has(t) && !/^(WhatsApp|Meta AI)$/i.test(t); });
      for (const row of rows) {
        const t = tituloDaLinha(row); feitos.add(t);
        try {
          await abrir(row);
          const ctx = await esperarContexto(6000); if (!ctx || ehGrupo(ctx)) { log('censo: grupo/sem contexto, salto', t); continue; }
          const numero = ctx.numero; if (!numero) { log('censo: sem numero, salto', t); continue; }
          if (numero === OWN) continue;
          const scroller = document.querySelector('#main [data-testid="conversation-panel-messages"]') || document.querySelector('#main .copyable-area') || document.querySelector('#main');
          for (let i = 0; i < 4; i++) { if (scroller) scroller.scrollTop = 0; await espera(500); }
          const msgs = mensagensAbertas().map(m => ({ id: m.id, dir: m.dir, texto: m.texto, tipo: m.tipo, ts: m.ts }));
          for (const m of msgs) handled.add(m.id);
          const r = await bg({ tipo: 'censo', dados: { numero, nome_guardado: ehNumero(t) ? null : t, grupo: false, mensagens: msgs } });
          n++; log('censo', numero, msgs.length, r && r.papel, 'entradas=' + msgs.filter(m => m.dir === 'entrada').length, 'saidas=' + msgs.filter(m => m.dir === 'saida').length);
        } catch (e) { log('censo falhou', t, e && e.message); }
        await espera(400);
      }
      const fim = pane.scrollTop + pane.clientHeight >= pane.scrollHeight - 2;
      pane.scrollTop += pane.clientHeight * 0.7; await espera(500);
      if (fim && !rows.length) break;
    }
    guardaSet(KEY_HANDLED, handled, 3000);
    // So se marca como feito se o cerebro recebeu pelo menos uma conversa: a 02/09 o censo marcou-se
    // "feito" com o worker velho a rejeitar tudo, e nunca mais corria.
    if (n > 0) localStorage.setItem(KEY_CENSO, new Date().toISOString());
    log('CENSO terminado:', n, 'conversas', n > 0 ? '' : '(nenhuma entregue -- volta a tentar no proximo arranque)');
  }

  // --- arranque -------------------------------------------------------------
  (async () => {
    let s = null;
    try { s = await bg({ tipo: 'saude' }); log('cerebro:', JSON.stringify(s)); }
    catch (e) { log('AVISO: cerebro local nao respondeu (', e.message, ')'); }
    log('VERSAO ' + VERSION, ENVIO_DESLIGADO ? '(ENVIO DESLIGADO)' : '');
    // baseline: tudo o que esta visivel agora conta como visto; so o que chegar a seguir e novo
    if (!localStorage.getItem(KEY_HANDLED)) { log('1a vez: baseline, nao respondo ao historico'); }
    setInterval(varrer, VARRER_MS);
    setInterval(despachar, PENDENTES_MS);
    if (s && s.pedir_censo) { setTimeout(censo, 8000); }
    const alvo = document.querySelector('#pane-side');
    if (alvo) new MutationObserver(() => { clearTimeout(window.__vigiaObs); window.__vigiaObs = setTimeout(varrer, 1200); }).observe(alvo, { childList: true, subtree: true, characterData: true });
  })();
  window.__vigiaBoraVarrer = varrer;
  window.__vigiaBoraCenso = censo;
})();
