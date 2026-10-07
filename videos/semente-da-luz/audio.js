// audio.js — leitos sintetizados dos 4 clips; o mix.sh junta com o tema real, sfx reais e falas reais (ffmpeg).
const path = require('path'); const fs = require('fs');
const S = require('../_tools/synth.js');
const out = path.join(__dirname, 'out'); fs.mkdirSync(out, { recursive: true });

// abertura: drone grave 0–2.6 s (só até o tema entrar)
{ const tr = new S.Track(12);
  tr.add(S.pad(['D2', 'A2', 'D3'], 3.0, { cutoff: 400, a: 0.6, r: 0.6 }), 0, 0.5);
  tr.add(S.riser(1.2), 1.3, 0.35);
  tr.reverb(0.2); tr.write(path.join(out, 'bed_abertura.wav'), { normalize: 0.5 }); }

// fecho: nada sintetizado (tema real)

// s02: vento + drone + risers
{ const tr = new S.Track(10);
  const wind = S.lowpass(S.highpass(S.noise(10), 150), p => 300 + 2500 * Math.pow(Math.sin(Math.PI * Math.min(1, p * 1.1)), 2));
  const env = new Float32Array(wind.length); for (let i = 0; i < env.length; i++) { const t = i / S.SR; env[i] = t < 0.6 ? t / 0.6 * 0.25 : (t < 9 ? 0.25 + 0.75 * Math.min(1, (t - 0.6) / 4) : Math.max(0, 1 - (t - 9))); }
  tr.add(S.mul(wind, env), 0, 0.5);
  tr.add(S.pad(['D2', 'A2', 'Eb3'], 10.5, { cutoff: 350, a: 1.0, r: 1.0 }), 0, 0.42);
  tr.add(S.riser(1.3), 1.0, 0.35); tr.add(S.riser(1.0), 4.4, 0.45); tr.add(S.kick(0.5, { f0: 90, f1: 35, tau: 0.25 }), 5.4, 0.8);
  tr.gainCurve(t => t > 9.2 ? Math.max(0, 1 - (t - 9.2) / 0.8) : 1);
  tr.reverb(0.25); tr.write(path.join(out, 'bed_s02.wav'), { normalize: 0.7 }); }

// s12: leito de teclas suave em Fá, sino quando a caixa brilha
{ const tr = new S.Track(10);
  tr.add(S.pad(['F3', 'A3', 'C4'], 5.5, { cutoff: 800, a: 0.8, r: 1.0 }), 0, 0.16);
  tr.add(S.pad(['Bb2', 'D3', 'F3', 'A3'], 5.5, { cutoff: 800, a: 0.8, r: 1.2 }), 5.0, 0.16);
  for (const [t, n] of [[0.3, 'F4'], [1.6, 'A4'], [2.9, 'C5'], [4.2, 'A4'], [5.6, 'F5'], [7.0, 'D5']]) tr.add(S.keys(n, 1.2), t, 0.12);
  tr.add(S.bell('A5', 2.5, { tau: 0.9 }), 5.6, 0.22); tr.add(S.bell('C6', 2.5, { tau: 0.9 }), 6.2, 0.16, 0.3);
  tr.gainCurve(t => t > 9.2 ? Math.max(0, 1 - (t - 9.2) / 0.8) : 1);
  tr.reverb(0.2); tr.write(path.join(out, 'bed_s12.wav'), { normalize: 0.55 }); }
console.log('OK beds');
