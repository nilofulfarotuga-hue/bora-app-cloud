// mux.js — frames + áudio → MP4 H.264 yuv420p 30 fps AAC.
// uso: node _tools/mux.js --frames dir --audio x.wav --out y.mp4 [--ext png|jpg] [--fps 30] [--crf 17]
const { execFileSync } = require('child_process');
const path = require('path');
const fs = require('fs');
const args = {};
for (let i = 2; i < process.argv.length; i++) { const a = process.argv[i]; if (a.startsWith('--')) { const k = a.slice(2); const v = process.argv[i + 1] && !process.argv[i + 1].startsWith('--') ? process.argv[++i] : true; args[k] = v; } }
const frames = path.resolve(args.frames); const audio = path.resolve(args.audio); const out = path.resolve(args.out);
const fps = args.fps || '30'; const crf = args.crf || '17';
const ext = args.ext || (fs.readdirSync(frames).some(f => f.endsWith('.png')) ? 'png' : 'jpg');
fs.mkdirSync(path.dirname(out), { recursive: true });
const cmd = ['-y', '-framerate', fps, '-i', path.join(frames, `f%05d.${ext}`), '-i', audio,
  '-c:v', 'libx264', '-preset', args.preset || 'medium', '-crf', crf, '-pix_fmt', 'yuv420p', '-r', fps,
  '-af', 'loudnorm=I=-14:TP=-1:LRA=9', '-c:a', 'aac', '-b:a', '192k', '-ar', '48000',
  '-movflags', '+faststart', '-shortest', out];
console.log('ffmpeg', cmd.join(' '));
execFileSync('ffmpeg', cmd, { stdio: ['ignore', 'ignore', 'inherit'] });
const probe = execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration:stream=codec_type,codec_name,width,height,r_frame_rate,sample_rate,channels', '-of', 'default=noprint_wrappers=1', out]).toString();
console.log(probe);
