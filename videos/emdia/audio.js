// audio.js — D2 Em Dia: 24 s, 90 bpm, Fá maior, tom tranquilo; eventos do beatgrid.md
const path = require('path'); const fs = require('fs');
const S = require('../_tools/synth.js');
const DUR = 24; const B = 60 / 90; const bar = n => n * 4 * B;
const music = new S.Track(DUR), sfx = new S.Track(DUR);
const chords = [['F3', 'A3', 'C4', 'E4'], ['A3', 'C4', 'E4', 'G4'], ['D3', 'F3', 'A3', 'C4'], ['Bb2', 'D3', 'F3', 'A3']];
const roots = ['F2', 'A2', 'D2', 'Bb1'];
for (let b = 0; b < 9; b++) {
  const t = bar(b), ch = chords[b % 4];
  music.add(S.pad(ch, bar(1) + 0.4, { cutoff: 900, a: 0.5, r: 0.7 }), t, 0.22);
  music.add(S.bass(roots[b % 4], 0.6), t, 0.3);
  if (b >= 1 && b < 7) { music.add(S.kick(0.3, { f0: 120, f1: 45, tau: 0.09 }), t, 0.45); music.add(S.hat(0.09, true), t + 2 * B, 0.08); music.add(S.hat(0.05), t + B, 0.06); music.add(S.hat(0.05), t + 3 * B, 0.06); }
  // teclas arpejadas: uma nota por tempo, suave
  if (b >= 1 && b < 7) for (let k = 0; k < 4; k++) music.add(S.keys(ch[(k + b) % 4], 0.7), t + k * B, 0.17, (k % 2 ? 0.25 : -0.25));
}
// melodia nas captions
for (const [t, n] of [[B, 'F4'], [2 * B, 'A4'], [bar(1), 'C5'], [bar(2.5), 'A4'], [bar(3), 'C5'], [bar(4), 'F4'], [bar(5.5), 'A4']]) music.add(S.pluck(n, 0.8, { tau: 0.22 }), t, 0.3);
// contador: sinos pequenos ascendentes
for (let i = 0; i < 16; i++) sfx.add(S.tick(), bar(5.5) + 0.4 + i * 0.09, 0.35);
music.add(S.bell('F5', 1.2, { tau: 0.5 }), bar(5.5) + 1.9, 0.28);
// fecho: Fmaj7 em 18.67, F em 21.33
music.add(S.pad(['F3', 'A3', 'C4', 'E4', 'F4'], 3.0, { cutoff: 1300, a: 0.1, r: 1.5 }), bar(7), 0.3);
music.add(S.kick(0.3, { f0: 120, f1: 45 }), bar(7), 0.5);
music.add(S.pad(['F3', 'A3', 'C4', 'F4'], 2.8, { cutoff: 1400, a: 0.05, r: 1.6 }), bar(8), 0.32);
music.add(S.bass('F2', 1.4), bar(8), 0.4);
music.add(S.bell('C6', 2.0, { tau: 0.8 }), bar(8) + B, 0.16, 0.3); music.add(S.bell('F5', 2.0, { tau: 0.8 }), bar(8) + B, 0.2, -0.2);
music.reverb(0.16);
music.gainCurve(t => t > 23.0 ? Math.max(0, 1 - (t - 23.0) / 1.0) : 1);

// efeitos
sfx.add(S.pop({ f0: 500, f1: 180 }), 0.0, 0.6);
sfx.add(S.whoosh(0.5, { peak: 0.6 }), bar(1) - 0.3, 0.4);
for (let i = 0; i < 4; i++) { sfx.add(S.pop({ f0: 600 + i * 120, f1: 220 }), bar(1) + B + i * B, 0.6); sfx.add(S.tick(), bar(1) + B + i * B + 2 * B, 0.5); sfx.add(S.bell(['F5', 'A5', 'C6', 'F6'][i], 0.5, { tau: 0.2 }), bar(1) + B + i * B + 2 * B, 0.16); }
sfx.add(S.whoosh(0.45, { peak: 0.6 }), bar(2.5) - 0.3, 0.4);
sfx.add(S.bell('C5', 0.8), bar(3), 0.3); sfx.add(S.bell('E5', 0.8), bar(3) + B, 0.25);
sfx.add(S.whoosh(0.45, { peak: 0.6 }), bar(4) - 0.3, 0.4);
sfx.add(S.ding('A5', 1.2), 12.0, 0.5);
sfx.add(S.whoosh(0.45, { peak: 0.6 }), bar(5.5) - 0.3, 0.4);
sfx.add(S.whoosh(0.5, { peak: 0.6 }), bar(7) - 0.3, 0.45); sfx.add(S.ding('F5', 1.5), bar(7) + 0.3, 0.5);
sfx.add(S.pop({ f0: 520, f1: 200 }), bar(8), 0.6); sfx.add(S.pop({ f0: 650, f1: 240 }), bar(8) + B / 2, 0.6);
sfx.reverb(0.1);
music.mixIn(sfx, 1.0);
fs.mkdirSync(path.join(__dirname, 'out'), { recursive: true });
console.log('OK', music.write(path.join(__dirname, 'out', 'emdia_audio.wav')));
