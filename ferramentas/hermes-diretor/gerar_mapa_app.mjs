#!/usr/bin/env node
// Gera o MAPA DA APP do Bora: ecrãs e botões (cliente, estafeta, parceiro, admin)
// lidos do código Flutter. Só biblioteca padrão do Node. Não corre Flutter.
//
// Uso: node gerar_mapa_app.mjs <raiz-do-repo> [--json saida.json] [--sql saida.sql]
//
// Missão hermes-diretor-2026-11-20, bloco B6.1.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const APPS = ['cliente', 'estafeta', 'parceiro', 'admin'];
const TIPO_PRIO = { botao: 0, menu: 1, separador: 2, titulo: 3 };
const SUFIXO_ECRA = /(Screen|Page|Sheet|Dialog|Modal)$/;

// ---------------------------------------------------------------------------
// 1. Lexer mínimo de Dart: tira comentários e esvazia o interior das strings.
//    `code`  = fonte sem comentários (strings intactas)
//    `skel`  = igual, mas com o interior das strings em espaços (para contar
//              parênteses/chavetas e procurar nomes sem falsos positivos).
//    Os dois têm o mesmo comprimento: as posições servem para ambos.
// ---------------------------------------------------------------------------

function skipInterp(src, j) {
  let depth = 1;
  const n = src.length;
  while (j < n && depth > 0) {
    const ch = src[j];
    if (ch === '{') depth++;
    else if (ch === '}') depth--;
    else if (ch === "'" || ch === '"') {
      j = skipString(src, j, false);
      continue;
    }
    j++;
  }
  return j;
}

function skipString(src, i, raw) {
  const q = src[i];
  const triple = src[i + 1] === q && src[i + 2] === q;
  let j = i + (triple ? 3 : 1);
  const n = src.length;
  while (j < n) {
    const ch = src[j];
    if (!raw && ch === '\\') { j += 2; continue; }
    if (!raw && ch === '$' && src[j + 1] === '{') { j = skipInterp(src, j + 2); continue; }
    if (triple) {
      if (ch === q && src[j + 1] === q && src[j + 2] === q) return j + 3;
    } else {
      if (ch === q) return j + 1;
      if (ch === '\n') return j; // string por fechar: não deixar estragar o resto
    }
    j++;
  }
  return n;
}

export function lex(src) {
  const n = src.length;
  const code = new Uint16Array(n);
  const skel = new Uint16Array(n);
  for (let i = 0; i < n; i++) { const c = src.charCodeAt(i); code[i] = c; skel[i] = c; }
  const blank = (arr, a, b) => { for (let k = a; k < b; k++) if (arr[k] !== 10) arr[k] = 32; };
  let i = 0;
  while (i < n) {
    const c = src.charCodeAt(i);
    const d = src.charCodeAt(i + 1);
    if (c === 47 && d === 47) {
      let j = i;
      while (j < n && src.charCodeAt(j) !== 10) j++;
      blank(code, i, j); blank(skel, i, j);
      i = j; continue;
    }
    if (c === 47 && d === 42) {
      let depth = 1, j = i + 2;
      while (j < n && depth > 0) {
        if (src[j] === '/' && src[j + 1] === '*') { depth++; j += 2; }
        else if (src[j] === '*' && src[j + 1] === '/') { depth--; j += 2; }
        else j++;
      }
      blank(code, i, j); blank(skel, i, j);
      i = j; continue;
    }
    if (c === 39 || c === 34) {
      const raw = i > 0 && src[i - 1] === 'r' && !(i > 1 && /\w/.test(src[i - 2]));
      const end = skipString(src, i, raw);
      const triple = src[i + 1] === src[i] && src[i + 2] === src[i];
      const open = triple ? 3 : 1;
      if (end - open > i + open) blank(skel, i + open, end - open);
      i = end; continue;
    }
    i++;
  }
  const toStr = (arr) => Buffer.from(arr.buffer, arr.byteOffset, arr.byteLength).toString('utf16le');
  return { code: toStr(code), skel: toStr(skel) };
}

function matchClose(skel, open) {
  let depth = 0;
  for (let i = open; i < skel.length; i++) {
    const c = skel[i];
    if (c === '(' || c === '[' || c === '{') depth++;
    else if (c === ')' || c === ']' || c === '}') {
      depth--;
      if (depth === 0) return i;
    }
  }
  return -1;
}

/** Parte os argumentos de uma chamada por vírgulas ao nível 0. Devolve spans. */
function splitArgs(skel, open, close) {
  const out = [];
  let depth = 0, start = open + 1;
  for (let i = open + 1; i < close; i++) {
    const c = skel[i];
    if (c === '(' || c === '[' || c === '{') depth++;
    else if (c === ')' || c === ']' || c === '}') depth--;
    else if (c === ',' && depth === 0) { out.push([start, i]); start = i + 1; }
  }
  if (skel.slice(start, close).trim() !== '') out.push([start, close]);
  return out.map(([a, b]) => ({ a, b, nome: null, va: a, vb: b })).map((arg) => {
    const m = /^\s*([A-Za-z_]\w*)\s*:(?!:)/.exec(skel.slice(arg.a, arg.b));
    if (m) { arg.nome = m[1]; arg.va = arg.a + m[0].length; }
    return arg;
  });
}

// ---------------------------------------------------------------------------
// 2. Resolver o texto de uma expressão Dart
// ---------------------------------------------------------------------------

const PLACEHOLDER = '{…}';

function decodeEscape(src, j) {
  // src[j] === '\\'. Devolve [texto, novoIndice]
  const e = src[j + 1];
  switch (e) {
    case 'n': case 't': case 'r': case 'b': case 'f': case 'v': return [' ', j + 2];
    case 'u': {
      if (src[j + 2] === '{') {
        const k = src.indexOf('}', j + 3);
        const hex = src.slice(j + 3, k);
        try { return [String.fromCodePoint(parseInt(hex, 16)), k + 1]; } catch { return ['', k + 1]; }
      }
      const hex = src.slice(j + 2, j + 6);
      return [String.fromCharCode(parseInt(hex, 16) || 32), j + 6];
    }
    case 'x': return [String.fromCharCode(parseInt(src.slice(j + 2, j + 4), 16) || 32), j + 4];
    default: return [e ?? '', j + 2];
  }
}

/** Lê um literal de string em code[i]. Devolve {valor, fim}. */
function lerLiteral(code, i) {
  const q = code[i];
  let raw = false;
  const triple = code[i + 1] === q && code[i + 2] === q;
  const prev = i > 0 && code[i - 1] === 'r' && !(i > 1 && /\w/.test(code[i - 2]));
  if (prev) raw = true;
  let j = i + (triple ? 3 : 1);
  let v = '';
  const n = code.length;
  while (j < n) {
    const ch = code[j];
    if (!raw && ch === '\\') { const [t, nj] = decodeEscape(code, j); v += t; j = nj; continue; }
    if (!raw && ch === '$') {
      if (code[j + 1] === '{') { const fim = skipInterp(code, j + 2); v += PLACEHOLDER; j = fim; continue; }
      const m = /^\$[A-Za-z_]\w*/.exec(code.slice(j, j + 80));
      if (m) { v += PLACEHOLDER; j += m[0].length; continue; }
    }
    if (triple) { if (ch === q && code[j + 1] === q && code[j + 2] === q) return { valor: v, fim: j + 3 }; }
    else { if (ch === q) return { valor: v, fim: j + 1 }; if (ch === '\n') return { valor: v, fim: j }; }
    v += ch; j++;
  }
  return { valor: v, fim: n };
}

function topLevelIdx(sk, re) {
  // primeira posição a nível 0 onde o carácter/padrão bate; devolve -1 se não houver
  let depth = 0;
  for (let i = 0; i < sk.length; i++) {
    const c = sk[i];
    if (c === '(' || c === '[' || c === '{') depth++;
    else if (c === ')' || c === ']' || c === '}') depth--;
    else if (depth === 0 && re(sk, i)) return i;
  }
  return -1;
}

function envolvidoPorParenteses(sk) {
  const s = sk.trim();
  if (s[0] !== '(') return false;
  return matchClose(s, 0) === s.length - 1;
}

/**
 * Resolve uma expressão Dart para uma lista de textos possíveis (ternário dá dois).
 * `consts` é um mapa nome -> texto de constantes String do projeto.
 */
export function resolverExpr(code, skel, a, b, consts = new Map(), prof = 0) {
  if (prof > 6) return [];
  let exprC = code.slice(a, b);
  let exprS = skel.slice(a, b);
  exprC = exprC.trim(); exprS = exprS.trim();
  if (!exprS) return [];
  const rec = (x, y) => resolverExpr(exprC, exprS, x, y, consts, prof + 1);

  exprS = exprS.replace(/^const\s+/, (m) => { exprC = exprC.slice(m.length); return ''; });
  if (!exprS) return [];

  // parênteses a envolver tudo
  if (envolvidoPorParenteses(exprS)) {
    const fim = matchClose(exprS, 0);
    return resolverExpr(exprC, exprS, 1, fim, consts, prof + 1);
  }

  // ternário a nível 0: cond ? A : B
  const q = topLevelIdx(exprS, (s, i) => s[i] === '?' && s[i + 1] !== '?' && s[i + 1] !== '.' && s[i - 1] !== '?');
  if (q > 0) {
    let nivel = 0, depth = 0, dp = -1;
    for (let i = q + 1; i < exprS.length; i++) {
      const c = exprS[i];
      if (c === '(' || c === '[' || c === '{') depth++;
      else if (c === ')' || c === ']' || c === '}') depth--;
      else if (depth === 0 && c === '?' && exprS[i + 1] !== '?' && exprS[i + 1] !== '.') nivel++;
      else if (depth === 0 && c === ':') { if (nivel === 0) { dp = i; break; } nivel--; }
    }
    if (dp > 0) return [...rec(q + 1, dp), ...rec(dp + 1, exprS.length)];
    return [];
  }

  // a ?? b
  const nn = topLevelIdx(exprS, (s, i) => s[i] === '?' && s[i + 1] === '?');
  if (nn > 0) return [...rec(0, nn), ...rec(nn + 2, exprS.length)];

  // concatenação com +
  const plus = [];
  {
    let depth = 0;
    for (let i = 0; i < exprS.length; i++) {
      const c = exprS[i];
      if (c === '(' || c === '[' || c === '{') depth++;
      else if (c === ')' || c === ']' || c === '}') depth--;
      else if (depth === 0 && c === '+' && exprS[i + 1] !== '+' && exprS[i - 1] !== '+') plus.push(i);
    }
  }
  if (plus.length) {
    const cortes = [-1, ...plus, exprS.length];
    let juntar = '', algum = false;
    for (let k = 0; k < cortes.length - 1; k++) {
      const parte = rec(cortes[k] + 1, cortes[k + 1]);
      if (parte.length) { juntar += parte[0]; algum = true; } else juntar += PLACEHOLDER;
    }
    return algum ? [juntar] : [];
  }

  // tirar sufixos de métodos que não mudam o sentido do texto
  let fimUtil = exprS.length;
  for (;;) {
    const s = exprS.slice(0, fimUtil);
    const m = /\.(?:tr|toUpperCase\(\)|toLowerCase\(\)|trim\(\)|toString\(\)|replaceAll\([^)]*\))$/.exec(s);
    if (m) { fimUtil = m.index; continue; }
    const m2 = /\.trArgs\s*\(/.exec(s);
    if (m2) {
      const open = m2.index + m2[0].length - 1;
      if (matchClose(s, open) === s.length - 1) { fimUtil = m2.index; continue; }
    }
    break;
  }
  if (fimUtil !== exprS.length) return resolverExpr(exprC, exprS, 0, fimUtil, consts, prof + 1);

  // literais de string adjacentes: 'a' 'b'
  if (exprS[0] === "'" || exprS[0] === '"') {
    let i = 0, v = '';
    while (i < exprS.length) {
      while (i < exprS.length && /\s/.test(exprS[i])) i++;
      if (exprS[i] !== "'" && exprS[i] !== '"') break;
      const l = lerLiteral(exprC, i);
      v += l.valor; i = l.fim;
    }
    const resto = exprS.slice(i).trim();
    if (resto === '' || resto[0] === '.') return [v];
    return [];
  }

  // constante String do projeto
  const idm = /^(?:[A-Za-z_]\w*\.)?([A-Za-z_]\w*)$/.exec(exprS);
  if (idm && consts.has(idm[1])) return [consts.get(idm[1])];
  return [];
}

/** Limpa o texto e decide se serve para um mapa de ecrã. Devolve o texto final ou null. */
export function limparTexto(t) {
  let s = t.replace(/\{\d+\}/g, PLACEHOLDER).replace(/[\u0000-\u001f]/g, ' ').replace(/\s+/g, ' ').trim();
  if (!s) return null;
  if (s.length > 140) return null;
  if (!/\p{L}/u.test(s)) return null;
  if (s.replace(/\{…\}/g, '').replace(/[^\p{L}]/gu, '').length < 2) return null;
  if (/^https?:\/\//i.test(s) || s.startsWith('/')) return null;
  if (/^[a-z0-9]+(?:[_.\-/][a-z0-9]+)+$/.test(s)) return null; // chaves/rotas técnicas
  if (/^[a-z]+(?:[A-Z][a-z0-9]+)+$/.test(s)) return null; // camelCase
  return s;
}

// ---------------------------------------------------------------------------
// 3. Tipos de elemento conhecidos + descoberta dos botões do design system
// ---------------------------------------------------------------------------

const KINDS_BASE = {
  ElevatedButton: { tipo: 'botao', args: ['child', 'label'] },
  FilledButton: { tipo: 'botao', args: ['child', 'label'] },
  OutlinedButton: { tipo: 'botao', args: ['child', 'label'] },
  TextButton: { tipo: 'botao', args: ['child', 'label'] },
  IconButton: { tipo: 'botao', args: ['tooltip'] },
  FloatingActionButton: { tipo: 'botao', args: ['label', 'tooltip'] },
  PopupMenuButton: { tipo: 'botao', args: ['tooltip'] },
  SimpleDialogOption: { tipo: 'botao', args: ['child'] },
  PopupMenuItem: { tipo: 'menu', args: ['child'] },
  DropdownMenuItem: { tipo: 'menu', args: ['child'] },
  ListTile: { tipo: 'menu', args: ['title'] },
  SwitchListTile: { tipo: 'menu', args: ['title'] },
  CheckboxListTile: { tipo: 'menu', args: ['title'] },
  RadioListTile: { tipo: 'menu', args: ['title'] },
  ExpansionTile: { tipo: 'menu', args: ['title'] },
  Tab: { tipo: 'separador', args: ['text', 'child'] },
  BottomNavigationBarItem: { tipo: 'separador', args: ['label'] },
  NavigationDestination: { tipo: 'separador', args: ['label'] },
  NavigationRailDestination: { tipo: 'separador', args: ['label'] },
  ButtonSegment: { tipo: 'separador', args: ['label'] },
  AppBar: { tipo: 'titulo', args: ['title'] },
  SliverAppBar: { tipo: 'titulo', args: ['title'] },
  AlertDialog: { tipo: 'titulo', args: ['title'] },
  SimpleDialog: { tipo: 'titulo', args: ['title'] },
  // design system do projeto (lib/widgets/bora/)
  BoraScreenAppBar: { tipo: 'titulo', args: ['title'] },
  BoraAppBar: { tipo: 'titulo', args: ['title'] },
  BoraPrimaryButton: { tipo: 'botao', args: ['label'] },
  BoraAccentButton: { tipo: 'botao', args: ['label'] },
  BoraTileCard: { tipo: 'menu', args: ['label'] },
  BoraSeparador: { tipo: 'separador', args: ['rotulo'] },
  _NavSpec: { tipo: 'separador', args: ['label'] },
};

const PARAMS_TEXTO = ['label', 'rotulo', 'texto', 'text', 'titulo', 'title'];

function tipoPorNomeDeClasse(nome) {
  if (/(Button|Botao|Btn|Fab)/i.test(nome)) return 'botao';
  if (/Chip/.test(nome)) return 'botao';
  if (/Separador|Tab(?!le)|Nav/.test(nome)) return 'separador';
  if (/Tile/.test(nome)) return 'menu';
  return null;
}

// ---------------------------------------------------------------------------
// 4. Ficheiros, classes, imports
// ---------------------------------------------------------------------------

function listarDart(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) { if (e.name.startsWith('.')) continue; listarDart(p, out); }
    else if (e.name.endsWith('.dart')) out.push(p);
  }
  return out;
}

const rx = (p) => p.split(path.sep).join('/');

function segmentarClasses(skel) {
  const re = /\b(?:abstract\s+|final\s+|base\s+|sealed\s+|interface\s+)*class\s+(\w+)([^{;]*)\{/g;
  const out = [];
  let m;
  while ((m = re.exec(skel))) {
    const open = m.index + m[0].length - 1;
    const close = matchClose(skel, open);
    if (close < 0) continue;
    const cab = m[2];
    const state = /extends\s+\w*State<\s*(\w+)\s*>/.exec(cab);
    const widget = /extends\s+(?:\w*Widget|\w*State<)/.test(cab) || /extends\s+\w*Widget\b/.test(cab);
    out.push({ nome: m[1], ini: m.index, fim: close, open, donoState: state ? state[1] : null, widget, corpo: [open, close] });
    re.lastIndex = close;
  }
  return out;
}

const semUnderscore = (n) => n.replace(/^_+/, '');

// ---------------------------------------------------------------------------
// 5. Análise de um ficheiro
// ---------------------------------------------------------------------------

function construirRegexChamadas(kinds) {
  const nomes = Object.keys(kinds).sort((a, b) => b.length - a.length);
  const alt = nomes.map((n) => n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|');
  // (?<![\w.$]) evita apanhar `Foo.TextButton` e `CheckboxListTile`
  return new RegExp(`(?<![\\w$.])(${alt})(?:\\.(\\w+))?\\s*(?:<[^>()]*>)?\\s*\\(`, 'g');
}

/** Textos visíveis dentro de um valor: os Text('…') que ele contém, ou o próprio literal. */
function textosDe(code, skel, va, vb, consts) {
  const sub = skel.slice(va, vb);
  const out = [];
  const re = /(?<![\w$.])(?:Text|AutoSizeText)\s*\(/g;
  let m;
  let achouText = false;
  while ((m = re.exec(sub))) {
    achouText = true;
    const open = va + m.index + m[0].length - 1;
    const close = matchClose(skel, open);
    if (close < 0 || close > vb) continue;
    const args = splitArgs(skel, open, close);
    const pos = args.find((x) => x.nome === null);
    if (!pos) continue;
    out.push(...resolverExpr(code, skel, pos.va, pos.vb, consts));
    re.lastIndex = close - va;
  }
  if (!achouText) out.push(...resolverExpr(code, skel, va, vb, consts));
  return out;
}

// ---------------------------------------------------------------------------
// 6. Gerar o mapa
// ---------------------------------------------------------------------------

function lerVersao(raiz) {
  try {
    const t = fs.readFileSync(path.join(raiz, 'pubspec.yaml'), 'utf8');
    const m = /^version:\s*(\S+)/m.exec(t);
    return m ? m[1] : 'desconhecida';
  } catch { return 'desconhecida'; }
}

function lerNomePacote(raiz) {
  try {
    const t = fs.readFileSync(path.join(raiz, 'pubspec.yaml'), 'utf8');
    const m = /^name:\s*(\S+)/m.exec(t);
    return m ? m[1] : null;
  } catch { return null; }
}

function appPorPasta(rel) {
  const r = rel;
  const base = r.split('/').pop();
  if (/^lib\/(?:screens|widgets)\/admin\//.test(r) || base.startsWith('admin_')) return ['admin'];
  if (/^lib\/screens\/client\//.test(r)) return ['cliente'];
  if (/^lib\/screens\/(?:partner)\//.test(r) || /^lib\/widgets\/partner\//.test(r)) return ['parceiro'];
  if (/^lib\/screens\/(?:driver|cleaner|washer|handyman)\//.test(r)) return ['estafeta'];
  if (/^lib\/screens\/(?:farmacia|impressao|market)\//.test(r)) return ['cliente'];
  if (/^client_/.test(base)) return ['cliente'];
  if (/^(?:driver_|ganhos_)/.test(base)) return ['estafeta'];
  if (/^(?:partner_|register_partner|restaurant_|parceiro_)/.test(base)) return ['parceiro'];
  // ecrãs soltos em lib/screens/ sem prefixo (carrinho, pedidos, perfil, login...):
  // são os ecrãs-base da app do cliente, partilhados pelos outros papéis.
  if (/^lib\/screens\/[^/]+\.dart$/.test(r)) return ['cliente'];
  return null;
}

export function gerarMapa(raiz) {
  raiz = path.resolve(raiz);
  const libDir = path.join(raiz, 'lib');
  if (!fs.existsSync(libDir)) throw new Error(`Não existe ${libDir}`);
  const versao = lerVersao(raiz);
  const pacote = lerNomePacote(raiz);
  const ficheiros = listarDart(libDir).map((p) => ({ abs: p, rel: rx(path.relative(raiz, p)) })).sort((a, b) => a.rel.localeCompare(b.rel));

  const ignorados = []; // {rel, motivo}
  const textos = new Map();
  const lexados = new Map();
  for (const f of ficheiros) {
    if (/\.(?:g|freezed)\.dart$/.test(f.rel)) { ignorados.push({ rel: f.rel, motivo: 'ficheiro gerado' }); continue; }
    if (f.rel.startsWith('lib/l10n/')) { ignorados.push({ rel: f.rel, motivo: 'dicionário de traduções (não é ecrã)' }); continue; }
    const t = fs.readFileSync(f.abs, 'utf8');
    textos.set(f.rel, t);
  }

  // 6.1 pré-passagem: constantes String, rotas, botões do design system, imports
  const consts = new Map();
  const conflitos = new Set();
  const kinds = { ...KINDS_BASE };
  const customDescobertos = [];
  const rotas = new Map(); // classe -> rota
  const importadoPor = new Map(); // rel -> Set(rel)
  const importes = new Map();
  const reImp = /^\s*(?:import|export)\s+['"]([^'"]+)['"]/gm;

  for (const [rel, t] of textos) {
    const lx = lex(t);
    lexados.set(rel, lx);
    // constantes
    const reC = /(?:static\s+)?(?:const|final)\s+String\s+(\w+)\s*=\s*(['"])/g;
    let m;
    while ((m = reC.exec(lx.skel))) {
      const iniLit = m.index + m[0].length - 1;
      const l = lerLiteral(lx.code, iniLit);
      const nome = m[1];
      if (consts.has(nome) && consts.get(nome) !== l.valor) conflitos.add(nome);
      consts.set(nome, l.valor);
    }
    // rotas `'/x': (_) => const Foo(`
    const reR = /['"](\/[\w\-/:]*)['"]\s*:\s*\(\s*\w*\s*\)\s*=>\s*(?:const\s+)?(\w+)/g;
    while ((m = reR.exec(lx.code))) if (!rotas.has(m[2])) rotas.set(m[2], m[1]);
    // classes de botão/tile/chip do projeto
    for (const c of segmentarClasses(lx.skel)) {
      if (kinds[c.nome] || /State$/.test(c.nome) || !c.widget) continue;
      const tipo = tipoPorNomeDeClasse(semUnderscore(c.nome));
      if (!tipo) continue;
      const corpo = lx.skel.slice(c.open, c.fim);
      let param = null;
      for (const p of PARAMS_TEXTO) {
        if (new RegExp(`final\\s+(?:String|Text)\\??\\s+${p}\\b`).test(corpo)) { param = p; break; }
      }
      if (param) { kinds[c.nome] = { tipo, args: [param] }; customDescobertos.push(`${c.nome}(${param}) → ${tipo}`); }
    }
    // imports (só dentro de lib/)
    const set = new Set();
    while ((m = reImp.exec(lx.code))) {
      const alvo = m[1];
      let res = null;
      if (alvo.startsWith('package:')) {
        if (pacote && alvo.startsWith(`package:${pacote}/`)) res = `lib/${alvo.slice(`package:${pacote}/`.length)}`;
      } else if (!alvo.startsWith('dart:')) {
        res = rx(path.relative(raiz, path.resolve(path.dirname(path.join(raiz, rel)), alvo)));
      }
      if (res && textos.has(res)) set.add(res);
    }
    importes.set(rel, set);
    for (const alvo of set) {
      if (!importadoPor.has(alvo)) importadoPor.set(alvo, new Set());
      importadoPor.get(alvo).add(rel);
    }
  }
  for (const nome of conflitos) consts.delete(nome);

  // 6.2 menu do painel admin (admin_menu_registry.dart): título, id, ecrã de destino
  const menus = []; // {id, titulo, destino, secao}
  const regRel = 'lib/screens/admin/admin_menu_registry.dart';
  if (lexados.has(regRel)) {
    const { code, skel } = lexados.get(regRel);
    const re = /(?<![\w$.])(AdminMenuItem|AdminMenuSection)\s*\(/g;
    let m;
    while ((m = re.exec(skel))) {
      const open = m.index + m[0].length - 1;
      const close = matchClose(skel, open);
      if (close < 0) continue;
      const args = splitArgs(skel, open, close);
      const get = (n) => args.find((a) => a.nome === n);
      const id = get('id');
      const title = get('title');
      if (!id || !title) continue;
      const idv = resolverExpr(code, skel, id.va, id.vb, consts)[0];
      const tv = limparTexto(resolverExpr(code, skel, title.va, title.vb, consts)[0] ?? '');
      if (!idv || !tv) continue;
      let destino = null;
      const b = get('builder');
      if (b) { const bm = /=>\s*(?:const\s+)?(\w+)/.exec(code.slice(b.va, b.vb)); if (bm) destino = bm[1]; }
      menus.push({ id: idv, titulo: tv, destino, secao: m[1] === 'AdminMenuSection' });
    }
    for (const mm of menus) if (mm.destino && !mm.secao && !rotas.has(mm.destino)) rotas.set(mm.destino, `menu:${mm.id}`);
  }

  // 6.3 análise de cada ficheiro
  const regexChamadas = construirRegexChamadas(kinds);
  const analise = new Map();
  let dinamicosTotal = 0;
  for (const [rel] of textos) {
    const lx = lexados.get(rel);
    // analisarFicheiro volta a lexar: evitar duplo trabalho passando o já lexado
    const r = analisarLexado(rel, lx, kinds, regexChamadas, consts);
    analise.set(rel, r);
    dinamicosTotal += r.dinamicos;
  }

  // 6.4 apps de cada ficheiro (pasta/prefixo; senão pelo uso)
  const apps = new Map(); // rel -> Set(app)
  const semente = new Set();
  for (const rel of textos.keys()) {
    const p = appPorPasta(rel);
    if (p) { apps.set(rel, new Set(p)); semente.add(rel); }
  }
  // Quem não tem app pela pasta/prefixo herda a dos ficheiros que o importam.
  // Os ecrãs do admin importam muita coisa do cliente só para a mostrar: contam
  // só se mais ninguém importar o ficheiro.
  const soAdmin = (s) => s && s.size === 1 && s.has('admin');
  let mudou = true;
  let voltas = 0;
  while (mudou && voltas++ < 30) {
    mudou = false;
    for (const rel of textos.keys()) {
      if (semente.has(rel)) continue;
      const imps = [...(importadoPor.get(rel) ?? [])];
      let novo = new Set();
      for (const imp of imps) if (!soAdmin(apps.get(imp))) for (const a of apps.get(imp) ?? []) novo.add(a);
      if (!novo.size) for (const imp of imps) for (const a of apps.get(imp) ?? []) novo.add(a);
      const atual = apps.get(rel) ?? new Set();
      if (novo.size !== atual.size || [...novo].some((a) => !atual.has(a))) { apps.set(rel, novo); mudou = true; }
    }
  }

  // 6.5 montar elementos
  const elementos = new Map(); // chave -> elemento
  const ecrasPorApp = Object.fromEntries(APPS.map((a) => [a, new Set()]));
  const compPorApp = Object.fromEntries(APPS.map((a) => [a, new Set()]));
  const motivosIgn = [];

  for (const [rel, r] of analise) {
    const { classes, brutos } = r;
    const listaApps = [...(apps.get(rel) ?? [])];
    const ecrasDoFicheiro = classes.filter((c) => c.widget && !c.donoState && SUFIXO_ECRA.test(semUnderscore(c.nome)));
    const publicas = classes.filter((c) => c.widget && !c.donoState && !c.nome.startsWith('_'));
    const primario = ecrasDoFicheiro[0] ?? publicas[0] ?? null;
    const temConteudo = brutos.length > 0 || ecrasDoFicheiro.length > 0;
    if (!temConteudo) continue;
    if (!listaApps.length) {
      motivosIgn.push({ rel, motivo: 'app desconhecida (nenhum ecrã de uma app importa este ficheiro e a pasta não diz)' });
      continue;
    }
    for (const c of ecrasDoFicheiro) for (const a of listaApps) ecrasPorApp[a].add(semUnderscore(c.nome));
    if (!ecrasDoFicheiro.length && primario) for (const a of listaApps) compPorApp[a].add(semUnderscore(primario.nome));
    if (!brutos.length) continue;
    if (!primario) { motivosIgn.push({ rel, motivo: 'tem textos mas nenhuma classe de ecrã/widget público' }); continue; }
    for (const b of brutos) {
      const seg = classes.find((c) => b.pos >= c.ini && b.pos <= c.fim);
      const dono = seg ? (seg.donoState ?? seg.nome) : null;
      let ecra;
      if (dono && SUFIXO_ECRA.test(semUnderscore(dono))) ecra = semUnderscore(dono);
      else if (!ecrasDoFicheiro.length && dono && !dono.startsWith('_')) ecra = dono;
      else ecra = semUnderscore(primario.nome);
      const rota = rotas.get(ecra) ?? null;
      for (const a of listaApps) {
        const chave = `${a}\u0000${ecra}\u0000${b.elemento}`;
        const ex = elementos.get(chave);
        if (!ex) elementos.set(chave, { app: a, ecra, rota, elemento: b.elemento, tipo: b.tipo, ficheiro: rel });
        else {
          if (TIPO_PRIO[b.tipo] < TIPO_PRIO[ex.tipo]) ex.tipo = b.tipo;
          if (!ex.rota && rota) ex.rota = rota;
        }
      }
    }
  }

  // entradas do menu do admin
  for (const mm of menus) {
    const chave = `admin\u0000AdminMenu\u0000${mm.titulo}`;
    if (!elementos.has(chave)) {
      elementos.set(chave, { app: 'admin', ecra: 'AdminMenu', rota: `menu:${mm.id}`, elemento: mm.titulo, tipo: 'menu', ficheiro: regRel });
    }
  }
  if (menus.length) ecrasPorApp.admin.add('AdminMenu');

  const lista = [...elementos.values()].sort((a, b) =>
    a.app.localeCompare(b.app) || a.ecra.localeCompare(b.ecra) || a.elemento.localeCompare(b.elemento));

  return { versao, elementos: lista, ecrasPorApp, compPorApp, ignorados: [...ignorados, ...motivosIgn], dinamicos: dinamicosTotal, custom: customDescobertos, ficheirosLidos: textos.size };
}

export function analisarLexado(rel, lx, kinds, regexChamadas, consts) {
  // mesma lógica de analisarFicheiro, mas sem lexar outra vez
  const { code, skel } = lx;
  const classes = segmentarClasses(skel);
  const brutos = [];
  let dinamicos = 0;
  regexChamadas.lastIndex = 0;
  let m;
  while ((m = regexChamadas.exec(skel))) {
    const kind = kinds[m[1]];
    const antes = skel.slice(Math.max(0, m.index - 12), m.index);
    if (/\b(?:class|extends|implements|with)\s+$/.test(antes)) continue;
    const open = m.index + m[0].length - 1;
    const close = matchClose(skel, open);
    if (close < 0) continue;
    const args = splitArgs(skel, open, close);
    for (const alvo of kind.args) {
      const arg = args.find((x) => x.nome === alvo);
      if (!arg) continue;
      const achados = textosDe(code, skel, arg.va, arg.vb, consts);
      if (!achados.length) { dinamicos++; continue; }
      for (const t of achados.slice(0, 4)) {
        const limpo = limparTexto(t);
        if (limpo) brutos.push({ pos: m.index, elemento: limpo, tipo: kind.tipo });
        else dinamicos++;
      }
    }
  }
  return { classes, brutos, dinamicos };
}

// ---------------------------------------------------------------------------
// 7. Saídas
// ---------------------------------------------------------------------------

const sqlTxt = (s) => `'${String(s).replace(/\u0000/g, '').replace(/'/g, "''")}'`;
const sqlNullTxt = (s) => (s == null ? 'null' : sqlTxt(s));

export function gerarSql(elementos, versao) {
  const linhas = [];
  linhas.push('-- Mapa da app do Bora (gerado por ferramentas/hermes-diretor/gerar_mapa_app.mjs).');
  linhas.push(`-- Versão do pubspec: ${versao}. Elementos: ${elementos.length}.`);
  linhas.push('-- Aplicar só quem decide; o DELETE do fim está comentado de propósito.');
  linhas.push('');
  for (let i = 0; i < elementos.length; i += 200) {
    const lote = elementos.slice(i, i + 200);
    linhas.push('insert into public.mapa_app (app, ecra, rota, elemento, tipo, ficheiro, versao, atualizado_em) values');
    linhas.push(lote.map((e) =>
      `(${sqlTxt(e.app)}, ${sqlTxt(e.ecra)}, ${sqlNullTxt(e.rota)}, ${sqlTxt(e.elemento)}, ${sqlTxt(e.tipo)}, ${sqlTxt(e.ficheiro)}, ${sqlTxt(versao)}, now())`).join(',\n'));
    linhas.push('on conflict (app, ecra, elemento) do update set rota=excluded.rota, tipo=excluded.tipo, ficheiro=excluded.ficheiro, versao=excluded.versao, atualizado_em=now();');
    linhas.push('');
  }
  linhas.push('-- Limpar o que já não existe nesta versão (descomentar só depois de conferir):');
  linhas.push(`-- delete from public.mapa_app where versao is distinct from ${sqlTxt(versao)};`);
  linhas.push('');
  return linhas.join('\n');
}

export function resumo(r) {
  const out = [];
  out.push(`Versão do pubspec: ${r.versao}`);
  out.push(`Ficheiros Dart lidos: ${r.ficheirosLidos}`);
  out.push(`Elementos (sem duplicados): ${r.elementos.length}`);
  out.push('');
  out.push('Por app: ecrãs | componentes | elementos');
  const tipos = ['botao', 'menu', 'separador', 'titulo'];
  for (const a of APPS) {
    const els = r.elementos.filter((e) => e.app === a);
    const porTipo = tipos.map((t) => `${t}=${els.filter((e) => e.tipo === t).length}`).join(' ');
    out.push(`  ${a.padEnd(9)} ecrãs=${r.ecrasPorApp[a].size} componentes=${r.compPorApp[a].size} elementos=${els.length} (${porTipo})`);
  }
  out.push('');
  const porTipoTotal = tipos.map((t) => `${t}=${r.elementos.filter((e) => e.tipo === t).length}`).join(' ');
  out.push(`Por tipo (total): ${porTipoTotal}`);
  out.push(`Textos não resolvidos (dinâmicos/técnicos), não entram: ${r.dinamicos}`);
  out.push(`Botões/tiles do design system descobertos: ${r.custom.length}`);
  const motivos = new Map();
  for (const i of r.ignorados) { if (!motivos.has(i.motivo)) motivos.set(i.motivo, []); motivos.get(i.motivo).push(i.rel); }
  out.push(`Ficheiros ignorados: ${r.ignorados.length}`);
  for (const [mot, fs_] of motivos) {
    out.push(`  - ${mot}: ${fs_.length}`);
    for (const f of fs_.slice(0, 8)) out.push(`      ${f}`);
    if (fs_.length > 8) out.push(`      … e mais ${fs_.length - 8}`);
  }
  return out.join('\n');
}

// ---------------------------------------------------------------------------
// 8. CLI
// ---------------------------------------------------------------------------

function main(argv) {
  const args = argv.slice(2);
  if (!args.length || args[0].startsWith('--')) {
    console.error('Uso: node gerar_mapa_app.mjs <raiz-do-repo> [--json saida.json] [--sql saida.sql]');
    process.exit(2);
  }
  const raiz = args[0];
  let jsonOut = null, sqlOut = null;
  for (let i = 1; i < args.length; i++) {
    if (args[i] === '--json') jsonOut = args[++i];
    else if (args[i] === '--sql') sqlOut = args[++i];
    else { console.error(`Argumento desconhecido: ${args[i]}`); process.exit(2); }
  }
  const r = gerarMapa(raiz);
  if (jsonOut) {
    fs.mkdirSync(path.dirname(path.resolve(jsonOut)), { recursive: true });
    fs.writeFileSync(jsonOut, JSON.stringify(r.elementos, null, 1) + '\n', 'utf8');
  }
  if (sqlOut) {
    fs.mkdirSync(path.dirname(path.resolve(sqlOut)), { recursive: true });
    fs.writeFileSync(sqlOut, gerarSql(r.elementos, r.versao), 'utf8');
  }
  console.log(resumo(r));
  if (jsonOut) console.log(`\nJSON: ${jsonOut}`);
  if (sqlOut) console.log(`SQL:  ${sqlOut}`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv);
