// synth.js — sintetizador mínimo em Node (sem dependências). Gera WAV 48 kHz estéreo 16-bit.
// Tudo nasce de sine/noise/envelope: kicks, hats, plucks, sinos, baixo, pad, whoosh, pop, ding, tick, riser.
const fs = require('fs');
const SR = 48000;

const NOTE = { C: 0, 'C#': 1, Db: 1, D: 2, 'D#': 3, Eb: 3, E: 4, F: 5, 'F#': 6, Gb: 6, G: 7, 'G#': 8, Ab: 8, A: 9, 'A#': 10, Bb: 10, B: 11 };
function freq(n) { if (typeof n === 'number') return n; const m = n.match(/^([A-G][#b]?)(-?\d)$/); const semi = NOTE[m[1]] + (parseInt(m[2]) + 1) * 12; return 440 * Math.pow(2, (semi - 69) / 12); }

function expDecay(n, tau) { const o = new Float32Array(n); for (let i = 0; i < n; i++) o[i] = Math.exp(-i / SR / tau); return o; }
function adsr(n, a, d, s, r) { const o = new Float32Array(n); const A = a * SR, D = d * SR, R = r * SR; for (let i = 0; i < n; i++) { let v; if (i < A) v = i / A; else if (i < A + D) v = 1 - (1 - s) * (i - A) / D; else if (i < n - R) v = s; else v = s * (n - i) / R; o[i] = Math.max(0, v); } return o; }
function lowpass(x, cutoff) { const o = new Float32Array(x.length); let y = 0; const fn = typeof cutoff === 'function' ? cutoff : () => cutoff; for (let i = 0; i < x.length; i++) { const c = fn(i / x.length); const a = 1 - Math.exp(-2 * Math.PI * c / SR); y += a * (x[i] - y); o[i] = y; } return o; }
function highpass(x, cutoff) { const lp = lowpass(x, cutoff); const o = new Float32Array(x.length); for (let i = 0; i < x.length; i++) o[i] = x[i] - lp[i]; return o; }
function mul(a, b) { const o = new Float32Array(a.length); for (let i = 0; i < a.length; i++) o[i] = a[i] * (typeof b === 'number' ? b : b[i]); return o; }
function mix(...xs) { const n = Math.max(...xs.map(x => x.length)); const o = new Float32Array(n); for (const x of xs) for (let i = 0; i < x.length; i++) o[i] += x[i]; return o; }

function osc(type, f, dur, opts = {}) {
  const n = Math.ceil(dur * SR); const o = new Float32Array(n); let ph = 0; const ff = typeof f === 'function' ? f : () => f; const det = opts.detune || 0;
  for (let i = 0; i < n; i++) { const fr = ff(i / n) * Math.pow(2, det / 1200); ph += fr / SR; const p = ph - Math.floor(ph);
    let v; switch (type) { case 'sine': v = Math.sin(2 * Math.PI * p); break; case 'tri': v = 4 * Math.abs(p - 0.5) - 1; break; case 'saw': v = 2 * p - 1; break; case 'square': v = p < 0.5 ? 1 : -1; break; default: v = Math.sin(2 * Math.PI * p); }
    o[i] = v; }
  return o;
}
function noise(dur) { const n = Math.ceil(dur * SR); const o = new Float32Array(n); for (let i = 0; i < n; i++) o[i] = Math.random() * 2 - 1; return o; }

// ---------- instrumentos ----------
function kick(dur = 0.35, opts = {}) { const n = Math.ceil(dur * SR); const f0 = opts.f0 || 160, f1 = opts.f1 || 48; const body = osc('sine', p => f1 + (f0 - f1) * Math.exp(-p * 18), dur); const env = expDecay(n, opts.tau || 0.11); const click = mul(highpass(noise(0.01), 2000), expDecay(Math.ceil(0.01 * SR), 0.003)); return mix(mul(body, env), mul(click, 0.25)); }
function hat(dur = 0.06, open = false) { const n = Math.ceil(dur * SR); return mul(highpass(noise(dur), 7000), expDecay(n, open ? 0.08 : 0.018)); }
function clap(dur = 0.2) { const n = Math.ceil(dur * SR); const b = highpass(lowpass(noise(dur), 6000), 900); const env = new Float32Array(n); for (let i = 0; i < n; i++) { const t = i / SR; env[i] = (t < 0.03 ? (t % 0.01) / 0.01 * 0.8 : Math.exp(-(t - 0.03) / 0.045)); } return mul(b, env); }
function pluck(note, dur = 0.5, opts = {}) { const f = freq(note); const n = Math.ceil(dur * SR); const o = mix(osc('tri', f, dur), mul(osc('sine', f * 2, dur), 0.35), mul(osc('sine', f * 3, dur), 0.12)); const filt = lowpass(o, p => 600 + 5000 * Math.exp(-p * 6)); return mul(filt, expDecay(n, opts.tau || 0.16)); }
function bell(note, dur = 1.2, opts = {}) { const f = freq(note); const n = Math.ceil(dur * SR); const o = mix(osc('sine', f, dur), mul(osc('sine', f * 2.0, dur), 0.4), mul(osc('sine', f * 3.01, dur), 0.18), mul(osc('sine', f * 4.2, dur), 0.08)); const env = new Float32Array(n); for (let i = 0; i < n; i++) { const t = i / SR; env[i] = Math.min(1, t / 0.004) * Math.exp(-t / (opts.tau || 0.45)); } return mul(o, env); }
function bass(note, dur = 0.4) { const f = freq(note); const n = Math.ceil(dur * SR); const o = mix(osc('saw', f, dur), mul(osc('sine', f, dur), 0.6)); return mul(lowpass(o, p => 180 + 900 * Math.exp(-p * 5)), adsr(n, 0.005, 0.12, 0.55, 0.08)); }
function pad(notes, dur, opts = {}) { const n = Math.ceil(dur * SR); let o = new Float32Array(n); for (const nt of notes) { const f = freq(nt); o = mix(o, osc('saw', f, dur, { detune: -7 }), osc('saw', f, dur, { detune: 7 }), mul(osc('sine', f, dur), 0.8)); } o = lowpass(o, opts.cutoff || 900); return mul(mul(o, 1 / (notes.length * 2.5)), adsr(n, opts.a || 0.6, 0.3, 0.8, opts.r || 0.8)); }
function keys(note, dur = 0.8) { const f = freq(note); const n = Math.ceil(dur * SR); const o = mix(osc('sine', f, dur), mul(osc('sine', f * 2, dur), 0.25), mul(osc('tri', f * 0.5, dur), 0.15)); return mul(lowpass(o, 2500), adsr(n, 0.01, 0.25, 0.5, 0.25)); }

// ---------- efeitos ----------
function whoosh(dur = 0.5, opts = {}) { const n = Math.ceil(dur * SR); const nz = noise(dur); const peak = opts.peak ?? 0.45; const env = new Float32Array(n); for (let i = 0; i < n; i++) { const p = i / n; env[i] = Math.pow(Math.sin(Math.PI * Math.min(1, p / peak * 0.5 + (p > peak ? (p - peak) / (1 - peak) * 0.5 : 0))), 1.6); } const filt = lowpass(highpass(nz, 300), p => (opts.down ? 5000 - 4200 * p : 600 + 5000 * Math.sin(Math.PI * p))); return mul(filt, env); }
function pop(opts = {}) { const dur = 0.09; const n = Math.ceil(dur * SR); const f0 = opts.f0 || 900, f1 = opts.f1 || 250; const o = osc('sine', p => f1 + (f0 - f1) * Math.exp(-p * 9), dur); return mul(o, expDecay(n, 0.02)); }
function ding(note = 'A5', dur = 1.0) { return bell(note, dur, { tau: 0.35 }); }
function tick() { const dur = 0.03; return mul(highpass(noise(dur), 3000), expDecay(Math.ceil(dur * SR), 0.004)); }
function riser(dur = 1.0) { const n = Math.ceil(dur * SR); const nz = lowpass(highpass(noise(dur), 200), p => 300 + 6000 * p * p); const env = new Float32Array(n); for (let i = 0; i < n; i++) env[i] = Math.pow(i / n, 2); return mul(nz, env); }
function swell(note, dur = 1.0) { const f = freq(note); const n = Math.ceil(dur * SR); const o = mix(osc('sine', f, dur), mul(osc('sine', f * 1.5, dur), 0.3)); const env = new Float32Array(n); for (let i = 0; i < n; i++) { const p = i / n; env[i] = Math.pow(Math.sin(Math.PI * p), 1.2); } return mul(o, env); }

// ---------- pista ----------
class Track {
  constructor(dur) { this.n = Math.ceil(dur * SR); this.L = new Float32Array(this.n); this.R = new Float32Array(this.n); }
  add(x, t, gain = 1, pan = 0) { const s = Math.round(t * SR); const gl = gain * Math.cos((pan + 1) * Math.PI / 4), gr = gain * Math.sin((pan + 1) * Math.PI / 4); for (let i = 0; i < x.length; i++) { const j = s + i; if (j < 0 || j >= this.n) continue; this.L[j] += x[i] * gl; this.R[j] += x[i] * gr; } return this; }
  gainCurve(fn) { for (let i = 0; i < this.n; i++) { const g = fn(i / SR); this.L[i] *= g; this.R[i] *= g; } return this; }
  mixIn(tr, gain = 1) { for (let i = 0; i < this.n; i++) { this.L[i] += tr.L[i] * gain; this.R[i] += tr.R[i] * gain; } return this; }
  delay(time, fb, wet) { const d = Math.round(time * SR); const L = new Float32Array(this.n), R = new Float32Array(this.n); for (let i = 0; i < this.n; i++) { const pl = i - d >= 0 ? L[i - d] : 0, pr = i - d >= 0 ? R[i - d] : 0; L[i] = this.L[i] + pl * fb; R[i] = this.R[i] + pr * fb; } for (let i = 0; i < this.n; i++) { const pl = i - d >= 0 ? L[i - d] : 0, pr = i - d >= 0 ? R[i - d] : 0; this.L[i] += pr * wet; this.R[i] += pl * wet; } return this; }
  reverb(wet = 0.18) { const taps = [0.0297, 0.0371, 0.0411, 0.0437, 0.0533, 0.0617]; const L = new Float32Array(this.n), R = new Float32Array(this.n); for (const tp of taps) { const d = Math.round(tp * SR); const fb = 0.72; const bl = new Float32Array(this.n), br = new Float32Array(this.n); for (let i = 0; i < this.n; i++) { bl[i] = this.L[i] + (i - d >= 0 ? bl[i - d] * fb : 0); br[i] = this.R[i] + (i - d >= 0 ? br[i - d] * fb : 0); } for (let i = 0; i < this.n; i++) { L[i] += bl[i] / taps.length; R[i] += br[i] / taps.length; } } const lL = lowpass(L, 3500), lR = lowpass(R, 3500); for (let i = 0; i < this.n; i++) { this.L[i] += lL[i] * wet; this.R[i] += lR[i] * wet; } return this; }
  write(file, { normalize = 0.89 } = {}) { let peak = 1e-6; for (let i = 0; i < this.n; i++) peak = Math.max(peak, Math.abs(this.L[i]), Math.abs(this.R[i])); const g = normalize / peak; const buf = Buffer.alloc(44 + this.n * 4); buf.write('RIFF', 0); buf.writeUInt32LE(36 + this.n * 4, 4); buf.write('WAVE', 8); buf.write('fmt ', 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(2, 22); buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 4, 28); buf.writeUInt16LE(4, 32); buf.writeUInt16LE(16, 34); buf.write('data', 36); buf.writeUInt32LE(this.n * 4, 40); for (let i = 0; i < this.n; i++) { const l = Math.tanh(this.L[i] * g * 1.15) / 1.15, r = Math.tanh(this.R[i] * g * 1.15) / 1.15; buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, l)) * 32767), 44 + i * 4); buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, r)) * 32767), 46 + i * 4); } fs.writeFileSync(file, buf); return file; }
}

module.exports = { SR, freq, Track, osc, noise, expDecay, adsr, lowpass, highpass, mul, mix, kick, hat, clap, pluck, bell, bass, pad, keys, whoosh, pop, ding, tick, riser, swell };
