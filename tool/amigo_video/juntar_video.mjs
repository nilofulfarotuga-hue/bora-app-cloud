// Junta as imagens do gravador (gravar_amigo_test.dart) com as falas, num MP4.
// Uso: node tool/amigo_video/juntar_video.mjs <pasta-das-imagens> <saida.mp4>
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';

const [pasta, saida] = process.argv.slice(2);
const j = JSON.parse(readFileSync(join(pasta, 'faixas.json'), 'utf8'));
const args = ['-v', 'error', '-y', '-framerate', String(1000 / j.quadro_ms), '-i', join(pasta, 'q_%05d.png')];
const filtros = [];
j.faixas.forEach((f, i) => {
  args.push('-i', f.audio);
  const ms = Math.round(f.t0);
  filtros.push(`[${i + 1}:a]adelay=${ms}|${ms},aformat=channel_layouts=stereo[a${i}]`);
});
filtros.push(`${j.faixas.map((_, i) => `[a${i}]`).join('')}amix=inputs=${j.faixas.length}:normalize=0:duration=longest[aout]`);
args.push('-filter_complex', filtros.join(';'), '-map', '0:v', '-map', '[aout]',
  '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '23', '-preset', 'medium',
  '-c:a', 'aac', '-b:a', '128k', '-t', String(j.quadros * j.quadro_ms / 1000), saida);
const r = spawnSync('ffmpeg', args, { stdio: 'inherit' });
process.exit(r.status ?? 1);
