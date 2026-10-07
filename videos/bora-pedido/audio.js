// audio.js — D1 "Pedido a caminho": música 120 bpm em Sol + efeitos nos cortes do beatgrid.md
const path = require('path'); const fs = require('fs');
const S = require('../_tools/synth.js');
const DUR = 25; const BPM = 120; const B = 60 / BPM; // 0.5 s
const music = new S.Track(DUR), sfx = new S.Track(DUR);

// --- harmonia: G – Em – C – D, 1 acorde por compasso (2 s)
const chords = [['G3', 'B3', 'D4'], ['E3', 'G3', 'B3'], ['C3', 'E3', 'G3'], ['D3', 'F#3', 'A3']];
const roots = ['G2', 'E2', 'C2', 'D2'];
for (let bar = 0; bar < 12; bar++) {
  const t = bar * 2; const ch = chords[bar % 4];
  // pad suave (mais baixo nas cenas com voz de texto)
  const g = bar >= 11 ? 0.0 : 0.27;
  if (g > 0) music.add(S.pad(ch, 2.3, { cutoff: 1100, a: 0.4, r: 0.6 }), t, g);
  // baixo: tempo 1 e "e" do 3
  music.add(S.bass(roots[bar % 4], 0.45), t, 0.42);
  music.add(S.bass(roots[bar % 4], 0.25), t + 1.5, 0.3);
  // teclas: acorde curto no tempo 2 e 4 (off), só a partir do compasso 2
  if (bar >= 1 && bar < 11) { for (const n of ch) { music.add(S.keys(n, 0.35), t + 1.0, 0.16); music.add(S.keys(n, 0.35), t + 1.75, 0.12); } }
}
// kicks nos tempos 1 e 3 (t inteiro), de 0 a 23; mais forte em 10 e 16
for (let t = 0; t <= 23; t += 1) music.add(S.kick(0.35), t, (t === 10 || t === 16) ? 0.95 : 0.72);
// hats nos contratempos de 2 a 23
for (let t = 2; t < 23.5; t += 0.5) { music.add(S.hat(0.06), t + 0.25, 0.22); if (Math.floor(t) % 2 === 1) music.add(S.hat(0.08, true), t + 0.5 - 0.01, 0.1); }
// palmas no tempo 2 e 4 (t = x.5 impar) entre 6 e 22
for (let t = 6.5; t < 22; t += 1) music.add(S.clap(0.2), t, 0.26);
// sinos em arpejo durante a viagem (10–16): um por tempo
const arp = ['G4', 'B4', 'D5', 'G5', 'D5', 'B4'];
for (let i = 0, t = 10; t < 16; t += B, i++) music.add(S.bell(arp[i % arp.length], 0.9, { tau: 0.3 }), t, 0.2, (i % 2 ? 0.35 : -0.35));
// pluck da melodia nas entradas de texto (do beatgrid)
const plucks = [[1.0, 'G4'], [3.5, 'B4'], [7.0, 'G4'], [13.0, 'D5'], [17.25, 'B4'], [19.5, 'G4']];
for (const [t, n] of plucks) music.add(S.pluck(n, 0.6), t, 0.42);
// acorde final em 22.0 (Sol) e cauda até 25
music.add(S.pad(['G3', 'B3', 'D4', 'G4'], 3.0, { cutoff: 1600, a: 0.05, r: 1.6 }), 22.0, 0.34);
music.add(S.bass('G2', 1.2), 22.0, 0.45);
music.add(S.bell('G5', 2.2, { tau: 0.7 }), 23.5, 0.25);
music.add(S.bell('B5', 2.2, { tau: 0.7 }), 23.5, 0.18, 0.3);
music.reverb(0.12);
// curva de volume: desce na frase/código (18.5–22) e cauda final
music.gainCurve(t => (t > 18.5 && t < 22 ? 0.8 : 1) * (t > 24.2 ? Math.max(0, 1 - (t - 24.2) / 0.8) : 1));

// --- efeitos (beatgrid)
sfx.add(S.pop({ f0: 700, f1: 220 }), 0.0, 0.8);           // logo salta
sfx.add(S.whoosh(0.5), 1.72, 0.55);                        // corte 2.0 (o whoosh culmina no corte)
sfx.add(S.pop(), 3.0, 0.75);                               // toque tile
sfx.add(S.pop(), 5.0, 0.75); sfx.add(S.bell('D5', 0.6), 5.08, 0.3); // adicionar + badge
sfx.add(S.ding('A5', 1.2), 6.0, 0.7);                      // confirmado
sfx.add(S.whoosh(0.5, { down: true }), 8.75, 0.6);         // corte 9.0 → mapa
sfx.add(S.pop({ f0: 600, f1: 200 }), 9.5, 0.7);            // pino loja
sfx.add(S.riser(0.9), 9.1, 0.35);                          // arranque 10.0
sfx.add(S.whoosh(0.35), 9.9, 0.4);                         // mota arranca
sfx.add(S.tick(), 14.0, 0.5); sfx.add(S.bell('E5', 0.5), 14.0, 0.25); // ETA
sfx.add(S.pop({ f0: 600, f1: 200 }), 16.0, 0.8);           // pino casa / travagem
sfx.add(S.ding('E6', 1.2), 16.5, 0.6);                     // notificação
sfx.add(S.whoosh(0.5), 18.2, 0.55);                        // corte 18.5
sfx.add(S.bell('G5', 1.0), 18.75, 0.4);                    // Olá!
sfx.add(S.pop({ f0: 800, f1: 260 }), 20.5, 0.8); sfx.add(S.ding('A5', 1.0), 20.55, 0.45); // código
sfx.add(S.pop({ f0: 520, f1: 200 }), 22.5, 0.7); sfx.add(S.pop({ f0: 650, f1: 240 }), 22.75, 0.7); sfx.add(S.pop({ f0: 800, f1: 300 }), 23.0, 0.7); // badges
sfx.reverb(0.08);

music.mixIn(sfx, 1.0);
fs.mkdirSync(path.join(__dirname, 'out'), { recursive: true });
const f = music.write(path.join(__dirname, 'out', 'pedido_audio.wav'));
console.log('OK', f);
