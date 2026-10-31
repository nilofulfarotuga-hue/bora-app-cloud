// Olhos do Dipsy: captura_ecra (PowerShell) e ver_imagem (Gemini). Código nosso, missão C-liga, 30/10/2026.
// A chave GOOGLE_AI_API_KEY lê-se do ambiente no momento do pedido e nunca é escrita, registada nem devolvida.
// ATENÇÃO de privacidade: a imagem sai do PC para a Google (plano grátis, que pode guardar). Só capturar o que a tarefa pede.

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFile } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const AQUI = path.dirname(fileURLToPath(import.meta.url))
export const SCRIPT_CAPTURA = path.join(AQUI, '..', 'scripts', 'captura.ps1')
export const PASTA_CAPTURAS = path.join(os.homedir(), '.dsh', 'capturas')
const MODELOS = ['gemini-3.1-flash-lite', 'gemini-3.6-flash', 'gemini-3.8-flash']
const EXTENSOES = { '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.gif': 'image/gif', '.bmp': 'image/bmp' }
const MAX_BYTES = 8 * 1024 * 1024
const PERGUNTA_PADRAO = 'Descreve em português simples o que vês: janelas e aplicações abertas, texto legível, números, botões e qualquer erro ou aviso. Sê concreto e curto.'

function limparCapturasVelhas() {
  try {
    const limite = Date.now() - 24 * 3600 * 1000
    for (const f of fs.readdirSync(PASTA_CAPTURAS)) {
      const p = path.join(PASTA_CAPTURAS, f)
      const st = fs.statSync(p)
      if (st.isFile() && st.mtimeMs < limite && /\.(png|jpg|jpeg)$/i.test(f)) fs.unlinkSync(p)
    }
  } catch { /* pasta ainda não existe */ }
}

export function capturarEcra(sinal) {
  fs.mkdirSync(PASTA_CAPTURAS, { recursive: true })
  limparCapturasVelhas()
  const saida = path.join(PASTA_CAPTURAS, `ecra-${new Date().toISOString().replace(/[:.]/g, '-')}.png`)
  return new Promise((resolve, reject) => {
    const filho = execFile(
      'powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', SCRIPT_CAPTURA, '-Saida', saida],
      { windowsHide: true, timeout: 30000, signal: sinal },
      (erro, stdout, stderr) => {
        if (erro) return reject(new Error(`a captura falhou: ${String(stderr || erro.message).slice(0, 200)}`))
        if (!fs.existsSync(saida)) return reject(new Error('a captura não criou o ficheiro'))
        resolve(saida)
      },
    )
    filho.stdin?.end()
  })
}

async function perguntarAoGemini(base64, mime, pergunta, sinal) {
  const chave = process.env.GOOGLE_AI_API_KEY
  if (!chave) throw new Error('falta a variável GOOGLE_AI_API_KEY no ambiente do Dipsy')
  const corpo = JSON.stringify({
    contents: [{ parts: [{ text: pergunta }, { inline_data: { mime_type: mime, data: base64 } }] }],
    generationConfig: { temperature: 0.2, maxOutputTokens: 1200 },
  })
  let ultimo = 'sem resposta'
  for (const modelo of MODELOS) {
    let r
    try {
      r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${modelo}:generateContent`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'x-goog-api-key': chave },
        body: corpo,
        signal: sinal,
      })
    } catch (e) {
      ultimo = `${modelo}: erro de rede`
      continue
    }
    if (r.status === 429 || r.status === 404 || r.status === 503) { ultimo = `${modelo}: HTTP ${r.status}`; continue }
    if (!r.ok) throw new Error(`${modelo}: HTTP ${r.status}`)
    const j = await r.json()
    const texto = (j.candidates?.[0]?.content?.parts ?? []).map((p) => p.text ?? '').join('').trim()
    if (texto) return { texto, modelo }
    ultimo = `${modelo}: resposta vazia`
  }
  throw new Error(`nenhum modelo respondeu (${ultimo})`)
}

export async function verImagem(origem, pergunta, sinal) {
  let caminho = String(origem ?? '').trim()
  let capturada = false
  if (!caminho || caminho.toLowerCase() === 'ecra') {
    caminho = await capturarEcra(sinal)
    capturada = true
  }
  const ext = path.extname(caminho).toLowerCase()
  const mime = EXTENSOES[ext]
  if (!mime) throw new Error('só leio imagens (png, jpg, webp, gif, bmp)')
  const st = fs.statSync(caminho)
  if (!st.isFile()) throw new Error('isso não é um ficheiro')
  if (st.size > MAX_BYTES) throw new Error('imagem demasiado grande (máximo 8 MB)')
  const dados = fs.readFileSync(caminho).toString('base64')
  const { texto, modelo } = await perguntarAoGemini(dados, mime, String(pergunta || PERGUNTA_PADRAO), sinal)
  return `${texto}\n\n(Imagem: ${capturada ? 'captura do ecrã agora' : caminho}. Descrita por ${modelo}; a imagem foi enviada à Google, plano grátis.)`
}
