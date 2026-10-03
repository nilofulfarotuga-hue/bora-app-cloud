/* Vigia do WhatsApp da loja (Bora) v9 — a PORTA do PC. Corre dentro da sessao associada do
 * web.whatsapp.com. Le cada mensagem nova das conversas INDIVIDUAIS (grupos: nunca), inclui contactos
 * GUARDADOS COM NOME (numero lido no painel de info, uma vez, e guardado), apanha AUDIOS e IMAGENS
 * (blob -> base64), entrega tudo ao cerebro (127.0.0.1:8790) como eventos com o id do WhatsApp, e vem
 * buscar as respostas a fila de saida, enviando com "a escrever..." e uma espera proporcional.
 * v9  2026-09-02 (noite) — FALHA F: a varredura e o despacho corriam ao mesmo tempo; a varredura abriu
 *     outra conversa no segundo em que o despacho escrevia, e "enviado" era so "o composer ficou vazio".
 *     Agora: UMA tranca para varrer/despachar/comandos; "enviado" so com a BOLHA visivel nesta conversa
 *     (texto igual, visto), reenvio ate 3 vezes sem duplicar, e comandos remotos do cerebro (ler uma
 *     conversa) para auditar sem abrir uma segunda sessao do WhatsApp Web.
 */
(function () {
  if (window.__vigiaBora) { console.log('[VigiaBora] ja ativa'); return; }
  window.__vigiaBora = true;

  const VERSION = 'v9c-2026-09-02-entrega-confirmada';
  const ARRANQUE = Date.now();          // so e "nova" a mensagem que o WhatsApp diz que esta por ler, ou que chegou depois do arranque
  const marca = (k, v) => { try { document.documentElement.setAttribute('data-vigia-' + k, String(v)); } catch {} };
  marca('bora', VERSION);
  const ENVIO_DESLIGADO = false;        // 2a tranca; a 1a e o cerebro (ENVIO_DESLIGADO + whatsapp_settings)
  const OWN = '351937501673';
  const VARRER_MS = 3000;
  const PENDENTES_MS = 2000;
  const COMANDOS_MS = 5000;
  const KEY_HANDLED = 'bora_vigia_handled_v7';
  const KEY_ENVIADAS = 'bora_vigia_enviadas_v7';
  const KEY_CENSO = 'bora_vigia_censo_v7e';
  const KEY_NUMEROS = 'bora_vigia_numeros_v9b';  // titulo guardado -> numero (lido no painel de info; v9b: nunca de um grupo)
  const logRemoto = (linha) => { try { chrome.runtime.sendMessage({ tipo: 'log', linha: String(linha).slice(0, 300), versao: VERSION }, () => { void chrome.runtime.lastError; }); } catch {} };
  const log = (...a) => { console.log('[VigiaBora]', ...a); logRemoto(a.map(x => (typeof x === 'string' ? x : JSON.stringify(x))).join(' ')); };
  window.addEventListener('error', (e) => logRemoto('ERRO JS: ' + (e.message || e)));
  window.addEventListener('unhandledrejection', (e) => logRemoto('PROMESSA REJEITADA: ' + (e.reason && e.reason.message || e.reason)));
  const espera = ms => new Promise(r => setTimeout(r, ms));
  const soDigitos = s => ((s || '').match(/\d/g) || []).join('');
  const ehNumero = t => /^\+?\d[\d\s]{6,}$/.test((t || '').trim());
  const norm = t => (t || '').replace(/\s+/g, ' ').trim().toLowerCase();

  function setDe(key) { try { return new Set(JSON.parse(localStorage.getItem(key) || '[]')); } catch { return new Set(); } }
  function guardaSet(key, s, cap) { try { localStorage.setItem(key, JSON.stringify([...s].slice(-(cap || 1500)))); } catch {} }
  function mapaDe(key) { try { return new Map(Object.entries(JSON.parse(localStorage.getItem(key) || '{}'))); } catch { return new Map(); } }
  function guardaMapa(key, m) { try { localStorage.setItem(key, JSON.stringify(Object.fromEntries(m))); } catch {} }
  const handled = setDe(KEY_HANDLED);
  const enviadas = setDe(KEY_ENVIADAS);
  const numerosGuardados = mapaDe(KEY_NUMEROS);

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
  const nNaoLidas = row => {
    for (const s of row.querySelectorAll('span[aria-label]')) {
      const a = s.getAttribute('aria-label') || '';
      if (/não lida|nao lida|unread/i.test(a)) { const m = a.match(/(\d+)/); return m ? parseInt(m[1], 10) : 1; }
    }
    return 0;
  };
  // numa linha de GRUPO a pre-visualizacao vem "Nome: texto" (quem falou); num contacto individual nao
  const linhaPareceGrupo = row => {
    const t = (row.innerText || '').split('\n').map(s => s.trim()).filter(Boolean);
    return t.slice(1).some(l => /^[^:\n]{2,40}:\s\S/.test(l) && !/^\d{1,2}:\d{2}/.test(l));
  };
  const tsMs = ts => { if (!ts) return null; const d = new Date(ts); return isNaN(d.getTime()) ? null : d.getTime(); };
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
  // NESTE BUILD (02/09/2026) o data-id e so um hexadecimal sem JID e as classes sao ofuscadas. O que e
  // fiavel: o carimbo [hora, data] REMETENTE: das mensagens, o icone de visto nas saidas, o destinatario
  // do composer para o NUMERO, e o cabecalho (subtitulo "info do grupo" / lista de participantes) para GRUPO.
  function contextoAberto() {
    const h = document.querySelector('#main header');
    if (!h) return null;
    const titulo = tituloAberto();
    const ls = (h.innerText || '').split('\n').map(s => s.trim()).filter(Boolean);
    const sub = ls.slice(1).join(' | ');
    const grupo = !!h.querySelector('[data-icon*="group"], [data-icon*="community"]')
      || /info do grupo|dados do grupo|group info|participantes|participants|membros|members|comunidade|community/i.test(sub)
      || ls.slice(1).some(l => /(^|, )(você|you)(,|$)/i.test(l) || (l.split(',').length >= 3 && !/\d{3}\s?\d{3}\s?\d{3}/.test(l)));
    const alvo = alvoDoComposer();
    let numero = (alvo && ehNumero(alvo)) ? soDigitos(alvo) : (ehNumero(titulo) ? soDigitos(titulo) : '');
    if (!numero && !grupo && titulo && numerosGuardados.has(titulo)) numero = numerosGuardados.get(titulo);
    return { titulo, grupo, numero, chave: numero || (titulo ? 'nome:' + titulo : '') };
  }
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

  // Contacto GUARDADO com nome: o composer nao diz o numero. Abre-se o painel de info (clique no cabecalho),
  // le-se o "+351 ..." e fecha-se com Escape. Uma vez por titulo; fica guardado.
  async function numeroPeloPainel(titulo) {
    if (!titulo || numerosGuardados.has(titulo)) return numerosGuardados.get(titulo) || '';
    const h = document.querySelector('#main header');
    if (!h) return '';
    const antes = (document.body.innerText || '');
    (h.querySelector('span[title]') || h).click();
    await espera(900);
    let numero = ''; let ehGrupoPainel = false;
    for (let i = 0; i < 6 && !numero && !ehGrupoPainel; i++) {
      const txt = (document.body.innerText || '');
      // v9b: o painel de um GRUPO tambem tem numeros (os participantes) -- a 23:16 apanhou o numero de um
      // participante de "Brasileiros na Guarda". Se o painel fala de participantes/membros/sair do grupo, e grupo: zero numeros.
      if (/\d+\s+(participantes|members|membros)|sair do grupo|exit group|leave group|info do grupo|group info|descri[çc][ãa]o do grupo|criado por|created by/i.test(txt)) { ehGrupoPainel = true; break; }
      const m = txt.match(/\+\s?\d{2,3}[\s\d]{8,14}/g) || [];
      const cands = m.map(soDigitos).filter(d => d.length >= 11 && d !== OWN);
      if (cands.length === 1) numero = cands[0];          // mais do que um numero no painel = nao e um contacto
      else if (cands.length > 1) { ehGrupoPainel = true; break; }
      if (!numero) await espera(400);
    }
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
    const btnFechar = document.querySelector('[data-icon="x"], [aria-label="Fechar"], [aria-label="Close"]');
    if (btnFechar) { try { btnFechar.closest('button,[role="button"]')?.click(); } catch {} }
    await espera(500);
    if (ehGrupoPainel) { saltadas.set(titulo, Date.now()); log('painel diz GRUPO, nunca:', titulo); return ''; }
    if (numero) { numerosGuardados.set(titulo, numero); guardaMapa(KEY_NUMEROS, numerosGuardados); log('numero lido no painel para', titulo, '->', numero.slice(0, 5) + '***' + numero.slice(-3)); }
    else log('painel de info sem numero para', titulo);
    return numero;
  }

  function mensagensAbertas(ctx) {
    const out = [];
    for (const m of document.querySelectorAll('#main div[data-id]')) {
      const id = m.getAttribute('data-id') || '';
      const pre = m.querySelector('[data-pre-plain-text]');
      const meta = pre ? (pre.getAttribute('data-pre-plain-text') || '') : '';
      const rem = (meta.match(/\]\s*(.*?):\s*$/) || [])[1] || '';
      const icone = m.querySelector('[data-icon="msg-check"],[data-icon="msg-dblcheck"],[data-icon="msg-time"]');
      const visto = !!icone || !!m.querySelector('[aria-label*="Enviada"],[aria-label*="Entregue"],[aria-label*="Lida"],[aria-label*="Sent"],[aria-label*="Delivered"],[aria-label*="Read"]');
      const estado = icone ? ({ 'msg-time': 'relogio', 'msg-check': 'visto', 'msg-dblcheck': 'entregue' }[icone.getAttribute('data-icon')] || 'visto') : (visto ? 'visto' : null);
      const remD = soDigitos(rem);
      const proprio = visto || (!!meta && (remD === OWN || rem === ',' || rem === ''));
      const doContacto = !!(meta && ctx && ((ctx.numero && remD === ctx.numero) || (ctx.titulo && rem === ctx.titulo)));
      const incerta = !proprio && !!meta && !!ctx && !doContacto;
      const dir = (proprio || incerta) ? 'saida' : 'entrada';
      const texto = (m.querySelector('.copyable-text span.selectable-text, .selectable-text')?.innerText || pre?.innerText || '').trim();
      const audio = !!m.querySelector('[data-icon="audio-play"],[data-icon="ptt-status"],[data-icon="audio-download"],audio');
      const img = !!m.querySelector('img[src^="blob:"]') && !audio;
      const tipo = audio ? 'audio' : (img ? 'imagem' : 'texto');
      const th = meta.match(/^\[(\d{1,2}:\d{2}),\s*(\d{2})\/(\d{2})\/(\d{4})\]/);
      const ts = th ? `${th[4]}-${th[3]}-${th[2]}T${th[1].padStart(5, '0')}:00` : null;
      if (!texto && !audio && !img) continue;
      out.push({ id, dir, incerta, rem, texto, tipo, ts, estado, el: m });
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
  async function abrirPorTitulo(titulo) {
    const row = linhas().find(r => tituloDaLinha(r) === titulo);
    if (row) { await abrir(row); return await esperarContexto(4000); }
    const busca = document.querySelector('#side div[contenteditable="true"]');
    if (!busca) return null;
    busca.focus();
    document.execCommand('selectAll', false, null);
    document.execCommand('insertText', false, titulo);
    await espera(1500);
    const cand = linhas().find(r => tituloDaLinha(r) === titulo) || linhas()[0];
    if (cand) { await abrir(cand); }
    busca.focus(); document.execCommand('selectAll', false, null); document.execCommand('delete', false, null);
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
    await espera(400);
    return await esperarContexto(4000);
  }
  async function abrirPorNumero(numero) {
    const row = linhas().find(r => soDigitos(tituloDaLinha(r)) === numero || numerosGuardados.get(tituloDaLinha(r)) === numero);
    if (row) { await abrir(row); const c = await esperarContexto(4000); if (c && c.numero === numero) return true; }
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
  const mesmoTexto = (bolha, texto) => { const a = norm(bolha), b = norm(texto); return a === b || (b.length > 60 && a.startsWith(b.slice(0, 60))); };
  function bolhaDoTexto(ctx, texto, antes) {
    return mensagensAbertas(ctx).filter(m => m.dir === 'saida' && !antes.has(m.id) && mesmoTexto(m.texto, texto)).slice(-1)[0] || null;
  }
  // Devolve {ok, msg_id, estado, erro}. ok SO quando a bolha com este texto apareceu NESTA conversa.
  async function enviar(texto, numeroEsperado, antesOriginal) {
    if (ENVIO_DESLIGADO) { log('ENVIO DESLIGADO: NAO envio para', numeroEsperado); return { ok: false, erro: 'envio desligado' }; }
    const cAberta = contextoAberto();
    if (!cAberta || cAberta.numero !== numeroEsperado || cAberta.grupo) { log('ABORTAR: conversa aberta nao e', numeroEsperado); return { ok: false, erro: 'conversa aberta nao e a certa' }; }
    // a bolha de uma tentativa anterior apareceu tarde? entao ja esta enviada -- nunca duplicar
    const tardia = antesOriginal ? bolhaDoTexto(cAberta, texto, antesOriginal) : null;
    if (tardia) { enviadas.add(tardia.id); guardaSet(KEY_ENVIADAS, enviadas); return { ok: true, msg_id: tardia.id, estado: tardia.estado || 'visto', tardia: true }; }
    const antes = new Set(mensagensAbertas(cAberta).filter(m => m.dir === 'saida').map(m => m.id));
    const c = document.querySelector('footer div[contenteditable="true"]');
    if (!c) return { ok: false, erro: 'sem composer' };
    c.focus();
    try { const r = document.createRange(); r.selectNodeContents(c); const s = getSelection(); s.removeAllRanges(); s.addRange(r); } catch {}
    document.execCommand('insertText', false, texto);
    await espera(300);
    if (!(c.innerText || '').trim()) {
      const dt = new DataTransfer(); dt.setData('text/plain', texto);
      c.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
      await espera(200);
    }
    await espera(Math.min(2500, 600 + texto.length * 15));
    // a conversa ainda e a certa? (a varredura ja nao corre ao mesmo tempo, mas o WhatsApp pode mudar sozinho)
    const cAntesDeEnviar = contextoAberto();
    if (!cAntesDeEnviar || cAntesDeEnviar.numero !== numeroEsperado || cAntesDeEnviar.grupo) {
      try { document.execCommand('selectAll', false, null); document.execCommand('delete', false, null); } catch {}
      log('ABORTAR antes do clique: a conversa mudou para', cAntesDeEnviar && cAntesDeEnviar.titulo);
      return { ok: false, erro: 'conversa mudou antes de enviar' };
    }
    const btn = botaoEnviar();
    if (btn) btn.click();
    else c.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true }));
    // CONFIRMACAO: a bolha com este texto tem de aparecer nesta conversa (ate 5 s); se ficar de relogio
    // (sem rede), espera-se mais 15 s pelo visto.
    let bolha = null; const t0 = Date.now();
    while (Date.now() - t0 < 5000 && !bolha) {
      await espera(400);
      const agora = contextoAberto();
      if (!agora || agora.numero !== numeroEsperado) return { ok: false, erro: 'conversa mudou depois do clique' };
      bolha = bolhaDoTexto(agora, texto, antes);
    }
    if (!bolha) return { ok: false, erro: 'sem bolha em 5 s', composer_vazio: !(c.innerText || '').trim() };
    while (bolha.estado === 'relogio' && Date.now() - t0 < 20000) {
      await espera(1000);
      const agora = contextoAberto(); if (!agora || agora.numero !== numeroEsperado) break;
      bolha = bolhaDoTexto(agora, texto, antes) || bolha;
    }
    enviadas.add(bolha.id); guardaSet(KEY_ENVIADAS, enviadas);
    return { ok: bolha.estado !== 'relogio', msg_id: bolha.id, estado: bolha.estado || 'visto', erro: bolha.estado === 'relogio' ? 'ficou de relogio 20 s' : null };
  }

  // --- tranca unica ----------------------------------------------------------
  // v9: varredura, despacho e comandos partilham UMA tranca. A 02/09 21:08 a varredura abriu um grupo no
  // segundo em que o despacho escrevia a resposta -- a resposta perdeu-se e o cerebro achou que saiu.
  let ocupada = false;
  const saltadas = new Map();   // titulo -> ts: linhas sem numero/grupo nao se reabrem durante 30 min

  // --- varredura: mensagens novas -> eventos ---------------------------------
  async function varrer() {
    if (ocupada) return; ocupada = true;
    try {
      const rows = linhas();
      const candidatas = rows.filter(r => temNaoLida(r) && !/^(WhatsApp|Meta AI)$/i.test(tituloDaLinha(r)));
      for (const row of candidatas) {
        const titulo = tituloDaLinha(row);
        const salto = saltadas.get(titulo);
        if (salto && Date.now() - salto < 30 * 60 * 1000) continue;
        if (linhaPareceGrupo(row)) { log('GRUPO (pela linha), nunca:', titulo); saltadas.set(titulo, Date.now()); continue; }
        const naoLidas = nNaoLidas(row);
        await abrir(row);
        let ctx = await esperarContexto(6000);
        if (!ctx) { log('sem contexto, salto', titulo); saltadas.set(titulo, Date.now()); continue; }
        if (ehGrupo(ctx)) { log('GRUPO, nunca:', titulo); saltadas.set(titulo, Date.now()); continue; }
        if (!ctx.numero) {
          const n = await numeroPeloPainel(titulo);
          ctx = contextoAberto() || ctx;
          if (!n || !ctx.numero) { log('sem numero (grupo ou contacto sem numero legivel), salto 30 min', titulo); saltadas.set(titulo, Date.now()); continue; }
        }
        const numero = ctx.numero;
        if (numero === OWN) continue;
        const nomeGuardado = ehNumero(titulo) ? null : titulo;
        const msgs = mensagensAbertas(ctx);
        const porVer = msgs.filter(m => !handled.has(m.id));
        const limite = ARRANQUE - 15 * 60 * 1000;
        const recente = m => { const t = tsMs(m.ts); return t === null || t >= limite; };
        let entradas = porVer.filter(m => m.dir === 'entrada');
        entradas = (naoLidas > 0 ? entradas.slice(-naoLidas) : entradas.filter(recente)).slice(-3);
        const saidasDanilo = porVer.filter(m => m.dir === 'saida' && !m.incerta && !enviadas.has(m.id) && m.texto && recente(m)).slice(-3);
        const historico = porVer.length - entradas.length - saidasDanilo.length;
        if (historico > 0) log('baseline:', historico, 'mensagens por ver ficam como historico (badge=' + naoLidas + ')', titulo);
        for (const m of porVer.slice(-6)) log('msg', m.dir + (m.incerta ? '?' : ''), 'rem=' + JSON.stringify(m.rem), m.ts, m.estado || '', JSON.stringify((m.texto || '').slice(0, 40)));
        for (const m of msgs) handled.add(m.id);
        guardaSet(KEY_HANDLED, handled, 3000);
        for (const m of saidasDanilo) {
          try { await bg({ tipo: 'evento', evento: { numero, msg_id: m.id, dir: 'saida-danilo', tipo: 'texto', texto: m.texto, ts: m.ts } }); } catch {}
        }
        for (const m of entradas) {
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
  async function despachar() {
    if (ocupada || ENVIO_DESLIGADO) return; ocupada = true;
    try {
      const r = await bg({ tipo: 'pendentes' });
      for (const item of (r && r.mensagens) || []) {
        const numero = soDigitos(item.numero);
        let res = { ok: false, erro: 'nao tentado' }; let antesOriginal = null; let tent = 0;
        for (tent = 1; tent <= 3 && !res.ok; tent++) {
          const aberto = await abrirPorNumero(numero);
          if (!aberto) { res = { ok: false, erro: 'nao consegui abrir a conversa' }; await espera(1500); continue; }
          if (!antesOriginal) antesOriginal = new Set(mensagensAbertas(contextoAberto()).filter(m => m.dir === 'saida').map(m => m.id));
          res = await enviar(item.texto, numero, tent > 1 ? antesOriginal : null);
          if (!res.ok) { log('sem bolha, tentativa', tent, JSON.stringify(res)); await espera(1500); }
        }
        const dados = { id: item.id, numero, texto: item.texto, ok: !!res.ok, msg_id: res.msg_id || null, estado: res.estado || null, tentativas: Math.min(tent - 1, 3), erro: res.ok ? null : (res.erro || 'sem bolha') };
        try { await bg({ tipo: 'enviado', dados }); } catch {}
        log('enviado', numero, res.ok, res.estado || res.erro, 'tent=' + dados.tentativas, item.motivo);
        await espera(1500);
      }
    } catch (e) { log('despachar falhou', e.message); }
    finally { ocupada = false; }
  }

  // --- comandos remotos do cerebro (auditoria sem 2a sessao do WhatsApp Web) ---
  async function comandos() {
    if (ocupada || !document.querySelector('#pane-side')) return;   // so com a lista carregada (a 23:19 pediu-os 7 s apos o arranque e "nao abriu")
    ocupada = true;
    try {
      const r = await bg({ tipo: 'comandos' });
      for (const cmd of (r && r.comandos) || []) {
        let resultado = { id: cmd.id, ok: false };
        try {
          if (cmd.tipo === 'ler_conversa') {
            const ctx = cmd.numero ? ((await abrirPorNumero(soDigitos(cmd.numero))) ? contextoAberto() : null) : await abrirPorTitulo(cmd.titulo);
            if (!ctx) resultado.erro = 'nao abriu';
            else {
              await espera(2000);                        // as bolhas entram uns segundos depois do cabecalho
              const msgs = mensagensAbertas(ctx).slice(-(cmd.n || 8)).map(m => ({ id: m.id, dir: m.dir, incerta: m.incerta, rem: m.rem, texto: (m.texto || '').slice(0, 300), tipo: m.tipo, ts: m.ts, estado: m.estado }));
              resultado = { id: cmd.id, ok: true, contexto: { titulo: ctx.titulo, grupo: ctx.grupo, numero: ctx.numero }, mensagens: msgs };
            }
          } else if (cmd.tipo === 'estado') {
            const rows = linhas();
            resultado = { id: cmd.id, ok: true, versao: VERSION, linhas: rows.length, nao_lidas: rows.filter(temNaoLida).map(tituloDaLinha), aberta: contextoAberto(), saltadas: [...saltadas.keys()] };
          } else resultado.erro = 'comando desconhecido: ' + cmd.tipo;
        } catch (e) { resultado.erro = e.message; }
        try { await bg({ tipo: 'comando_resultado', dados: resultado }); } catch {}
        log('comando', cmd.tipo, cmd.titulo || cmd.numero || '', '->', resultado.ok ? 'ok' : resultado.erro);
      }
    } catch (e) { log('comandos falharam', e.message); }
    finally { ocupada = false; }
  }

  // --- censo: fichas a partir do historico, sem responder --------------------
  async function censo() {
    if (localStorage.getItem(KEY_CENSO)) return;
    log('CENSO: a percorrer todas as conversas individuais (sem responder)');
    let pane = null;
    for (let i = 0; i < 90 && !pane; i++) { pane = document.querySelector('#pane-side'); if (!pane) await espera(1000); }
    if (!pane) { log('censo: lista nao apareceu em 90 s; tento no proximo arranque'); return; }
    const feitos = new Set();
    let n = 0;
    pane.scrollTop = 0;
    for (let passo = 0; passo < 80; passo++) {
      const rows = linhas().filter(r => { const t = tituloDaLinha(r); return t && !feitos.has(t) && !/^(WhatsApp|Meta AI)$/i.test(t); });
      for (const row of rows) {
        const t = tituloDaLinha(row); feitos.add(t);
        try {
          if (linhaPareceGrupo(row)) { log('censo: grupo (pela linha), salto', t); continue; }
          await abrir(row);
          const ctx = await esperarContexto(6000); if (!ctx || ehGrupo(ctx)) { log('censo: grupo/sem contexto, salto', t); continue; }
          const numero = ctx.numero; if (!numero) { log('censo: sem numero, salto', t); continue; }
          if (numero === OWN) continue;
          const scroller = document.querySelector('#main [data-testid="conversation-panel-messages"]') || document.querySelector('#main .copyable-area') || document.querySelector('#main');
          for (let i = 0; i < 4; i++) { if (scroller) scroller.scrollTop = 0; await espera(500); }
          const msgs = mensagensAbertas(ctx).map(m => ({ id: m.id, dir: m.dir, texto: m.texto, tipo: m.tipo, ts: m.ts }));
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
    if (n > 0) localStorage.setItem(KEY_CENSO, new Date().toISOString());
    log('CENSO terminado:', n, 'conversas', n > 0 ? '' : '(nenhuma entregue -- volta a tentar no proximo arranque)');
  }

  // --- arranque -------------------------------------------------------------
  (async () => {
    let s = null;
    try { s = await bg({ tipo: 'saude' }); log('cerebro:', JSON.stringify(s)); }
    catch (e) { log('AVISO: cerebro local nao respondeu (', e.message, ')'); }
    log('VERSAO ' + VERSION, ENVIO_DESLIGADO ? '(ENVIO DESLIGADO)' : '');
    if (!localStorage.getItem(KEY_HANDLED)) { log('1a vez: baseline, nao respondo ao historico'); }
    setInterval(varrer, VARRER_MS);
    setInterval(despachar, PENDENTES_MS);
    setInterval(comandos, COMANDOS_MS);
    if (s && s.pedir_censo) { setTimeout(censo, 8000); }
    const alvo = document.querySelector('#pane-side');
    if (alvo) new MutationObserver(() => { clearTimeout(window.__vigiaObs); window.__vigiaObs = setTimeout(varrer, 1200); }).observe(alvo, { childList: true, subtree: true, characterData: true });
  })();
  window.__vigiaBoraVarrer = varrer;
  window.__vigiaBoraCenso = censo;
})();
