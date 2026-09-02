// WhatsApp da loja Bora — PORTA 2 (VPS, Baileys, sem navegador) — v2, missao 02/09/2026.
// Emparelha (QR ao vivo em :8099 + codigo de emparelhamento para o Telegram quando o 401 levantar),
// recebe mensagens INDIVIDUAIS (grupos: nunca), incluindo audio e imagem (bytes -> base64), e
// entrega-as ao cerebro local (127.0.0.1:8790, o mesmo codigo do PC). Vai buscar as respostas a
// fila de saida e envia com "a escrever..." e espera proporcional. As duas portas nunca respondem a
// mesma mensagem: a tranca e por id no Supabase (whatsapp_locks), feita pelo cerebro.
// ENVIO DESLIGADO: enquanto existir /root/whatsapp-bora/ENVIO_DESLIGADO nada sai por aqui (e o
// cerebro tambem nao poe nada na fila). Anti-ban: so responde a quem escreve, espaco minimo entre
// envios, nunca em massa (o cerebro so entrega 1 mensagem de cada vez com 4 s de intervalo).
const { default: makeWASocket, useMultiFileAuthState, downloadMediaMessage, DisconnectReason } = require('@whiskeysockets/baileys')
const QRCode = require('qrcode')
const fs = require('fs')
const http = require('http')
const pino = require('pino')
const { execFile } = require('child_process')

const DIR = '/root/whatsapp-bora'
const CEREBRO = 'http://127.0.0.1:8790'
const OWN = '351937501673'
const HERMES_C = 'hermes-agent-fvnc-hermes-agent-1'
const ENVIO_DESLIGADO = () => fs.existsSync(DIR + '/ENVIO_DESLIGADO')
let qrDataUrl = ''
let estado = 'a arrancar'
let sock = null
let ultimoCodigo = 0
const log = (...a) => { const l = new Date().toISOString() + ' ' + a.join(' '); console.log(l); try { fs.appendFileSync(DIR + '/ligar.log', l + '\n') } catch {} }

function telegram(msg) {
  execFile('docker', ['exec', '-u', 'hermes', HERMES_C, '/opt/hermes/bin/hermes', 'send', '-t', 'telegram', msg], { timeout: 30000 }, (e) => { if (e) log('telegram falhou:', e.message) })
}
async function postJson(caminho, corpo, ms) {
  const ac = new AbortController(); const t = setTimeout(() => ac.abort(), ms || 60000)
  try {
    const r = await fetch(CEREBRO + caminho, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(corpo), signal: ac.signal })
    return await r.json()
  } finally { clearTimeout(t) }
}
async function getJson(caminho, ms) {
  const ac = new AbortController(); const t = setTimeout(() => ac.abort(), ms || 8000)
  try { const r = await fetch(CEREBRO + caminho, { signal: ac.signal }); return await r.json() } finally { clearTimeout(t) }
}

// --- pagina do QR ao vivo (auto-refresh 4 s) ---
http.createServer((req, res) => {
  if (req.url.indexOf('/qr.png') === 0 && qrDataUrl) {
    const b = Buffer.from(qrDataUrl.split(',')[1], 'base64')
    res.writeHead(200, { 'Content-Type': 'image/png', 'Cache-Control': 'no-store' }); res.end(b); return
  }
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' })
  const corpo = estado.indexOf('LIGADO') === 0
    ? '<h1 style="color:green">ASSOCIADO! Ja podes fechar esta pagina.</h1>'
    : (qrDataUrl ? '<p>Le este QR com o telemovel: WhatsApp &rarr; Aparelhos associados &rarr; Associar um aparelho.</p><img src="/qr.png?' + Date.now() + '">' : '<p>A gerar o QR, aguarda uns segundos...</p>')
  res.end('<html><head><meta http-equiv="refresh" content="4"><title>WhatsApp Bora</title><style>body{font-family:sans-serif;text-align:center;background:#eee;padding:24px}img{width:320px;border:8px solid #fff;border-radius:8px}</style></head><body><h2>Associar o WhatsApp da loja</h2>' + corpo + '<p style="color:#888">estado: ' + estado + '</p></body></html>')
}).listen(8099, '0.0.0.0', () => log('PAGINA_QR :8099'))

// --- mensagens recebidas -> cerebro ---
function textoDe(m) {
  const c = m.message || {}
  return c.conversation || (c.extendedTextMessage && c.extendedTextMessage.text) || (c.imageMessage && c.imageMessage.caption) || (c.documentMessage && c.documentMessage.caption) || ''
}
async function tratar(m) {
  const jid = m.key.remoteJid || ''
  if (m.key.fromMe || /@g\.us$/.test(jid) || jid === 'status@broadcast' || !m.message) return
  const numero = jid.replace(/@.*$/, '').replace(/:\d+$/, '').replace(/\D/g, '')
  if (!numero || numero === OWN) return
  const c = m.message
  const ev = { numero, msg_id: 'false_' + jid + '_' + m.key.id, dir: 'entrada', tipo: 'texto', texto: textoDe(m), ts: new Date((m.messageTimestamp || 0) * 1000).toISOString(), grupo: false, push_name: m.pushName || null }
  try {
    if (c.audioMessage) {
      ev.tipo = 'audio'
      const buf = await downloadMediaMessage(m, 'buffer', {}, { logger: pino({ level: 'silent' }), reuploadRequest: sock.updateMediaMessage })
      ev.audio_b64 = Buffer.from(buf).toString('base64'); ev.mime = c.audioMessage.mimetype || 'audio/ogg'
    } else if (c.imageMessage) {
      ev.tipo = 'imagem'
      const buf = await downloadMediaMessage(m, 'buffer', {}, { logger: pino({ level: 'silent' }), reuploadRequest: sock.updateMediaMessage })
      ev.imagem_b64 = Buffer.from(buf).toString('base64'); ev.mime = c.imageMessage.mimetype || 'image/jpeg'
    }
  } catch (e) { log('media falhou', numero, e.message) }
  if (!ev.texto && !ev.audio_b64 && !ev.imagem_b64) return
  try { const r = await postJson('/evento', ev, 90000); log('evento', numero, ev.tipo, '->', r && r.acao) }
  catch (e) { log('cerebro nao respondeu', e.message) }
}

// --- fila de saida -> WhatsApp ---
let aEnviar = false
async function despachar() {
  if (aEnviar || !sock || ENVIO_DESLIGADO() || estado.indexOf('LIGADO') !== 0) return
  aEnviar = true
  try {
    const r = await getJson('/pendentes')
    for (const item of (r && r.mensagens) || []) {
      const numero = String(item.numero).replace(/\D/g, '')
      const jid = numero + '@s.whatsapp.net'
      let ok = false, erro = null
      try {
        await sock.sendPresenceUpdate('composing', jid)
        await new Promise(res => setTimeout(res, Math.min(4000, 1000 + item.texto.length * 25)))
        await sock.sendMessage(jid, { text: item.texto })
        await sock.sendPresenceUpdate('paused', jid)
        ok = true
      } catch (e) { erro = e.message }
      try { await postJson('/enviado', { id: item.id, numero, texto: item.texto, ok, erro }, 8000) } catch {}
      log('enviado', numero, ok, item.motivo || '')
    }
  } catch (e) { log('despachar falhou', e.message) }
  finally { aEnviar = false }
}
setInterval(despachar, 4000)

// --- ligacao ---
async function start() {
  const { state, saveCreds } = await useMultiFileAuthState(DIR + '/auth')
  sock = makeWASocket({ auth: state, printQRInTerminal: false, logger: pino({ level: 'silent' }), browser: ['Bora Atendimento', 'Chrome', '2.0'], qrTimeout: 60000 })
  sock.ev.on('creds.update', saveCreds)
  sock.ev.on('connection.update', async (u) => {
    const { connection, lastDisconnect, qr } = u
    if (qr) {
      qrDataUrl = await QRCode.toDataURL(qr, { width: 320, margin: 2 })
      estado = 'QR pronto (le no telemovel)'
      log('QR_NOVO')
      // Codigo de emparelhamento: maximo 1 tentativa por hora; vai IMEDIATAMENTE para o Telegram.
      if (!state.creds.registered && Date.now() - ultimoCodigo > 3600000) {
        ultimoCodigo = Date.now()
        try {
          const code = await sock.requestPairingCode(OWN)
          fs.writeFileSync(DIR + '/codigo.txt', code)
          telegram('WhatsApp da loja (VPS): codigo de emparelhamento ' + code + ' - no telemovel: WhatsApp > Aparelhos conectados > Conectar com numero > digitar o codigo. Expira em minutos; se passar, diz "pronto" que eu peco outro. (Ou le o QR em http://srv1786862.hstgr.cloud:8099)')
          log('CODIGO_ENVIADO')
        } catch (e) { log('requestPairingCode falhou (usar o QR):', e.message) }
      }
    }
    if (connection === 'open') {
      estado = 'LIGADO ' + new Date().toISOString(); qrDataUrl = ''
      fs.writeFileSync(DIR + '/estado.txt', estado); log('LIGADO')
      // o cerebro (e o do PC, pelo Supabase) fica a saber que esta porta esta emparelhada: e por aqui que
      // as mensagens que o PC nao conseguiu entregar passam a sair (falha F, 02/09)
      postJson('/emparelhada', { ligada: true, porta: 'vps-baileys' }, 8000).catch((e) => log('emparelhada falhou:', e.message))
    }
    if (connection === 'close') {
      const code = lastDisconnect && lastDisconnect.error && lastDisconnect.error.output && lastDisconnect.error.output.statusCode
      log('FECHADO ' + code)
      postJson('/emparelhada', { ligada: false, porta: 'vps-baileys', motivo: String(code) }, 8000).catch(() => {})
      if (code === DisconnectReason.loggedOut) { estado = 'sessao terminada no telemovel; apaga ./auth para emparelhar de novo'; return }
      // 401 numa sessao limpa = WhatsApp a recusar por tentativas a mais. A v1 insistia de 10 em 10 min
      // (6 tentativas/hora) e o bloqueio nunca levantou em 2 dias. Ordem do Danilo: MAXIMO 1 por hora.
      if (code === 401) { estado = 'em espera (WhatsApp recusou, 401 - nova tentativa em 60 min) ' + new Date().toISOString(); setTimeout(start, 3600000); return }
      setTimeout(start, 3000)
    }
  })
  sock.ev.on('messages.upsert', async ({ messages, type }) => {
    if (type !== 'notify') return
    for (const m of messages) { try { await tratar(m) } catch (e) { log('tratar falhou', e.message) } }
  })
}
start()
