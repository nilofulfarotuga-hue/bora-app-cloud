// Espelha a pasta comum de skills (repo bora-app-cloud/.claude/skills) com ~/.claude/skills do PC.
// Missão livro-comum-2026-10-23 (adendo skills). Regras:
//  - repo → PC: toda a skill do repo é copiada para o PC (o repo é a fonte; as do PC eram cópias).
//  - PC → repo: skill que só existe no PC (ex.: criada pelo vigia das 23:30) é copiada para o repo,
//    exceto as de licença proprietária e a pasta synced/ (gerida pela app Claude).
//  - Nunca apaga nada. Uso: node espelhar-skills.mjs [--seco]
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const REPO = 'C:/BoraLocal/projetosflutter/bora_app/.claude/skills';
const PC = path.join(os.homedir(), '.claude', 'skills');
const SECO = process.argv.includes('--seco');
const NUNCA = new Set(['synced', 'sistema', 'docx', 'pdf', 'pptx', 'xlsx', 'file-reading', 'pdf-reading',
  'chrome-browser', 'built-in-browser', 'computer-use', 'testsprite-onboard', 'testsprite-verify']);

const dirs = (d) => fs.readdirSync(d, { withFileTypes: true }).filter((e) => e.isDirectory()).map((e) => e.name);
const temSkill = (d) => fs.existsSync(path.join(d, 'SKILL.md'));
let paraPc = 0; let paraRepo = 0;
for (const s of dirs(REPO)) {
  if (NUNCA.has(s) || !temSkill(path.join(REPO, s))) continue;
  if (!SECO) fs.cpSync(path.join(REPO, s), path.join(PC, s), { recursive: true, force: true });
  paraPc++;
}
const noRepo = new Set(dirs(REPO));
const novas = [];
for (const s of dirs(PC)) {
  if (NUNCA.has(s) || noRepo.has(s) || !temSkill(path.join(PC, s))) continue;
  if (!SECO) fs.cpSync(path.join(PC, s), path.join(REPO, s), { recursive: true });
  paraRepo++; novas.push(s);
}
console.log(`${SECO ? '[seco] ' : ''}repo→PC: ${paraPc} · PC→repo: ${paraRepo}${novas.length ? ' (' + novas.join(', ') + ')' : ''}`);
