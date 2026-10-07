// audio.js — D1 v2 "Bora Assistente": 15 s, 120 bpm, Sol maior; eventos do beatgrid.md
const path = require('path'); const fs = require('fs');
const S = require('../_tools/synth.js');
const DUR = 15; const B = 0.5;
const music = new S.Track(DUR), sfx = new S.Track(DUR);
const chords = [['G3', 'B3', 'D4'], ['E3', 'G3', 'B3'], ['C3', 'E3', 'G3'], ['D3', 'F#3', 'A3']];
const roots = ['G2', 'E2', 'C2', 'D2'];
for (let bar = 0; bar < 6; bar++) {
  const t = bar * 2, ch = chords[bar % 4];
  music.add(S.pad(ch, 2.3, { cutoff: 1100, a: 0.4, r: 0.6 }), t, 0.27);
  music.add(S.bass(roots[bar % 4], 0.45), t, 0.42); music.add(S.bass(roots[bar % 4], 0.25), t + 1.5, 0.3);
  if (bar >= 1) for (const n of ch) { music.add(S.keys(n, 0.35), t + 1.0, 0.16); music.add(S.keys(n, 0.35), t + 1.75, 0.12); }
}
for (let t = 0; t <= 12; t += 1) music.add(S.kick(0.35), t, (t === 10 || t === 6) ? 0.95 : 0.72);
for (let t = 1.5; t < 12.5; t += 0.5) music.add(S.hat(0.06), t + 0.25, 0.22);
for (let t = 4.5; t < 12; t += 1) music.add(S.clap(0.2), t, 0.24);
const arp = ['G4', 'B4', 'D5', 'G5'];
for (let i = 0, t = 8; t < 10; t += B, i++) music.add(S.bell(arp[i % 4], 0.9, { tau: 0.3 }), t, 0.2, i % 2 ? 0.35 : -0.35);
for (const [t, n] of [[0.75, 'G4'], [2.0, 'B4'], [6.0, 'D5'], [10.0, 'G4']]) music.add(S.pluck(n, 0.6), t, 0.4);
music.add(S.pad(['G3', 'B3', 'D4', 'G4'], 2.6, { cutoff: 1600, a: 0.05, r: 1.4 }), 12.5, 0.34);
music.add(S.bass('G2', 1.2), 12.5, 0.45);
music.add(S.bell('G5', 2.0, { tau: 0.7 }), 13.75, 0.25); music.add(S.bell('B5', 2.0, { tau: 0.7 }), 13.75, 0.18, 0.3);
music.reverb(0.12);
music.gainCurve(t => t > 14.2 ? Math.max(0, 1 - (t - 14.2) / 0.8) : 1);

sfx.add(S.pop({ f0: 700, f1: 220 }), 0.0, 0.8);
sfx.add(S.whoosh(0.45), 1.25, 0.55); sfx.add(S.pop(), 1.6, 0.6);
for (let i = 0; i < 26; i++) sfx.add(S.tick(), 2.5 + i * (1.75 / 26), 0.5);
sfx.add(S.pop({ f0: 900, f1: 300 }), 4.5, 0.75);
sfx.add(S.pop(), 6.0, 0.7); sfx.add(S.pop({ f0: 1000, f1: 280 }), 6.5, 0.7); sfx.add(S.pop({ f0: 1100, f1: 300 }), 7.0, 0.7);
sfx.add(S.ding('A5', 1.0), 7.5, 0.6);
sfx.add(S.pop({ f0: 800, f1: 260 }), 10.0, 0.85);
sfx.add(S.pop(), 11.0, 0.75); sfx.add(S.bell('D5', 0.6), 11.08, 0.3);
sfx.add(S.ding('E6', 1.0), 11.5, 0.55);
sfx.add(S.whoosh(0.5), 12.2, 0.55);
sfx.add(S.pop({ f0: 520, f1: 200 }), 13.0, 0.7); sfx.add(S.pop({ f0: 650, f1: 240 }), 13.25, 0.7); sfx.add(S.pop({ f0: 800, f1: 300 }), 13.5, 0.7);
sfx.reverb(0.08);
music.mixIn(sfx, 1.0);
fs.mkdirSync(path.join(__dirname, 'out'), { recursive: true });
console.log('OK', music.write(path.join(__dirname, 'out', 'assistente_audio.wav')));
