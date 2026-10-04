// WhatsApp da loja Bora — PORTA 2 (VPS, Baileys, sem navegador) — v2, missao 02/09/2026.
// Emparelha (QR ao vivo em :8099 + codigo de emparelhamento para o Telegram quando o 401 levantar),
// recebe mensagens INDIVIDUAIS (grupos: nunca), incluindo audio e imagem (bytes -> base64), e
// entrega-as ao cerebro local (127.0.0.1:8790, o mesmo codigo do PC). Vai buscar as respostas a
// fila de saida e envia com "a escrever..." e espera proporcional. As duas portas nunca respondem a
// mesma mensagem: a tranca e por id no Supabase (whatsapp_locks), feita pelo cerebro.
// ENVIO DESLIGADO: enquanto existir /root/whatsapp-bora/ENVIO_DESLIGADO nada sai por aqui (e o
// cerebro tambem nao poe nada na fila). Anti-ban: so responde a quem escreve, espaco minimo entre
// envios, nunca em massa (o cerebro so entrega 1 mensagem de cada vez com 4 s de intervalo).
const { default: makeWASocket, useMultiFileAuthState, downloadMediaMessage, fetchLatestBaileysVersion, DisconnectReason } = require('@whiskeysockets/baileys')
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

// INSTANCIA UNICA. Dois processos com as mesmas credenciais rodam chaves Signal um por cima do
// outro e o telemovel do outro lado deixa de conseguir decifrar. O systemd ja garante um, mas um
// arranque a mao ao lado do servico ja aconteceu -- isto recusa-se a arrancar nesse caso.
const TRANCA = DIR + '/.baileys.pid'
try {
  const anterior = parseInt(fs.readFileSync(TRANCA, 'utf-8').trim(), 10)
  if (anterior && anterior !== process.pid) {
    try {
      process.kill(anterior, 0)   // nao mata: so pergunta se esta vivo
      console.error('JA HA UM BAILEYS VIVO (pid ' + anterior + ') - este processo nao arranca')
      process.exit(3)
    } catch { /* o pid guardado ja morreu: seguimos */ }
  }
} catch { /* sem ficheiro de tranca: primeiro arranque */ }
fs.writeFileSync(TRANCA, String(process.pid))
process.on('exit', () => { try { if (fs.readFileSync(TRANCA, 'utf-8').trim() === String(process.pid)) fs.unlinkSync(TRANCA) } catch {} })

// GUARDA DAS MENSAGENS ENVIADAS - e daqui que sai a copia quando o telemovel pede reenvio.
const GUARDA = DIR + '/enviadas.json'
let guarda = {}
try { guarda = JSON.parse(fs.readFileSync(GUARDA, 'utf-8')) } catch { guarda = {} }
function guardarEnviada(id, conteudo, numero, idFila) {
  if (!id) return
  guarda[id] = { message: conteudo, numero, idFila, ts: Date.now() }
  const ids = Object.keys(guarda)
  if (ids.length > 500) for (const k of ids.slice(0, ids.length - 500)) delete guarda[k]
  try { fs.writeFileSync(GUARDA, JSON.stringify(guarda)) } catch (e) { log('guarda falhou', e.message) }
}
let ultimoAvisoReenvio = 0

// ENDERECO DE RESPOSTA POR CONTACTO. Guardado em disco: se o processo reiniciar entre a pergunta
// e a resposta, tem de responder na mesma sessao, senao volta o "A aguardar pela mensagem".
const JIDS = DIR + '/jids.json'
let jidsPorNumero = {}
try { jidsPorNumero = JSON.parse(fs.readFileSync(JIDS, 'utf-8')) } catch { jidsPorNumero = {} }
function lembrarJid(numero, jidBruto) {
  if (!numero || !jidBruto || jidsPorNumero[numero] === jidBruto) return
  jidsPorNumero[numero] = jidBruto
  try { fs.writeFileSync(JIDS, JSON.stringify(jidsPorNumero)) } catch {}
  log('ENDERECO_DE_RESPOSTA', numero, '->', jidBruto)
}
let qrDataUrl = ''
let estado = 'a arrancar'
let sock = null
let ultimoCodigo = 0
const log = (...a) => { const l = new Date().toISOString() + ' ' + a.join(' '); console.log(l); try { fs.appendFileSync(DIR + '/ligar.log', l + '\n') } catch {} }

function envAt(chave) {
  try {
    const t = fs.readFileSync('/opt/data/.env', 'utf-8')
    const m = t.match(new RegExp('^' + chave + '=(.*)$', 'm'))
    return m ? m[1].trim() : ''
  } catch { return '' }
}
// TEXTO SIMPLES, sempre. O `hermes send -t telegram` passa pelo servico de voz e o codigo
// de emparelhamento chegava como nota de voz - impossivel de copiar (04/09/2026).
function telegram(msg) {
  const tok = envAt('TELEGRAM_BOT_TOKEN'), ch = envAt('TELEGRAM_HOME_CHANNEL')
  if (!tok || !ch) { log('telegram: sem token/canal em /opt/data/.env'); return }
  fetch('https://api.telegram.org/bot' + tok + '/sendMessage', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ chat_id: ch, text: msg }),
  }).then(r => r.json()).then(j => log('telegram', j && j.ok ? 'ok ' + j.result.message_id : 'falhou'))
    .catch(e => log('telegram falhou:', e.message))
}
let ultimaCopia = 0
// Uma ligacao que funciona e' um bem: guarda-se. Custou 5 dias a conseguir a primeira.
function guardarCopiaBoa() {
  if (Date.now() - ultimaCopia < 3600000) return
  ultimaCopia = Date.now()
  try {
    const destino = DIR + '/auth.ultima-boa'
    fs.mkdirSync(destino, { recursive: true })
    for (const f of fs.readdirSync(destino)) fs.unlinkSync(destino + '/' + f)
    for (const f of fs.readdirSync(DIR + '/auth')) fs.copyFileSync(DIR + '/auth/' + f, destino + '/' + f)
    log('COPIA_BOA guardada')
  } catch (e) { log('COPIA_BOA falhou', e.message) }
}

function limparAuth(porque) {
  try {
    for (const f of fs.readdirSync(DIR + '/auth')) fs.unlinkSync(DIR + '/auth/' + f)
    log('AUTH_LIMPA', porque)
  } catch (e) { log('AUTH_LIMPA falhou', e.message) }
}
async function postJson(caminho, corpo, ms, base) {
  const ac = new AbortController(); const t = setTimeout(() => ac.abort(), ms || 60000)
  try {
    const r = await fetch((base || CEREBRO) + caminho, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(corpo), signal: ac.signal })
    return await r.json()
  } finally { clearTimeout(t) }
}
async function getJson(caminho, ms, base) {
  const ac = new AbortController(); const t = setTimeout(() => ac.abort(), ms || 8000)
  try { const r = await fetch((base || CEREBRO) + caminho, { signal: ac.signal }); return await r.json() } finally { clearTimeout(t) }
}
// ASSISTENTE DE NEGOCIO (01/10/2026): "funcionario digital" de outros negocios (1.o: Mister Navalha).
// Cada mensagem pergunta-lhe primeiro "e tua?". So os numeros do cliente certo (em teste: a allowlist)
// sao tratados la; o resto segue EXACTAMENTE o caminho antigo (cerebro da Bora, pausado).
// A saida do assistente nao obedece ao interruptor da Bora (ENVIO_DESLIGADO / envio_ligado).
const ASSISTENTE = 'http://127.0.0.1:8795'

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
  // A WhatsApp ja entrega muitos contactos como @lid (identificador interno) em vez do numero.
  // Sem isto abria-se uma ficha nova por pessoa (o Danilo virou 16149513265317) e a tranca
  // partilhada nunca colidia com a da extensao. O numero real vem em key.senderPn (04/09/2026).
  const jidBruto = m.key.remoteJid || ''
  const jid = (/@lid$/.test(jidBruto) && m.key.senderPn) ? m.key.senderPn : jidBruto
  if (m.key.fromMe || /@g\.us$/.test(jidBruto) || jid === 'status@broadcast' || !m.message) return
  const numero = jid.replace(/@.*$/, '').replace(/:\d+$/, '').replace(/\D/g, '')
  if (!numero || numero === OWN) return
  lembrarJid(numero, jidBruto.replace(/:\d+@/, '@'))   // responder por onde ele falou
  const c = m.message
  const ev = { numero, msg_id: 'false_' + jid.replace('@s.whatsapp.net', '@c.us') + '_' + m.key.id, dir: 'entrada', tipo: 'texto', texto: textoDe(m), ts: new Date((m.messageTimestamp || 0) * 1000).toISOString(), grupo: false, push_name: m.pushName || null }
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
  const ctx = (c.extendedTextMessage && c.extendedTextMessage.contextInfo) || null
  if (ctx && ctx.stanzaId) ev.quoted_id = ctx.stanzaId
  // 1.o "e teu?" (rapido, sem motor). Se for, a mensagem e SO do assistente: mesmo que ele demore ou
  // falhe, nunca cai tambem no cerebro da Bora (senao, com a Bora ligada, haveria duas respostas).
  let meu = false
  try {
    // 04/10: o inicio do texto vai junto para o "TESTE 1234" do Secretario Virtual ativar a demo.
    const q = await getJson('/quem?numero=' + numero + '&sessao=vps-baileys:' + OWN +
      '&texto=' + encodeURIComponent(String(ev.texto || '').slice(0, 40)), 5000, ASSISTENTE)
    meu = !!(q && q.meu)
  } catch (e) { log('assistente /quem falhou (segue o caminho antigo):', e.message) }
  if (meu) {
    try {
      const ra = await postJson('/evento', Object.assign({ sessao: 'vps-baileys:' + OWN }, ev), 170000, ASSISTENTE)
      log('assistente', numero, ev.tipo, '->', ra && ra.acao)
    } catch (e) { log('assistente /evento falhou (sem resposta da Bora a este numero):', e.message) }
    return
  }
  try { const r = await postJson('/evento', ev, 90000); log('evento', numero, ev.tipo, '->', r && r.acao) }
  catch (e) { log('cerebro nao respondeu', e.message) }
}

// Uma linha marcada `entregue` que afinal o cliente nao conseguiu ler tem de deixar de mentir.
function naoDecifrada(idFila, numero, idWa) {
  postJson('/enviado', { id: idFila, numero, ok: false, estado: 'nao-decifrada', msg_id: idWa,
    erro: 'o telemovel nao conseguiu decifrar e pediu reenvio' }, 8000, String(idFila).indexOf('an-') === 0 ? ASSISTENTE : null).catch(() => {})
  const agora = Date.now()
  if (agora - ultimoAvisoReenvio > 600000) {
    ultimoAvisoReenvio = agora
    telegram('WhatsApp da loja: o telemovel de ' + numero + ' nao conseguiu ler uma resposta e pediu '
      + 'reenvio. Mandei a copia outra vez. Se se repetir muito, a sessao esta estragada e eu limpo-a.')
  }
}

// --- fila de saida -> WhatsApp ---
// mensagens ja entregues ao WhatsApp mas ainda SEM aviso de entrega. So saem daqui com prova.
const porConfirmar = new Map()
const SEM_CONFIRMACAO_MS = 90000
setInterval(async () => {
  const agora = Date.now()
  for (const [idWa, e] of porConfirmar) {
    if (agora - e.ts < SEM_CONFIRMACAO_MS) continue
    porConfirmar.delete(idWa)
    try { await postJson('/enviado', { id: e.id, numero: e.numero, texto: e.texto, ok: false, msg_id: idWa,
      erro: 'a WhatsApp nao confirmou a entrega em ' + (SEM_CONFIRMACAO_MS / 1000) + ' s' }, 8000, e.base) } catch {}
    log('SEM_CONFIRMACAO', e.numero, idWa)
  }
}, 15000)
let aEnviar = false
async function despachar() {
  if (aEnviar || !sock || ENVIO_DESLIGADO() || estado.indexOf('LIGADO') !== 0) return
  aEnviar = true
  try { await enviarFila(null) } finally { aEnviar = false }
}
setInterval(despachar, 4000)
// Fila do assistente de negocio: independente do interruptor da Bora (so liga/desliga pelo modo do cliente).
let aEnviarAssistente = false
async function despacharAssistente() {
  if (aEnviarAssistente || !sock || estado.indexOf('LIGADO') !== 0) return
  aEnviarAssistente = true
  try { await enviarFila(ASSISTENTE) } finally { aEnviarAssistente = false }
}
setInterval(despacharAssistente, 3000)
async function enviarFila(base) {
  try {
    const r = await getJson('/pendentes', 8000, base)
    for (const item of (r && r.mensagens) || []) {
      const numero = String(item.numero).replace(/\D/g, '')
      const jid = jidsPorNumero[numero] || (numero + '@s.whatsapp.net')
      try {
        // nota de voz do assistente (ogg/opus, PTT): "a gravar audio..." e depois o audio
        const voz = item.audio_path && base ? fs.readFileSync(item.audio_path) : null
        await sock.sendPresenceUpdate(voz ? 'recording' : 'composing', jid)
        await new Promise(res => setTimeout(res, Math.min(4000, 1000 + item.texto.length * 25)))
        const res = voz
          ? await sock.sendMessage(jid, { audio: voz, mimetype: 'audio/ogg; codecs=opus', ptt: true })
          : await sock.sendMessage(jid, { text: item.texto })
        await sock.sendPresenceUpdate('paused', jid)
        const idWa = res && res.key && res.key.id
        if (!idWa) throw new Error('o WhatsApp nao devolveu id da mensagem')
        guardarEnviada(idWa, res.message || { conversation: item.texto }, numero, item.id)
        // NAO se diz que chegou. Fica a espera do aviso de entrega da propria WhatsApp.
        porConfirmar.set(idWa, { id: item.id, numero, texto: item.texto, ts: Date.now(), base })
        if (base) { try { await postJson('/enviado', { id: item.id, numero, ok: true, estado: 'a-caminho', msg_id: idWa }, 8000, base) } catch {} }
        log('a-caminho', numero, idWa, item.motivo || '', base ? '(assistente)' : '')
      } catch (e) {
        try { await postJson('/enviado', { id: item.id, numero, texto: item.texto, ok: false, erro: e.message }, 8000, base) } catch {}
        log('envio-falhou', numero, e.message)
      }
    }
  } catch (e) { log('despachar falhou', base || 'bora', e.message) }
}

// --- ligacao ---
async function start() {
  const { state, saveCreds } = await useMultiFileAuthState(DIR + '/auth')
  const { version } = await fetchLatestBaileysVersion()
  log('VERSAO_WA ' + JSON.stringify(version))
  // A identificacao TEM de ser uma das normais. Com o nome inventado ('Bora Atendimento')
  // a WhatsApp recusou o emparelhamento durante 5 dias, por QR e por codigo (04/09/2026).
  sock = makeWASocket({
    auth: state,
    version,
    printQRInTerminal: false,
    logger: pino({ level: 'silent' }),
    browser: ['Ubuntu', 'Chrome', '22.04.4'],
    qrTimeout: 120000,
    syncFullHistory: false,
    // O telemovel so pede isto quando NAO conseguiu decifrar. Devolver a copia resolve o
    // "A aguardar pela mensagem"; e o pedido em si e a prova de que a entrega nao valeu.
    getMessage: async (key) => {
      const g = key && key.id ? guarda[key.id] : null
      log('PEDIDO_DE_REENVIO', key && key.id, g ? g.numero : 'SEM COPIA GUARDADA')
      if (g) {
        naoDecifrada(g.idFila, g.numero, key.id)
        return g.message
      }
      return undefined
    },
  })
  sock.ev.on('creds.update', saveCreds)
  sock.ev.on('connection.update', async (u) => {
    const { connection, lastDisconnect, qr } = u
    if (qr) {
      qrDataUrl = await QRCode.toDataURL(qr, { width: 320, margin: 2 })
      estado = 'QR pronto (le no telemovel)'
      log('QR_NOVO')
      // Codigo de emparelhamento: maximo 1 tentativa por hora; vai IMEDIATAMENTE para o Telegram.
      const aPedido = fs.existsSync(DIR + '/pedir-codigo')
      if (!state.creds.registered && (aPedido || Date.now() - ultimoCodigo > 3600000)) {
        if (aPedido) { try { fs.unlinkSync(DIR + '/pedir-codigo') } catch {} }
        ultimoCodigo = Date.now()
        try {
          const code = await sock.requestPairingCode(OWN)
          fs.writeFileSync(DIR + '/codigo.txt', code)
          const linhas = ['CODIGO DO WHATSAPP DA LOJA (expira em minutos)', '', code, '',
            'No telemovel: WhatsApp > Definicoes > Aparelhos ligados > Ligar aparelho > Ligar com numero de telefone > escreve o codigo acima.',
            'Se ja expirou, le antes o QR em http://srv1786862.hstgr.cloud:8099']
          telegram(linhas.join(String.fromCharCode(10)))
          log('CODIGO_ENVIADO')
        } catch (e) { log('requestPairingCode falhou (usar o QR):', e.message) }
      }
    }
    if (connection === 'open') {
      guardarCopiaBoa()
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
      // Se nunca chegou a emparelhar, o creds.json que fica no disco e meio escrito e faz o
      // 401 seguinte ser imediato e eterno. Limpa-se antes de tentar outra vez (04/09/2026).
      // NAO se apagam credenciais aqui. Ver o cabecalho do remendo de 05/09: `registered` e' false
      // tambem numa sessao boa, e esta linha apagou a sessao viva a meio da noite.
      const retomar = (ms, porque) => {
        log('RETOMAR_EM ' + Math.round(ms / 1000) + 's ' + porque)
        setTimeout(() => { log('RETOMAR'); start().catch(e => { log('RETOMAR falhou:', e.message); setTimeout(() => process.exit(1), 2000) }) }, ms)
      }
      if (code === 401) { estado = 'em espera (WhatsApp recusou, 401 - nova tentativa em 60 min) ' + new Date().toISOString(); retomar(3600000, '401'); return }
      retomar(3000, String(code))
    }
  })
  // status da WhatsApp: 2 = chegou ao servidor, 3 = entregue no telemovel, 4 = visto.
  // So 3 ou 4 valem como entrega. Antes disto o banco dizia 'visto' por o envio nao ter dado erro.
  sock.ev.on('messages.update', async (ups) => {
    for (const u of ups) {
      const idWa = u.key && u.key.id
      const st = u.update && u.update.status
      const e = idWa && porConfirmar.get(idWa)
      if (!e || st == null) continue
      const n = typeof st === 'number' ? st : Number(st)
      if (n < 3) continue
      porConfirmar.delete(idWa)
      try { await postJson('/enviado', { id: e.id, numero: e.numero, texto: e.texto, ok: true, msg_id: idWa,
        estado: n >= 4 ? 'visto' : 'entregue' }, 8000, e.base) } catch {}
      log('ENTREGUE', e.numero, idWa, 'status=' + n, e.base ? '(assistente)' : '')
    }
  })
  sock.ev.on('messages.upsert', async ({ messages, type }) => {
    // Escrito a mao no telemovel do negocio (fromMe, nao enviado pelo robo): o assistente cala-se 12 h
    // nessa conversa. Espera 4 s para o id do robo ja estar na guarda; ignora historico antigo.
    for (const m of messages) {
      if (!m.key || !m.key.fromMe || /@g\.us$/.test(m.key.remoteJid || '')) continue
      if (Date.now() / 1000 - Number(m.messageTimestamp || 0) > 120) continue
      setTimeout(() => {
        if (guarda[m.key.id]) return
        const rj = (m.key.remoteJid || '').replace(/:\d+@/, '@')
        let num = /@s\.whatsapp\.net$/.test(rj) ? rj.replace(/@.*$/, '') : ''
        if (!num) for (const [n, j] of Object.entries(jidsPorNumero)) if (j === rj) num = n
        if (!num || num === OWN) return
        postJson('/dono-falou', { sessao: 'vps-baileys:' + OWN, numero: num }, 8000, ASSISTENTE)
          .then(r => { if (r && r.ok) log('DONO_ESCREVEU', num, 'assistente calado ate', r.silenciado_ate) }).catch(() => {})
      }, 4000)
    }
    if (type !== 'notify') return
    for (const m of messages) { try { await tratar(m) } catch (e) { log('tratar falhou', e.message) } }
  })
}
start().catch(e => { log('ARRANQUE falhou:', e.message); setTimeout(() => process.exit(1), 2000) })
